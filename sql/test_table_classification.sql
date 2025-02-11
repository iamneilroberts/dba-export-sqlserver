USE ExportTest;
GO

-- Create test tables
CREATE TABLE dbo.Orders (
    OrderId int PRIMARY KEY,
    OrderDate datetime2 INDEX ix_orderdate NONCLUSTERED,
    CustomerId int,
    TotalAmount decimal(18,2),
    Status varchar(50)
);

CREATE TABLE dbo.OrderDetails (
    OrderDetailId int PRIMARY KEY,
    OrderId int FOREIGN KEY REFERENCES dbo.Orders(OrderId),
    ProductId int,
    Quantity int,
    UnitPrice decimal(18,2)
);

CREATE TABLE dbo.Customers (
    CustomerId int PRIMARY KEY,
    Name varchar(100),
    Email varchar(255)
);

-- Insert test data
INSERT INTO dbo.Customers (CustomerId, Name, Email)
SELECT 
    n,
    'Customer ' + CAST(n as varchar(10)),
    'customer' + CAST(n as varchar(10)) + '@test.com'
FROM (SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.objects a, sys.objects b) n(n);

INSERT INTO dbo.Orders (OrderId, OrderDate, CustomerId, TotalAmount, Status)
SELECT 
    n,
    DATEADD(day, -ABS(CHECKSUM(NEWID()) % 365), GETDATE()),
    ABS(CHECKSUM(NEWID()) % 1000) + 1,
    CAST(ABS(CHECKSUM(NEWID()) % 1000) as decimal(18,2)),
    CASE ABS(CHECKSUM(NEWID()) % 3)
        WHEN 0 THEN 'Pending'
        WHEN 1 THEN 'Processing'
        WHEN 2 THEN 'Completed'
    END
FROM (SELECT TOP 50000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.objects a, sys.objects b, sys.objects c) n(n);

INSERT INTO dbo.OrderDetails (OrderDetailId, OrderId, ProductId, Quantity, UnitPrice)
SELECT 
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    OrderId,
    ABS(CHECKSUM(NEWID()) % 100) + 1,
    ABS(CHECKSUM(NEWID()) % 10) + 1,
    CAST(ABS(CHECKSUM(NEWID()) % 100) as decimal(18,2))
FROM dbo.Orders
CROSS APPLY (SELECT TOP (ABS(CHECKSUM(NEWID()) % 5) + 1) 1 FROM sys.objects) n;

-- Run table classification
EXEC dba.sp_UpdateTableClassification 
    @MinimumTransactionRows = 10000,
    @ConfidenceThreshold = 0.60,
    @Debug = 1;

-- View results
SELECT 'Classification Summary' as Section;
SELECT * FROM dba.vw_TableClassificationSummary;

SELECT 'Transaction Tables' as Section;
SELECT * FROM dba.vw_TransactionTables;

SELECT 'Supporting Tables' as Section;
SELECT * FROM dba.vw_SupportingTables;

SELECT 'Full Copy Tables' as Section;
SELECT 
    SchemaName,
    TableName,
    RecordCount,
    DateColumnName,
    ConfidenceScore,
    ReasonCodes
FROM dba.TableClassification
WHERE Classification = 'Full Copy'
ORDER BY RecordCount DESC;

-- Cleanup test tables
DROP TABLE dbo.OrderDetails;
DROP TABLE dbo.Orders;
DROP TABLE dbo.Customers;