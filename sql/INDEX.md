# SQL Scripts Index

This document provides an overview of all SQL scripts in the DateExport project, their purposes, and the database objects they create or modify.

## Core System Scripts

### Initial Setup
- **File:** `initial_setup.sql`
- **Purpose:** Initial database and schema creation
- **Objects Created:**
  - ExportTest database
  - dba schema

## Core Stored Procedures

### Database Structure Analysis
- **File:** `sp_AnalyzeDatabaseStructure.sql`
- **Purpose:** Main procedure for analyzing database structure and identifying transaction tables
- **Objects Created:**
  - dba.sp_AnalyzeDatabaseStructure
- **Features:**
  - Automated transaction table detection
  - Confidence scoring based on multiple factors
  - Parent table identification
  - Comprehensive analysis reporting

### Date Column Analysis
- **File:** `sp_AnalyzeDateColumns.sql`
- **Purpose:** Analyzes and identifies date-based columns for export criteria
- **Objects Created:**
  - dba.sp_AnalyzeDateColumns
- **Features:**
  - Date column pattern recognition
  - Index analysis for performance
  - Date format validation

### Table Relationships
- **File:** `sp_AnalyzeTableRelationships.sql`
- **Purpose:** Maps and manages table relationships
- **Objects Created:**
  - dba.sp_AnalyzeTableRelationships
- **Features:**
  - Foreign key relationship detection
  - Relationship depth analysis
  - Circular reference detection

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

### Export Table Building
- **File:** `sp_BuildExportTables.sql`
- **Purpose:** Creates and populates export tables
- **Objects Created:**
  - dba.sp_BuildExportTables
- **Dependencies:**
  - sp_ProcessParentTables
  - sp_ProcessRelatedTables

### Export Processing Control
- **File:** `sp_ExportProcessing.sql`
- **Purpose:** Manages the export process workflow
- **Objects Created:**
  - dba.sp_ExportProcessing
- **Features:**
  - Progress tracking
  - Error handling
  - Performance monitoring

## Relationship Management

### Manual Relationship Management
- **File:** `sp_RelationshipManagement.sql`
- **Purpose:** Manages manual table relationships
- **Objects Created:**
  - dba.sp_ManageRelationship
  - dba.vw_ActiveManualRelationships
- **Features:**
  - Add/Update/Remove relationships
  - Relationship validation
  - Active relationship tracking

## Table Processing

### Parent Table Types
- **File:** `sp_ParentTableTypes.sql`
- **Purpose:** Defines table types for parent table processing
- **Objects Created:**
  - dba.ParentTableType (User-Defined Table Type)

### Parent Table Processing
- **File:** `sp_ProcessParentTables.sql`
- **Purpose:** Handles parent table exports
- **Objects Created:**
  - dba.sp_ProcessParentTables
- **Dependencies:**
  - ParentTableType

### Related Table Processing
- **File:** `sp_ProcessRelatedTables.sql`
- **Purpose:** Processes tables related to transaction tables
- **Objects Created:**
  - dba.sp_ProcessRelatedTables

## Table Classification

### Table Classification
- **File:** `sp_TableClassification.sql`
- **Purpose:** Classifies tables based on their characteristics
- **Objects Created:**
  - dba.sp_TableClassification
- **Features:**
  - Pattern-based classification
  - Usage analysis
  - Data volume consideration

### Classification Updates
- **File:** `sp_UpdateTableClassification.sql`
- **Purpose:** Updates table classifications based on new data
- **Objects Created:**
  - dba.sp_UpdateTableClassification
- **Features:**
  - Classification refinement
  - Historical tracking
  - Change logging

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

## Testing

### Test Scripts
- **File:** `test_analyzer.sql`
- **Purpose:** Tests for the analysis system
- **Contents:**
  - Analysis procedure tests
  - Configuration validation
  - Performance testing

### Table Classification Tests
- **File:** `test_table_classification.sql`
- **Purpose:** Tests for the classification system
- **Contents:**
  - Classification accuracy tests
  - Pattern matching validation
  - Edge case handling

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

## Obsolete Scripts (Moved to /old)

The following scripts have been moved to the /old directory as they have been superseded by newer versions:

1. **sp_TableAnalysis.sql**
   - Replaced by: sp_AnalyzeDatabaseStructure.sql
   - Reason: Functionality consolidated into more robust implementation

2. **sp_AnalyzeTransactionTables.sql**
   - Replaced by: sp_AnalyzeDatabaseStructure.sql
   - Reason: Less comprehensive scoring system and lacks parent table detection

3. **sp_ManageRelationship.sql**
   - Replaced by: sp_RelationshipManagement.sql
   - Reason: Duplicate functionality