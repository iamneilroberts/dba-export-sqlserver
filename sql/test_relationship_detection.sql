-- Test script to verify automatic relationship detection
USE ExportTest;
GO

-- Clean up environment
EXEC ('USE ExportTest; ' + (SELECT STRING_AGG('DROP TABLE IF EXISTS ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ';', CHAR(13))
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.name NOT LIKE 'sys%'));
GO

-- Create test tables
CREATE TABLE dbo.Products (
    ProductID int IDENTITY(1,1) PRIMARY KEY,
    Name nvarchar(100),
    Price decimal(18,2),
    SKU nvarchar(50)
);

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
INSERT INTO dbo.Products (Name, Price, SKU)
VALUES 
    ('Widget A', 50.00, 'WID-A'),
    ('Widget B', 75.00, 'WID-B'),
    ('Widget C', 100.00, 'WID-C'),
    ('Gadget X', 150.00, 'GAD-X'),
    ('Gadget Y', 200.00, 'GAD-Y'),
    ('Gadget Z', 250.00, 'GAD-Z'),
    ('Tool 1', 300.00, 'TOOL-1'),
    ('Tool 2', 350.00, 'TOOL-2'),
    ('Tool 3', 400.00, 'TOOL-3'),
    ('Tool 4', 450.00, 'TOOL-4');

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

-- Configure export settings
DELETE FROM dba.ExportConfig;
DELETE FROM dba.TableRelationships;

INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate', 0),
    ('dbo', 'Products', 0, NULL, 1);  -- Force full export for Products
GO

-- Run export process
DECLARE @ExportID int;

PRINT 'Running export with automatic relationship detection...';
EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-02-01',
    @AnalyzeStructure = 1,
    @Debug = 1;

-- Get the ExportID
SELECT @ExportID = MAX(ExportID)
FROM dba.ExportLog
WHERE Status = 'Completed';

-- Verify detected relationships
PRINT CHAR(13) + CHAR(10) + 'Detected Relationships:';
SELECT 
    ParentSchema,
    ParentTable,
    ParentColumn,
    ChildSchema,
    ChildTable,
    ChildColumn,
    RelationshipLevel,
    RelationshipPath
FROM dba.TableRelationships
ORDER BY RelationshipLevel, ParentSchema, ParentTable;

-- Verify export completeness
PRINT CHAR(13) + CHAR(10) + 'Export Results:';
WITH TableStats AS (
    SELECT 
        OBJECT_SCHEMA_NAME(object_id) AS schema_name,
        name,
        SUM(row_count) AS TotalRows
    FROM sys.dm_db_partition_stats
    WHERE index_id < 2
    GROUP BY object_id, name
),
ExportStats AS (
    SELECT 
        t.name AS TableName,
        t.TotalRows,
        (
            SELECT COUNT(*)
            FROM (
                SELECT TOP 1 * 
                FROM sys.objects 
                WHERE name = 'Export_' + t.schema_name + '_' + t.name
            ) x
        ) AS HasExportTable,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM sys.objects 
                WHERE name = 'Export_' + t.schema_name + '_' + t.name
            ) THEN (
                SELECT COUNT(*)
                FROM (
                    SELECT *
                    FROM (
                        SELECT TOP 1 *
                        FROM sys.objects
                        WHERE name = 'Export_' + t.schema_name + '_' + t.name
                    ) x
                    CROSS APPLY (
                        SELECT COUNT(*) AS cnt
                        FROM dba.[Export_' + t.schema_name + '_' + t.name]
                        WHERE ExportID = @ExportID
                    ) c
                ) x
            )
            ELSE 0
        END AS ExportedRows,
        CASE 
            WHEN t.name = 'Products' THEN t.TotalRows  -- Should match total
            WHEN t.name = 'Orders' THEN 5              -- Orders in date range
            ELSE NULL                                  -- Varies based on relationships
        END AS ExpectedRows
    FROM TableStats t
    WHERE t.schema_name = 'dbo'
)
SELECT 
    TableName,
    TotalRows,
    CASE WHEN HasExportTable = 1 THEN 'Yes' ELSE 'No' END AS HasExportTable,
    ExportedRows,
    ExpectedRows,
    CASE 
        WHEN ExpectedRows IS NULL THEN 'N/A'
        WHEN ExportedRows = ExpectedRows THEN 'PASS'
        ELSE 'FAIL'
    END AS TestResult
FROM ExportStats
ORDER BY TableName;

-- Show validation results
PRINT CHAR(13) + CHAR(10) + 'Validation Results:';
SELECT 
    SchemaName + '.' + TableName AS TableName,
    ValidationType,
    Severity,
    Category,
    RecordCount,
    Details
FROM dba.ValidationResults
WHERE ExportID = @ExportID
ORDER BY 
    CASE Severity
        WHEN 'Error' THEN 1
        WHEN 'Warning' THEN 2
        ELSE 3
    END,
    SchemaName,
    TableName;
GO