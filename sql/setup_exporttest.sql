-- Setup script for ExportTest database
USE ExportTest;
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