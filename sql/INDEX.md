# SQL Scripts Index

This document provides an overview of all SQL scripts in the DateExport project, their purposes, and the database objects they create or modify.

## Core System Scripts

### Initial Setup
- **File:** `initial_setup.sql`
- **Purpose:** Initial database and schema creation
- **Objects Created:**
  - ExportTest database
  - dba schema

### Setup Test Environment
- **File:** `setup_exporttest.sql`
- **Purpose:** Creates test database structure and sample data
- **Objects Created:**
  - Test tables (Customers, Orders, OrderItems, CustomerNotes)
  - Sample data
  - Initial configuration

## Core Stored Procedures

### Export Processing
- **File:** `sp_ExportData.sql`
- **Purpose:** Main export orchestration procedure
- **Objects Created:**
  - dba.sp_ExportData
- **Dependencies:**
  - sp_BuildExportTables
  - sp_ValidateExportTables
  - sp_AnalyzeDatabaseStructure
  - sp_AnalyzeTableRelationships

### Table Analysis
- **File:** `sp_AnalyzeDatabaseStructure.sql`
- **Purpose:** Analyzes database structure to identify transaction tables
- **Objects Created:**
  - dba.sp_AnalyzeDatabaseStructure

### Relationship Management
- **File:** `sp_AnalyzeTableRelationships.sql`
- **Purpose:** Maps and manages table relationships
- **Objects Created:**
  - dba.sp_AnalyzeTableRelationships

### Export Table Building
- **File:** `sp_BuildExportTables.sql`
- **Purpose:** Creates and populates export tables
- **Objects Created:**
  - dba.sp_BuildExportTables
- **Dependencies:**
  - sp_ProcessParentTables
  - sp_ProcessTransactionTables
  - sp_ProcessRelatedTables

## Parent Table Processing

### Parent Table Types
- **File:** `sp_ParentTableTypes.sql`
- **Purpose:** Defines table types for parent table processing
- **Objects Created:**
  - dba.ParentTableType (User-Defined Table Type)

### Parent Table Processing
- **File:** `sp_ParentTableProcessing.sql`
- **Purpose:** Handles parent table exports
- **Objects Created:**
  - dba.sp_ProcessParentTables
- **Dependencies:**
  - ParentTableType

## Validation System

### Export Validation
- **File:** `sp_ValidateExportTables.sql`
- **Purpose:** Validates export table integrity
- **Objects Created:**
  - dba.sp_ValidateExportTables

### Validation Processing
- **File:** `sp_ValidationProcessing.sql`
- **Purpose:** Handles validation result processing
- **Objects Created:**
  - dba.sp_ValidationProcessing

### Validation Reporting
- **File:** `sp_GenerateValidationReport.sql`
- **Purpose:** Generates validation reports
- **Objects Created:**
  - dba.sp_GenerateValidationReport

## Utility Scripts

### Utilities
- **File:** `sp_Utilities.sql`
- **Purpose:** Common utility functions
- **Objects Created:**
  - Various utility functions and procedures

### Cleanup
- **File:** `cleanup_master.sql`
- **Purpose:** Cleanup script for removing test data and resetting the system
- **Actions:**
  - Drops test tables
  - Cleans up export tables
  - Resets configuration

## Testing

### Test System
- **File:** `test_export_system.sql`
- **Purpose:** Test script with various export scenarios
- **Contents:**
  - Basic usage examples
  - Automatic analysis tests
  - Manual configuration tests
  - Validation report examples

## Best Practices for Maintaining This Index

1. **Update on Changes:**
   - Add new scripts immediately when created
   - Update dependencies when modified
   - Document breaking changes

2. **Script Organization:**
   - Keep scripts in logical groups
   - Maintain clear naming conventions
   - Document dependencies clearly

3. **Version Control:**
   - Include this index in version control
   - Update index with each pull request
   - Note major version changes

4. **Dependencies:**
   - List all dependencies for each script
   - Note required execution order
   - Document any configuration requirements