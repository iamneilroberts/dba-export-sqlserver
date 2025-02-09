CREATE OR ALTER PROCEDURE dba.sp_GenerateValidationReport
    @ExportID int,
    @ReportType varchar(20) = 'Summary',  -- 'Summary', 'Detailed', or 'JSON'
    @IncludeQueries bit = 0,              -- Include validation queries in output
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate parameters
    IF NOT EXISTS (SELECT 1 FROM dba.ExportLog WHERE ExportID = @ExportID)
    BEGIN
        DECLARE @ErrorMsg nvarchar(max) = 'Export ID ' + CAST(@ExportID AS varchar(20)) + ' not found';
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    IF @ReportType NOT IN ('Summary', 'Detailed', 'JSON')
    BEGIN
        RAISERROR('Invalid report type. Must be Summary, Detailed, or JSON', 16, 1);
        RETURN;
    END

    -- Get export info
    DECLARE @StartDate datetime, @EndDate datetime;
    SELECT 
        @StartDate = CAST(JSON_VALUE(Parameters, '$.startDate') AS datetime),
        @EndDate = CAST(JSON_VALUE(Parameters, '$.endDate') AS datetime)
    FROM dba.ExportLog 
    WHERE ExportID = @ExportID;

    -- Generate appropriate report
    IF @ReportType = 'Summary'
    BEGIN
        -- Summary by severity
        SELECT
            'Validation Summary' as ReportSection,
            Severity,
            COUNT(*) as IssueCount,
            COUNT(DISTINCT SchemaName + '.' + TableName) as TablesAffected,
            SUM(ISNULL(RecordCount, 0)) as TotalRecordsAffected
        FROM dba.ValidationResults
        WHERE ExportID = @ExportID
        GROUP BY Severity
        ORDER BY 
            CASE Severity
                WHEN 'Error' THEN 1
                WHEN 'Warning' THEN 2
                ELSE 3
            END;

        -- Summary by category
        SELECT
            'Category Summary' as ReportSection,
            Category,
            Severity,
            COUNT(*) as IssueCount,
            STRING_AGG(SchemaName + '.' + TableName, ', ') as AffectedTables
        FROM dba.ValidationResults
        WHERE ExportID = @ExportID
        GROUP BY Category, Severity
        ORDER BY 
            CASE Severity
                WHEN 'Error' THEN 1
                WHEN 'Warning' THEN 2
                ELSE 3
            END,
            Category;

        -- Tables with most issues
        SELECT TOP 5
            'Most Affected Tables' as ReportSection,
            SchemaName + '.' + TableName as TableName,
            COUNT(*) as IssueCount,
            STRING_AGG(Category + ' (' + Severity + ')', ', ') as Issues
        FROM dba.ValidationResults
        WHERE ExportID = @ExportID
        GROUP BY SchemaName, TableName
        ORDER BY COUNT(*) DESC;
    END
    ELSE IF @ReportType = 'Detailed'
    BEGIN
        -- Export information
        SELECT
            'Export Information' as ReportSection,
            @ExportID as ExportID,
            el.StartDate,
            el.EndDate,
            el.Status,
            el.RowsProcessed,
            @StartDate as ExportStartDate,
            @EndDate as ExportEndDate
        FROM dba.ExportLog el
        WHERE ExportID = @ExportID;

        -- All validation results with details
        SELECT
            'Validation Details' as ReportSection,
            SchemaName + '.' + TableName as TableName,
            ValidationType,
            Severity,
            Category,
            RecordCount as AffectedRecords,
            Details,
            CASE WHEN @IncludeQueries = 1 THEN ValidationQuery ELSE NULL END as ValidationQuery
        FROM dba.ValidationResults
        WHERE ExportID = @ExportID
        ORDER BY 
            CASE Severity
                WHEN 'Error' THEN 1
                WHEN 'Warning' THEN 2
                ELSE 3
            END,
            SchemaName,
            TableName;

        -- Performance metrics
        SELECT
            'Performance Metrics' as ReportSection,
            SchemaName + '.' + TableName as TableName,
            RowsProcessed,
            ProcessingTime as ProcessingTimeSeconds,
            CASE 
                WHEN ProcessingTime > 0 
                THEN CAST(RowsProcessed / ProcessingTime AS decimal(18,2))
                ELSE 0 
            END as RowsPerSecond
        FROM dba.ExportPerformance
        WHERE ExportID = @ExportID
        ORDER BY ProcessingTime DESC;
    END
    ELSE -- JSON
    BEGIN
        SELECT (
            SELECT
                el.ExportID,
                el.StartDate,
                el.EndDate,
                el.Status,
                el.RowsProcessed,
                (
                    SELECT 
                        v.SchemaName + '.' + v.TableName as TableName,
                        v.ValidationType,
                        v.Severity,
                        v.Category,
                        v.RecordCount as AffectedRecords,
                        v.Details,
                        CASE WHEN @IncludeQueries = 1 THEN v.ValidationQuery ELSE NULL END as ValidationQuery
                    FROM dba.ValidationResults v
                    WHERE v.ExportID = @ExportID
                    FOR JSON PATH
                ) as ValidationResults,
                (
                    SELECT
                        SchemaName + '.' + TableName as TableName,
                        RowsProcessed,
                        ProcessingTime as ProcessingTimeSeconds
                    FROM dba.ExportPerformance
                    WHERE ExportID = @ExportID
                    FOR JSON PATH
                ) as PerformanceMetrics
            FROM dba.ExportLog el
            WHERE el.ExportID = @ExportID
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) as JSONReport;
    END

    -- Debug information
    IF @Debug = 1
    BEGIN
        SELECT 
            'Debug Information' as ReportSection,
            v.SchemaName + '.' + v.TableName as TableName,
            v.ValidationType,
            v.ValidationQuery
        FROM dba.ValidationResults v
        WHERE v.ExportID = @ExportID
        AND v.ValidationQuery IS NOT NULL
        ORDER BY v.SchemaName, v.TableName;
    END
END;
GO