# Testing Transaction Table Analyzer on Large Database

## Step 1: Initial Analysis
```sql
-- Run analyzer in debug mode with low threshold to see all potential tables
EXEC dba.sp_AnalyzeTransactionTables
    @MinimumRows = 1,           -- Show all tables
    @ConfidenceThreshold = 0.1, -- Show more results
    @Debug = 1;
```

This will:
- Show all tables with their confidence scores
- Display detailed analysis for each table
- Reveal relationship patterns
- Identify date columns and indexes

## Step 2: Review High Confidence Tables
```sql
-- Focus on high confidence transaction tables
EXEC dba.sp_AnalyzeTransactionTables
    @MinimumRows = 1000,        -- Production threshold
    @ConfidenceThreshold = 0.7, -- High confidence only
    @GenerateScript = 1,        -- Generate config scripts
    @Debug = 1;
```

Look for:
- Tables with clear transaction patterns
- Proper date column indexing
- Strong relationship networks
- Business-relevant column patterns

## Step 3: Test Export Configuration
1. Start with a single high-confidence table:
```sql
-- Configure one table first
DELETE FROM dba.ExportConfig;
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport,
    ExportPriority
)
SELECT TOP 1
    SchemaName,
    TableName,
    1,
    SuggestedDateColumn,
    0,
    CAST(TotalScore * 10 AS int)
FROM #AnalysisResults
WHERE TotalScore >= 0.7
ORDER BY TotalScore DESC;

-- Test export with small date range
EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-01-07',  -- One week
    @Debug = 1;
```

2. Verify results:
- Check exported record counts
- Validate relationships
- Review performance metrics
- Analyze any validation warnings

## Step 4: Expand Testing
1. Add more transaction tables:
```sql
-- Add top 5 confident tables
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport,
    ExportPriority
)
SELECT TOP 5
    SchemaName,
    TableName,
    1,
    SuggestedDateColumn,
    0,
    CAST(TotalScore * 10 AS int)
FROM #AnalysisResults
WHERE TotalScore >= 0.7
AND NOT EXISTS (
    SELECT 1 
    FROM dba.ExportConfig e 
    WHERE e.SchemaName = SchemaName 
    AND e.TableName = TableName
)
ORDER BY TotalScore DESC;
```

2. Test with larger date range:
```sql
EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-01-31',  -- One month
    @Debug = 1;
```

## Step 5: Performance Testing
1. Test with production-like load:
```sql
EXEC dba.sp_ExportData
    @StartDate = '2023-01-01',
    @EndDate = '2024-01-01',  -- One year
    @Debug = 1;
```

2. Monitor:
- Export duration
- Memory usage
- CPU utilization
- I/O patterns

## Success Criteria

1. Analyzer Accuracy
- ≥90% accuracy for known transaction tables
- Correct date column identification
- Proper relationship detection
- Meaningful confidence scores

2. Export Performance
- Completes within acceptable time
- Maintains data consistency
- Handles relationships properly
- Generates valid export tables

3. Resource Usage
- Acceptable memory consumption
- Manageable I/O impact
- No blocking issues
- Clean error handling

## Rollback Plan

1. If issues occur:
```sql
-- Clear configuration
DELETE FROM dba.ExportConfig;

-- Drop export tables
EXEC dba.sp_CleanupExportTables;

-- Restore original configuration if needed
INSERT INTO dba.ExportConfig
SELECT * FROM dba.ExportConfig_Backup;
```

2. Document any issues:
- Performance bottlenecks
- Incorrect detections
- Relationship problems
- Resource constraints

Would you like me to help you execute this test plan on your database?