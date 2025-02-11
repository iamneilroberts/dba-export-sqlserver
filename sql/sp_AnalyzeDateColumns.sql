CREATE OR ALTER PROCEDURE dba.sp_AnalyzeDateColumns
    @MinimumRows int = 5000,           -- Minimum rows to consider for indexing
    @UpdateFrequencyThreshold int = 20, -- Percentage threshold for update frequency
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Temporary table for analysis
    CREATE TABLE #DateColumnAnalysis (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        ColumnName nvarchar(128),
        DataType nvarchar(128),
        TableSize bigint,
        IsIndexed bit,
        IndexName nvarchar(128),
        IsLeadingIndexColumn bit,
        DistinctValues bigint,
        NullCount bigint,
        UpdateFrequency decimal(5,2),
        SelectFrequency decimal(5,2),
        Score decimal(5,2)
    );

    -- Get all date columns from user tables
    INSERT INTO #DateColumnAnalysis (
        SchemaName,
        TableName,
        ColumnName,
        DataType,
        TableSize,
        IsIndexed,
        IndexName,
        IsLeadingIndexColumn
    )
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        c.name AS ColumnName,
        ty.name AS DataType,
        p.TableSize,
        CASE WHEN i.index_id IS NOT NULL THEN 1 ELSE 0 END AS IsIndexed,
        i.name AS IndexName,
        CASE WHEN ic.key_ordinal = 1 THEN 1 ELSE 0 END AS IsLeadingIndexColumn
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.types ty ON c.system_type_id = ty.system_type_id
    INNER JOIN (
        SELECT object_id, SUM(rows) as TableSize
        FROM sys.partitions
        WHERE index_id IN (0,1)
        GROUP BY object_id
    ) p ON t.object_id = p.object_id
    LEFT JOIN sys.index_columns ic ON 
        c.object_id = ic.object_id 
        AND c.column_id = ic.column_id 
        AND ic.key_ordinal = 1
    LEFT JOIN sys.indexes i ON 
        ic.object_id = i.object_id 
        AND ic.index_id = i.index_id
    WHERE 
        ty.name IN ('datetime', 'datetime2', 'date')
        AND t.is_ms_shipped = 0
        AND s.name != 'dba'
        AND p.TableSize >= @MinimumRows;

    -- Analyze column statistics and usage patterns
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @ColumnName nvarchar(128);
    DECLARE @SQL nvarchar(max);
    DECLARE @Params nvarchar(max);
    DECLARE @DistinctValues bigint;
    DECLARE @NullCount bigint;

    DECLARE column_cursor CURSOR FOR
    SELECT SchemaName, TableName, ColumnName
    FROM #DateColumnAnalysis;

    OPEN column_cursor;
    FETCH NEXT FROM column_cursor INTO @SchemaName, @TableName, @ColumnName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Get distinct values and null count
        SET @SQL = N'
        SELECT @DistinctValues = COUNT(DISTINCT ' + QUOTENAME(@ColumnName) + '),
               @NullCount = SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1 ELSE 0 END)
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);

        SET @Params = N'@DistinctValues bigint OUTPUT, @NullCount bigint OUTPUT';
        
        EXEC sp_executesql @SQL, @Params, 
            @DistinctValues = @DistinctValues OUTPUT,
            @NullCount = @NullCount OUTPUT;

        -- Update analysis results
        UPDATE #DateColumnAnalysis
        SET 
            DistinctValues = @DistinctValues,
            NullCount = @NullCount
        WHERE 
            SchemaName = @SchemaName
            AND TableName = @TableName
            AND ColumnName = @ColumnName;

        FETCH NEXT FROM column_cursor INTO @SchemaName, @TableName, @ColumnName;
    END

    CLOSE column_cursor;
    DEALLOCATE column_cursor;

    -- Calculate scores based on analysis
    UPDATE #DateColumnAnalysis
    SET Score = CASE
        -- Higher score for date columns with high cardinality and low null count
        WHEN (DistinctValues * 1.0 / NULLIF(TableSize - NullCount, 0)) > 0.8 THEN 1.0
        WHEN (DistinctValues * 1.0 / NULLIF(TableSize - NullCount, 0)) > 0.5 THEN 0.8
        WHEN (DistinctValues * 1.0 / NULLIF(TableSize - NullCount, 0)) > 0.2 THEN 0.6
        ELSE 0.4
    END;

    -- Generate index suggestions
    INSERT INTO dba.IndexSuggestions (
        SchemaName,
        TableName,
        ColumnName,
        SuggestedIndexName,
        IndexDefinition,
        Reason,
        EstimatedImpact,
        IsImplemented,
        CreatedDate,
        ModifiedDate
    )
    SELECT 
        a.SchemaName,
        a.TableName,
        a.ColumnName,
        'IX_' + a.TableName + '_' + a.ColumnName AS SuggestedIndexName,
        'CREATE NONCLUSTERED INDEX [IX_' + a.TableName + '_' + a.ColumnName + '] ON ' +
        QUOTENAME(a.SchemaName) + '.' + QUOTENAME(a.TableName) + '(' + QUOTENAME(a.ColumnName) + ' ASC)' AS IndexDefinition,
        CASE
            WHEN a.TableSize >= 1000000 THEN 'Large table with high row count'
            WHEN a.TableSize >= 100000 THEN 'Medium-sized table with significant row count'
            ELSE 'Table meets minimum size threshold for indexing'
        END + 
        CASE
            WHEN a.Score >= 0.8 THEN ' and high column selectivity'
            WHEN a.Score >= 0.6 THEN ' and medium column selectivity'
            ELSE ' and moderate column selectivity'
        END AS Reason,
        a.Score AS EstimatedImpact,
        0 AS IsImplemented,
        GETUTCDATE(),
        GETUTCDATE()
    FROM #DateColumnAnalysis a
    WHERE 
        a.IsIndexed = 0
        AND NOT EXISTS (
            SELECT 1 
            FROM dba.IndexSuggestions s 
            WHERE s.SchemaName = a.SchemaName
            AND s.TableName = a.TableName
            AND s.ColumnName = a.ColumnName
        );

    -- Debug output
    IF @Debug = 1
    BEGIN
        -- Output column analysis
        SELECT 
            SchemaName,
            TableName,
            ColumnName,
            TableSize,
            IsIndexed,
            IndexName,
            IsLeadingIndexColumn,
            DistinctValues,
            NullCount,
            Score
        FROM #DateColumnAnalysis
        ORDER BY Score DESC, TableSize DESC;

        -- Output index suggestions
        SELECT 
            SchemaName,
            TableName,
            ColumnName,
            SuggestedIndexName,
            IndexDefinition,
            Reason,
            EstimatedImpact,
            CreatedDate
        FROM dba.IndexSuggestions
        WHERE IsImplemented = 0
        ORDER BY EstimatedImpact DESC;
    END

    -- Return suggestions
    SELECT 
        s.SchemaName,
        s.TableName,
        s.ColumnName,
        s.SuggestedIndexName,
        s.IndexDefinition,
        s.Reason,
        s.EstimatedImpact,
        tc.Classification,
        tc.TableSize
    FROM dba.IndexSuggestions s
    LEFT JOIN dba.TableClassification tc
        ON s.SchemaName = tc.SchemaName
        AND s.TableName = tc.TableName
    WHERE s.IsImplemented = 0
    ORDER BY 
        tc.Classification,
        s.EstimatedImpact DESC;

    -- Cleanup
    DROP TABLE #DateColumnAnalysis;
END;
GO

-- Create view for active index suggestions
CREATE OR ALTER VIEW dba.vw_ActiveIndexSuggestions
AS
SELECT
    s.SchemaName,
    s.TableName,
    s.ColumnName,
    s.SuggestedIndexName,
    s.IndexDefinition,
    s.Reason,
    s.EstimatedImpact,
    tc.Classification,
    tc.TableSize,
    tc.ConfidenceScore
FROM dba.IndexSuggestions s
LEFT JOIN dba.TableClassification tc
    ON s.SchemaName = tc.SchemaName
    AND s.TableName = tc.TableName
WHERE s.IsImplemented = 0;
GO