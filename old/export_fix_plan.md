# Export System Fix Plan

## Current Issues

1. **Redundant Code**
   - initial_setup.sql and setup_exporttest.sql both create the same base tables
   - Cleanup code duplicated between cleanup_master.sql and setup_exporttest.sql
   - TableRelationships table definition inconsistent between scripts

2. **Missing Columns**
   - ParentColumn and ChildColumn missing from TableRelationships in initial_setup.sql
   - Causing errors in multiple stored procedures:
     - sp_ProcessParentTables
     - sp_GetTableRelationships
     - sp_GenerateJoinClauses
     - sp_ValidateRelationshipIntegrity

3. **Incomplete Initial Setup**
   - initial_setup.sql only creates tables and indexes
   - Should create all core database objects per INDEX.md

## Fix Plan

### 1. Restructure Initial Setup
- Move all base table creation to initial_setup.sql
- Include correct TableRelationships definition with ParentColumn/ChildColumn
- Add stored procedure creation
- Remove redundant table creation from setup_exporttest.sql

### 2. Clean Up Test Environment Setup
- Focus setup_exporttest.sql on test data and configuration only
- Remove redundant cleanup code
- Keep test table creation and sample data insertion
- Move cleanup code to cleanup_master.sql

### 3. Script Organization
- initial_setup.sql: Core database objects
- cleanup_master.sql: All cleanup operations
- setup_exporttest.sql: Test environment only

### 4. Testing Approach
Start with basic test using Orders table:
1. Run initial_setup.sql to create core objects
2. Run setup_exporttest.sql to create test environment
3. Execute sp_ExportData with Orders table
4. Verify exported data and relationships

## Implementation Steps

1. Update initial_setup.sql:
   - Add ParentColumn/ChildColumn to TableRelationships
   - Add stored procedure creation
   - Ensure all core objects are created

2. Clean up setup_exporttest.sql:
   - Remove redundant table creation
   - Keep only test-specific code
   - Update configuration for Orders table

3. Update cleanup_master.sql:
   - Consolidate cleanup operations
   - Ensure proper cleanup order
   - Add any missing cleanup steps

4. Verify stored procedures:
   - Confirm ParentColumn/ChildColumn usage
   - Test relationship management
   - Validate export process