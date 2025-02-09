-- Create schema if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dba')
BEGIN
    EXEC('CREATE SCHEMA dba')
END
GO

-- Drop existing stored procedures first
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

-- Drop existing user-defined types
IF TYPE_ID('dba.ParentTableType') IS NOT NULL DROP TYPE dba.ParentTableType;
GO

-- Drop existing tables in correct order (handle foreign key constraints)
IF OBJECT_ID('dba.ValidationResults', 'U') IS NOT NULL DROP TABLE dba.ValidationResults;
IF OBJECT_ID('dba.ExportPerformance', 'U') IS NOT NULL DROP TABLE dba.ExportPerformance;
IF OBJECT_ID('dba.ExportLog', 'U') IS NOT NULL DROP TABLE dba.ExportLog;
IF OBJECT_ID('dba.TableRelationships', 'U') IS NOT NULL DROP TABLE dba.TableRelationships;
IF OBJECT_ID('dba.ExportConfig', 'U') IS NOT NULL DROP TABLE dba.ExportConfig;
GO

-- Create configuration table
CREATE TABLE dba.ExportConfig (
    ConfigID int IDENTITY(1,1) PRIMARY KEY,
    TableName nvarchar(128) NOT NULL,
    SchemaName nvarchar(128) NOT NULL,
    IsTransactionTable bit NULL,
    DateColumnName nvarchar(128) NULL,
    ForceFullExport bit NOT NULL DEFAULT 0,
    ExportPriority int NOT NULL DEFAULT 0,
    MaxRelationshipLevel int NOT NULL DEFAULT 1,
    BatchSize int NOT NULL DEFAULT 10000,
    CONSTRAINT UQ_ExportConfig_Table UNIQUE (SchemaName, TableName)
);
GO

-- Create relationship tracking table with ParentColumn and ChildColumn
CREATE TABLE dba.TableRelationships (
    RelationshipID int IDENTITY(1,1) PRIMARY KEY,
    ParentSchema nvarchar(128) NOT NULL,
    ParentTable nvarchar(128) NOT NULL,
    ChildSchema nvarchar(128) NOT NULL,
    ChildTable nvarchar(128) NOT NULL,
    ParentColumn nvarchar(128) NULL,
    ChildColumn nvarchar(128) NULL,
    RelationshipLevel int NOT NULL,
    RelationshipPath nvarchar(max) NULL,
    IsActive bit NOT NULL DEFAULT 1,
    CONSTRAINT UQ_TableRelationships UNIQUE (ParentSchema, ParentTable, ChildSchema, ChildTable)
);
GO

-- Create logging table
CREATE TABLE dba.ExportLog (
    ExportID int IDENTITY(1,1) PRIMARY KEY,
    StartDate datetime NOT NULL DEFAULT GETDATE(),
    EndDate datetime NULL,
    Status nvarchar(50) NOT NULL,
    RowsProcessed int NULL,
    ErrorMessage nvarchar(max) NULL,
    Parameters nvarchar(max) NULL -- JSON string of export parameters
);
GO

-- Create performance monitoring table
CREATE TABLE dba.ExportPerformance (
    PerformanceID int IDENTITY(1,1) PRIMARY KEY,
    ExportID int NOT NULL,
    TableName nvarchar(128) NOT NULL,
    SchemaName nvarchar(128) NOT NULL,
    RowsProcessed int NOT NULL DEFAULT 0,
    ProcessingTime decimal(18,2) NOT NULL DEFAULT 0,
    RelationshipDepth int NOT NULL DEFAULT 0,
    BatchNumber int NOT NULL DEFAULT 0,
    StartTime datetime NOT NULL DEFAULT GETDATE(),
    EndTime datetime NULL,
    CONSTRAINT FK_ExportPerformance_ExportLog FOREIGN KEY (ExportID) REFERENCES dba.ExportLog(ExportID)
);
GO

-- Create validation results table
CREATE TABLE dba.ValidationResults (
    ValidationID int IDENTITY(1,1) PRIMARY KEY,
    ExportID int NOT NULL,
    ValidationTime datetime NOT NULL DEFAULT GETDATE(),
    SchemaName nvarchar(128) NOT NULL,
    TableName nvarchar(128) NOT NULL,
    ValidationType varchar(50) NOT NULL,
    Severity varchar(20) NOT NULL,  -- 'Error', 'Warning', or 'Info'
    Category varchar(50) NOT NULL,  -- 'Missing Table', 'Orphaned Records', 'Data Consistency', etc.
    RecordCount int NULL,          -- Number of affected records
    Details nvarchar(max) NULL,    -- Detailed description or JSON with specific findings
    ValidationQuery nvarchar(max) NULL, -- The actual query used for validation (useful for debugging)
    CONSTRAINT FK_ValidationResults_ExportLog FOREIGN KEY (ExportID) REFERENCES dba.ExportLog(ExportID)
);
GO

-- Create indexes for performance
CREATE INDEX IX_TableRelationships_Parent ON dba.TableRelationships (ParentSchema, ParentTable);
CREATE INDEX IX_TableRelationships_Child ON dba.TableRelationships (ChildSchema, ChildTable);
CREATE INDEX IX_ExportPerformance_ExportID ON dba.ExportPerformance (ExportID);
CREATE INDEX IX_ValidationResults_ExportID ON dba.ValidationResults (ExportID);
CREATE INDEX IX_ValidationResults_Table ON dba.ValidationResults (SchemaName, TableName);
CREATE INDEX IX_ValidationResults_Category ON dba.ValidationResults (Category, Severity);
CREATE INDEX IX_ValidationResults_Time ON dba.ValidationResults (ValidationTime);
GO

-- Create user-defined types
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

-- Create stored procedures in dependency order
-- 1. Base utilities and functions
PRINT 'Creating utility procedures...';
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_Utilities AS BEGIN SET NOCOUNT ON; END';
GO
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_TableAnalysis AS BEGIN SET NOCOUNT ON; END';
GO

-- 2. Analysis procedures
PRINT 'Creating analysis procedures...';
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_AnalyzeDatabaseStructure AS BEGIN SET NOCOUNT ON; END';
GO
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_AnalyzeTableRelationships AS BEGIN SET NOCOUNT ON; END';
GO

-- 3. Parent table processing
PRINT 'Creating parent table procedures...';
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_ProcessParentTables AS BEGIN SET NOCOUNT ON; END';
GO

-- 4. Export table building
PRINT 'Creating export table procedures...';
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_BuildExportTables AS BEGIN SET NOCOUNT ON; END';
GO

-- 5. Validation procedures
PRINT 'Creating validation procedures...';
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_ValidationProcessing AS BEGIN SET NOCOUNT ON; END';
GO
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_ValidateExportTables AS BEGIN SET NOCOUNT ON; END';
GO
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_GenerateValidationReport AS BEGIN SET NOCOUNT ON; END';
GO

-- 6. Main export procedure
PRINT 'Creating main export procedure...';
EXEC sp_executesql N'CREATE OR ALTER PROCEDURE dba.sp_ExportData AS BEGIN SET NOCOUNT ON; END';
GO

-- Now update the stored procedures with their actual implementations
PRINT 'Updating stored procedure implementations...';
