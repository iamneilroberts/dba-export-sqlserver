CREATE OR ALTER PROCEDURE dba.sp_ExportData
    @StartDate datetime,
    @EndDate datetime = NULL,
    @AnalyzeStructure bit = 1,     -- Re-analyze database structure
    @MaxRelationshipLevel int = 1,  -- Maximum levels of relationships to analyze
    @MinimumRows int = 1000,       -- Minimum rows for transaction consideration
    @ConfidenceThreshold decimal(5,2) = 0.7,  -- Confidence threshold for auto-identification
    @BatchSize int = 10000,        -- Batch size for processing
    @Debug bit = 0                 -- Enable debug output
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @msg nvarchar(max);
    DECLARE @ErrorMsg nvarchar(max);
    DECLARE @ExportID int;
    DECLARE @StartTime datetime = GETDATE();
    DECLARE @RelationshipSummary nvarchar(max);
    DECLARE @TransactionTableList nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);

    BEGIN TRY
        -- Step 1: Analyze database structure if requested
        IF @AnalyzeStructure = 1
        BEGIN
            IF @Debug = 1 RAISERROR('Step 1: Analyzing database structure...', 0, 1) WITH NOWAIT;
            
            EXEC dba.sp_AnalyzeDatabaseStructure 
                @MinimumRows = @MinimumRows,
                @ConfidenceThreshold = @ConfidenceThreshold,
                @Debug = @Debug;

            IF @Debug = 1
            BEGIN
                SELECT @TransactionTableList = STRING_AGG(
                    CONCAT(
                        SchemaName, '.', TableName, 
                        ' (Date Column: ', ISNULL(DateColumnName, 'None'), ')'
                    ),
                    CHAR(13) + CHAR(10)
                )
                FROM dba.ExportConfig
                WHERE IsTransactionTable = 1;

                SET @msg = 'Identified transaction tables:' + CHAR(13) + CHAR(10) + 
                    ISNULL(@TransactionTableList, 'None found');

                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END

        -- Step 2: Analyze table relationships
        IF @Debug = 1 RAISERROR('Step 2: Analyzing table relationships...', 0, 1) WITH NOWAIT;
        
        EXEC dba.sp_AnalyzeTableRelationships
            @MaxRelationshipLevel = @MaxRelationshipLevel,
            @Debug = @Debug;

        IF @Debug = 1
        BEGIN
            SELECT @RelationshipSummary = STRING_AGG(
                CONCAT(
                    'Level ', RelationshipLevel, ': ',
                    RelCount, ' relationships'
                ),
                CHAR(13) + CHAR(10)
            )
            FROM (
                SELECT 
                    RelationshipLevel,
                    COUNT(*) as RelCount
                FROM dba.TableRelationships
                GROUP BY RelationshipLevel
                ORDER BY RelationshipLevel
                OFFSET 0 ROWS
            ) t;

            SET @msg = 'Relationship summary:' + CHAR(13) + CHAR(10) + 
                ISNULL(@RelationshipSummary, 'No relationships found');

            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        -- Validate configuration
        IF NOT EXISTS (SELECT 1 FROM dba.ExportConfig WHERE IsTransactionTable = 1)
        BEGIN
            SET @ErrorMsg = 'No transaction tables identified. Please configure at least one transaction table.';
            RAISERROR(@ErrorMsg, 16, 1);
        END

        -- Step 3: Build export tables
        IF @Debug = 1 RAISERROR('Step 3: Building export tables...', 0, 1) WITH NOWAIT;
        
        INSERT INTO dba.ExportLog (
            StartDate, 
            Status, 
            Parameters
        )
        SELECT 
            GETDATE(),
            'Started',
            (
                SELECT 
                    @StartDate as startDate,
                    @EndDate as endDate,
                    @BatchSize as batchSize
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        
        SET @ExportID = SCOPE_IDENTITY();

        -- First process parent tables
        DECLARE @ParentTables TABLE (
            SchemaName nvarchar(128),
            TableName nvarchar(128)
        );

        -- Get all parent tables of transaction tables
        INSERT INTO @ParentTables
        SELECT DISTINCT 
            tr.ParentSchema,
            tr.ParentTable
        FROM dba.TableRelationships tr
        INNER JOIN dba.ExportConfig ec ON 
            tr.ChildSchema = ec.SchemaName 
            AND tr.ChildTable = ec.TableName
        WHERE ec.IsTransactionTable = 1;

        -- Process each parent table
        DECLARE @ParentSchema nvarchar(128), @ParentTable nvarchar(128);
        DECLARE parent_cursor CURSOR FOR
        SELECT SchemaName, TableName FROM @ParentTables;

        OPEN parent_cursor;
        FETCH NEXT FROM parent_cursor INTO @ParentSchema, @ParentTable;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @Debug = 1 
                RAISERROR('Processing parent table: [%s].[%s]', 0, 1, @ParentSchema, @ParentTable) WITH NOWAIT;

            DECLARE @StartProcessTime datetime = GETDATE();
            DECLARE @RowCount int = 0;

            -- Get primary key column for parent table
            SELECT TOP 1 @PKColumn = c.name
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.is_primary_key = 1
            AND i.object_id = OBJECT_ID(@ParentSchema + '.' + @ParentTable);

            -- Create export table for parent
            DECLARE @ExportTableName nvarchar(256) = QUOTENAME('dba') + '.' + QUOTENAME('Export_' + @ParentSchema + '_' + @ParentTable);
            
            -- Drop if exists
            IF OBJECT_ID(@ExportTableName, 'U') IS NOT NULL
            BEGIN
                SET @SQL = 'DROP TABLE ' + @ExportTableName;
                EXEC sp_executesql @SQL;
            END

            -- Create export table
            SET @SQL = '
            CREATE TABLE ' + @ExportTableName + ' (
                ExportID int NOT NULL,
                SourceID int NOT NULL,
                PRIMARY KEY (ExportID, SourceID)
            )';
            EXEC sp_executesql @SQL;

            -- Insert parent records that are referenced by transaction table records
            SET @SQL = '
            INSERT INTO ' + @ExportTableName + ' (ExportID, SourceID)
            SELECT DISTINCT
                @ExportID,
                p.' + QUOTENAME(@PKColumn) + '
            FROM ' + QUOTENAME(@ParentSchema) + '.' + QUOTENAME(@ParentTable) + ' p
            INNER JOIN dba.TableRelationships tr ON 
                tr.ParentSchema = @ParentSchema
                AND tr.ParentTable = @ParentTable
            INNER JOIN dba.ExportConfig ec ON 
                tr.ChildSchema = ec.SchemaName 
                AND tr.ChildTable = ec.TableName
            WHERE ec.IsTransactionTable = 1';

            EXEC sp_executesql @SQL, N'@ExportID int, @ParentSchema nvarchar(128), @ParentTable nvarchar(128)',
                @ExportID, @ParentSchema, @ParentTable;

            SET @RowCount = @@ROWCOUNT;

            -- Log performance
            INSERT INTO dba.ExportPerformance (
                ExportID,
                TableName,
                SchemaName,
                RowsProcessed,
                ProcessingTime,
                RelationshipDepth,
                BatchNumber,
                StartTime,
                EndTime
            )
            VALUES (
                @ExportID,
                @ParentTable,
                @ParentSchema,
                @RowCount,
                DATEDIFF(ms, @StartProcessTime, GETDATE()) / 1000.0,
                0,  -- Parent tables are at depth 0
                1,  -- Single batch for parents
                @StartProcessTime,
                GETDATE()
            );

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Processed ', @ParentSchema, '.', @ParentTable, CHAR(13), CHAR(10),
                    'Rows: ', @RowCount, CHAR(13), CHAR(10),
                    'Time: ', CAST(DATEDIFF(ms, @StartProcessTime, GETDATE()) / 1000.0 AS varchar(20)), ' seconds'
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END

            FETCH NEXT FROM parent_cursor INTO @ParentSchema, @ParentTable;
        END

        CLOSE parent_cursor;
        DEALLOCATE parent_cursor;

        -- Now process transaction and related tables
        EXEC dba.sp_BuildExportTables
            @StartDate = @StartDate,
            @EndDate = @EndDate,
            @BatchSize = @BatchSize,
            @Debug = @Debug;

        -- Step 4: Validate export tables
        IF @Debug = 1 RAISERROR('Step 4: Validating export tables...', 0, 1) WITH NOWAIT;
        
        EXEC dba.sp_ValidateExportTables
            @ExportID = @ExportID,
            @ThrowError = 0,
            @Debug = @Debug;

        -- Check validation results and format a detailed error message if needed
        DECLARE @ValidationErrors nvarchar(max);
        SELECT @ValidationErrors = STRING_AGG(
            CONCAT(
                Category, ' (', Severity, '): ',
                SchemaName, '.', TableName,
                CASE 
                    WHEN TableSize IS NOT NULL THEN ' - ' + CAST(TableSize AS varchar(20)) + ' records affected'
                    ELSE ''
                END,
                ' - ', Details
            ),
            CHAR(13) + CHAR(10)
        )
        FROM dba.ValidationResults
        WHERE ExportID = @ExportID
        AND Severity = 'Error';

        IF @ValidationErrors IS NOT NULL
        BEGIN
            -- Update export log status
            UPDATE dba.ExportLog
            SET 
                Status = 'Failed',
                EndDate = GETDATE(),
                ErrorMessage = @ValidationErrors
            WHERE ExportID = @ExportID;

            -- Raise error with complete validation results
            RAISERROR(@ValidationErrors, 16, 1);
            RETURN;
        END

        -- Return export summary
        SELECT 
            el.ExportID,
            el.StartDate,
            el.EndDate,
            el.Status,
            el.RowsProcessed,
            JSON_QUERY(el.Parameters) as Parameters,
            DATEDIFF(SECOND, @StartTime, GETDATE()) as TotalProcessingSeconds,
            (
                SELECT 
                    SchemaName,
                    TableName,
                    RowsProcessed,
                    DATEDIFF(ms, StartTime, EndTime) / 1000.0 as ProcessingTimeSeconds
                FROM dba.ExportPerformance
                WHERE ExportID = el.ExportID
                FOR JSON PATH
            ) as TableDetails
        FROM dba.ExportLog el
        WHERE ExportID = @ExportID;

        IF @Debug = 1
        BEGIN
            SET @msg = CONCAT(
                'Export completed successfully', CHAR(13), CHAR(10),
                'Total time: ', DATEDIFF(SECOND, @StartTime, GETDATE()), ' seconds', CHAR(13), CHAR(10),
                'Export ID: ', @ExportID
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END
    END TRY
    BEGIN CATCH
        SET @ErrorMsg = ERROR_MESSAGE();
        
        -- Log error if we have an export ID
        IF @ExportID IS NOT NULL
        BEGIN
            UPDATE dba.ExportLog
            SET 
                EndDate = GETDATE(),
                Status = 'Failed',
                ErrorMessage = @ErrorMsg
            WHERE ExportID = @ExportID;
        END

        -- Re-raise the error using RAISERROR
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END;
GO
