-- Create table type for parent table information if it doesn't exist
IF TYPE_ID('dba.ParentTableType') IS NOT NULL
    DROP TYPE dba.ParentTableType;
GO

CREATE TYPE dba.ParentTableType AS TABLE
(
    SchemaName nvarchar(128),
    TableName nvarchar(128),
    ChildSchema nvarchar(128),
    ChildTable nvarchar(128),
    ParentColumn nvarchar(128),
    ChildColumn nvarchar(128),
    DateColumn nvarchar(128)
);
GO