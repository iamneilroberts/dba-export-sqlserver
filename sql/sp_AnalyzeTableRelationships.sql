CREATE OR ALTER PROCEDURE dba.sp_AnalyzeTableRelationships
    @MaxRelationshipLevel int = 3,    -- Increased from 1 to 3
    @MaxTableRows int = NULL,         -- Maximum rows to consider per table
    @Debug bit = 0                    -- Enable debug output
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @msg nvarchar(max);
    DECLARE @CurrentLevel int = 1;

    -- Clear existing relationships
    DELETE FROM dba.TableRelationships;

    -- Create temp table for relationship processing
    CREATE TABLE #RelationshipQueue (
        ParentSchema nvarchar(128),
        ParentTable nvarchar(128),
        ParentColumn nvarchar(128),
        ChildSchema nvarchar(128),
        ChildTable nvarchar(128),
        ChildColumn nvarchar(128),
        RelationshipLevel int,
        RelationshipType varchar(50),
        RelationshipPath nvarchar(max),
        Processed bit DEFAULT 0
    );

    -- Get all direct foreign key relationships
    INSERT INTO #RelationshipQueue (
        ParentSchema, 
        ParentTable,
        ParentColumn,
        ChildSchema, 
        ChildTable,
        ChildColumn,
        RelationshipLevel,
        RelationshipType,
        RelationshipPath
    )
    SELECT 
        ps.name AS ParentSchema,
        pt.name AS ParentTable,
        pc.name AS ParentColumn,
        cs.name AS ChildSchema,
        ct.name AS ChildTable,
        cc.name AS ChildColumn,
        1 AS RelationshipLevel,
        'ForeignKey' AS RelationshipType,
        CONCAT(
            ps.name, '.', pt.name, '(', pc.name, ')',
            ' -> ',
            cs.name, '.', ct.name, '(', cc.name, ')'
        ) AS RelationshipPath
    FROM sys.foreign_keys fk
    INNER JOIN sys.tables pt ON fk.referenced_object_id = pt.object_id
    INNER JOIN sys.schemas ps ON pt.schema_id = ps.schema_id
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN sys.columns pc ON fkc.referenced_object_id = pc.object_id AND fkc.referenced_column_id = pc.column_id
    INNER JOIN sys.tables ct ON fk.parent_object_id = ct.object_id
    INNER JOIN sys.schemas cs ON ct.schema_id = cs.schema_id
    INNER JOIN sys.columns cc ON fkc.parent_object_id = cc.object_id AND fkc.parent_column_id = cc.column_id
    WHERE
        pt.is_ms_shipped = 0
        AND ct.is_ms_shipped = 0
        AND ps.name != 'dba'  -- Exclude DBA schema tables as parents
        AND cs.name != 'dba'  -- Exclude DBA schema tables as children
        AND (@MaxTableRows IS NULL OR (
            (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = pt.object_id AND p.index_id IN (0,1)) <= @MaxTableRows
            AND (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = ct.object_id AND p.index_id IN (0,1)) <= @MaxTableRows
        ));

    -- Add manual relationships
    INSERT INTO #RelationshipQueue (
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        RelationshipLevel,
        RelationshipType,
        RelationshipPath
    )
    SELECT
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        1 AS RelationshipLevel,
        'Manual' AS RelationshipType,
        CONCAT(
            ParentSchema, '.', ParentTable, '(', ParentColumn, ')',
            ' -> ',
            ChildSchema, '.', ChildTable, '(', ChildColumn, ')'
        ) AS RelationshipPath
    FROM dba.ManualRelationships
    WHERE IsActive = 1;

    -- Process relationships level by level if recursive analysis is enabled
    DECLARE @MaxIterations int = 1000; -- Safety limit
    DECLARE @IterationCount int = 0;
    
    WHILE @CurrentLevel < @MaxRelationshipLevel AND @IterationCount < @MaxIterations
    BEGIN
        SET @IterationCount = @IterationCount + 1;
        DECLARE @NewRelationships int = 0;
        DECLARE @ProcessedTables int = 0;
        
        IF @Debug = 1
            PRINT CONCAT('Processing level ', @CurrentLevel, ' (Iteration ', @IterationCount, ')');
        
        -- Find next level relationships through foreign keys
        INSERT INTO #RelationshipQueue (
            ParentSchema,
            ParentTable,
            ParentColumn,
            ChildSchema,
            ChildTable,
            ChildColumn,
            RelationshipLevel,
            RelationshipType,
            RelationshipPath
        )
        SELECT DISTINCT
            r.ParentSchema,
            r.ParentTable,
            r.ParentColumn,
            cs.name,
            ct.name,
            cc.name,
            @CurrentLevel + 1,
            'ForeignKey',
            CONCAT(
                r.RelationshipPath,
                ' -> ',
                cs.name, '.', ct.name, '(', cc.name, ')'
            )
        FROM #RelationshipQueue r
        INNER JOIN sys.tables pt ON pt.name = r.ChildTable
        INNER JOIN sys.schemas ps ON ps.name = r.ChildSchema AND pt.schema_id = ps.schema_id
        INNER JOIN sys.foreign_keys fk ON fk.referenced_object_id = pt.object_id
        INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN sys.columns cc ON fkc.parent_object_id = cc.object_id AND fkc.parent_column_id = cc.column_id
        INNER JOIN sys.tables ct ON fk.parent_object_id = ct.object_id
        INNER JOIN sys.schemas cs ON ct.schema_id = cs.schema_id
        WHERE
            r.RelationshipLevel = @CurrentLevel
            AND ct.is_ms_shipped = 0
            AND cs.name != 'dba' -- Exclude DBA schema tables from recursive relationships
            AND NOT EXISTS (
                -- Enhanced cycle detection
                SELECT 1
                FROM #RelationshipQueue existing
                WHERE (
                    -- Direct cycle check
                    (existing.ParentSchema = r.ParentSchema
                    AND existing.ParentTable = r.ParentTable
                    AND existing.ChildSchema = cs.name
                    AND existing.ChildTable = ct.name)
                    OR
                    -- Indirect cycle check through path
                    (existing.RelationshipPath LIKE CONCAT('%', cs.name, '.', ct.name, '%'))
                )
            );

        SET @ProcessedTables = @@ROWCOUNT;
        SET @NewRelationships = @NewRelationships + @ProcessedTables;

        IF @Debug = 1 AND @ProcessedTables > 0
            PRINT CONCAT('Added ', @ProcessedTables, ' new foreign key relationships');

        -- Find next level relationships through manual relationships
        INSERT INTO #RelationshipQueue (
            ParentSchema,
            ParentTable,
            ParentColumn,
            ChildSchema,
            ChildTable,
            ChildColumn,
            RelationshipLevel,
            RelationshipType,
            RelationshipPath
        )
        SELECT DISTINCT
            r.ParentSchema,
            r.ParentTable,
            r.ParentColumn,
            mr.ChildSchema,
            mr.ChildTable,
            mr.ChildColumn,
            @CurrentLevel + 1,
            'Manual',
            CONCAT(
                r.RelationshipPath,
                ' -> ',
                mr.ChildSchema, '.', mr.ChildTable, '(', mr.ChildColumn, ')'
            )
        FROM #RelationshipQueue r
        INNER JOIN dba.ManualRelationships mr ON 
            mr.ParentSchema = r.ChildSchema
            AND mr.ParentTable = r.ChildTable
        WHERE
            r.RelationshipLevel = @CurrentLevel
            AND mr.IsActive = 1
            AND NOT EXISTS (
                -- Avoid cycles
                SELECT 1 
                FROM #RelationshipQueue existing
                WHERE existing.ParentSchema = r.ParentSchema
                AND existing.ParentTable = r.ParentTable
                AND existing.ChildSchema = mr.ChildSchema
                AND existing.ChildTable = mr.ChildTable
            );

        SET @ProcessedTables = @@ROWCOUNT;
        SET @NewRelationships = @NewRelationships + @ProcessedTables;

        IF @Debug = 1 AND @ProcessedTables > 0
            PRINT CONCAT('Added ', @ProcessedTables, ' new manual relationships');

        -- Exit if no new relationships found at this level
        IF @NewRelationships = 0
        BEGIN
            IF @Debug = 1
                PRINT CONCAT('No new relationships found at level ', @CurrentLevel, '. Exiting...');
            BREAK;
        END

        -- Safety check - if we've found too many relationships, something might be wrong
        IF (SELECT COUNT(*) FROM #RelationshipQueue) > 10000
        BEGIN
            IF @Debug = 1
                PRINT 'Warning: Large number of relationships detected. Possible cycle. Exiting...';
            BREAK;
        END

        SET @CurrentLevel = @CurrentLevel + 1;
    END

    -- Insert relationships into permanent table
    -- First, create a temp table with deduplicated relationships
    CREATE TABLE #DedupedRelationships (
        ParentSchema nvarchar(128),
        ParentTable nvarchar(128),
        ParentColumn nvarchar(128),
        ChildSchema nvarchar(128),
        ChildTable nvarchar(128),
        ChildColumn nvarchar(128),
        RelationshipLevel int,
        RelationshipType varchar(50),
        RelationshipPath nvarchar(max)
    );

    -- Get deduplicated relationships with minimum level paths
    INSERT INTO #DedupedRelationships
    SELECT
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        MIN(RelationshipLevel) as RelationshipLevel,
        -- Take the first relationship type instead of concatenating all of them
        MIN(RelationshipType) as RelationshipType,
        MIN(RelationshipPath) as RelationshipPath
    FROM #RelationshipQueue
    GROUP BY
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn;

    -- Clear existing relationships
    TRUNCATE TABLE dba.TableRelationships;

    -- Insert deduplicated relationships
    INSERT INTO dba.TableRelationships (
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        RelationshipLevel,
        RelationshipType,
        RelationshipPath,
        IsActive
    )
    SELECT
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        RelationshipLevel,
        RelationshipType,
        RelationshipPath,
        1 AS IsActive
    FROM #DedupedRelationships;

    -- Debug output
    IF @Debug = 1
    BEGIN
        -- Output relationship summary by level and type
        DECLARE @Level int = 1;
        WHILE @Level <= @MaxRelationshipLevel
        BEGIN
            SELECT @msg = CONCAT(
                'Level ', @Level, ' Relationships (',
                (SELECT COUNT(*) FROM dba.TableRelationships WHERE RelationshipLevel = @Level),
                ' relationships found):', CHAR(13), CHAR(10),
                '----------------------------------------'
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;

            -- Output relationships for this level
            SELECT
                RelationshipType,
                RelationshipPath
            FROM dba.TableRelationships
            WHERE RelationshipLevel = @Level
            ORDER BY 
                RelationshipType,
                ParentSchema,
                ParentTable,
                ChildSchema,
                ChildTable;

            SET @Level = @Level + 1;
        END;

        -- Output relationship type summary
        SELECT
            RelationshipType,
            COUNT(*) as RelationshipCount,
            MIN(RelationshipLevel) as MinLevel,
            MAX(RelationshipLevel) as MaxLevel
        FROM dba.TableRelationships
        GROUP BY RelationshipType
        ORDER BY RelationshipCount DESC;
    END

    -- Return relationship summary
    SELECT 
        tr.ParentSchema,
        tr.ParentTable,
        tr.ParentColumn,
        tr.ChildSchema,
        tr.ChildTable,
        tr.ChildColumn,
        tr.RelationshipLevel,
        tr.RelationshipType,
        tr.RelationshipPath,
        CASE 
            WHEN tc.Classification = 'Transaction' THEN 'Transaction Table'
            WHEN tc.Classification = 'Supporting' THEN 'Supporting Table'
            ELSE 'Related Table'
        END AS ParentTableType,
        tc.DateColumnName AS ParentDateColumn
    FROM dba.TableRelationships tr
    LEFT JOIN dba.TableClassification tc
        ON tr.ParentSchema = tc.SchemaName 
        AND tr.ParentTable = tc.TableName
    ORDER BY 
        tr.RelationshipLevel,
        tr.RelationshipType,
        tr.ParentSchema,
        tr.ParentTable,
        tr.ChildSchema,
        tr.ChildTable;

    -- Cleanup
    DROP TABLE #RelationshipQueue;
    DROP TABLE #DedupedRelationships;
END;
GO
