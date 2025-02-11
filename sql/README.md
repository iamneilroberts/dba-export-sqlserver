# SQL Export System Setup

## Prerequisites
- SQL Server 2016 or later
- SQLCMD utility installed
- Appropriate database permissions (CREATE TABLE, CREATE PROCEDURE, etc.)

## Setup Process

The setup process uses SQLCMD to execute scripts in the correct order with proper dependency management. The main entry point is `setup_master.sql`.

### Running the Setup

1. Open a command prompt with access to sqlcmd
2. Navigate to the sql directory
3. Run the setup using:
```bash
sqlcmd -S <server_name> -d <database_name> -i setup_master.sql
```

Replace:
- `<server_name>` with your SQL Server instance name
- `<database_name>` with your target database name

For example:
```bash
sqlcmd -S localhost -d ExportTest -i setup_master.sql
```

### What Gets Created

The setup process will:
1. Create the `dba` schema if it doesn't exist
2. Create all required tables:
   - ExportConfig
   - TableRelationships
   - TableClassification
   - ExportTables
   - ExportColumns
   - ExportRelationships
   - ExportLog
   - ExportPerformance
   - ValidationResults
3. Create necessary indexes for performance
4. Create the ParentTableType user-defined type
5. Create all stored procedures in dependency order:
   - Base utilities (sp_Utilities, sp_TableAnalysis)
   - Analysis procedures (sp_AnalyzeDatabaseStructure, sp_AnalyzeTableRelationships, sp_UpdateTableClassification)
   - Parent table processing (sp_ParentTableProcessing)
   - Export table building (sp_BuildExportTables)
   - Validation procedures (sp_ValidationProcessing, sp_ValidateExportTables, sp_GenerateValidationReport)
   - Main export procedure (sp_ExportData)

### Verification

After setup completes, you can verify the installation by:
1. Checking for "Setup complete. All objects created." message
2. Running `setup_verify.sql` to confirm all objects exist
3. Running the test scripts in the following order:
   - test_table_classification.sql
   - test_relationship_detection.sql
   - test_export_pipeline.sql

### Troubleshooting

If you encounter errors:
1. Ensure SQLCMD is installed and in your PATH
2. Verify you have appropriate permissions on the target database
3. Check that all .sql files are in the correct locations
4. Review any error messages in the SQLCMD output

Common issues:
- Syntax errors in SQL editors for SQLCMD commands (`:r`) are normal and can be ignored
- If a stored procedure fails to create, check the corresponding .sql file exists
- If verification fails, ensure all scripts were run in the correct order