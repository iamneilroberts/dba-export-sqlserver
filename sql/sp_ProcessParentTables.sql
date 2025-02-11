

CREATE OR ALTER PROCEDURE dba.sp_ProcessParentTables
    @ExportID int,
    @StartDate datetime,
    @EndDate datetime,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @msg nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @ParentSchema nvarchar(128);
    DECLARE @ParentTable nvarchar(128);
    DECLARE @ExportTableName nvarchar(256);
    DECLARE @StartProcessTime datetime;
    DECLARE @RowCount int;
    DECLARE @ErrorMsg nvarchar(max);

    BEGIN TRY
        -- Validate parameters
        IF NOT EXISTS (SELECT 1 FROM dba.ExportLog WHERE ExportID = @ExportID)
        BEGIN
            RAISERROR('Invalid Export ID: %d', 16, 1, @ExportID);
            RETURN;
        END

        -- Get all parent tables of transaction tables
        DECLARE @ParentTables TABLE (
            SchemaName nvarchar(128),
            TableName nvarchar(128),
            ChildSchema nvarchar(128),
            ChildTable nvarchar(128),
            ParentColumn nvarchar(128),
            ChildColumn nvarchar(128),
            DateColumn nvarchar(128)
        );

        INSERT INTO @ParentTables
        SELECT DISTINCT 
            tr.ParentSchema,
            tr.ParentTable,
            tr.ChildSchema,
            tr.ChildTable,
            tr.ParentColumn,
            tr.ChildColumn,
            ec.DateColumnName
        FROM dba.TableRelationships tr
        INNER JOIN dba.ExportConfig ec ON 
            tr.ChildSchema = ec.SchemaName 
            AND tr.ChildTable = ec.TableName
        WHERE ec.IsTransactionTable = 1;

        IF @Debug = 1
        BEGIN
            SELECT @msg = CONCAT(
                'Found ', (SELECT COUNT(*) FROM @ParentTables), ' parent tables to process'
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        -- Process each parent table
        DECLARE parent_cursor CURSOR FOR
        SELECT DISTINCT SchemaName, TableName FROM @ParentTables;

        OPEN parent_cursor;
        FETCH NEXT FROM parent_cursor INTO @ParentSchema, @ParentTable;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                IF @Debug = 1 
                    RAISERROR('Processing parent table: [%s].[%s]', 0, 1, @ParentSchema, @ParentTable) WITH NOWAIT;

                SET @StartProcessTime = GETDATE();

                -- Get primary key column for parent table
                SELECT TOP 1 @PKColumn = c.name
                FROM sys.indexes i
                INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
                WHERE i.is_primary_key = 1
                AND i.object_id = OBJECT_ID(@ParentSchema + '.' + @ParentTable);

                IF @PKColumn IS NULL
                BEGIN
                    RAISERROR('No primary key found for table [%s].[%s]', 16, 1, @ParentSchema, @ParentTable);
                    CONTINUE;
                END

                -- Create export table for parent
                SET @ExportTableName = '[dba].[Export_' + @ParentSchema + '_' + @ParentTable + ']';
                
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

                -- Build dynamic SQL for each child relationship
                SELECT @SQL = STRING_AGG(
                    'SELECT DISTINCT p.' + QUOTENAME(@PKColumn) + ' as ParentID ' +
                    'FROM ' + QUOTENAME(@ParentSchema) + '.' + QUOTENAME(@ParentTable) + ' p ' +
                    'INNER JOIN ' + QUOTENAME(ChildSchema) + '.' + QUOTENAME(ChildTable) + ' c ' +
                    'ON c.' + QUOTENAME(ChildColumn) + ' = p.' + QUOTENAME(ParentColumn) + ' ' +
                    'WHERE c.' + QUOTENAME(DateColumn) + ' BETWEEN @StartDate AND @EndDate',
                    ' UNION '
                )
                FROM @ParentTables
                WHERE SchemaName = @ParentSchema
                AND TableName = @ParentTable;

                -- Combine child queries
                SET @SQL = '
                INSERT INTO ' + @ExportTableName + ' (ExportID, SourceID)
                SELECT DISTINCT @ExportID, ParentID
                FROM (
                    ' + @SQL + '
                ) AS Combined';

                -- Execute the query
                EXEC sp_executesql @SQL,
                    N'@ExportID int, @StartDate datetime, @EndDate datetime',
                    @ExportID, @StartDate, @EndDate;

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
            END TRY
            BEGIN CATCH
                -- Log error but continue with next table
                SET @msg = CONCAT(
                    'Error processing table ', @ParentSchema, '.', @ParentTable, ': ',
                    ERROR_MESSAGE()
                );
                RAISERROR(@msg, 10, 1) WITH NOWAIT;
            END CATCH

            FETCH NEXT FROM parent_cursor INTO @ParentSchema, @ParentTable;
        END

        CLOSE parent_cursor;
        DEALLOCATE parent_cursor;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('global', 'parent_cursor') >= 0
        BEGIN
            CLOSE parent_cursor;
            DEALLOCATE parent_cursor;
        END

        SET @ErrorMsg = ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END;
GO