-- Test script for DateExport system
USE ExportTest;
GO

-- Example 1: Basic Usage
-- This example demonstrates the basic usage of the export system
PRINT 'Example 1: Basic Usage';
PRINT '--------------------';

-- First, let's manually configure a transaction table
DELETE FROM dba.ExportConfig;
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate', 0);

-- Execute the export process
DECLARE @ExportID1 int;
INSERT INTO dba.ExportLog (StartDate, Status, Parameters)
VALUES (GETDATE(), 'Started', 
    (SELECT '2024-01-01' as startDate, '2024-02-01' as endDate, 1000 as batchSize FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
);
SET @ExportID1 = SCOPE_IDENTITY();

EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-02-01',
    @Debug = 1;

-- Example 2: Automatic Analysis
-- This example demonstrates the automatic analysis features
PRINT '';
PRINT 'Example 2: Automatic Analysis';
PRINT '-------------------------';

-- Clear previous configuration
DELETE FROM dba.ExportConfig;

-- Run export with automatic analysis
DECLARE @ExportID2 int;
INSERT INTO dba.ExportLog (StartDate, Status, Parameters)
VALUES (GETDATE(), 'Started', 
    (SELECT '2024-01-01' as startDate, '2024-02-01' as endDate, 1000 as batchSize FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
);
SET @ExportID2 = SCOPE_IDENTITY();

EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-02-01',
    @AnalyzeStructure = 1,
    @MaxRelationshipLevel = 2,
    @MinimumRows = 1,  -- Lower threshold for test data
    @ConfidenceThreshold = 0.5,  -- Lower threshold for test data
    @Debug = 1;

-- Example 3: Manual Configuration
-- This example demonstrates how to manually configure the export system
PRINT '';
PRINT 'Example 3: Manual Configuration';
PRINT '----------------------------';

-- Clear previous configuration
DELETE FROM dba.ExportConfig;

-- Configure tables manually
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport,
    BatchSize
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate', 0, 1000),
    ('dbo', 'CustomerNotes', 1, 'NoteDate', 0, 1000),
    ('dbo', 'Customers', 0, NULL, 1, 1000);  -- Force full export for Customers

-- Run export with manual configuration
DECLARE @ExportID3 int;
INSERT INTO dba.ExportLog (StartDate, Status, Parameters)
VALUES (GETDATE(), 'Started', 
    (SELECT '2024-01-01' as startDate, '2024-02-01' as endDate, 1000 as batchSize FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
);
SET @ExportID3 = SCOPE_IDENTITY();

EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-02-01',
    @AnalyzeStructure = 0,  -- Skip analysis since we configured manually
    @Debug = 1;

-- Example 4: Enhanced Validation Reports
-- This example demonstrates the new validation reporting system
PRINT '';
PRINT 'Example 4: Enhanced Validation Reports';
PRINT '--------------------------------';

-- Clear previous configuration
DELETE FROM dba.ExportConfig;

-- Configure tables to demonstrate various validation scenarios
INSERT INTO dba.ExportConfig (
    SchemaName,
    TableName,
    IsTransactionTable,
    DateColumnName,
    ForceFullExport,
    BatchSize
)
VALUES
    ('dbo', 'Orders', 1, 'OrderDate', 0, 1000),        -- Transaction table with date range
    ('dbo', 'CustomerNotes', 1, 'NoteDate', 0, 1000),  -- Another transaction table
    ('dbo', 'OrderItems', 0, NULL, 1, 1000);           -- Force full export to ensure all related records

-- Run export to generate validation scenarios
DECLARE @ExportID4 int;
INSERT INTO dba.ExportLog (StartDate, Status, Parameters)
VALUES (GETDATE(), 'Started', 
    (SELECT '2024-01-01' as startDate, '2024-02-01' as endDate, 1000 as batchSize FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
);
SET @ExportID4 = SCOPE_IDENTITY();

EXEC dba.sp_ExportData
    @StartDate = '2024-01-01',
    @EndDate = '2024-02-01',
    @Debug = 1;

-- Generate validation reports in different formats
PRINT '';
PRINT 'Summary Report:';
PRINT '---------------';
EXEC dba.sp_GenerateValidationReport
    @ExportID = @ExportID4,
    @ReportType = 'Summary';

PRINT '';
PRINT 'Detailed Report:';
PRINT '----------------';
EXEC dba.sp_GenerateValidationReport
    @ExportID = @ExportID4,
    @ReportType = 'Detailed',
    @IncludeQueries = 1;

PRINT '';
PRINT 'JSON Report:';
PRINT '------------';
EXEC dba.sp_GenerateValidationReport
    @ExportID = @ExportID4,
    @ReportType = 'JSON';

-- Query export results
PRINT '';
PRINT 'Export Performance Summary:';
PRINT '-------------------------';
SELECT 
    el.ExportID,
    el.StartDate,
    el.EndDate,
    el.Status,
    el.RowsProcessed,
    ep.TableName,
    ep.RowsProcessed as TableRows,
    DATEDIFF(ms, ep.StartTime, ep.EndTime) / 1000.0 as ProcessingSeconds
FROM dba.ExportLog el
INNER JOIN dba.ExportPerformance ep ON el.ExportID = ep.ExportID
ORDER BY el.ExportID DESC, ep.TableName;

-- Query relationship map
PRINT '';
PRINT 'Table Relationships:';
PRINT '-------------------';
SELECT 
    ParentSchema,
    ParentTable,
    ChildSchema,
    ChildTable,
    RelationshipLevel,
    RelationshipPath
FROM dba.TableRelationships
ORDER BY RelationshipLevel, ParentSchema, ParentTable;

-- Query validation results
PRINT '';
PRINT 'Latest Validation Results:';
PRINT '------------------------';
SELECT 
    vr.ValidationTime,
    vr.SchemaName + '.' + vr.TableName as TableName,
    vr.ValidationType,
    vr.Severity,
    vr.Category,
    vr.RecordCount,
    vr.Details
FROM dba.ValidationResults vr
WHERE vr.ExportID = @ExportID4
ORDER BY 
    CASE vr.Severity
        WHEN 'Error' THEN 1
        WHEN 'Warning' THEN 2
        ELSE 3
    END,
    vr.SchemaName,
    vr.TableName;
