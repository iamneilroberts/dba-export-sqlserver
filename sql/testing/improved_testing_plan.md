# Improved Database Export Testing Plan

## Goals
1. Reduce unnecessary debug output
2. Implement a clear step-by-step testing workflow
3. Ensure referential integrity while maintaining date-based filtering
4. Improve table classification accuracy

## Testing Workflow

### 1. Initial Setup
- Start with empty metadata tables in dba schema
- Clear any existing export tables
- Disable verbose debugging output unless specifically testing a stored procedure

### 2. Table Relationship Analysis
- Build and verify table relationships
- Output only the key relationship metrics:
  - Total relationships found
  - Relationship levels
  - Any circular references
  - Tables without relationships

### 3. Transaction Table Classification
First Pass:
- Analyze tables for transaction patterns
- Output only likely transaction table candidates with:
  - Table name
  - Date column(s)
  - Record count
  - Classification confidence score
- Generate UPDATE statements for user to mark transaction tables
- Allow user to review and execute appropriate UPDATE statements

### 4. Export Table Creation
- Create dba.Export* tables only for confirmed transaction tables
- Base export criteria on date columns
- Output only:
  - Tables processed
  - Number of IDs captured
  - Any errors encountered

### 5. Supporting Table Analysis
- Analyze relationships to transaction tables
- For each supporting table:
  - Check for relationships to transaction tables
  - Verify if IDs exist in transaction Export tables
  - Create corresponding Export table
  - Handle multi-level relationships (supporting tables of supporting tables)

### 6. Transaction-Supporting Table Handling
Special handling for tables that are both transaction and supporting:
1. First apply date criteria as a transaction table
2. Then check for additional IDs needed for referential integrity
3. Add any missing IDs to maintain relationships
4. Flag these tables in metadata for special processing

### 7. Full Copy Table Classification
Final pass to identify:
- Tables with no relationships
- Tables with low record counts
- Configuration/lookup tables
- Tables that would be complex to filter

## Testing Output Format

```sql
-- Example of desired output format
PRINT 'Phase: Table Relationship Analysis'
PRINT '================================='
PRINT 'Total Relationships: 123'
PRINT 'Max Relationship Level: 3'
PRINT 'Circular References Found: 0'

-- Only show detailed output when debugging
IF @Debug = 1
BEGIN
    -- Detailed relationship information
END
```

## Success Criteria
1. All transaction tables correctly identified
2. Referential integrity maintained
3. Date filtering applied where appropriate
4. Supporting tables properly linked
5. Full copy tables identified
6. Minimal unnecessary output

## Testing Validation
1. Compare row counts between source and export
2. Verify referential integrity
3. Validate date ranges in transaction tables
4. Check for orphaned records
5. Verify full copy table completeness

## Error Handling
- Clear error messages
- Specific error codes for different failure types
- Transaction rollback where appropriate
- Error logging with minimal output unless debugging

## Debugging Mode
When enabled (@Debug = 1):
- Full relationship details
- Table classification scoring
- Detailed processing steps
- SQL statements being executed
- Row counts and performance metrics