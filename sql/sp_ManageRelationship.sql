CREATE OR ALTER PROCEDURE dba.sp_ManageRelationship
    @Action varchar(10), -- 'ADD', 'UPDATE', 'REMOVE'
    @ParentSchema nvarchar(128),
    @ParentTable nvarchar(128),
    @ParentColumn nvarchar(128),
    @ChildSchema nvarchar(128),
    @ChildTable nvarchar(128),
    @ChildColumn nvarchar(128),
    @Description nvarchar(max) = NULL,
    @IsActive bit = 1,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate tables and columns exist
    DECLARE @ErrorMsg nvarchar(max);
    
    -- Check parent table
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.tables t
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = @ParentSchema AND t.name = @ParentTable
    )
    BEGIN
        SET @ErrorMsg = CONCAT('Parent table ', @ParentSchema, '.', @ParentTable, ' does not exist.');
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    -- Check child table
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.tables t
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = @ChildSchema AND t.name = @ChildTable
    )
    BEGIN
        SET @ErrorMsg = CONCAT('Child table ', @ChildSchema, '.', @ChildTable, ' does not exist.');
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    -- Check parent column
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns c
        JOIN sys.tables t ON c.object_id = t.object_id
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = @ParentSchema 
        AND t.name = @ParentTable 
        AND c.name = @ParentColumn
    )
    BEGIN
        SET @ErrorMsg = CONCAT('Column ', @ParentColumn, ' does not exist in parent table.');
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    -- Check child column
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns c
        JOIN sys.tables t ON c.object_id = t.object_id
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = @ChildSchema 
        AND t.name = @ChildTable 
        AND c.name = @ChildColumn
    )
    BEGIN
        SET @ErrorMsg = CONCAT('Column ', @ChildColumn, ' does not exist in child table.');
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    -- Perform requested action
    IF @Action = 'ADD'
    BEGIN
        IF EXISTS (
            SELECT 1 
            FROM dba.ManualRelationships
            WHERE ParentSchema = @ParentSchema
            AND ParentTable = @ParentTable
            AND ParentColumn = @ParentColumn
            AND ChildSchema = @ChildSchema
            AND ChildTable = @ChildTable
            AND ChildColumn = @ChildColumn
        )
        BEGIN
            SET @ErrorMsg = 'Relationship already exists.';
            RAISERROR(@ErrorMsg, 16, 1);
            RETURN;
        END

        INSERT INTO dba.ManualRelationships (
            ParentSchema, ParentTable, ParentColumn,
            ChildSchema, ChildTable, ChildColumn,
            Description, IsActive
        )
        VALUES (
            @ParentSchema, @ParentTable, @ParentColumn,
            @ChildSchema, @ChildTable, @ChildColumn,
            @Description, @IsActive
        );
    END
    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE dba.ManualRelationships
        SET Description = @Description,
            IsActive = @IsActive,
            ModifiedDate = GETUTCDATE(),
            ModifiedBy = SYSTEM_USER
        WHERE ParentSchema = @ParentSchema
        AND ParentTable = @ParentTable
        AND ParentColumn = @ParentColumn
        AND ChildSchema = @ChildSchema
        AND ChildTable = @ChildTable
        AND ChildColumn = @ChildColumn;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @ErrorMsg = 'Relationship not found.';
            RAISERROR(@ErrorMsg, 16, 1);
            RETURN;
        END
    END
    ELSE IF @Action = 'REMOVE'
    BEGIN
        DELETE FROM dba.ManualRelationships
        WHERE ParentSchema = @ParentSchema
        AND ParentTable = @ParentTable
        AND ParentColumn = @ParentColumn
        AND ChildSchema = @ChildSchema
        AND ChildTable = @ChildTable
        AND ChildColumn = @ChildColumn;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @ErrorMsg = 'Relationship not found.';
            RAISERROR(@ErrorMsg, 16, 1);
            RETURN;
        END
    END
    ELSE
    BEGIN
        SET @ErrorMsg = 'Invalid action. Use ADD, UPDATE, or REMOVE.';
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    -- Debug output
    IF @Debug = 1
    BEGIN
        SELECT 
            RelationshipId,
            ParentSchema,
            ParentTable,
            ParentColumn,
            ChildSchema,
            ChildTable,
            ChildColumn,
            Description,
            IsActive,
            CreatedDate,
            CreatedBy,
            ModifiedDate,
            ModifiedBy
        FROM dba.ManualRelationships
        WHERE ParentSchema = @ParentSchema
        AND ParentTable = @ParentTable
        AND ParentColumn = @ParentColumn
        AND ChildSchema = @ChildSchema
        AND ChildTable = @ChildTable
        AND ChildColumn = @ChildColumn;
    END
END;
GO

-- Create view for active manual relationships
CREATE OR ALTER VIEW dba.vw_ActiveManualRelationships
AS
SELECT
    RelationshipId,
    ParentSchema,
    ParentTable,
    ParentColumn,
    ChildSchema,
    ChildTable,
    ChildColumn,
    Description,
    CreatedDate,
    CreatedBy,
    ModifiedDate,
    ModifiedBy
FROM dba.ManualRelationships
WHERE IsActive = 1;
GO