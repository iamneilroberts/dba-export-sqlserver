-- Test the improved database analysis procedure
SET NOCOUNT ON;

-- First ensure metadata tables exist
EXEC dba.sp_CreateMetadataTables;

-- Enable debug output for testing
UPDATE dba.DebugConfiguration
SET OutputLevel = 'DEBUG'
WHERE CategoryName = 'TableAnalysis';

-- Run the analysis with default parameters
PRINT 'Running database analysis...';
PRINT '==========================';
EXEC dba.sp_AnalyzeDatabaseStructure;

-- Run again with lower threshold to see more potential transaction tables
PRINT '';
PRINT 'Running analysis with lower confidence threshold...';
PRINT '================================================';
EXEC dba.sp_AnalyzeDatabaseStructure 
    @MinimumRows = 1000,           -- Consider tables with at least 1000 rows
    @ConfidenceThreshold = 0.5,    -- Lower threshold to see more candidates
    @Debug = 1;                    -- Enable debug output

-- Run with focus on very large tables
PRINT '';
PRINT 'Running analysis focused on large tables...';
PRINT '=========================================';
EXEC dba.sp_AnalyzeDatabaseStructure 
    @MinimumRows = 100000,         -- Only look at tables with 100k+ rows
    @ConfidenceThreshold = 0.4,    -- Lower threshold since size is main factor
    @Debug = 1;                    -- Enable debug output

-- Show tables that changed classification between runs
SELECT 
    t1.SchemaName,
    t1.TableName,
    t1.Classification AS InitialClassification,
    t2.Classification AS LowerThresholdClassification,
    t3.Classification AS LargeTableClassification,
    FORMAT(CAST(JSON_VALUE(t1.Analysis, '$.tableRowCount') AS bigint), 'N0') AS RecordCount,
    t1.ClassificationReason AS InitialReason,
    t2.ClassificationReason AS LowerThresholdReason,
    t3.ClassificationReason AS LargeTableReason
FROM dba.TableClassificationHistory t1
INNER JOIN dba.TableClassificationHistory t2 
    ON t1.SchemaName = t2.SchemaName 
    AND t1.TableName = t2.TableName
    AND t2.HistoryID = t1.HistoryID + 1
INNER JOIN dba.TableClassificationHistory t3
    ON t2.SchemaName = t3.SchemaName 
    AND t2.TableName = t3.TableName
    AND t3.HistoryID = t2.HistoryID + 1
WHERE 
    t1.Classification != t2.Classification
    OR t2.Classification != t3.Classification
ORDER BY 
    CAST(JSON_VALUE(t1.Analysis, '$.tableRowCount') AS bigint) DESC;