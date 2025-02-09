-- Setup script for ExportTest database
USE ExportTest;
GO

-- Create schema if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dba')
BEGIN
    EXEC('CREATE SCHEMA dba')
END
GO

-- First drop foreign key constraints from ValidationResults and ExportPerformance
DECLARE @sql nvarchar(max) = '';
SELECT @sql = @sql + 'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(parent_object_id)) + 
    ' DROP CONSTRAINT ' + QUOTENAME(name) + ';'
FROM sys.foreign_keys
WHERE referenced_object_id = OBJECT_ID('dba.ExportLog');

IF LEN(@sql) > 0
    EXEC sp_executesql @sql;
GO

-- Drop existing configuration tables in correct order
IF OBJECT_ID('dba.ValidationResults', 'U') IS NOT NULL DROP TABLE dba.ValidationResults;
IF OBJECT_ID('dba.ExportPerformance', 'U') IS NOT NULL DROP TABLE dba.ExportPerformance;
IF OBJECT_ID('dba.ExportLog', 'U') IS NOT NULL DROP TABLE dba.ExportLog;
IF OBJECT_ID('dba.TableRelationships', 'U') IS NOT NULL DROP TABLE dba.TableRelationships;
IF OBJECT_ID('dba.ExportConfig', 'U') IS NOT NULL DROP TABLE dba.ExportConfig;
GO

-- Create configuration tables
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

CREATE TABLE dba.ExportLog (
    ExportID int IDENTITY(1,1) PRIMARY KEY,
    StartDate datetime NOT NULL DEFAULT GETDATE(),
    EndDate datetime NULL,
    Status nvarchar(50) NOT NULL,
    RowsProcessed int NULL,
    ErrorMessage nvarchar(max) NULL,
    Parameters nvarchar(max) NULL
);

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

-- Drop existing test tables in correct order (child tables first)
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.CustomerNotes', 'U') IS NOT NULL DROP TABLE dbo.CustomerNotes;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

-- Create test tables
CREATE TABLE dbo.Customers (
    CustomerID int IDENTITY(1,1) PRIMARY KEY,
    Name nvarchar(100),
    Email nvarchar(255),
    CreatedDate datetime DEFAULT GETDATE()
);

CREATE TABLE dbo.Orders (
    OrderID int IDENTITY(1,1) PRIMARY KEY,
    CustomerID int FOREIGN KEY REFERENCES dbo.Customers(CustomerID),
    OrderDate datetime DEFAULT GETDATE(),
    TotalAmount decimal(18,2)
);

CREATE TABLE dbo.OrderItems (
    OrderItemID int IDENTITY(1,1) PRIMARY KEY,
    OrderID int FOREIGN KEY REFERENCES dbo.Orders(OrderID),
    ProductName nvarchar(100),
    Quantity int,
    UnitPrice decimal(18,2)
);

CREATE TABLE dbo.CustomerNotes (
    NoteID int IDENTITY(1,1) PRIMARY KEY,
    CustomerID int FOREIGN KEY REFERENCES dbo.Customers(CustomerID),
    NoteDate datetime DEFAULT GETDATE(),
    Note nvarchar(max)
);

-- Insert test data
INSERT INTO dbo.Customers (Name, Email, CreatedDate)
VALUES 
    ('John Doe', 'john@example.com', '2023-01-01'),
    ('Jane Smith', 'jane@example.com', '2023-01-15'),
    ('Bob Wilson', 'bob@example.com', '2023-02-01'),
    ('Alice Brown', 'alice@example.com', '2023-03-01');

INSERT INTO dbo.Orders (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2024-01-15', 100.00),
    (1, '2024-02-01', 150.00),
    (2, '2024-01-20', 200.00),
    (3, '2024-01-25', 75.00),
    (2, '2024-02-05', 300.00),
    (4, '2023-12-15', 250.00),  -- Order before date range
    (4, '2024-02-15', 175.00),  -- Order after date range
    (1, '2024-01-31', 125.00);  -- Additional order within range

INSERT INTO dbo.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
VALUES
    (1, 'Widget A', 2, 50.00),
    (2, 'Widget B', 3, 50.00),
    (3, 'Widget C', 4, 50.00),
    (4, 'Widget A', 1, 75.00),
    (5, 'Widget B', 6, 50.00),
    (6, 'Widget C', 5, 50.00),  -- For order before range
    (7, 'Widget A', 3, 58.33),  -- For order after range
    (8, 'Widget B', 2, 62.50);  -- For additional order within range

INSERT INTO dbo.CustomerNotes (CustomerID, NoteDate, Note)
VALUES
    (1, '2024-01-15', 'First time customer'),
    (2, '2024-01-20', 'Preferred customer'),
    (3, '2024-01-25', 'Requires special handling'),
    (4, '2023-12-15', 'New customer referral'),  -- Note before date range
    (4, '2024-02-15', 'Follow-up required'),     -- Note after date range
    (1, '2024-01-31', 'Customer satisfaction verified'); -- Note within range

-- Create indexes on date columns
CREATE INDEX IX_Orders_OrderDate ON dbo.Orders(OrderDate);
CREATE INDEX IX_CustomerNotes_NoteDate ON dbo.CustomerNotes(NoteDate);
GO

-- Configure Orders as a transaction table
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate', 0);
GO