CREATE OR ALTER PROCEDURE dba.sp_ValidateExportTables
    @ExportID int,
    @ThrowError bit = 1,         -- Throw error on validation failure
    @Debug bit = 0               -- Enable debug output
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL nvarchar(max);
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @msg nvarchar(max);
    
    -- Clean up any existing validation results for this export
    DELETE FROM dba.ValidationResults WHERE ExportID = @ExportID;

    -- Validate export ID exists
    IF NOT EXISTS (SELECT 1 FROM dba.ExportLog WHERE ExportID = @ExportID)
    BEGIN
        IF @Debug = 1 RAISERROR('Export ID %d not found', 0, 1, @ExportID) WITH NOWAIT;
        RAISERROR('Invalid Export ID', 16, 1);
        RETURN;
    END

    -- Process each table in the database
    DECLARE table_cursor CURSOR FOR
    SELECT DISTINCT 
        t.name AS TableName,
        s.name AS SchemaName
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_ms_shipped = 0
    AND s.name != 'dba'  -- Exclude dba schema tables
    ORDER BY s.name, t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @ExportTableName nvarchar(256) = '[dba].[Export_' + @SchemaName + '_' + @TableName + ']';
        
        -- Check if export table exists
        IF OBJECT_ID(@ExportTableName, 'U') IS NULL
        BEGIN
            INSERT INTO dba.ValidationResults (
                ExportID, SchemaName, TableName, ValidationType,
                Severity, Category, Details, ValidationTime
            )
            VALUES (
                @ExportID, @SchemaName, @TableName, 'Table Existence',
                'Error', 'Missing Table', 'Export table does not exist',
                GETDATE()
            );
        END
        ELSE
        BEGIN
            -- Get primary key column
            DECLARE @PKColumn nvarchar(128);
            SELECT TOP 1 @PKColumn = c.name
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.is_primary_key = 1
            AND i.object_id = OBJECT_ID(@SchemaName + '.' + @TableName);

            -- Validate column completeness
            INSERT INTO dba.ValidationResults (
                ExportID, SchemaName, TableName, ValidationType,
                Severity, Category, RecordCount, Details, ValidationQuery,
                ValidationTime
            )
            SELECT 
                @ExportID, @SchemaName, @TableName, 'Column Completeness',
                'Warning', 'Missing Columns',
                COUNT(*),
                'Missing columns: ' + STRING_AGG(c.name, ', '),
                'Column comparison query',
                GETDATE()
            FROM sys.columns c
            WHERE c.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
            AND NOT EXISTS (
                SELECT 1 
                FROM sys.columns ec
                WHERE ec.object_id = OBJECT_ID(@ExportTableName)
                AND ec.name = c.name
                AND ec.system_type_id = c.system_type_id
            )
            HAVING COUNT(*) > 0;

            -- Validate data type consistency
            INSERT INTO dba.ValidationResults (
                ExportID, SchemaName, TableName, ValidationType,
                Severity, Category, RecordCount, Details, ValidationQuery,
                ValidationTime
            )
            SELECT 
                @ExportID, @SchemaName, @TableName, 'Data Type Consistency',
                'Error', 'Type Mismatch',
                COUNT(*),
                'Type mismatches: ' + STRING_AGG(
                    c.name + ' (' + 
                    TYPE_NAME(c.system_type_id) + ' vs ' + 
                    TYPE_NAME(ec.system_type_id) + ')',
                    ', '
                ),
                'Data type comparison query',
                GETDATE()
            FROM sys.columns c
            INNER JOIN sys.columns ec ON 
                ec.object_id = OBJECT_ID(@ExportTableName)
                AND ec.name = c.name
                AND ec.system_type_id != c.system_type_id
            WHERE c.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
            HAVING COUNT(*) > 0;

            -- Validate relationship integrity
            IF EXISTS (
                SELECT 1 
                FROM dba.TableRelationships tr
                WHERE tr.ChildSchema = @SchemaName
                AND tr.ChildTable = @TableName
            )
            BEGIN
                -- Build validation query for each parent relationship
                DECLARE @ValidationSQL nvarchar(max) = N'
                SELECT @OrphanCount = COUNT(*)
                FROM ' + @ExportTableName + ' e
                INNER JOIN ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
                    ON t.' + QUOTENAME(@PKColumn) + ' = e.SourceID
                WHERE e.ExportID = @ExportID
                AND NOT EXISTS (';

                DECLARE @ParentChecks nvarchar(max) = '';
                
                WITH NumberedRelationships AS (
                    SELECT 
                        tr.ParentSchema,
                        tr.ParentTable,
                        pc.name as ParentColumn,
                        cc.name as ChildColumn,
                        ROW_NUMBER() OVER (ORDER BY tr.RelationshipLevel) as RowNum
                    FROM dba.TableRelationships tr
                    INNER JOIN sys.foreign_keys fk ON 
                        fk.referenced_object_id = OBJECT_ID(tr.ParentSchema + '.' + tr.ParentTable)
                        AND fk.parent_object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
                    INNER JOIN sys.foreign_key_columns fkc ON 
                        fk.object_id = fkc.constraint_object_id
                    INNER JOIN sys.columns pc ON 
                        fkc.referenced_object_id = pc.object_id 
                        AND fkc.referenced_column_id = pc.column_id
                    INNER JOIN sys.columns cc ON 
                        fkc.parent_object_id = cc.object_id 
                        AND fkc.parent_column_id = cc.column_id
                    WHERE tr.ChildSchema = @SchemaName
                    AND tr.ChildTable = @TableName
                )
                SELECT @ParentChecks = STRING_AGG(
                    'SELECT 1 FROM [dba].[Export_' + ParentSchema + '_' + ParentTable + '] pe' +
                    CAST(RowNum AS varchar(10)) +
                    ' INNER JOIN ' + QUOTENAME(ParentSchema) + '.' + QUOTENAME(ParentTable) + ' p' +
                    CAST(RowNum AS varchar(10)) + ' ON p' + CAST(RowNum AS varchar(10)) + '.' +
                    QUOTENAME(ParentColumn) + ' = pe' + CAST(RowNum AS varchar(10)) + '.SourceID' +
                    ' WHERE pe' + CAST(RowNum AS varchar(10)) + '.ExportID = e.ExportID' +
                    ' AND p' + CAST(RowNum AS varchar(10)) + '.' + QUOTENAME(ParentColumn) + 
                    ' = t.' + QUOTENAME(ChildColumn),
                    ' UNION ALL '
                )
                FROM NumberedRelationships;

                IF @ParentChecks IS NOT NULL
                BEGIN
                    SET @ValidationSQL = @ValidationSQL + @ParentChecks + ')';
                    
                    IF @Debug = 1
                    BEGIN
                        SET @msg = CONCAT(
                            'Validating relationships for ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                            'SQL:', CHAR(13), CHAR(10), @ValidationSQL
                        );
                        RAISERROR(@msg, 0, 1) WITH NOWAIT;
                    END

                    DECLARE @OrphanCount int;
                    EXEC sp_executesql @ValidationSQL, 
                        N'@ExportID int, @OrphanCount int OUTPUT',
                        @ExportID, @OrphanCount OUTPUT;

                    IF @OrphanCount > 0
                    BEGIN
                        INSERT INTO dba.ValidationResults (
                            ExportID, SchemaName, TableName, ValidationType,
                            Severity, Category, RecordCount, Details, ValidationQuery,
                            ValidationTime
                        )
                        VALUES (
                            @ExportID, @SchemaName, @TableName, 'Relationship Integrity',
                            'Error', 'Missing Related Records', @OrphanCount,
                            'Found ' + CAST(@OrphanCount AS varchar(20)) + ' records with missing related records in export set. These records have valid relationships in the source database but their related records were not included in the export set. This may indicate that related records outside the date range need to be included.',
                            @ValidationSQL,
                            GETDATE()
                        );
                    END
                END
            END

            -- Validate data consistency
            DECLARE @InvalidRecords int;
            SET @SQL = N'
            SELECT @InvalidRecords = COUNT(*)
            FROM ' + @ExportTableName + ' e
            WHERE e.ExportID = @ExportID
            AND NOT EXISTS (
                SELECT 1 
                FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
                WHERE t.' + QUOTENAME(@PKColumn) + ' = e.SourceID
            )';

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Validating data consistency for ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'SQL:', CHAR(13), CHAR(10), @SQL
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END

            EXEC sp_executesql @SQL,
                N'@ExportID int, @InvalidRecords int OUTPUT',
                @ExportID, @InvalidRecords OUTPUT;

            IF @InvalidRecords > 0
            BEGIN
                INSERT INTO dba.ValidationResults (
                    ExportID, SchemaName, TableName, ValidationType,
                    Severity, Category, RecordCount, Details, ValidationQuery,
                    ValidationTime
                )
                VALUES (
                    @ExportID, @SchemaName, @TableName, 'Data Consistency',
                    'Error', 'Non-Existent Records', @InvalidRecords,
                    'Found ' + CAST(@InvalidRecords AS varchar(20)) + ' records in export set that do not exist in source table. This indicates a data consistency issue.',
                    @SQL,
                    GETDATE()
                );
            END

            -- Validate date ranges for transaction tables
            IF EXISTS (
                SELECT 1 FROM dba.ExportConfig 
                WHERE SchemaName = @SchemaName 
                AND TableName = @TableName
                AND IsTransactionTable = 1
                AND DateColumnName IS NOT NULL
            )
            BEGIN
                DECLARE @DateColumn nvarchar(128);
                DECLARE @StartDate datetime, @EndDate datetime;
                SELECT @DateColumn = DateColumnName
                FROM dba.ExportConfig
                WHERE SchemaName = @SchemaName 
                AND TableName = @TableName;

                -- Get export date range
                SELECT 
                    @StartDate = CAST(JSON_VALUE(Parameters, '$.startDate') AS datetime),
                    @EndDate = CAST(JSON_VALUE(Parameters, '$.endDate') AS datetime)
                FROM dba.ExportLog 
                WHERE ExportID = @ExportID;

                -- First validate that all records within date range are included
                DECLARE @MissingInRangeSQL nvarchar(max) = N'
                SELECT @MissingCount = COUNT(*)
                FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
                WHERE t.' + QUOTENAME(@DateColumn) + ' BETWEEN @StartDate AND @EndDate
                AND NOT EXISTS (
                    SELECT 1
                    FROM ' + @ExportTableName + ' e
                    WHERE e.ExportID = @ExportID
                    AND e.SourceID = t.' + QUOTENAME(@PKColumn) + '
                )';

                DECLARE @MissingCount int;
                EXEC sp_executesql @MissingInRangeSQL,
                    N'@ExportID int, @StartDate datetime, @EndDate datetime, @MissingCount int OUTPUT',
                    @ExportID, @StartDate, @EndDate, @MissingCount OUTPUT;

                IF @MissingCount > 0
                BEGIN
                    INSERT INTO dba.ValidationResults (
                        ExportID, SchemaName, TableName, ValidationType,
                        Severity, Category, RecordCount, Details, ValidationQuery,
                        ValidationTime
                    )
                    VALUES (
                        @ExportID, @SchemaName, @TableName, 'Date Range Completeness',
                        'Error', 'Missing In-Range Records', @MissingCount,
                        'Found ' + CAST(@MissingCount AS varchar(20)) + ' records within the date range that were not included in the export set. All records within the specified date range should be exported.',
                        @MissingInRangeSQL,
                        GETDATE()
                    );
                END

                -- Then check for out of range records
                DECLARE @DateRangeSQL nvarchar(max) = N'
                SELECT @OutOfRangeCount = COUNT(*)
                FROM ' + @ExportTableName + ' e
                INNER JOIN ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
                    ON t.' + QUOTENAME(@PKColumn) + ' = e.SourceID
                WHERE e.ExportID = @ExportID
                AND t.' + QUOTENAME(@DateColumn) + ' NOT BETWEEN @StartDate AND @EndDate';

                DECLARE @OutOfRangeCount int;
                EXEC sp_executesql @DateRangeSQL,
                    N'@ExportID int, @StartDate datetime, @EndDate datetime, @OutOfRangeCount int OUTPUT',
                    @ExportID, @StartDate, @EndDate, @OutOfRangeCount OUTPUT;

                IF @OutOfRangeCount > 0
                BEGIN
                    INSERT INTO dba.ValidationResults (
                        ExportID, SchemaName, TableName, ValidationType,
                        Severity, Category, RecordCount, Details, ValidationQuery,
                        ValidationTime
                    )
                    VALUES (
                        @ExportID, @SchemaName, @TableName, 'Date Range',
                        'Warning', 'Date Range Mismatch', @OutOfRangeCount,
                        'Found ' + CAST(@OutOfRangeCount AS varchar(20)) + ' records outside the specified date range (' + 
                        CONVERT(varchar, @StartDate, 120) + ' to ' + CONVERT(varchar, @EndDate, 120) + 
                        '). This may be expected if these records are related to transaction records within the date range.',
                        @DateRangeSQL,
                        GETDATE()
                    );
                END
            END
        END

        FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- Check for missing required tables
    INSERT INTO dba.ValidationResults (
        ExportID, SchemaName, TableName, ValidationType,
        Severity, Category, Details, ValidationTime
    )
    SELECT 
        @ExportID, SchemaName, TableName, 'Configuration',
        'Error', 'Required Table Missing', 'Transaction table export is required but missing',
        GETDATE()
    FROM dba.ExportConfig ec
    WHERE ec.IsTransactionTable = 1
    AND NOT EXISTS (
        SELECT 1
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = 'dba'
        AND t.name = 'Export_' + ec.SchemaName + '_' + ec.TableName
    );

    -- Update export log with validation status
    UPDATE dba.ExportLog
    SET Status = CASE 
            WHEN EXISTS (
                SELECT 1 FROM dba.ValidationResults 
                WHERE ExportID = @ExportID 
                AND Severity = 'Error'
            ) THEN 'Validation Failed'
            WHEN EXISTS (
                SELECT 1 FROM dba.ValidationResults 
                WHERE ExportID = @ExportID 
                AND Severity = 'Warning'
            ) THEN 'Validation Passed with Warnings'
            ELSE 'Validation Passed'
        END,
        EndDate = GETDATE()
    WHERE ExportID = @ExportID;

    -- Return validation results
    SELECT 
        ValidationType,
        Severity,
        Category,
        SchemaName,
        TableName,
        RecordCount,
        Details
    FROM dba.ValidationResults
    WHERE ExportID = @ExportID
    ORDER BY 
        CASE Severity
            WHEN 'Error' THEN 1
            WHEN 'Warning' THEN 2
            ELSE 3
        END,
        CASE Category
            WHEN 'Required Table Missing' THEN 1  -- Critical configuration issue
            WHEN 'Missing Table' THEN 2          -- Critical structural issue
            WHEN 'Type Mismatch' THEN 3         -- Schema mismatch
            WHEN 'Missing Related Records' THEN 4 -- Data relationship issue
            WHEN 'Non-Existent Records' THEN 5   -- Data consistency issue
            ELSE 6
        END,
        SchemaName,
        TableName;

    -- Throw error if validation failed and requested
    IF @ThrowError = 1 AND EXISTS (
        SELECT 1 FROM dba.ValidationResults 
        WHERE ExportID = @ExportID 
        AND Severity = 'Error'
    )
    BEGIN
        DECLARE @ErrorMsg nvarchar(max) = (
            SELECT STRING_AGG(
                CONCAT(
                    Category, ' (', Severity, '): ',
                    SchemaName, '.', TableName,
                    CASE 
                        WHEN RecordCount IS NOT NULL THEN ' - ' + CAST(RecordCount AS varchar(20)) + ' records affected'
                        ELSE ''
                    END,
                    ' - ', Details
                ),
                CHAR(13) + CHAR(10)
            )
            FROM dba.ValidationResults
            WHERE ExportID = @ExportID
            AND Severity = 'Error'
        );

        RAISERROR(@ErrorMsg, 16, 1);
    END
END;
GO
