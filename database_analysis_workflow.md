# Database Analysis Workflow

## Approach Options

### 1. Automatic Analysis (Recommended First Step)
```sql
-- Run analyzer with debug output
EXEC dba.sp_AnalyzeTransactionTables
    @Debug = 1,
    @GenerateScript = 1;
```
- Reviews all database tables
- Identifies potential transaction tables
- Provides confidence scores and reasoning
- Generates configuration scripts
- Shows relationship analysis

### 2. Manual Configuration
```sql
-- Configure known transaction tables
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate');
```
- Direct configuration of known tables
- More control over export process
- Good for specific requirements

### 3. Hybrid Approach (Recommended)
1. Run automatic analysis first
2. Review suggestions and scores
3. Modify generated scripts as needed
4. Test with sample date range
5. Adjust configuration based on results

## Best Practices

1. Initial Analysis
   - Run analyzer with debug output
   - Review confidence scores
   - Check relationship analysis
   - Verify date column selections

2. Configuration Review
   - Verify suggested transaction tables
   - Check related table recommendations
   - Review date column selections
   - Consider business rules

3. Testing
   - Start with small date range
   - Verify exported data
   - Check relationship integrity
   - Validate data completeness

4. Refinement
   - Adjust configurations as needed
   - Add manual overrides if required
   - Document special cases
   - Update for new requirements

## Example Workflow

1. Run Initial Analysis
```sql
EXEC dba.sp_AnalyzeTransactionTables
    @MinimumRows = 100,
    @ConfidenceThreshold = 0.5,
    @Debug = 1,
    @GenerateScript = 1;
```

2. Review Results
- Check high confidence tables (>0.8)
- Review medium confidence tables (0.5-0.8)
- Note relationship patterns
- Verify date column selections

3. Apply Configuration
- Use generated scripts as starting point
- Modify based on business knowledge
- Add any missing tables
- Configure full export tables

4. Test Export
```sql
EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-01-31',
    @Debug = 1;
```

5. Validate Results
- Check export tables
- Verify relationships
- Confirm data completeness
- Review validation reports

## Maintenance

1. Regular Review
   - Run analyzer periodically
   - Check for new tables
   - Verify configuration still valid
   - Update as schema changes

2. Performance Monitoring
   - Track export times
   - Monitor row counts
   - Check relationship depth
   - Optimize as needed

3. Documentation
   - Keep configuration notes
   - Document special cases
   - Track schema changes
   - Maintain test cases

Would you like me to switch to code mode to implement the analyzer?