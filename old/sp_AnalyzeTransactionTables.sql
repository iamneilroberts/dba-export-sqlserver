CREATE OR ALTER PROCEDURE dba.sp_AnalyzeTransactionTables
    @MinimumRows int = 1000,              -- Minimum rows for consideration
    @ConfidenceThreshold decimal(5,2) = 0.5,  -- Minimum confidence score
    @GenerateScript bit = 1,              -- Generate INSERT scripts
    @Debug bit = 0                        -- Show analysis details
AS
BEGIN
    SET NOCOUNT ON;

    -- Create temporary table to store analysis results
    CREATE TABLE #TableAnalysis (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        RecordCount int,                  -- Changed from RowCount to RecordCount
        DateColumns nvarchar(max),        -- JSON array of date columns
        IndexedDateColumns nvarchar(max), -- JSON array of indexed date columns
        NameScore decimal(5,2),           -- Score based on naming patterns
        DateScore decimal(5,2),           -- Score based on date columns
        RelationshipScore decimal(5,2),   -- Score based on relationships
        ColumnScore decimal(5,2),         -- Score based on column patterns
        TotalScore decimal(5,2),          -- Combined confidence score
        ReasonCodes nvarchar(max),        -- JSON array of reason codes
        SuggestedDateColumn nvarchar(128),
        RelatedTables nvarchar(max),      -- JSON array of related tables
        GeneratedScript nvarchar(max)
    );

    -- Get all user tables with row counts
    INSERT INTO #TableAnalysis (
        SchemaName,
        TableName,
        RecordCount,
        DateColumns,
        IndexedDateColumns,
        NameScore,
        DateScore,
        RelationshipScore,
        ColumnScore,
        TotalScore
    )
    SELECT 
        OBJECT_SCHEMA_NAME(t.object_id),
        t.name,
        SUM(p.rows),
        NULL, -- DateColumns
        NULL, -- IndexedDateColumns
        0,    -- NameScore
        0,    -- DateScore
        0,    -- RelationshipScore
        0,    -- ColumnScore
        0     -- TotalScore
    FROM sys.tables t
    INNER JOIN sys.partitions p ON t.object_id = p.object_id
    WHERE t.is_ms_shipped = 0
    AND p.index_id IN (0, 1) -- Heap or clustered index
    AND OBJECT_SCHEMA_NAME(t.object_id) != 'dba' -- Exclude DBA schema
    GROUP BY t.object_id, t.name
    HAVING SUM(p.rows) >= @MinimumRows;

    -- Analyze table names (10%)
    UPDATE #TableAnalysis
    SET NameScore = CASE
        WHEN TableName LIKE '%Order%' THEN 0.10
        WHEN TableName LIKE '%Transaction%' THEN 0.10
        WHEN TableName LIKE '%Invoice%' THEN 0.10
        WHEN TableName LIKE '%Payment%' THEN 0.10
        WHEN TableName LIKE '%Journal%' THEN 0.10
        WHEN TableName LIKE '%Entry%' THEN 0.08
        WHEN TableName LIKE '%Log%' THEN 0.05
        WHEN TableName LIKE '%History%' THEN 0.05
        WHEN TableName LIKE '%Audit%' THEN 0.05
        WHEN TableName LIKE 'STG[_]%' THEN 0.02 -- Staging tables
        WHEN TableName LIKE 'TEMP[_]%' THEN 0.02 -- Temp tables
        ELSE 0.0
    END;

    -- Find date columns
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @SQL nvarchar(max);
    DECLARE @DateColsJson nvarchar(max);
    DECLARE @IndexedDateColsJson nvarchar(max);
    DECLARE @ParamDef nvarchar(max);
    DECLARE @FullTableName nvarchar(max);
    
    DECLARE table_cursor CURSOR FOR
    SELECT SchemaName, TableName
    FROM #TableAnalysis;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @FullTableName = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);

        -- Get date columns
        SET @SQL = N'
        SELECT @DateColsJson = (
            SELECT 
                c.name AS [name],
                t.name AS [dataType]
            FROM sys.columns c
            INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
            WHERE c.object_id = OBJECT_ID(@TableName)
            AND t.name IN (''datetime'', ''datetime2'', ''date'')
            FOR JSON PATH
        )';

        SET @ParamDef = N'@TableName nvarchar(256), @DateColsJson nvarchar(max) OUTPUT';
        EXEC sp_executesql @SQL, @ParamDef,
            @TableName = @FullTableName,
            @DateColsJson = @DateColsJson OUTPUT;

        -- Get indexed date columns
        SET @SQL = N'
        SELECT @IndexedDateColsJson = (
            SELECT DISTINCT c.name AS [name]
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
            WHERE i.object_id = OBJECT_ID(@TableName)
            AND t.name IN (''datetime'', ''datetime2'', ''date'')
            FOR JSON PATH
        )';

        SET @ParamDef = N'@TableName nvarchar(256), @IndexedDateColsJson nvarchar(max) OUTPUT';
        EXEC sp_executesql @SQL, @ParamDef,
            @TableName = @FullTableName,
            @IndexedDateColsJson = @IndexedDateColsJson OUTPUT;

        -- Update analysis results
        UPDATE #TableAnalysis
        SET 
            DateColumns = @DateColsJson,
            IndexedDateColumns = @IndexedDateColsJson,
            DateScore = CASE
                WHEN @IndexedDateColsJson IS NOT NULL THEN 0.10  -- Has indexed date columns
                WHEN @DateColsJson IS NOT NULL THEN 0.05         -- Has date columns
                ELSE 0.0
            END
        WHERE SchemaName = @SchemaName
        AND TableName = @TableName;

        FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- Analyze relationships
    WITH RelationshipCounts AS (
        SELECT 
            OBJECT_SCHEMA_NAME(fk.parent_object_id) AS SchemaName,
            OBJECT_NAME(fk.parent_object_id) AS TableName,
            COUNT(*) AS RelationshipCount,
            STRING_AGG(
                QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) + '.' + 
                QUOTENAME(OBJECT_NAME(fk.referenced_object_id)),
                ', '
            ) AS RelatedTables
        FROM sys.foreign_keys fk
        GROUP BY fk.parent_object_id
    )
    UPDATE t
    SET 
        RelationshipScore = CASE
            WHEN rc.RelationshipCount >= 5 THEN 0.10
            WHEN rc.RelationshipCount >= 3 THEN 0.07
            WHEN rc.RelationshipCount >= 1 THEN 0.05
            ELSE 0.0
        END,
        RelatedTables = JSON_ARRAY(rc.RelatedTables)
    FROM #TableAnalysis t
    LEFT JOIN RelationshipCounts rc 
        ON t.SchemaName = rc.SchemaName 
        AND t.TableName = rc.TableName;

    -- Analyze column patterns
    DECLARE @Columns table (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        ColumnList nvarchar(max)
    );

    INSERT INTO @Columns
    SELECT 
        OBJECT_SCHEMA_NAME(t.object_id),
        t.name,
        STRING_AGG(c.name, ', ')
    FROM sys.tables t
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    GROUP BY t.object_id, t.name;

    UPDATE t
    SET ColumnScore = CASE
        WHEN c.ColumnList LIKE '%Status%' THEN 0.05
        WHEN c.ColumnList LIKE '%Amount%' THEN 0.05
        WHEN c.ColumnList LIKE '%Total%' THEN 0.05
        WHEN c.ColumnList LIKE '%Quantity%' THEN 0.05
        WHEN c.ColumnList LIKE '%Number%' THEN 0.03
        WHEN c.ColumnList LIKE '%Reference%' THEN 0.03
        ELSE 0.0
    END
    FROM #TableAnalysis t
    INNER JOIN @Columns c 
        ON t.SchemaName = c.SchemaName 
        AND t.TableName = c.TableName;

    -- Calculate total score and suggest date columns
    UPDATE #TableAnalysis
    SET 
        TotalScore = NameScore + DateScore + RelationshipScore + ColumnScore,
        SuggestedDateColumn = JSON_VALUE(IndexedDateColumns, '$[0].name'),
        ReasonCodes = (
            SELECT 
                CASE WHEN NameScore > 0 THEN 'NamePattern' END AS nameReason,
                CASE WHEN DateScore > 0 THEN 'DateColumns' END AS dateReason,
                CASE WHEN RelationshipScore > 0 THEN 'Relationships' END AS relReason,
                CASE WHEN ColumnScore > 0 THEN 'ColumnPatterns' END AS colReason
            WHERE 
                NameScore > 0 OR 
                DateScore > 0 OR 
                RelationshipScore > 0 OR 
                ColumnScore > 0
            FOR JSON PATH
        );

    -- Generate configuration scripts
    UPDATE #TableAnalysis
    SET GeneratedScript = 
        CASE 
        WHEN TotalScore >= @ConfidenceThreshold
        THEN CONCAT('
-- Generated by sp_AnalyzeTransactionTables (Score: ', CAST(TotalScore AS varchar(10)), ')
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport,
    ExportPriority
)
VALUES (
    ''', SchemaName, ''',
    ''', TableName, ''',
    1,
    ''', ISNULL(SuggestedDateColumn, ''), ''',
    0,
    ', CAST(CAST(TotalScore * 10 AS int) AS varchar(10)), ' -- Priority based on confidence score
);')
        ELSE NULL
        END
    WHERE TotalScore > 0;

    -- Output results
    SELECT 
        SchemaName,
        TableName,
        RecordCount,
        DateColumns,
        IndexedDateColumns,
        NameScore,
        DateScore,
        RelationshipScore,
        ColumnScore,
        TotalScore,
        ReasonCodes,
        SuggestedDateColumn,
        RelatedTables,
        GeneratedScript
    FROM #TableAnalysis
    WHERE TotalScore >= @ConfidenceThreshold
    ORDER BY TotalScore DESC;

    -- Debug output
    IF @Debug = 1
    BEGIN
        SELECT 
            'Analysis Details' AS Section,
            SchemaName,
            TableName,
            RecordCount,
            DateColumns,
            IndexedDateColumns,
            NameScore,
            DateScore,
            RelationshipScore,
            ColumnScore,
            TotalScore,
            ReasonCodes,
            SuggestedDateColumn,
            RelatedTables
        FROM #TableAnalysis
        ORDER BY TotalScore DESC;
    END

    DROP TABLE #TableAnalysis;
END;
GO