USE ExportTest;
GO

-- Clean up any existing test tables
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.CustomerNotes', 'U') IS NOT NULL DROP TABLE dbo.CustomerNotes;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
IF OBJECT_ID('dbo.Products', 'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID('dbo.Categories', 'U') IS NOT NULL DROP TABLE dbo.Categories;
IF OBJECT_ID('dbo.TBL_123_MAIN', 'U') IS NOT NULL DROP TABLE dbo.TBL_123_MAIN;
IF OBJECT_ID('dbo.STG_Orders', 'U') IS NOT NULL DROP TABLE dbo.STG_Orders;
GO

-- Create schema if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dbo')
BEGIN
    EXEC('CREATE SCHEMA dbo');
END
GO

-- Create test tables with various patterns

-- Clear transaction pattern
CREATE TABLE dbo.Customers (
    CustomerID int IDENTITY(1,1) PRIMARY KEY,
    Name nvarchar(100),
    Email nvarchar(255),
    CreatedDate datetime DEFAULT GETDATE(),
    ModifiedDate datetime
);
GO

CREATE TABLE dbo.Orders (
    OrderID int IDENTITY(1,1) PRIMARY KEY,
    CustomerID int,
    OrderDate datetime,
    Status nvarchar(50),
    TotalAmount decimal(18,2),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID)
);
GO

CREATE INDEX IX_Orders_OrderDate ON dbo.Orders(OrderDate);
GO

-- Related tables
CREATE TABLE dbo.OrderItems (
    OrderItemID int IDENTITY(1,1) PRIMARY KEY,
    OrderID int,
    ProductID int,
    Quantity int,
    UnitPrice decimal(18,2),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID)
);
GO

CREATE TABLE dbo.Products (
    ProductID int IDENTITY(1,1) PRIMARY KEY,
    Name nvarchar(100),
    Price decimal(18,2),
    LastUpdated datetime
);
GO

-- Table with unclear name but transaction pattern
CREATE TABLE dbo.TBL_123_MAIN (
    ID int IDENTITY(1,1) PRIMARY KEY,
    ProcessDate datetime,
    Status nvarchar(50),
    Amount decimal(18,2)
);
GO

CREATE INDEX IX_TBL_123_MAIN_ProcessDate ON dbo.TBL_123_MAIN(ProcessDate);
GO

-- Staging table (should score low)
CREATE TABLE dbo.STG_Orders (
    OrderID int,
    OrderDate datetime,
    Amount decimal(18,2)
);
GO

-- Insert sample data
INSERT INTO dbo.Customers (Name, Email, CreatedDate, ModifiedDate)
VALUES 
    ('John Doe', 'john@example.com', '2023-01-01', '2024-01-15'),
    ('Jane Smith', 'jane@example.com', '2023-01-15', '2024-01-20'),
    ('Bob Wilson', 'bob@example.com', '2023-02-01', '2024-01-25');
GO

INSERT INTO dbo.Orders (CustomerID, OrderDate, Status, TotalAmount)
VALUES
    (1, '2024-01-15', 'Completed', 100.00),
    (1, '2024-02-01', 'Completed', 150.00),
    (2, '2024-01-20', 'Completed', 200.00),
    (3, '2024-01-25', 'Pending', 75.00),
    (2, '2024-02-05', 'Completed', 300.00);
GO

INSERT INTO dbo.Products (Name, Price, LastUpdated)
VALUES
    ('Widget A', 50.00, '2024-01-01'),
    ('Widget B', 75.00, '2024-01-15'),
    ('Widget C', 100.00, '2024-02-01');
GO

INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
VALUES
    (1, 1, 2, 50.00),
    (2, 2, 2, 75.00),
    (3, 3, 2, 100.00),
    (4, 1, 1, 75.00),
    (5, 2, 4, 75.00);
GO

INSERT INTO dbo.TBL_123_MAIN (ProcessDate, Status, Amount)
VALUES
    ('2024-01-15', 'Completed', 500.00),
    ('2024-01-20', 'Completed', 750.00),
    ('2024-02-01', 'Pending', 1000.00);
GO

INSERT INTO dbo.STG_Orders (OrderID, OrderDate, Amount)
VALUES
    (1, '2024-01-15', 100.00),
    (2, '2024-01-20', 200.00);
GO

-- Run analyzer with debug output
EXEC dba.sp_AnalyzeTransactionTables
    @MinimumRows = 1,           -- Low threshold for test data
    @ConfidenceThreshold = 0.3, -- Show more results
    @Debug = 1;
GO