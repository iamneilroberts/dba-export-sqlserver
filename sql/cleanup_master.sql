-- Clean up all tables and start fresh
USE ExportTest;
GO

-- First drop all export tables
DECLARE @sql nvarchar(max) = '';
SELECT @sql = @sql + 'DROP TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ';'
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.name LIKE 'Export_%'
ORDER BY t.name DESC;  -- Ensure child tables are dropped first

IF LEN(@sql) > 0
    EXEC sp_executesql @sql;
GO

-- Drop existing test tables in correct order (child tables first)
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.CustomerNotes', 'U') IS NOT NULL DROP TABLE dbo.CustomerNotes;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

-- Drop stored procedures
IF OBJECT_ID('dba.sp_ValidateExportTables', 'P') IS NOT NULL DROP PROCEDURE dba.sp_ValidateExportTables;
IF OBJECT_ID('dba.sp_ValidationProcessing', 'P') IS NOT NULL DROP PROCEDURE dba.sp_ValidationProcessing;
IF OBJECT_ID('dba.sp_GenerateValidationReport', 'P') IS NOT NULL DROP PROCEDURE dba.sp_GenerateValidationReport;
IF OBJECT_ID('dba.sp_ExportData', 'P') IS NOT NULL DROP PROCEDURE dba.sp_ExportData;
IF OBJECT_ID('dba.sp_BuildExportTables', 'P') IS NOT NULL DROP PROCEDURE dba.sp_BuildExportTables;
IF OBJECT_ID('dba.sp_ProcessParentTables', 'P') IS NOT NULL DROP PROCEDURE dba.sp_ProcessParentTables;
IF OBJECT_ID('dba.sp_AnalyzeTableRelationships', 'P') IS NOT NULL DROP PROCEDURE dba.sp_AnalyzeTableRelationships;
IF OBJECT_ID('dba.sp_AnalyzeDatabaseStructure', 'P') IS NOT NULL DROP PROCEDURE dba.sp_AnalyzeDatabaseStructure;
IF OBJECT_ID('dba.sp_TableAnalysis', 'P') IS NOT NULL DROP PROCEDURE dba.sp_TableAnalysis;
IF OBJECT_ID('dba.sp_Utilities', 'P') IS NOT NULL DROP PROCEDURE dba.sp_Utilities;
GO

-- Drop user-defined types
IF TYPE_ID('dba.ParentTableType') IS NOT NULL DROP TYPE dba.ParentTableType;
GO

-- Drop foreign key constraints from system tables
DECLARE @sql nvarchar(max) = '';
SELECT @sql = @sql + 'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(parent_object_id)) + 
    ' DROP CONSTRAINT ' + QUOTENAME(name) + ';'
FROM sys.foreign_keys
WHERE referenced_object_id = OBJECT_ID('dba.ExportLog');

IF LEN(@sql) > 0
    EXEC sp_executesql @sql;
GO

-- Drop system tables in correct order
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