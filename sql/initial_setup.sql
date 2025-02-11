-- don't put USE statement here as the script will be executed in the context of the database where the script is run

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
IF OBJECT_ID('dba.sp_UpdateTableClassification', 'P') IS NOT NULL DROP PROCEDURE dba.sp_UpdateTableClassification;
IF OBJECT_ID('dba.sp_AnalyzeDatabaseStructure', 'P') IS NOT NULL DROP PROCEDURE dba.sp_AnalyzeDatabaseStructure;
IF OBJECT_ID('dba.sp_TableAnalysis', 'P') IS NOT NULL DROP PROCEDURE dba.sp_TableAnalysis;
IF OBJECT_ID('dba.sp_Utilities', 'P') IS NOT NULL DROP PROCEDURE dba.sp_Utilities;
IF OBJECT_ID('dba.sp_ManageRelationship', 'P') IS NOT NULL DROP PROCEDURE dba.sp_ManageRelationship;
IF OBJECT_ID('dba.sp_AnalyzeDateColumns', 'P') IS NOT NULL DROP PROCEDURE dba.sp_AnalyzeDateColumns;
GO

-- Drop existing user-defined types
IF TYPE_ID('dba.ParentTableType') IS NOT NULL DROP TYPE dba.ParentTableType;
GO

-- Drop existing tables in correct order (handle foreign key constraints)
IF OBJECT_ID('dba.ValidationResults', 'U') IS NOT NULL DROP TABLE dba.ValidationResults;
IF OBJECT_ID('dba.ExportPerformance', 'U') IS NOT NULL DROP TABLE dba.ExportPerformance;
IF OBJECT_ID('dba.ExportLog', 'U') IS NOT NULL DROP TABLE dba.ExportLog;
IF OBJECT_ID('dba.ExportRelationships', 'U') IS NOT NULL DROP TABLE dba.ExportRelationships;
IF OBJECT_ID('dba.ExportColumns', 'U') IS NOT NULL DROP TABLE dba.ExportColumns;
IF OBJECT_ID('dba.ExportTables', 'U') IS NOT NULL DROP TABLE dba.ExportTables;
IF OBJECT_ID('dba.IndexSuggestions', 'U') IS NOT NULL DROP TABLE dba.IndexSuggestions;
IF OBJECT_ID('dba.TableClassification', 'U') IS NOT NULL DROP TABLE dba.TableClassification;
IF OBJECT_ID('dba.ManualRelationships', 'U') IS NOT NULL DROP TABLE dba.ManualRelationships;
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
    IsExcluded bit NOT NULL DEFAULT 0,
    ExportPriority int NOT NULL DEFAULT 0,
    MaxRelationshipLevel int NOT NULL DEFAULT 1,
    BatchSize int NOT NULL DEFAULT 10000,
    CONSTRAINT UQ_ExportConfig_Table UNIQUE (SchemaName, TableName)
);
GO

-- Create manual relationship configuration table
CREATE TABLE dba.ManualRelationships (
    RelationshipId int IDENTITY(1,1) PRIMARY KEY,
    ParentSchema nvarchar(128) NOT NULL,
    ParentTable nvarchar(128) NOT NULL,
    ParentColumn nvarchar(128) NOT NULL,
    ChildSchema nvarchar(128) NOT NULL,
    ChildTable nvarchar(128) NOT NULL,
    ChildColumn nvarchar(128) NOT NULL,
    Description nvarchar(max),
    IsActive bit DEFAULT 1,
    CreatedDate datetime2 DEFAULT GETUTCDATE(),
    CreatedBy nvarchar(128) DEFAULT SYSTEM_USER,
    ModifiedDate datetime2 DEFAULT GETUTCDATE(),
    ModifiedBy nvarchar(128) DEFAULT SYSTEM_USER,
    CONSTRAINT UQ_ManualRelationships UNIQUE (
        ParentSchema, ParentTable, ParentColumn,
        ChildSchema, ChildTable, ChildColumn
    )
);
GO

-- Create relationship tracking table
CREATE TABLE dba.TableRelationships (
    RelationshipID int IDENTITY(1,1) PRIMARY KEY,
    ParentSchema nvarchar(128) NOT NULL,
    ParentTable nvarchar(128) NOT NULL,
    ParentColumn nvarchar(128) NOT NULL,
    ChildSchema nvarchar(128) NOT NULL,
    ChildTable nvarchar(128) NOT NULL,
    ChildColumn nvarchar(128) NOT NULL,
    RelationshipLevel int NOT NULL,
    RelationshipType varchar(50) NOT NULL,  -- Increased from varchar(20) to varchar(50)
    RelationshipPath nvarchar(max) NULL,
    IsActive bit NOT NULL DEFAULT 1,
    CONSTRAINT UQ_TableRelationships UNIQUE (
        ParentSchema, ParentTable, ParentColumn,
        ChildSchema, ChildTable, ChildColumn
    )
);
GO

-- Create table classification table
CREATE TABLE dba.TableClassification (
    SchemaName nvarchar(128) NOT NULL,
    TableName nvarchar(128) NOT NULL,
    Classification varchar(50) NOT NULL,
    TableSize int NOT NULL,
    ChangeFrequency decimal(5,2) NULL,
    DateColumnName nvarchar(128) NULL,
    RelatedTransactionTables nvarchar(max) NULL,
    RelationshipPaths nvarchar(max) NULL,
    ReasonCodes nvarchar(max) NULL,
    ConfidenceScore decimal(5,2) NULL,
    Priority int NOT NULL DEFAULT 100,
    LastAnalyzed datetime2 NOT NULL,
    PRIMARY KEY (SchemaName, TableName)
);
GO

-- Create index suggestions table
CREATE TABLE dba.IndexSuggestions (
    SuggestionId int IDENTITY(1,1) PRIMARY KEY,
    SchemaName nvarchar(128) NOT NULL,
    TableName nvarchar(128) NOT NULL,
    ColumnName nvarchar(128) NOT NULL,
    SuggestedIndexName nvarchar(128) NOT NULL,
    IndexDefinition nvarchar(max) NOT NULL,
    Reason nvarchar(max) NOT NULL,
    EstimatedImpact decimal(5,2) NOT NULL,
    IsImplemented bit DEFAULT 0,
    CreatedDate datetime2 DEFAULT GETUTCDATE(),
    ModifiedDate datetime2 DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_IndexSuggestions UNIQUE (
        SchemaName, TableName, ColumnName
    )
);
GO

-- Create export tables
CREATE TABLE dba.ExportTables (
    TableId int IDENTITY(1,1) PRIMARY KEY,
    SchemaName nvarchar(128) NOT NULL,
    TableName nvarchar(128) NOT NULL,
    IsTransactionTable bit NOT NULL DEFAULT 0,
    IsFullCopy bit NOT NULL DEFAULT 0,
    DateColumnName nvarchar(128) NULL,
    WhereClause nvarchar(max) NULL,
    ExportPriority int NOT NULL DEFAULT 0,
    CONSTRAINT UQ_ExportTables UNIQUE (SchemaName, TableName)
);
GO

CREATE TABLE dba.ExportColumns (
    ColumnId int IDENTITY(1,1) PRIMARY KEY,
    TableId int NOT NULL,
    ColumnName nvarchar(128) NOT NULL,
    DataType nvarchar(128) NOT NULL,
    IsNullable bit NOT NULL,
    IsIdentity bit NOT NULL,
    IsPrimaryKey bit NOT NULL,
    CONSTRAINT FK_ExportColumns_Table FOREIGN KEY (TableId) REFERENCES dba.ExportTables(TableId),
    CONSTRAINT UQ_ExportColumns UNIQUE (TableId, ColumnName)
);
GO

CREATE TABLE dba.ExportRelationships (
    RelationshipId int IDENTITY(1,1) PRIMARY KEY,
    ParentTableId int NOT NULL,
    ChildTableId int NOT NULL,
    ParentColumn nvarchar(128) NOT NULL,
    ChildColumn nvarchar(128) NOT NULL,
    CONSTRAINT FK_ExportRelationships_ParentTable FOREIGN KEY (ParentTableId) REFERENCES dba.ExportTables(TableId),
    CONSTRAINT FK_ExportRelationships_ChildTable FOREIGN KEY (ChildTableId) REFERENCES dba.ExportTables(TableId),
    CONSTRAINT UQ_ExportRelationships UNIQUE (ParentTableId, ChildTableId, ParentColumn, ChildColumn)
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
    TableSize int NULL,          -- Number of affected records
    Details nvarchar(max) NULL,    -- Detailed description or JSON with specific findings
    ValidationQuery nvarchar(max) NULL, -- The actual query used for validation
    CONSTRAINT FK_ValidationResults_ExportLog FOREIGN KEY (ExportID) REFERENCES dba.ExportLog(ExportID)
);
GO

-- Create indexes for performance
CREATE INDEX IX_TableRelationships_Parent ON dba.TableRelationships (ParentSchema, ParentTable);
CREATE INDEX IX_TableRelationships_Child ON dba.TableRelationships (ChildSchema, ChildTable);
CREATE INDEX IX_ManualRelationships_Parent ON dba.ManualRelationships (ParentSchema, ParentTable);
CREATE INDEX IX_ManualRelationships_Child ON dba.ManualRelationships (ChildSchema, ChildTable);
CREATE INDEX IX_IndexSuggestions_Table ON dba.IndexSuggestions (SchemaName, TableName);
CREATE INDEX IX_TableClassification_Priority ON dba.TableClassification (Priority);
CREATE INDEX IX_ExportTables_Types ON dba.ExportTables (IsTransactionTable, IsFullCopy);
CREATE INDEX IX_ExportColumns_TableId ON dba.ExportColumns (TableId);
CREATE INDEX IX_ExportRelationships_Parent ON dba.ExportRelationships (ParentTableId);
CREATE INDEX IX_ExportRelationships_Child ON dba.ExportRelationships (ChildTableId);
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
