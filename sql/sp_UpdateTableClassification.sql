CREATE OR ALTER PROCEDURE dba.sp_UpdateTableClassification
    @MinimumTransactionRows int = 100,    -- Minimum rows for transaction tables (lowered threshold)
    @ConfidenceThreshold decimal(5,2) = 0.50, -- Minimum confidence score (adjusted threshold)
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Create temporary table for analysis
    CREATE TABLE #TableAnalysis (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        TableSize int,
        DateColumns nvarchar(max),          -- JSON array of date columns
        IndexedDateColumns nvarchar(max),   -- JSON array of indexed date columns
        NameScore decimal(5,2),            -- 20% weight
        RecordScore decimal(5,2),          -- 30% weight
        DateScore decimal(5,2),            -- 25% weight
        RelationshipScore decimal(5,2),    -- 15% weight
        ColumnScore decimal(5,2),          -- 10% weight
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
        RecordScore,
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
        0,    -- RecordScore
        0,    -- DateScore
        0,    -- RelationshipScore
        0,    -- ColumnScore
        0     -- TotalScore
    FROM sys.tables t
    INNER JOIN sys.partitions p ON t.object_id = p.object_id
    WHERE t.is_ms_shipped = 0
    AND p.index_id IN (0, 1) -- Heap or clustered index
    AND OBJECT_SCHEMA_NAME(t.object_id) NOT IN ('dba', 'sys') -- Exclude system schemas
    GROUP BY t.object_id, t.name;

    -- Calculate record count score (20%) and initialize TotalScore
    UPDATE #TableAnalysis
    SET
        RecordScore = CASE
            WHEN TableSize >= 50000 THEN 0.20   -- High volume
            WHEN TableSize >= 5000 THEN 0.15    -- Medium-high volume
            WHEN TableSize >= 1000 THEN 0.10    -- Medium volume
            WHEN TableSize >= 100 THEN 0.05     -- Low volume
            ELSE 0.02                           -- Minimal volume
        END,
        TotalScore = 0;  -- Initialize TotalScore to 0

    -- Analyze table names (40%) and update total
    UPDATE #TableAnalysis
    SET
        NameScore = CASE
            -- General transaction patterns (0.40)
            WHEN TableName LIKE '%Tran[_]%' THEN 0.40
            WHEN TableName LIKE '%Trans[_]%' THEN 0.40
            WHEN TableName LIKE '%Activity%' THEN 0.40
            WHEN TableName LIKE '%Event%' THEN 0.40
            WHEN TableName LIKE '%Entry%' THEN 0.40
            WHEN TableName LIKE '%Record%' THEN 0.40
            -- Healthcare transaction patterns (0.40)
            WHEN TableName LIKE '%Visit%' THEN 0.40
            WHEN TableName LIKE '%Encounter%' THEN 0.40
            WHEN TableName LIKE '%Admission%' THEN 0.40
            WHEN TableName LIKE '%Registration%' THEN 0.40
            WHEN TableName LIKE '%Appointment%' THEN 0.40
            WHEN TableName LIKE '%Procedure%' THEN 0.40
            WHEN TableName LIKE '%Service%' THEN 0.40
            -- Clinical transaction patterns (0.40)
            WHEN TableName LIKE '%Diagnosis%' THEN 0.40
            WHEN TableName LIKE '%Treatment%' THEN 0.40
            WHEN TableName LIKE '%Result%' THEN 0.40
            WHEN TableName LIKE '%Order%' THEN 0.40
            WHEN TableName LIKE '%Lab%' THEN 0.40
            WHEN TableName LIKE '%Test%' THEN 0.40
            -- Financial transaction patterns (0.40)
            WHEN TableName LIKE '%Claim%' THEN 0.40
            WHEN TableName LIKE '%Charge%' THEN 0.40
            WHEN TableName LIKE '%Payment%' THEN 0.40
            WHEN TableName LIKE '%Bill%' THEN 0.40
            WHEN TableName LIKE '%Invoice%' THEN 0.40
            -- Supporting patterns (0.25)
            WHEN TableName LIKE '%Authorization%' THEN 0.25
            WHEN TableName LIKE '%Referral%' THEN 0.25
            WHEN TableName LIKE '%Document%' THEN 0.25
            WHEN TableName LIKE '%Note%' THEN 0.25
            -- Historical patterns (0.15)
            WHEN TableName LIKE '%Log%' THEN 0.15
            WHEN TableName LIKE '%History%' THEN 0.15
            WHEN TableName LIKE '%Audit%' THEN 0.15
            WHEN TableName LIKE '%Archive%' THEN 0.15
            WHEN TableName LIKE '%Journal%' THEN 0.15
            -- Staging patterns (0.05)
            WHEN TableName LIKE 'STG[_]%' THEN 0.05
            WHEN TableName LIKE 'TEMP[_]%' THEN 0.05
            WHEN TableName LIKE '%Staging%' THEN 0.05
            ELSE 0.0
        END,
        TotalScore = CASE
            -- General transaction patterns (0.40)
            WHEN TableName LIKE '%Tran[_]%' THEN 0.40
            WHEN TableName LIKE '%Trans[_]%' THEN 0.40
            WHEN TableName LIKE '%Activity%' THEN 0.40
            WHEN TableName LIKE '%Event%' THEN 0.40
            WHEN TableName LIKE '%Entry%' THEN 0.40
            WHEN TableName LIKE '%Record%' THEN 0.40
            -- Healthcare transaction patterns (0.40)
            WHEN TableName LIKE '%Visit%' THEN 0.40
            WHEN TableName LIKE '%Encounter%' THEN 0.40
            WHEN TableName LIKE '%Admission%' THEN 0.40
            WHEN TableName LIKE '%Registration%' THEN 0.40
            WHEN TableName LIKE '%Appointment%' THEN 0.40
            WHEN TableName LIKE '%Procedure%' THEN 0.40
            WHEN TableName LIKE '%Service%' THEN 0.40
            -- Clinical transaction patterns (0.40)
            WHEN TableName LIKE '%Diagnosis%' THEN 0.40
            WHEN TableName LIKE '%Treatment%' THEN 0.40
            WHEN TableName LIKE '%Result%' THEN 0.40
            WHEN TableName LIKE '%Order%' THEN 0.40
            WHEN TableName LIKE '%Lab%' THEN 0.40
            WHEN TableName LIKE '%Test%' THEN 0.40
            -- Financial transaction patterns (0.40)
            WHEN TableName LIKE '%Claim%' THEN 0.40
            WHEN TableName LIKE '%Charge%' THEN 0.40
            WHEN TableName LIKE '%Payment%' THEN 0.40
            WHEN TableName LIKE '%Bill%' THEN 0.40
            WHEN TableName LIKE '%Invoice%' THEN 0.40
            -- Supporting patterns (0.25)
            WHEN TableName LIKE '%Authorization%' THEN 0.25
            WHEN TableName LIKE '%Referral%' THEN 0.25
            WHEN TableName LIKE '%Document%' THEN 0.25
            WHEN TableName LIKE '%Note%' THEN 0.25
            -- Historical patterns (0.15)
            WHEN TableName LIKE '%Log%' THEN 0.15
            WHEN TableName LIKE '%History%' THEN 0.15
            WHEN TableName LIKE '%Audit%' THEN 0.15
            WHEN TableName LIKE '%Archive%' THEN 0.15
            WHEN TableName LIKE '%Journal%' THEN 0.15
            -- Staging patterns (0.05)
            WHEN TableName LIKE 'STG[_]%' THEN 0.05
            WHEN TableName LIKE 'TEMP[_]%' THEN 0.05
            WHEN TableName LIKE '%Staging%' THEN 0.05
            ELSE 0.0
        END + RecordScore;

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

        -- Get date columns, prioritizing UTC and standard date naming patterns
        SET @SQL = N'
        SELECT @DateColsJson = (
            SELECT
                c.name AS [name],
                t.name AS [dataType],
                CASE
                    WHEN c.name LIKE ''%UTC%'' THEN 1
                    WHEN c.name IN (''DateTimeStamp'', ''CreateDate'', ''CreatedDate'', ''ModifiedDate'', ''LastModified'') THEN 2
                    ELSE 3
                END as [priority]
            FROM sys.columns c
            INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
            WHERE c.object_id = OBJECT_ID(@TableName)
            AND t.name IN (''datetime'', ''datetime2'', ''date'')
            ORDER BY
                CASE
                    WHEN c.name LIKE ''%UTC%'' THEN 1
                    WHEN c.name IN (''DateTimeStamp'', ''CreateDate'', ''CreatedDate'', ''ModifiedDate'', ''LastModified'') THEN 2
                    ELSE 3
                END
            FOR JSON PATH
        )';

        SET @ParamDef = N'@TableName nvarchar(256), @DateColsJson nvarchar(max) OUTPUT';
        EXEC sp_executesql @SQL, @ParamDef,
            @TableName = @FullTableName,
            @DateColsJson = @DateColsJson OUTPUT;

        -- Get indexed date columns, prioritizing UTC and standard date naming patterns
        SET @SQL = N'
        SELECT @IndexedDateColsJson = (
            SELECT DISTINCT
                c.name AS [name],
                CASE
                    WHEN c.name LIKE ''%UTC%'' THEN 1
                    WHEN c.name IN (''DateTimeStamp'', ''CreateDate'', ''CreatedDate'', ''ModifiedDate'', ''LastModified'') THEN 2
                    ELSE 3
                END as [priority]
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
            WHERE i.object_id = OBJECT_ID(@TableName)
            AND t.name IN (''datetime'', ''datetime2'', ''date'')
            ORDER BY
                CASE
                    WHEN c.name LIKE ''%UTC%'' THEN 1
                    WHEN c.name IN (''DateTimeStamp'', ''CreateDate'', ''CreatedDate'', ''ModifiedDate'', ''LastModified'') THEN 2
                    ELSE 3
                END
            FOR JSON PATH
        )';

        SET @ParamDef = N'@TableName nvarchar(256), @IndexedDateColsJson nvarchar(max) OUTPUT';
        EXEC sp_executesql @SQL, @ParamDef,
            @TableName = @FullTableName,
            @IndexedDateColsJson = @IndexedDateColsJson OUTPUT;

        -- Update analysis results with date score (25%)
        UPDATE #TableAnalysis
        SET 
            DateColumns = @DateColsJson,
            IndexedDateColumns = @IndexedDateColsJson,
            DateScore = CASE
                WHEN @DateColsJson IS NOT NULL THEN 0.25  -- Any date column is good enough
                ELSE 0.0
            END,
            SuggestedDateColumn = COALESCE(
                JSON_VALUE(@IndexedDateColsJson, '$[0].name'),  -- Prefer indexed
                JSON_VALUE(@DateColsJson, '$[0].name')          -- Fall back to any date column
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
        -- Strong transaction indicators (0.10)
        WHEN c.ColumnList LIKE '%Status%' THEN 0.10
        WHEN c.ColumnList LIKE '%Amount%' THEN 0.10
        WHEN c.ColumnList LIKE '%Total%' THEN 0.10
        WHEN c.ColumnList LIKE '%Quantity%' THEN 0.10
        WHEN c.ColumnList LIKE '%Date%' THEN 0.10
        -- Medium transaction indicators (0.08)
        WHEN c.ColumnList LIKE '%Number%' THEN 0.08
        WHEN c.ColumnList LIKE '%Reference%' THEN 0.08
        WHEN c.ColumnList LIKE '%Type%' THEN 0.08
        WHEN c.ColumnList LIKE '%Code%' THEN 0.08
        -- Supporting indicators (0.05)
        WHEN c.ColumnList LIKE '%ID%' THEN 0.05
        WHEN c.ColumnList LIKE '%Description%' THEN 0.05
        WHEN c.ColumnList LIKE '%Comment%' THEN 0.05
        WHEN c.ColumnList LIKE '%Note%' THEN 0.05
        ELSE 0.0
    END
    FROM #TableAnalysis t
    INNER JOIN @Columns c 
        ON t.SchemaName = c.SchemaName 
        AND t.TableName = c.TableName;

    -- Calculate total score and generate reason codes
    UPDATE #TableAnalysis
    SET 
        TotalScore = NameScore + RecordScore + DateScore + RelationshipScore + ColumnScore,
        ReasonCodes = (
            SELECT 
                CASE WHEN NameScore > 0 THEN 'NamePattern' END AS nameReason,
                CASE WHEN RecordScore >= 0.20 THEN 'HighVolume' 
                     WHEN RecordScore >= 0.10 THEN 'MediumVolume'
                     ELSE 'LowVolume' END AS volumeReason,
                CASE WHEN DateScore > 0 THEN 'DateColumns' END AS dateReason,
                CASE WHEN RelationshipScore > 0 THEN 'Relationships' END AS relReason,
                CASE WHEN ColumnScore > 0 THEN 'ColumnPatterns' END AS colReason
            WHERE 
                NameScore > 0 OR 
                RecordScore > 0 OR
                DateScore > 0 OR 
                RelationshipScore > 0 OR 
                ColumnScore > 0
            FOR JSON PATH
        );

    -- Clear existing classifications
    TRUNCATE TABLE dba.TableClassification;

    -- First identify high volume tables with date columns as transactions
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
        LastAnalyzed
    )
    SELECT
        t.SchemaName,
        t.TableName,
        'Transaction',
        t.TableSize,
        t.SuggestedDateColumn,
        NULL, -- No related transaction tables for transaction tables
        NULL, -- No relationship paths for transaction tables
        t.ReasonCodes,
        t.TotalScore,
        GETUTCDATE()
    FROM #TableAnalysis t
    WHERE t.TableSize >= 10000     -- High volume threshold
    AND t.DateColumns IS NOT NULL; -- Must have a date column

    -- Then identify additional transaction tables based on name patterns
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
        LastAnalyzed
    )
    SELECT
        t.SchemaName,
        t.TableName,
        'Transaction',
        t.TableSize,
        t.SuggestedDateColumn,
        NULL, -- No related transaction tables for transaction tables
        NULL, -- No relationship paths for transaction tables
        t.ReasonCodes,
        t.TotalScore,
        GETUTCDATE()
    FROM #TableAnalysis t
    WHERE t.TableSize >= @MinimumTransactionRows
    AND t.DateColumns IS NOT NULL  -- Must have a date column
    AND t.NameScore >= 0.25        -- Name pattern match
    AND NOT EXISTS (               -- Don't duplicate tables already classified
        SELECT 1
        FROM dba.TableClassification tc
        WHERE tc.SchemaName = t.SchemaName
        AND tc.TableName = t.TableName
    );

    -- Identify supporting tables (tables with FK relationships to transaction tables)
    -- These are classified as supporting regardless of whether they have date columns
    WITH TransactionTables AS (
        SELECT SchemaName, TableName
        FROM dba.TableClassification
        WHERE Classification = 'Transaction'
    ),
    -- Get all tables that have any foreign key relationships
    TablesWithRelationships AS (
        SELECT DISTINCT
            OBJECT_SCHEMA_NAME(fk.parent_object_id) AS SchemaName,
            OBJECT_NAME(fk.parent_object_id) AS TableName
        FROM sys.foreign_keys fk
        WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) NOT IN ('dba', 'sys')
        UNION
        SELECT DISTINCT
            OBJECT_SCHEMA_NAME(fk.referenced_object_id),
            OBJECT_NAME(fk.referenced_object_id)
        FROM sys.foreign_keys fk
        WHERE OBJECT_SCHEMA_NAME(fk.referenced_object_id) NOT IN ('dba', 'sys')
    ),
    -- Find both child and parent supporting tables that have relationships with transaction tables
    SupportingTableRelationships AS (
        -- Tables that reference transaction tables (child tables)
        SELECT
            OBJECT_SCHEMA_NAME(fk.parent_object_id) AS SupportingSchema,
            OBJECT_NAME(fk.parent_object_id) AS SupportingTable,
            STRING_AGG(
                QUOTENAME(tt.SchemaName) + '.' + QUOTENAME(tt.TableName),
                ', '
            ) WITHIN GROUP (ORDER BY tt.SchemaName, tt.TableName) AS RelatedTables,
            STRING_AGG(
                QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + '.' +
                QUOTENAME(OBJECT_NAME(fk.parent_object_id)) + ' -> ' +
                QUOTENAME(tt.SchemaName) + '.' + QUOTENAME(tt.TableName),
                ', '
            ) WITHIN GROUP (ORDER BY tt.SchemaName, tt.TableName) AS Paths
        FROM sys.foreign_keys fk
        INNER JOIN TransactionTables tt
            ON OBJECT_SCHEMA_NAME(fk.referenced_object_id) = tt.SchemaName
            AND OBJECT_NAME(fk.referenced_object_id) = tt.TableName
        WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) NOT IN ('dba', 'sys')
        GROUP BY fk.parent_object_id

        UNION

        -- Tables that are referenced by transaction tables (parent tables)
        SELECT
            OBJECT_SCHEMA_NAME(fk.referenced_object_id),
            OBJECT_NAME(fk.referenced_object_id),
            STRING_AGG(
                QUOTENAME(tt.SchemaName) + '.' + QUOTENAME(tt.TableName),
                ', '
            ) WITHIN GROUP (ORDER BY tt.SchemaName, tt.TableName),
            STRING_AGG(
                QUOTENAME(tt.SchemaName) + '.' + QUOTENAME(tt.TableName) +
                ' -> ' +
                QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) + '.' +
                QUOTENAME(OBJECT_NAME(fk.referenced_object_id)),
                ', '
            ) WITHIN GROUP (ORDER BY tt.SchemaName, tt.TableName)
        FROM sys.foreign_keys fk
        INNER JOIN TransactionTables tt
            ON OBJECT_SCHEMA_NAME(fk.parent_object_id) = tt.SchemaName
            AND OBJECT_NAME(fk.parent_object_id) = tt.TableName
        WHERE OBJECT_SCHEMA_NAME(fk.referenced_object_id) NOT IN ('dba', 'sys')
        GROUP BY fk.referenced_object_id
    )
    -- First classify tables that have relationships with transaction tables as supporting
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
        LastAnalyzed
    )
    SELECT
        t.SchemaName,
        t.TableName,
        'Supporting',
        t.TableSize,
        t.SuggestedDateColumn,
        JSON_ARRAY(str.RelatedTables),
        JSON_ARRAY(str.Paths),
        t.ReasonCodes,
        t.TotalScore,
        GETUTCDATE()
    FROM #TableAnalysis t
    INNER JOIN TablesWithRelationships twr
        ON t.SchemaName = twr.SchemaName
        AND t.TableName = twr.TableName
    INNER JOIN SupportingTableRelationships str
        ON t.SchemaName = str.SupportingSchema
        AND t.TableName = str.SupportingTable
    WHERE NOT EXISTS (
        SELECT 1
        FROM dba.TableClassification tc
        WHERE tc.SchemaName = t.SchemaName
        AND tc.TableName = t.TableName
    );

    -- Then classify remaining tables with relationships as full copy
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
        LastAnalyzed
    )
    SELECT
        t.SchemaName,
        t.TableName,
        'Full Copy',
        t.TableSize,
        t.SuggestedDateColumn,
        NULL,
        NULL,
        t.ReasonCodes,
        t.TotalScore,
        GETUTCDATE()
    FROM #TableAnalysis t
    INNER JOIN TablesWithRelationships twr
        ON t.SchemaName = twr.SchemaName
        AND t.TableName = twr.TableName
    WHERE NOT EXISTS (
        SELECT 1
        FROM dba.TableClassification tc
        WHERE tc.SchemaName = t.SchemaName
        AND tc.TableName = t.TableName
    );

    -- Insert remaining tables (those without relationships) as full copy
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
        GETUTCDATE()
    FROM #TableAnalysis t
    WHERE NOT EXISTS (
        -- Exclude tables that have relationships
        SELECT 1
        FROM TablesWithRelationships twr
        WHERE twr.SchemaName = t.SchemaName
        AND twr.TableName = t.TableName
    )
    AND NOT EXISTS (
        -- Exclude tables already classified
        SELECT 1
        FROM dba.TableClassification tc
        WHERE tc.SchemaName = t.SchemaName
        AND tc.TableName = t.TableName
    );

    -- Output results if debug mode
    IF @Debug = 1
    BEGIN
        -- First output all tables in the database
        SELECT 'DATABASE TABLE OVERVIEW' as Analysis;
        SELECT
            t.SchemaName,
            t.TableName,
            t.TableSize as [Row Count],
            t.DateColumns as [Date Columns],
            t.IndexedDateColumns as [Indexed Date Columns],
            CASE
                WHEN t.TableSize < @MinimumTransactionRows THEN 'Too small'
                WHEN t.DateColumns IS NULL THEN 'No dates'
                ELSE 'Potential'
            END as InitialStatus
        FROM #TableAnalysis t
        WHERE t.TableSize >= 100
        ORDER BY t.TableSize DESC;

        -- Output tables with transaction-like names
        SELECT 'POTENTIAL TRANSACTION TABLES BY NAME' as Analysis;
        SELECT
            t.SchemaName,
            t.TableName,
            t.TableSize as [Row Count],
            t.DateColumns as [Date Columns],
            t.NameScore as [Name Score]
        FROM #TableAnalysis t
        WHERE t.NameScore >= 0.20
        ORDER BY t.NameScore DESC, t.TableSize DESC;

        -- Output tables with date columns
        SELECT 'TABLES WITH DATE COLUMNS' as Analysis;
        SELECT
            t.SchemaName,
            t.TableName,
            t.TableSize as [Row Count],
            t.DateColumns as [Date Columns],
            t.IndexedDateColumns as [Indexed Date Columns],
            t.NameScore as [Name Score]
        FROM #TableAnalysis t
        WHERE t.DateColumns IS NOT NULL
        ORDER BY t.TableSize DESC;

        -- Output detailed analysis
        SELECT 'DETAILED TABLE ANALYSIS' as Analysis;
        SELECT
            t.SchemaName,
            t.TableName,
            t.TableSize as [Row Count],
            CASE WHEN t.DateColumns IS NOT NULL THEN N'Yes' ELSE N'No' END as [Has Date Columns],
            t.SuggestedDateColumn as [Date Column],
            t.NameScore as [Name Score],
            t.RecordScore as [Record Score],
            t.DateScore as [Date Score],
            t.RelationshipScore as [Relationship Score],
            t.ColumnScore as [Column Score],
            t.TotalScore as [Total Score],
            CASE
                WHEN t.TableSize < @MinimumTransactionRows THEN N'Too few rows'
                WHEN t.DateColumns IS NULL THEN N'No date columns'
                WHEN t.TotalScore < @ConfidenceThreshold THEN N'Low confidence'
                ELSE N'Meets criteria'
            END as [Status],
            t.DateColumns as [All Date Columns],
            t.IndexedDateColumns as [Indexed Date Columns],
            t.RelatedTables as [Related Tables],
            t.ReasonCodes as [Reason Codes]
        FROM #TableAnalysis t
        WHERE t.TableSize >= 100  -- Show all tables with at least 100 rows
        ORDER BY t.TotalScore DESC;

        -- Output potential transaction tables
        SELECT 'POTENTIAL TRANSACTION TABLES' as Analysis;
        SELECT
            t.SchemaName,
            t.TableName,
            t.TableSize as [Row Count],
            t.SuggestedDateColumn as [Date Column],
            t.NameScore as [Name Score],
            t.RecordScore as [Record Score],
            t.DateScore as [Date Score],
            t.RelationshipScore as [Relationship Score],
            t.ColumnScore as [Column Score],
            t.TotalScore as [Total Score],
            t.ReasonCodes as [Reason Codes]
        FROM #TableAnalysis t
        WHERE t.DateColumns IS NOT NULL
        AND t.TableSize >= @MinimumTransactionRows
        AND t.TotalScore >= (@ConfidenceThreshold * 0.8)  -- Show tables close to threshold
        ORDER BY t.TotalScore DESC;

        -- Output classification summary
        SELECT 'CLASSIFICATION SUMMARY' as Analysis;
        SELECT
            Classification,
            COUNT(*) as TableCount,
            AVG(TableSize) as AvgRecords,
            AVG(ConfidenceScore) as AvgConfidence
        FROM dba.TableClassification
        GROUP BY Classification
        ORDER BY TableCount DESC;

        -- Output transaction tables
        SELECT 'IDENTIFIED TRANSACTION TABLES' as Analysis;
        SELECT
            SchemaName,
            TableName,
            Classification,
            TableSize,
            DateColumnName,
            ConfidenceScore,
            ReasonCodes
        FROM dba.TableClassification
        WHERE Classification = 'Transaction'
        ORDER BY ConfidenceScore DESC;

        -- Output supporting tables
        SELECT 'IDENTIFIED SUPPORTING TABLES' as Analysis;
        SELECT
            SchemaName,
            TableName,
            Classification,
            TableSize,
            DateColumnName,
            RelatedTransactionTables,
            RelationshipPaths
        FROM dba.TableClassification
        WHERE Classification = 'Supporting'
        ORDER BY TableSize DESC;

        -- Output detailed scoring analysis for all tables
        -- This helps identify why tables aren't being classified as expected:
        -- 1. Row Count: Must be >= @MinimumTransactionRows (100)
        -- 2. Has Date Columns: Must be 'Yes' to be a transaction table
        -- 3. Total Score: Must be >= @ConfidenceThreshold (0.60)
        --    - Name Score: Up to 0.20 for transaction-like names
        --    - Record Score: Up to 0.30 based on row count
        --    - Date Score: Up to 0.25 for date columns (0.25 if indexed, 0.15 if not)
        --    - Relationship Score: Up to 0.15 based on FK relationships
        --    - Column Score: Up to 0.10 for transaction-like column names
        SELECT
            t.SchemaName,
            t.TableName,
            t.TableSize as [Row Count],
            CASE WHEN t.DateColumns IS NOT NULL THEN N'Yes' ELSE N'No' END as [Has Date Columns],
            t.SuggestedDateColumn as [Date Column],
            t.NameScore as [Name Score],
            t.RecordScore as [Record Score],
            t.DateScore as [Date Score],
            t.RelationshipScore as [Relationship Score],
            t.ColumnScore as [Column Score],
            t.TotalScore as [Total Score],
            CASE
                WHEN t.TableSize < @MinimumTransactionRows THEN N'Too few rows'
                WHEN t.DateColumns IS NULL THEN N'No date columns'
                WHEN t.TotalScore < @ConfidenceThreshold THEN N'Low confidence'
                ELSE N'Meets criteria'
            END as [Status],
            t.ReasonCodes as [Reason Codes]
        FROM #TableAnalysis t
        WHERE t.NameScore > 0  -- Show all tables with transaction-like names
        ORDER BY t.TotalScore DESC;
    END

    -- Cleanup
    DROP TABLE #TableAnalysis;
END;
GO