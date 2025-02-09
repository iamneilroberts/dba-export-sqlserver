# Transaction Table Analyzer Test Plan

## Test Scenarios

### 1. Basic Transaction Tables
Test database with clear transaction tables:
```sql
-- Clear transaction patterns
Orders (OrderDate, Status, Amount)
Invoices (InvoiceDate, Status, Total)
Shipments (ShipDate, Status, TrackingNo)

-- Related tables
Customers
Products
Categories
```
Expected: High confidence scores for Orders, Invoices, Shipments

### 2. Mixed Patterns
Test database with less obvious patterns:
```sql
-- Transaction-like but not transactions
Customers (CreatedDate, ModifiedDate)
Products (LastUpdated)

-- Actual transactions with unclear names
TBL_123_MAIN (ProcessDate, Status)
DATA_RECORDS (EntryDate, Type)
```
Expected: Correctly identify real transaction tables despite naming

### 3. Complex Relationships
Test database with deep relationships:
```sql
-- Core tables
Projects
Tasks
TimeEntries (Date, Hours)

-- Related tables
ProjectMembers
TaskAssignments
TimeCategories
```
Expected: Identify TimeEntries as transaction table, suggest full export for lookup tables

### 4. Edge Cases

#### A. Empty Tables
```sql
EmptyOrders (OrderDate)
EmptyTransactions (TransDate)
```
Expected: Skip or low confidence due to no data patterns

#### B. System Tables
```sql
SystemLog (LogDate, Message)
AuditTrail (AuditDate, Action)
```
Expected: Identify as potential transaction tables but lower confidence

#### C. Staging Tables
```sql
STG_Orders (OrderDate)
TEMP_Transactions (TransDate)
```
Expected: Lower confidence due to staging/temp naming

### 5. Mixed Date Column Usage
```sql
-- Multiple date columns
Reservations (
    BookingDate,    -- Transaction date
    CheckInDate,    -- Business date
    ModifiedDate,   -- System date
    CreatedDate     -- Audit date
)
```
Expected: Correctly identify BookingDate as primary transaction date

## Test Cases

1. Basic Analysis
```sql
EXEC dba.sp_AnalyzeTransactionTables;
```
Verify:
- Correct identification of obvious transaction tables
- Appropriate confidence scores
- Suggested date columns

2. Low Threshold Analysis
```sql
EXEC dba.sp_AnalyzeTransactionTables
    @MinimumRows = 1,
    @ConfidenceThreshold = 0.3;
```
Verify:
- More tables identified
- Lower confidence scores included
- Clear reasoning for each suggestion

3. Debug Output Analysis
```sql
EXEC dba.sp_AnalyzeTransactionTables
    @Debug = 1;
```
Verify:
- Detailed analysis steps shown
- Scoring breakdowns visible
- Relationship analysis clear

4. Script Generation
```sql
EXEC dba.sp_AnalyzeTransactionTables
    @GenerateScript = 1;
```
Verify:
- Valid INSERT scripts generated
- Proper ordering of configurations
- Clear comments explaining choices

## Verification Queries

1. Check Confidence Scores
```sql
SELECT TOP 10
    SchemaName,
    TableName,
    ConfidenceScore,
    ReasonCodes
FROM #AnalysisResults
ORDER BY ConfidenceScore DESC;
```

2. Verify Date Column Selection
```sql
SELECT 
    TableName,
    DateColumns,
    SuggestedDateColumn,
    ReasonForSelection
FROM #AnalysisResults
WHERE DateColumns IS NOT NULL;
```

3. Check Relationship Analysis
```sql
SELECT 
    TableName,
    RelatedTables,
    RelationshipDepth,
    RelationshipScore
FROM #AnalysisResults
WHERE RelationshipScore > 0;
```

## Success Criteria

1. Accuracy
- ≥90% accuracy for clear transaction tables
- ≥70% accuracy for mixed pattern tables
- ≤10% false positives

2. Performance
- Analysis completes within 5 minutes for databases up to 100 tables
- Script generation adds minimal overhead

3. Usability
- Clear, actionable output
- Helpful debug information
- Valid, ready-to-use configuration scripts

4. Robustness
- Handles empty tables gracefully
- Manages large databases efficiently
- Provides useful results even with partial information

Would you like me to switch to code mode to implement the analyzer and these test cases?