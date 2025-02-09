-- Clean up all tables and start fresh
USE ExportTest;
GO

-- Drop all export tables first
DECLARE @sql nvarchar(max) = '';
SELECT @sql = @sql + 'DROP TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ';'
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.name LIKE 'Export_%'
ORDER BY t.name DESC;  -- Ensure child tables are dropped first
IF LEN(@sql) > 0
    EXEC sp_executesql @sql;
GO

-- Drop existing tables in correct order (child tables first)
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.CustomerNotes', 'U') IS NOT NULL DROP TABLE dbo.CustomerNotes;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

-- Drop configuration tables in correct order (handle foreign key constraints)
-- First drop foreign key constraints
DECLARE @sql nvarchar(max) = '';
SELECT @sql = @sql + 'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(parent_object_id)) + 
    ' DROP CONSTRAINT ' + QUOTENAME(name) + ';'
FROM sys.foreign_keys
WHERE referenced_object_id = OBJECT_ID('dba.ExportLog');

IF LEN(@sql) > 0
    EXEC sp_executesql @sql;
GO

-- Now drop the tables in order
IF OBJECT_ID('dba.ValidationResults', 'U') IS NOT NULL DROP TABLE dba.ValidationResults;
IF OBJECT_ID('dba.ExportPerformance', 'U') IS NOT NULL DROP TABLE dba.ExportPerformance;
IF OBJECT_ID('dba.ExportLog', 'U') IS NOT NULL DROP TABLE dba.ExportLog;
IF OBJECT_ID('dba.TableRelationships', 'U') IS NOT NULL DROP TABLE dba.TableRelationships;
IF OBJECT_ID('dba.ExportConfig', 'U') IS NOT NULL DROP TABLE dba.ExportConfig;
GO

-- Drop schema if it exists and is empty
IF EXISTS (
    SELECT * 
    FROM sys.schemas 
    WHERE name = 'dba' 
    AND NOT EXISTS (
        SELECT * 
        FROM sys.objects 
        WHERE schema_id = schemas.schema_id
    )
)
    DROP SCHEMA dba;
GO