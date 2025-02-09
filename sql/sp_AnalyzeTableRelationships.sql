CREATE OR ALTER PROCEDURE dba.sp_AnalyzeTableRelationships
    @MaxRelationshipLevel int = 1,    -- Maximum levels of relationships to analyze
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
        ChildSchema nvarchar(128),
        ChildTable nvarchar(128),
        RelationshipLevel int,
        RelationshipPath nvarchar(max),
        Processed bit DEFAULT 0
    );

    -- Get all direct foreign key relationships
    INSERT INTO #RelationshipQueue (
        ParentSchema, 
        ParentTable, 
        ChildSchema, 
        ChildTable, 
        RelationshipLevel,
        RelationshipPath
    )
    SELECT 
        ps.name AS ParentSchema,
        pt.name AS ParentTable,
        cs.name AS ChildSchema,
        ct.name AS ChildTable,
        1 AS RelationshipLevel,
        CONCAT(
            ps.name, '.', pt.name, 
            ' -> ',
            cs.name, '.', ct.name
        ) AS RelationshipPath
    FROM sys.foreign_keys fk
    INNER JOIN sys.tables pt ON fk.referenced_object_id = pt.object_id
    INNER JOIN sys.schemas ps ON pt.schema_id = ps.schema_id
    INNER JOIN sys.tables ct ON fk.parent_object_id = ct.object_id
    INNER JOIN sys.schemas cs ON ct.schema_id = cs.schema_id
    WHERE 
        pt.is_ms_shipped = 0 
        AND ct.is_ms_shipped = 0;

    -- Process relationships level by level if recursive analysis is enabled
    WHILE @CurrentLevel < @MaxRelationshipLevel
    BEGIN
        -- Find next level relationships
        INSERT INTO #RelationshipQueue (
            ParentSchema, 
            ParentTable, 
            ChildSchema, 
            ChildTable, 
            RelationshipLevel,
            RelationshipPath
        )
        SELECT DISTINCT
            r.ParentSchema,
            r.ParentTable,
            cs.name,
            ct.name,
            @CurrentLevel + 1,
            CONCAT(
                r.RelationshipPath,
                ' -> ',
                cs.name, '.', ct.name
            )
        FROM #RelationshipQueue r
        INNER JOIN sys.tables pt ON pt.name = r.ChildTable
        INNER JOIN sys.schemas ps ON ps.name = r.ChildSchema AND pt.schema_id = ps.schema_id
        INNER JOIN sys.foreign_keys fk ON fk.referenced_object_id = pt.object_id
        INNER JOIN sys.tables ct ON fk.parent_object_id = ct.object_id
        INNER JOIN sys.schemas cs ON ct.schema_id = cs.schema_id
        WHERE 
            r.RelationshipLevel = @CurrentLevel
            AND ct.is_ms_shipped = 0
            AND NOT EXISTS (
                -- Avoid cycles
                SELECT 1 
                FROM #RelationshipQueue existing
                WHERE existing.ParentSchema = r.ParentSchema
                AND existing.ParentTable = r.ParentTable
                AND existing.ChildSchema = cs.name
                AND existing.ChildTable = ct.name
            );

        -- Exit if no new relationships found
        IF @@ROWCOUNT = 0 BREAK;

        SET @CurrentLevel = @CurrentLevel + 1;
    END

    -- Insert relationships into permanent table
    INSERT INTO dba.TableRelationships (
        ParentSchema,
        ParentTable,
        ChildSchema,
        ChildTable,
        RelationshipLevel,
        RelationshipPath,
        IsActive
    )
    SELECT DISTINCT
        ParentSchema,
        ParentTable,
        ChildSchema,
        ChildTable,
        RelationshipLevel,
        RelationshipPath,
        1 AS IsActive
    FROM #RelationshipQueue;

    -- Debug output
    IF @Debug = 1
    BEGIN
        -- Output relationship summary
        SELECT 
            RelationshipLevel,
            COUNT(*) as RelationshipCount,
            STRING_AGG(
                CONCAT(
                    ParentSchema, '.', ParentTable, 
                    ' -> ',
                    ChildSchema, '.', ChildTable
                ),
                CHAR(13) + CHAR(10)
            ) AS Relationships
        FROM dba.TableRelationships
        GROUP BY RelationshipLevel
        ORDER BY RelationshipLevel;

        -- Output relationship paths for each level
        DECLARE @Level int = 1;
        WHILE @Level <= @MaxRelationshipLevel
        BEGIN
            SET @msg = CONCAT(
                'Level ', @Level, ' Relationships:', CHAR(13), CHAR(10),
                '----------------------------------------'
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;

            SELECT @msg = STRING_AGG(RelationshipPath, CHAR(13) + CHAR(10))
            FROM dba.TableRelationships
            WHERE RelationshipLevel = @Level;

            IF @msg IS NOT NULL
                RAISERROR(@msg, 0, 1) WITH NOWAIT;

            SET @Level = @Level + 1;
        END
    END

    -- Return relationship summary
    SELECT 
        tr.ParentSchema,
        tr.ParentTable,
        tr.ChildSchema,
        tr.ChildTable,
        tr.RelationshipLevel,
        tr.RelationshipPath,
        CASE 
            WHEN ec.IsTransactionTable = 1 THEN 'Transaction Table'
            ELSE 'Related Table'
        END AS ParentTableType,
        ec.DateColumnName AS ParentDateColumn
    FROM dba.TableRelationships tr
    LEFT JOIN dba.ExportConfig ec 
        ON tr.ParentSchema = ec.SchemaName 
        AND tr.ParentTable = ec.TableName
    ORDER BY 
        tr.RelationshipLevel,
        tr.ParentSchema,
        tr.ParentTable,
        tr.ChildSchema,
        tr.ChildTable;

    -- Cleanup
    DROP TABLE #RelationshipQueue;
END;
GO
