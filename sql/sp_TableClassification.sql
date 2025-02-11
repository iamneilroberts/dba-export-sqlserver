-- Create stored procedure for updating classifications
CREATE OR ALTER PROCEDURE dba.sp_UpdateTableClassification
    @MinimumTransactionRows int = 5000,     -- Lowered from 10000
    @ConfidenceThreshold decimal(5,2) = 0.50, -- Lowered from 0.60
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Temporary table for analysis
    CREATE TABLE #TableAnalysis (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        TableSize int,
        DateColumns nvarchar(max),          -- JSON array of date columns
        IndexedDateColumns nvarchar(max),   -- JSON array of indexed date columns
        NameScore decimal(5,2),            -- 25% weight (increased from 20%)
        SizeScore decimal(5,2),          -- 25% weight (decreased from 30%)
        DateScore decimal(5,2),            -- 25% weight (unchanged)
        RelationshipScore decimal(5,2),    -- 15% weight (unchanged)
        ColumnScore decimal(5,2),          -- 10% weight (unchanged)
        TotalScore decimal(5,2),           -- Combined score
        ReasonCodes nvarchar(max),         -- JSON array of reasons
        SuggestedDateColumn nvarchar(128),
        RelatedTables nvarchar(max),       -- JSON array of related tables
        RelationshipPaths nvarchar(max)    -- JSON array of paths to transaction tables
    );

    -- Get all user tables with row counts
    INSERT INTO #TableAnalysis (
        SchemaName,
        TableName,
        TableSize,
        DateColumns,
        IndexedDateColumns,
        NameScore,
        SizeScore,
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
        0,    -- SizeScore
        0,    -- DateScore
        0,    -- RelationshipScore
        0,    -- ColumnScore
        0     -- TotalScore
    FROM sys.tables t
    INNER JOIN sys.partitions p ON t.object_id = p.object_id
    WHERE t.is_ms_shipped = 0
    AND p.index_id IN (0, 1) -- Heap or clustered index
    AND OBJECT_SCHEMA_NAME(t.object_id) != 'dba' -- Exclude DBA schema
    GROUP BY t.object_id, t.name;

    -- Calculate size score (25%)
    UPDATE #TableAnalysis
    SET SizeScore = CASE
        WHEN TableSize >= 1000000 THEN 0.25 -- High volume
        WHEN TableSize >= 100000 THEN 0.20  -- Medium-high volume
        WHEN TableSize >= 10000 THEN 0.15   -- Medium volume
        WHEN TableSize >= 5000 THEN 0.10    -- Low-medium volume
        ELSE 0.05                           -- Low volume
    END;

    -- Analyze table names (25%)
    UPDATE #TableAnalysis
    SET NameScore = CASE
        -- Known transaction tables (highest score)
        WHEN TableName LIKE '%Registration%' THEN 0.25
        WHEN TableName LIKE '%Issue%' THEN 0.25
        WHEN TableName LIKE '%Estimate%' THEN 0.25
        WHEN TableName LIKE '%Authorization%' THEN 0.25
        WHEN TableName LIKE '%RegsWorked%' THEN 0.25
        -- Common transaction patterns (high score)
        WHEN TableName LIKE '%Order%' THEN 0.20
        WHEN TableName LIKE '%Transaction%' THEN 0.20
        WHEN TableName LIKE '%Invoice%' THEN 0.20
        WHEN TableName LIKE '%Payment%' THEN 0.20
        -- Activity patterns (medium score)
        WHEN TableName LIKE '%Journal%' THEN 0.15
        WHEN TableName LIKE '%Entry%' THEN 0.15
        WHEN TableName LIKE '%Activity%' THEN 0.15
        WHEN TableName LIKE '%Event%' THEN 0.15
        -- Historical patterns (lower score)
        WHEN TableName LIKE '%Log%' THEN 0.10
        WHEN TableName LIKE '%History%' THEN 0.10
        WHEN TableName LIKE '%Audit%' THEN 0.10
        WHEN TableName LIKE '%Archive%' THEN 0.10
        -- Temporary/staging patterns (lowest score)
        WHEN TableName LIKE 'STG[_]%' THEN 0.05
        WHEN TableName LIKE 'TEMP[_]%' THEN 0.05
        ELSE 0.0
    END;

    -- Find and analyze date columns
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

        -- Get date columns with additional metadata
        SET @SQL = N'
        SELECT @DateColsJson = (
            SELECT 
                c.name AS [name],
                t.name AS [dataType],
                c.column_id AS [columnPosition],
                CASE 
                    WHEN c.name LIKE ''%Create%'' OR c.name LIKE ''%Insert%'' THEN 1
                    WHEN c.name LIKE ''%Update%'' OR c.name LIKE ''%Modify%'' THEN 2
                    WHEN c.name LIKE ''%Date%'' THEN 3
                    ELSE 4
                END AS [nameRelevance]
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

        -- Get indexed date columns with index details
        SET @SQL = N'
        SELECT @IndexedDateColsJson = (
            SELECT DISTINCT 
                c.name AS [name],
                i.name AS [indexName],
                ic.key_ordinal AS [keyPosition],
                i.is_unique AS [isUnique]
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

        -- Update analysis results with enhanced date score (25%)
        UPDATE #TableAnalysis
        SET 
            DateColumns = @DateColsJson,
            IndexedDateColumns = @IndexedDateColsJson,
            DateScore = CASE
                WHEN @IndexedDateColsJson IS NOT NULL AND 
                     EXISTS (SELECT * FROM OPENJSON(@IndexedDateColsJson)
                            WITH (keyPosition int '$.keyPosition',
                                 isUnique bit '$.isUnique')
                            WHERE keyPosition = 1) THEN 0.25  -- Has date column as leading index column
                WHEN @IndexedDateColsJson IS NOT NULL THEN 0.20  -- Has indexed date columns
                WHEN @DateColsJson IS NOT NULL AND
                     EXISTS (SELECT * FROM OPENJSON(@DateColsJson)
                            WITH (nameRelevance int '$.nameRelevance',
                                 columnPosition int '$.columnPosition')
                            WHERE nameRelevance <= 2) THEN 0.15  -- Has relevant date column names
                WHEN @DateColsJson IS NOT NULL THEN 0.10  -- Has any date columns
                ELSE 0.0
            END,
            SuggestedDateColumn = COALESCE(
                (SELECT TOP 1 JSON_VALUE(value, '$.name')
                 FROM OPENJSON(@IndexedDateColsJson)
                 ORDER BY JSON_VALUE(value, '$.keyPosition')),
                (SELECT TOP 1 JSON_VALUE(value, '$.name')
                 FROM OPENJSON(@DateColsJson)
                 ORDER BY JSON_VALUE(value, '$.nameRelevance'),
                          JSON_VALUE(value, '$.columnPosition'))
            )
        WHERE SchemaName = @SchemaName
        AND TableName = @TableName;

        FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- Analyze relationships (15%)
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
            WHEN rc.RelationshipCount >= 5 THEN 0.15
            WHEN rc.RelationshipCount >= 3 THEN 0.10
            WHEN rc.RelationshipCount >= 1 THEN 0.05
            ELSE 0.0
        END,
        RelatedTables = JSON_ARRAY(rc.RelatedTables)
    FROM #TableAnalysis t
    LEFT JOIN RelationshipCounts rc 
        ON t.SchemaName = rc.SchemaName 
        AND t.TableName = rc.TableName;

    -- Analyze column patterns (10%)
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
        WHEN c.ColumnList LIKE '%Status%' THEN 0.10
        WHEN c.ColumnList LIKE '%Amount%' THEN 0.10
        WHEN c.ColumnList LIKE '%Total%' THEN 0.10
        WHEN c.ColumnList LIKE '%Quantity%' THEN 0.10
        WHEN c.ColumnList LIKE '%Number%' THEN 0.05
        WHEN c.ColumnList LIKE '%Reference%' THEN 0.05
        ELSE 0.0
    END
    FROM #TableAnalysis t
    INNER JOIN @Columns c 
        ON t.SchemaName = c.SchemaName 
        AND t.TableName = c.TableName;

    -- Calculate total score and generate reason codes
    UPDATE #TableAnalysis
    SET 
        TotalScore = NameScore + SizeScore + DateScore + RelationshipScore + ColumnScore,
        ReasonCodes = (
            SELECT 
                CASE WHEN NameScore > 0 THEN 'NamePattern' END AS nameReason,
                CASE WHEN SizeScore >= 0.20 THEN 'HighVolume' 
                     WHEN SizeScore >= 0.10 THEN 'MediumVolume'
                     ELSE 'LowVolume' END AS volumeReason,
                CASE WHEN DateScore > 0 THEN 'DateColumns' END AS dateReason,
                CASE WHEN RelationshipScore > 0 THEN 'Relationships' END AS relReason,
                CASE WHEN ColumnScore > 0 THEN 'ColumnPatterns' END AS colReason
            WHERE 
                NameScore > 0 OR 
                SizeScore > 0 OR
                DateScore > 0 OR 
                RelationshipScore > 0 OR 
                ColumnScore > 0
            FOR JSON PATH
        );

    -- Clear existing classifications
    TRUNCATE TABLE dba.TableClassification;

    -- Insert transaction tables
    INSERT INTO dba.TableClassification (
        SchemaName,
        TableName,
        Classification,
        TableSize,
        DateColumnName,
        RelatedTransactionTables,
        RelationshipPaths,
        ReasonCodes,
        ConfidenceScore,
        Priority,
        LastAnalyzed
    )
    SELECT 
        SchemaName,
        TableName,
        'Transaction',
        TableSize,
        SuggestedDateColumn,
        NULL, -- No related transaction tables for transaction tables
        NULL, -- No relationship paths for transaction tables
        ReasonCodes,
        TotalScore,
        1, -- Highest priority for transaction tables
        GETUTCDATE()
    FROM #TableAnalysis
    WHERE (TotalScore >= @ConfidenceThreshold
           OR NameScore >= 0.20) -- Include known transaction tables even if total score is lower
    AND TableSize >= @MinimumTransactionRows
    AND DateColumns IS NOT NULL
    AND SuggestedDateColumn IS NOT NULL; -- Added this condition

    -- Get relationship paths for supporting tables
    WITH TransactionTables AS (
        SELECT SchemaName, TableName
        FROM dba.TableClassification
        WHERE Classification = 'Transaction'
    ),
    RelatedTables AS (
        SELECT 
            tr.ChildSchema,
            tr.ChildTable,
            JSON_ARRAY(tr.ParentSchema + '.' + tr.ParentTable) as RelatedTransactionTables,
            JSON_ARRAY(tr.RelationshipPath) as RelationshipPaths,
            tr.RelationshipLevel
        FROM dba.TableRelationships tr
        INNER JOIN TransactionTables tt 
            ON tr.ParentSchema = tt.SchemaName 
            AND tr.ParentTable = tt.TableName
    )
    INSERT INTO dba.TableClassification (
        SchemaName,
        TableName,
        Classification,
        TableSize,
        DateColumnName,
        RelatedTransactionTables,
        RelationshipPaths,
        ReasonCodes,
        ConfidenceScore,
        Priority,
        LastAnalyzed
    )
    SELECT 
        t.SchemaName,
        t.TableName,
        'Supporting',
        t.TableSize,
        t.SuggestedDateColumn,
        rt.RelatedTransactionTables,
        rt.RelationshipPaths,
        t.ReasonCodes,
        t.TotalScore,
        rt.RelationshipLevel + 1, -- Priority based on relationship level
        GETUTCDATE()
    FROM #TableAnalysis t
    INNER JOIN RelatedTables rt 
        ON t.SchemaName = rt.ChildSchema 
        AND t.TableName = rt.ChildTable
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dba.TableClassification tc 
        WHERE tc.SchemaName = t.SchemaName 
        AND tc.TableName = t.TableName
    );

    -- Insert remaining tables as full copy
    INSERT INTO dba.TableClassification (
        SchemaName,
        TableName,
        Classification,
        TableSize,
        DateColumnName,
        RelatedTransactionTables,
        RelationshipPaths,
        ReasonCodes,
        ConfidenceScore,
        Priority,
        LastAnalyzed
    )
    SELECT 
        SchemaName,
        TableName,
        'Full Copy',
        TableSize,
        SuggestedDateColumn,
        NULL,
        NULL,
        ReasonCodes,
        TotalScore,
        100, -- Lowest priority for full copy tables
        GETUTCDATE()
    FROM #TableAnalysis t
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dba.TableClassification tc 
        WHERE tc.SchemaName = t.SchemaName 
        AND tc.TableName = t.TableName
    );

    -- Output results if debug mode
    IF @Debug = 1
    BEGIN
        -- Output classification summary
        SELECT 
            Classification,
            COUNT(*) as TableCount,
            AVG(TableSize) as AvgTableSize,
            AVG(ConfidenceScore) as AvgConfidence
        FROM dba.TableClassification
        GROUP BY Classification
        ORDER BY TableCount DESC;

        -- Output detailed analysis for transaction tables
        SELECT 
            SchemaName,
            TableName,
            Classification,
            TableSize,
            DateColumnName,
            ConfidenceScore,
            Priority,
            ReasonCodes
        FROM dba.TableClassification
        WHERE Classification = 'Transaction'
        ORDER BY Priority, ConfidenceScore DESC;

        -- Output tables that were considered for transaction classification but rejected
        SELECT 
            SchemaName,
            TableName,
            TableSize,
            DateColumns,
            SuggestedDateColumn,
            TotalScore,
            NameScore,
            DateScore,
            ReasonCodes
        FROM #TableAnalysis
        WHERE NameScore >= 0.20  -- Known transaction patterns
        AND (SuggestedDateColumn IS NULL OR DateColumns IS NULL)  -- But missing required date column
        ORDER BY NameScore DESC, TableSize DESC;
    END

    -- Cleanup
    DROP TABLE #TableAnalysis;
END;
GO

-- Create helper views
CREATE OR ALTER VIEW dba.vw_TableClassificationSummary
AS
SELECT 
    Classification,
    COUNT(*) as TableCount,
    SUM(TableSize) as TotalSize,
    AVG(TableSize) as AvgTableSize,
    AVG(ConfidenceScore) as AvgConfidence,
    MIN(Priority) as MinPriority,
    MAX(Priority) as MaxPriority
FROM dba.TableClassification
GROUP BY Classification;
GO

CREATE OR ALTER VIEW dba.vw_TransactionTables
AS
SELECT
    SchemaName,
    TableName,
    TableSize,
    DateColumnName,
    ConfidenceScore,
    Priority,
    ReasonCodes,
    LastAnalyzed
FROM dba.TableClassification
WHERE Classification = 'Transaction';
GO

CREATE OR ALTER VIEW dba.vw_SupportingTables
AS
SELECT
    SchemaName,
    TableName,
    TableSize,
    DateColumnName,
    RelatedTransactionTables,
    RelationshipPaths,
    ConfidenceScore,
    Priority,
    LastAnalyzed
FROM dba.TableClassification
WHERE Classification = 'Supporting';
GO