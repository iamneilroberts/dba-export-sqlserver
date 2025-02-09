-- Create schema if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dba')
BEGIN
    EXEC('CREATE SCHEMA dba')
END
GO

-- Drop tables if they exist (for clean setup)
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

-- Create relationship tracking table
CREATE TABLE dba.TableRelationships (
    RelationshipID int IDENTITY(1,1) PRIMARY KEY,
    ParentSchema nvarchar(128) NOT NULL,
    ParentTable nvarchar(128) NOT NULL,
    ChildSchema nvarchar(128) NOT NULL,
    ChildTable nvarchar(128) NOT NULL,
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

-- Create indexes for performance
CREATE INDEX IX_TableRelationships_Parent ON dba.TableRelationships (ParentSchema, ParentTable);
CREATE INDEX IX_TableRelationships_Child ON dba.TableRelationships (ChildSchema, ChildTable);
CREATE INDEX IX_ExportPerformance_ExportID ON dba.ExportPerformance (ExportID);
GO
