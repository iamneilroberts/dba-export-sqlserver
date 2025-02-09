# Test Plan: Automatic Relationship Detection

## Objective
Verify that the system can correctly detect and analyze table relationships without pre-populated relationship data.

## Test Steps

1. Clean Up Environment
   - Run cleanup_master.sql to drop all tables
   - Ensure TableRelationships table is empty

2. Create Test Environment
   - Create test tables:
     * Customers (CustomerID PK)
     * Orders (OrderID PK, CustomerID FK)
     * OrderItems (OrderItemID PK, OrderID FK)
     * CustomerNotes (NoteID PK, CustomerID FK)
     * Products (ProductID PK) - No relationships to other tables
   - Insert sample data
   - Configure Orders as transaction table with OrderDate
   - Configure Products for full export (ForceFullExport = 1)

3. Run Export Process
   ```sql
   EXEC dba.sp_ExportData
       @StartDate = '2024-01-01',
       @EndDate = '2024-02-01',
       @AnalyzeStructure = 1,
       @Debug = 1;
   ```

4. Verify Detected Relationships
   - Query TableRelationships to verify:
     * Orders -> OrderItems relationship
     * Customers -> Orders relationship
     * Customers -> CustomerNotes relationship
     * Products has no relationships
   - Check relationship levels are correct
   - Verify ParentColumn and ChildColumn are properly detected

5. Expected Results
   ```sql
   -- Check relationships
   SELECT 
       ParentSchema,
       ParentTable,
       ParentColumn,
       ChildSchema,
       ChildTable,
       ChildColumn,
       RelationshipLevel
   FROM dba.TableRelationships
   ORDER BY RelationshipLevel, ParentSchema, ParentTable;
   ```

   Expected output:
   ```
   ParentSchema  ParentTable  ParentColumn  ChildSchema  ChildTable    ChildColumn   Level
   -----------  -----------  ------------  -----------  -----------   ------------  ------
   dbo          Customers    CustomerID    dbo         Orders        CustomerID    1
   dbo          Customers    CustomerID    dbo         CustomerNotes CustomerID    1
   dbo          Orders       OrderID       dbo         OrderItems    OrderID       1
   ```

   ```sql
   -- Check export tables
   SELECT 
       t.name AS TableName,
       e.RowCount AS ExportedRows,
       t.RowCount AS TotalRows,
       CASE 
           WHEN t.name = 'Products' THEN t.RowCount  -- Should match total
           WHEN t.name = 'Orders' THEN 5             -- Orders in date range
           ELSE NULL                                 -- Varies based on relationships
       END AS ExpectedRows
   FROM (
       SELECT 
           OBJECT_SCHEMA_NAME(object_id) AS schema_name,
           name,
           SUM(row_count) AS RowCount
       FROM sys.dm_db_partition_stats
       WHERE index_id < 2
       GROUP BY object_id, name
   ) t
   CROSS APPLY (
       SELECT COUNT(*) AS RowCount
       FROM dba.[Export_' + t.schema_name + '_' + t.name]
       WHERE ExportID = @ExportID
   ) e
   WHERE t.schema_name = 'dbo'
   ORDER BY t.name;
   ```

   Expected output:
   ```
   TableName      ExportedRows TotalRows ExpectedRows
   -------------- ------------ --------- ------------
   CustomerNotes  4           6         4           -- Notes in date range
   Customers      3           4         3           -- Customers with data in range
   OrderItems     5           8         5           -- Items for Orders in range
   Orders         5           8         5           -- Orders in date range
   Products       10          10        10          -- All products exported
   ```

6. Verify Export Results
   - Check that OrderItems are properly filtered based on Orders date range
   - Verify no orphaned records in export tables
   - Confirm all related records are included
   - Verify Products table has all records exported

## Implementation Notes

1. Create test_relationship_detection.sql that:
   - Includes all cleanup steps
   - Creates test environment including Products table
   - Runs export process
   - Includes verification queries
   - Shows results in an easy to read format

2. Add debug output to show:
   - Relationship detection process
   - SQL used to detect relationships
   - Confidence scores for transaction table detection
   - Join clause generation
   - Full export table processing

Would you like me to switch to code mode to implement this test plan?