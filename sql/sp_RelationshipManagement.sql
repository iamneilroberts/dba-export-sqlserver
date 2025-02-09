-- Relationship management procedures for the DateExport system

CREATE OR ALTER PROCEDURE dba.sp_GetTableRelationships
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @RelationshipLevel int,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    WITH RelatedTables AS (
        SELECT DISTINCT
            OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ParentSchema,
            OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
            OBJECT_SCHEMA_NAME(fk.parent_object_id) AS ChildSchema,
            OBJECT_NAME(fk.parent_object_id) AS ChildTable,
            pc.name AS ParentColumn,
            cc.name AS ChildColumn
        FROM sys.foreign_keys fk
        INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN sys.columns pc ON 
            fkc.referenced_object_id = pc.object_id 
            AND fkc.referenced_column_id = pc.column_id
        INNER JOIN sys.columns cc ON 
            fkc.parent_object_id = cc.object_id 
            AND fkc.parent_column_id = cc.column_id
        WHERE 
            OBJECT_SCHEMA_NAME(fk.parent_object_id) = @SchemaName
            AND OBJECT_NAME(fk.parent_object_id) = @TableName
    )
    INSERT INTO dba.TableRelationships (
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        RelationshipLevel
    )
    SELECT 
        ParentSchema,
        ParentTable,
        ParentColumn,
        ChildSchema,
        ChildTable,
        ChildColumn,
        @RelationshipLevel
    FROM RelatedTables rt
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dba.TableRelationships tr
        WHERE tr.ParentSchema = rt.ParentSchema
        AND tr.ParentTable = rt.ParentTable
        AND tr.ChildSchema = rt.ChildSchema
        AND tr.ChildTable = rt.ChildTable
    );

    IF @Debug = 1
    BEGIN
        DECLARE @msg nvarchar(max) = CONCAT(
            'Found relationships for ', @SchemaName, '.', @TableName, ':', CHAR(13), CHAR(10),
            'Level: ', @RelationshipLevel, CHAR(13), CHAR(10),
            'Count: ', @@ROWCOUNT
        );
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_BuildRelationshipHierarchy
    @MaxRelationshipLevel int,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentLevel int = 1;
    DECLARE @TablesProcessed int;
    
    WHILE @CurrentLevel <= @MaxRelationshipLevel
    BEGIN
        IF @Debug = 1
        BEGIN
            DECLARE @msg nvarchar(max) = CONCAT(
                'Processing relationship level ', @CurrentLevel
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        SET @TablesProcessed = 0;

        -- Get tables at current level
        DECLARE @SchemaName nvarchar(128);
        DECLARE @TableName nvarchar(128);
        
        DECLARE table_cursor CURSOR FOR
        SELECT DISTINCT 
            tr.ChildSchema,
            tr.ChildTable
        FROM dba.TableRelationships tr
        WHERE tr.RelationshipLevel = @CurrentLevel - 1;

        OPEN table_cursor;
        FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dba.sp_GetTableRelationships
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @RelationshipLevel = @CurrentLevel,
                @Debug = @Debug;

            SET @TablesProcessed = @TablesProcessed + 1;
            FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;
        END

        CLOSE table_cursor;
        DEALLOCATE table_cursor;

        IF @Debug = 1
        BEGIN
            SET @msg = CONCAT(
                'Level ', @CurrentLevel, ' complete:', CHAR(13), CHAR(10),
                'Tables processed: ', @TablesProcessed
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        -- Stop if no new relationships found
        IF @TablesProcessed = 0 BREAK;

        SET @CurrentLevel = @CurrentLevel + 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_GenerateJoinClauses
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @ExportID int,
    @JoinClauses nvarchar(max) OUTPUT,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    WITH NumberedRelationships AS (
        SELECT 
            tr.ParentSchema,
            tr.ParentTable,
            tr.ParentColumn,
            tr.ChildColumn,
            ROW_NUMBER() OVER (ORDER BY tr.RelationshipLevel) as RowNum
        FROM dba.TableRelationships tr
        INNER JOIN dba.ExportConfig ec 
            ON tr.ParentSchema = ec.SchemaName 
            AND tr.ParentTable = ec.TableName
        WHERE tr.ChildSchema = @SchemaName
        AND tr.ChildTable = @TableName
        AND ec.IsTransactionTable = 1
    )
    SELECT @JoinClauses = STRING_AGG(
        'INNER JOIN ' + QUOTENAME(ParentSchema) + '.' + QUOTENAME(ParentTable) + ' p' + 
        CAST(RowNum AS varchar(10)) + ' ON p' + CAST(RowNum AS varchar(10)) + '.' + 
        QUOTENAME(ParentColumn) + ' = t.' + QUOTENAME(ChildColumn) + ' ' +
        'INNER JOIN [dba].[Export_' + ParentSchema + '_' + ParentTable + '] pe' + 
        CAST(RowNum AS varchar(10)) + ' ON pe' + CAST(RowNum AS varchar(10)) +
        '.SourceID = p' + CAST(RowNum AS varchar(10)) + '.' + QUOTENAME(ParentColumn) +
        ' AND pe' + CAST(RowNum AS varchar(10)) + '.ExportID = @ExportID',
        ' '
    )
    FROM NumberedRelationships;

    IF @Debug = 1 AND @JoinClauses IS NOT NULL
    BEGIN
        DECLARE @msg nvarchar(max) = CONCAT(
            'Generated join clauses for ', @SchemaName, '.', @TableName, ':', CHAR(13), CHAR(10),
            @JoinClauses
        );
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END
END;
GO
