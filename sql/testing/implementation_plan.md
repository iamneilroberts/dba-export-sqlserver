# Database Export Testing Implementation Plan

## 1. Metadata Management

### New Stored Procedure: sp_InitializeMetadata
```sql
-- Key functionality:
- Clear existing metadata tables
- Initialize classification tracking
- Set up debug output configuration
- Create temporary testing tables
```

### Required Schema Changes
```sql
-- New table: dba.DebugConfiguration
- OutputLevel (ERROR, WARN, INFO, DEBUG)
- CategoryEnabled (Relationships, Analysis, Classification)
- MaxOutputRows

-- New table: dba.TableClassificationHistory
- Track changes in table classification
- Store reasoning for classification changes
```

## 2. Improved Table Classification

### Modify sp_AnalyzeDatabaseStructure
```sql
-- Changes needed:
1. Add weighted scoring system:
   - Table name patterns
   - Column patterns
   - Data patterns
   - Relationship patterns

2. Improve transaction table detection:
   - Check for date-based patterns
   - Analyze data distribution
   - Consider table relationships

3. Add dual-role table handling:
   - Flag tables that are both transaction and supporting
   - Track relationship dependencies
   - Special export handling logic
```

### Modify sp_AnalyzeTableRelationships
```sql
-- Changes needed:
1. Enhanced relationship tracking:
   - Track bidirectional relationships
   - Identify circular references
   - Handle multi-path relationships

2. Relationship classification:
   - Primary relationships (direct FK)
   - Secondary relationships (indirect)
   - Logical relationships (manual)

3. Improved cycle detection:
   - Track relationship paths
   - Identify and handle circular dependencies
   - Support relationship prioritization
```

## 3. Export Table Creation

### New Stored Procedure: sp_CreateExportTables
```sql
-- Key functionality:
1. Transaction tables:
   - Create based on date criteria
   - Handle multiple date columns
   - Support custom filters

2. Supporting tables:
   - Track relationship dependencies
   - Handle multi-level relationships
   - Maintain referential integrity

3. Dual-role tables:
   - Apply date criteria first
   - Add related IDs for referential integrity
   - Track source of each ID
```

## 4. Debug Output Control

### New Stored Procedure: sp_ConfigureDebugOutput
```sql
-- Key functionality:
1. Output levels:
   - ERROR: Always show
   - WARN: Show by default
   - INFO: Optional detailed info
   - DEBUG: Full debug output

2. Category control:
   - Relationship analysis
   - Table classification
   - Export table creation
   - Data validation

3. Output formatting:
   - Structured format
   - Support for different output types
   - Row count limits
```

## 5. Testing Framework

### New Stored Procedure: sp_RunExportTest
```sql
-- Key functionality:
1. Test phases:
   - Initialize metadata
   - Analyze relationships
   - Classify tables
   - Create export tables
   - Validate results

2. Validation checks:
   - Referential integrity
   - Date range compliance
   - Data completeness
   - Export size metrics

3. Output control:
   - Summary results
   - Detailed logs (optional)
   - Error reporting
```

## Implementation Order

1. Create new metadata tables and initialize procedure
2. Implement debug output control
3. Enhance relationship analysis
4. Improve table classification
5. Develop export table creation
6. Create testing framework
7. Add validation and reporting

## Success Criteria

1. Clean, minimal output by default
2. Accurate table classification
3. Proper handling of dual-role tables
4. Maintained referential integrity
5. Efficient export table creation
6. Clear error reporting
7. Comprehensive testing framework

## Migration Plan

1. Create new versions of procedures with '_v2' suffix
2. Test in parallel with existing procedures
3. Validate results match or improve upon current output
4. Switch to new versions after validation
5. Archive old versions for reference