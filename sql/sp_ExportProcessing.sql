-- Export table processing procedures for the DateExport system

CREATE OR ALTER PROCEDURE dba.sp_ProcessTransactionTables
    @ExportID int,
    @StartDate datetime,
    @EndDate datetime = NULL,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @DateColumn nvarchar(128);
    DECLARE @msg nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @RowCount int;
    DECLARE @BatchStart datetime = GETDATE();

    -- Process transaction tables
    DECLARE table_cursor CURSOR FOR
    SELECT DISTINCT 
        t.name AS TableName,
        s.name AS SchemaName,
        ec.DateColumnName
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN dba.ExportConfig ec ON s.name = ec.SchemaName AND t.name = ec.TableName
    WHERE t.is_ms_shipped = 0
    AND s.name != 'dba'
    AND ec.IsTransactionTable = 1
    ORDER BY s.name, t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName, @DateColumn;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Create export table
            EXEC dba.sp_CreateExportTable
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @Debug = @Debug;

            -- Initialize performance tracking
            EXEC dba.sp_TrackPerformance
                @ExportID = @ExportID,
                @SchemaName = @SchemaName,
                @TableName = @TableName;

            -- Get primary key column
            EXEC dba.sp_GetTablePrimaryKey
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @PKColumn = @PKColumn OUTPUT;

            -- Build and execute insert statement
            SET @SQL = N'
            INSERT INTO [dba].[Export_' + @SchemaName + '_' + @TableName + '] (ExportID, SourceID)
            SELECT 
                @ExportID,
                ' + QUOTENAME(@PKColumn) + '
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@DateColumn) + ' >= @StartDate
            AND (@EndDate IS NULL OR ' + QUOTENAME(@DateColumn) + ' <= @EndDate)';

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT('Executing SQL:', CHAR(13), CHAR(10), @SQL);
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END

            EXEC sp_executesql @SQL,
                N'@ExportID int, @StartDate datetime, @EndDate datetime',
                @ExportID, @StartDate, @EndDate;

            SET @RowCount = @@ROWCOUNT;

            -- Update performance tracking
            EXEC dba.sp_TrackPerformance
                @ExportID = @ExportID,
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @RowsProcessed = @RowCount,
                @IsComplete = 1;

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Processed ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Rows: ', @RowCount, CHAR(13), CHAR(10),
                    'Time: ', DATEDIFF(ms, @BatchStart, GETDATE()) / 1000.0, ' seconds'
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END TRY
        BEGIN CATCH
            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Error processing ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Error: ', ERROR_MESSAGE()
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END CATCH

        SET @BatchStart = GETDATE();
        FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName, @DateColumn;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_ProcessRelatedTables
    @ExportID int,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @msg nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @JoinClauses nvarchar(max);
    DECLARE @RowCount int;
    DECLARE @BatchStart datetime = GETDATE();

    -- Process related tables
    DECLARE table_cursor CURSOR FOR
    SELECT DISTINCT 
        t.name AS TableName,
        s.name AS SchemaName
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    LEFT JOIN dba.ExportConfig ec ON s.name = ec.SchemaName AND t.name = ec.TableName
    WHERE t.is_ms_shipped = 0
    AND s.name != 'dba'
    AND (ec.IsTransactionTable = 0 OR ec.IsTransactionTable IS NULL)
    AND EXISTS (
        SELECT 1 
        FROM dba.TableRelationships tr
        INNER JOIN dba.ExportConfig ec2 
            ON tr.ParentSchema = ec2.SchemaName 
            AND tr.ParentTable = ec2.TableName
        WHERE tr.ChildSchema = s.name
        AND tr.ChildTable = t.name
        AND ec2.IsTransactionTable = 1
    )
    ORDER BY s.name, t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Create export table
            EXEC dba.sp_CreateExportTable
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @Debug = @Debug;

            -- Initialize performance tracking
            EXEC dba.sp_TrackPerformance
                @ExportID = @ExportID,
                @SchemaName = @SchemaName,
                @TableName = @TableName;

            -- Get primary key column
            EXEC dba.sp_GetTablePrimaryKey
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @PKColumn = @PKColumn OUTPUT;

            -- Get join clauses
            EXEC dba.sp_GenerateJoinClauses
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @ExportID = @ExportID,
                @JoinClauses = @JoinClauses OUTPUT,
                @Debug = @Debug;

            -- Build and execute insert statement
            SET @SQL = N'
            INSERT INTO [dba].[Export_' + @SchemaName + '_' + @TableName + '] (ExportID, SourceID)
            SELECT DISTINCT
                @ExportID,
                t.' + QUOTENAME(@PKColumn) + '
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
            ' + ISNULL(@JoinClauses, '');

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT('Executing SQL:', CHAR(13), CHAR(10), @SQL);
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END

            EXEC sp_executesql @SQL,
                N'@ExportID int',
                @ExportID;

            SET @RowCount = @@ROWCOUNT;

            -- Update performance tracking
            EXEC dba.sp_TrackPerformance
                @ExportID = @ExportID,
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @RowsProcessed = @RowCount,
                @IsComplete = 1;

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Processed ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Rows: ', @RowCount, CHAR(13), CHAR(10),
                    'Time: ', DATEDIFF(ms, @BatchStart, GETDATE()) / 1000.0, ' seconds'
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END TRY
        BEGIN CATCH
            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Error processing ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Error: ', ERROR_MESSAGE()
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END CATCH

        SET @BatchStart = GETDATE();
        FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_ProcessFullExportTables
    @ExportID int,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @msg nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @RowCount int;
    DECLARE @BatchStart datetime = GETDATE();

    -- Process full export tables
    DECLARE table_cursor CURSOR FOR
    SELECT DISTINCT 
        t.name AS TableName,
        s.name AS SchemaName
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN dba.ExportConfig ec ON s.name = ec.SchemaName AND t.name = ec.TableName
    WHERE t.is_ms_shipped = 0
    AND s.name != 'dba'
    AND ec.ForceFullExport = 1
    AND ec.IsTransactionTable = 0
    ORDER BY s.name, t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Create export table
            EXEC dba.sp_CreateExportTable
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @Debug = @Debug;

            -- Initialize performance tracking
            EXEC dba.sp_TrackPerformance
                @ExportID = @ExportID,
                @SchemaName = @SchemaName,
                @TableName = @TableName;

            -- Get primary key column
            EXEC dba.sp_GetTablePrimaryKey
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @PKColumn = @PKColumn OUTPUT;

            -- Build and execute insert statement
            SET @SQL = N'
            INSERT INTO [dba].[Export_' + @SchemaName + '_' + @TableName + '] (ExportID, SourceID)
            SELECT 
                @ExportID,
                ' + QUOTENAME(@PKColumn) + '
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT('Executing SQL:', CHAR(13), CHAR(10), @SQL);
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END

            EXEC sp_executesql @SQL,
                N'@ExportID int',
                @ExportID;

            SET @RowCount = @@ROWCOUNT;

            -- Update performance tracking
            EXEC dba.sp_TrackPerformance
                @ExportID = @ExportID,
                @SchemaName = @SchemaName,
                @TableName = @TableName,
                @RowsProcessed = @RowCount,
                @IsComplete = 1;

            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Processed ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Rows: ', @RowCount, CHAR(13), CHAR(10),
                    'Time: ', DATEDIFF(ms, @BatchStart, GETDATE()) / 1000.0, ' seconds'
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END TRY
        BEGIN CATCH
            IF @Debug = 1
            BEGIN
                SET @msg = CONCAT(
                    'Error processing ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Error: ', ERROR_MESSAGE()
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END CATCH

        SET @BatchStart = GETDATE();
        FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;
END;
GO
