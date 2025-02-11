# Transaction Table Analyzer Feature

## Overview
Create a new stored procedure that analyzes a database to identify potential transaction tables and generates configuration scripts for the user.

## Analysis Criteria

1. Table Characteristics
   - Has datetime/date columns
   - Has indexed datetime columns
   - Table naming patterns (e.g., contains "Order", "Transaction", "Invoice")
   - Row count above threshold
   - Regular insert patterns (recent inserts)

2. Relationship Analysis
   - Tables with many child relationships likely contain core business data
   - Tables referenced by many other tables through foreign keys
   - Relationship depth and complexity

3. Column Analysis
   - Presence of common transaction columns:
     * Date/timestamp columns
     * Status columns
     * Amount/quantity columns
     * Reference number columns
   - Primary key structure
   - Foreign key relationships

4. Schema Analysis
   - Table location in schema hierarchy
   - Relationship to known system tables
   - Table and column naming conventions

## Implementation Plan

1. Create New Stored Procedure
```sql
CREATE PROCEDURE dba.sp_AnalyzeTransactionTables
    @MinimumRows int = 1000,              -- Minimum rows for consideration
    @ConfidenceThreshold decimal(5,2) = 0.5,  -- Minimum confidence score
    @GenerateScript bit = 1,              -- Generate INSERT scripts
    @Debug bit = 0                        -- Show analysis details
AS
```

2. Scoring System
   - Base score from table characteristics (40%)
     * DateTime columns: 10%
     * Indexed DateTime columns: 10%
     * Naming patterns: 10%
     * Row count/activity: 10%
   
   - Relationship score (30%)
     * Number of child tables: 10%
     * Relationship depth: 10%
     * Reference count: 10%
   
   - Column analysis score (30%)
     * Transaction-related columns: 15%
     * Key structure: 15%

3. Output Format
```sql
-- Analysis Results
SELECT 
    SchemaName,
    TableName,
    ConfidenceScore,
    ReasonCodes,
    DateColumns,
    RelatedTables,
    SuggestedDateColumn,
    GeneratedScript
FROM #AnalysisResults
WHERE ConfidenceScore >= @ConfidenceThreshold
ORDER BY ConfidenceScore DESC;
```

4. Generated Script Example
```sql
-- Generated Configuration Script
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport,
    ExportPriority
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate', 0, 10),        -- Score: 0.95
    ('dbo', 'Invoices', 1, 'InvoiceDate', 0, 10),    -- Score: 0.92
    ('dbo', 'Shipments', 1, 'ShipDate', 0, 8);       -- Score: 0.85

-- Related Tables (Consider for ForceFullExport)
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    ForceFullExport,
    ExportPriority
)
VALUES
    ('dbo', 'Products', 0, 1, 0),      -- Referenced by Orders
    ('dbo', 'Categories', 0, 1, 0);    -- Referenced by Products
```

5. Debug Output
```
Analyzing table: [dbo].[Orders]
- Found date columns: OrderDate (indexed), ModifiedDate
- Child tables: OrderItems, OrderNotes
- Transaction indicators:
  * Named like transaction table
  * Has date columns with indices
  * High relationship count
  * Contains typical columns (Date, Status, Amount)
Confidence score: 0.95
Suggested configuration: Use OrderDate as date column
```

## Usage Example

```sql
-- Basic analysis
EXEC dba.sp_AnalyzeTransactionTables;

-- Detailed analysis with lower threshold
EXEC dba.sp_AnalyzeTransactionTables
    @MinimumRows = 100,
    @ConfidenceThreshold = 0.3,
    @Debug = 1;

-- Generate configuration script
EXEC dba.sp_AnalyzeTransactionTables
    @GenerateScript = 1,
    @ConfidenceThreshold = 0.7;
```

## Benefits

1. Automated Discovery
   - Quickly analyze new databases
   - Identify potential transaction tables
   - Discover table relationships

2. Configuration Assistance
   - Generate ready-to-use configuration scripts
   - Provide confidence scores for decisions
   - Suggest related tables for full export

3. Documentation
   - Document analysis reasoning
   - Show relationship mappings
   - Explain configuration choices

4. Flexibility
   - Adjustable thresholds
   - Debug output for verification
   - Optional script generation

## Next Steps

1. Create sp_AnalyzeTransactionTables
2. Add detailed analysis logging
3. Create test cases with various database schemas
4. Add configuration script generation
5. Document usage patterns and best practices

Would you like me to proceed with implementing this analyzer?