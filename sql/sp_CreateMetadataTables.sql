-- Create metadata tables for improved export testing
CREATE OR ALTER PROCEDURE dba.sp_CreateMetadataTables
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Debug configuration table
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'DebugConfiguration' AND schema_id = SCHEMA_ID('dba'))
    BEGIN
        CREATE TABLE dba.DebugConfiguration
        (
            ConfigID int IDENTITY(1,1) PRIMARY KEY,
            CategoryName varchar(50) NOT NULL,
            OutputLevel varchar(20) NOT NULL 
                CONSTRAINT CK_DebugConfiguration_OutputLevel 
                CHECK (OutputLevel IN ('ERROR', 'WARN', 'INFO', 'DEBUG')),
            IsEnabled bit NOT NULL DEFAULT 1,
            MaxOutputRows int NULL,
            CreatedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            ModifiedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            CONSTRAINT UQ_DebugConfiguration_Category UNIQUE (CategoryName)
        );

        -- Insert default configuration
        INSERT INTO dba.DebugConfiguration (CategoryName, OutputLevel, IsEnabled, MaxOutputRows)
        VALUES 
            ('Relationships', 'WARN', 1, 1000),
            ('TableAnalysis', 'WARN', 1, 1000),
            ('Classification', 'WARN', 1, 1000),
            ('ExportTables', 'WARN', 1, 1000),
            ('Validation', 'WARN', 1, 1000);
    END

    -- Table classification history
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TableClassificationHistory' AND schema_id = SCHEMA_ID('dba'))
    BEGIN
        CREATE TABLE dba.TableClassificationHistory
        (
            HistoryID int IDENTITY(1,1) PRIMARY KEY,
            SchemaName nvarchar(128) NOT NULL,
            TableName nvarchar(128) NOT NULL,
            PreviousClassification varchar(50) NULL,
            NewClassification varchar(50) NOT NULL,
            DateColumnName nvarchar(128) NULL,
            ConfidenceScore decimal(5,2) NULL,
            ReasonCodes nvarchar(max) NULL,  -- JSON array of reason codes
            RelatedTables nvarchar(max) NULL, -- JSON array of related table info
            ChangedBy nvarchar(128) NOT NULL DEFAULT SYSTEM_USER,
            ChangedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            Notes nvarchar(max) NULL
        );

        CREATE INDEX IX_TableClassificationHistory_Table 
        ON dba.TableClassificationHistory (SchemaName, TableName);
        
        CREATE INDEX IX_TableClassificationHistory_Date 
        ON dba.TableClassificationHistory (ChangedDate);
    END

    -- Relationship tracking
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'RelationshipTypes' AND schema_id = SCHEMA_ID('dba'))
    BEGIN
        CREATE TABLE dba.RelationshipTypes
        (
            TypeID int IDENTITY(1,1) PRIMARY KEY,
            TypeName varchar(50) NOT NULL,
            Description nvarchar(max) NULL,
            Priority int NOT NULL DEFAULT 100,
            IsActive bit NOT NULL DEFAULT 1,
            CreatedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            ModifiedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            CONSTRAINT UQ_RelationshipTypes_Name UNIQUE (TypeName)
        );

        -- Insert default relationship types
        INSERT INTO dba.RelationshipTypes (TypeName, Description, Priority)
        VALUES 
            ('PrimaryForeignKey', 'Direct foreign key relationship', 100),
            ('SecondaryForeignKey', 'Indirect foreign key relationship through another table', 90),
            ('Manual', 'Manually defined relationship', 80),
            ('Logical', 'Logical relationship based on data patterns', 70);
    END

    -- Dual-role table tracking
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'DualRoleTables' AND schema_id = SCHEMA_ID('dba'))
    BEGIN
        CREATE TABLE dba.DualRoleTables
        (
            ConfigID int IDENTITY(1,1) PRIMARY KEY,
            SchemaName nvarchar(128) NOT NULL,
            TableName nvarchar(128) NOT NULL,
            PrimaryRole varchar(50) NOT NULL
                CONSTRAINT CK_DualRoleTables_PrimaryRole 
                CHECK (PrimaryRole IN ('Transaction', 'Supporting')),
            DateColumnName nvarchar(128) NULL,
            RelatedTransactionTables nvarchar(max) NULL, -- JSON array of related transaction tables
            RelatedSupportingTables nvarchar(max) NULL,  -- JSON array of related supporting tables
            ProcessingOrder int NOT NULL DEFAULT 100,
            IsActive bit NOT NULL DEFAULT 1,
            CreatedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            ModifiedDate datetime2 NOT NULL DEFAULT GETUTCDATE(),
            CONSTRAINT UQ_DualRoleTables_Table UNIQUE (SchemaName, TableName)
        );
    END

    -- Export processing log
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ExportProcessingLog' AND schema_id = SCHEMA_ID('dba'))
    BEGIN
        CREATE TABLE dba.ExportProcessingLog
        (
            LogID int IDENTITY(1,1) PRIMARY KEY,
            SchemaName nvarchar(128) NOT NULL,
            TableName nvarchar(128) NOT NULL,
            ProcessingPhase varchar(50) NOT NULL,
            StartTime datetime2 NOT NULL DEFAULT GETUTCDATE(),
            EndTime datetime2 NULL,
            RowsProcessed int NULL,
            RowsExported int NULL,
            Status varchar(20) NOT NULL
                CONSTRAINT CK_ExportProcessingLog_Status
                CHECK (Status IN ('Started', 'Completed', 'Failed', 'Skipped')),
            ErrorMessage nvarchar(max) NULL,
            Details nvarchar(max) NULL  -- JSON with additional processing details
        );

        CREATE INDEX IX_ExportProcessingLog_Table 
        ON dba.ExportProcessingLog (SchemaName, TableName);
        
        CREATE INDEX IX_ExportProcessingLog_Status 
        ON dba.ExportProcessingLog (Status);
        
        CREATE INDEX IX_ExportProcessingLog_Time 
        ON dba.ExportProcessingLog (StartTime);
    END
END;
GO