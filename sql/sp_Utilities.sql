-- Common utility procedures for the DateExport system

CREATE OR ALTER PROCEDURE dba.sp_GetTablePrimaryKey
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @PKColumn nvarchar(128) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP 1 @PKColumn = c.name
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.is_primary_key = 1
    AND i.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName));

    IF @PKColumn IS NULL
        THROW 50003, 'Table must have a primary key', 1;
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_CreateExportTable
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @DropExisting bit = 1,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL nvarchar(max);
    DECLARE @ExportTableName nvarchar(256) = '[dba].[Export_' + @SchemaName + '_' + @TableName + ']';
    
    -- Drop existing export table if requested
    IF @DropExisting = 1
    BEGIN
        SET @SQL = N'IF OBJECT_ID(''' + @ExportTableName + ''', ''U'') IS NOT NULL 
                    DROP TABLE ' + @ExportTableName;
        IF @Debug = 1 RAISERROR('Dropping existing table...', 0, 1) WITH NOWAIT;
        EXEC sp_executesql @SQL;
    END

    -- Create export table
    SET @SQL = N'
    CREATE TABLE ' + @ExportTableName + ' (
        ExportID int NOT NULL,
        SourceID sql_variant NOT NULL,
        DateAdded datetime NOT NULL DEFAULT GETDATE(),
        CONSTRAINT [PK_Export_' + @SchemaName + '_' + @TableName + '] PRIMARY KEY (ExportID, SourceID)
    )';
    
    IF @Debug = 1 RAISERROR('Creating export table...', 0, 1) WITH NOWAIT;
    EXEC sp_executesql @SQL;
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_LogExportOperation
    @StartDate datetime = NULL,
    @EndDate datetime = NULL,
    @BatchSize int = NULL,
    @Status nvarchar(50),
    @ErrorMessage nvarchar(max) = NULL,
    @ExportID int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @ExportID IS NULL
    BEGIN
        -- Start new export operation
        INSERT INTO dba.ExportLog (
            StartDate, 
            Status, 
            Parameters
        )
        SELECT 
            GETDATE(),
            @Status,
            (
                SELECT 
                    @StartDate as startDate,
                    @EndDate as endDate,
                    @BatchSize as batchSize
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        
        SET @ExportID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        -- Update existing export operation
        UPDATE dba.ExportLog
        SET 
            EndDate = CASE WHEN @Status IN ('Completed', 'Failed') THEN GETDATE() ELSE EndDate END,
            Status = @Status,
            ErrorMessage = @ErrorMessage,
            RowsProcessed = CASE 
                WHEN @Status = 'Completed' THEN (
                    SELECT SUM(RowsProcessed)
                    FROM dba.ExportPerformance
                    WHERE ExportID = @ExportID
                )
                ELSE RowsProcessed
            END
        WHERE ExportID = @ExportID;
    END
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_TrackPerformance
    @ExportID int,
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @RowsProcessed int = NULL,
    @IsComplete bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    IF NOT EXISTS (
        SELECT 1 
        FROM dba.ExportPerformance 
        WHERE ExportID = @ExportID 
        AND SchemaName = @SchemaName 
        AND TableName = @TableName
    )
    BEGIN
        -- Initialize performance tracking
        INSERT INTO dba.ExportPerformance (
            ExportID,
            TableName,
            SchemaName,
            StartTime
        )
        VALUES (
            @ExportID,
            @TableName,
            @SchemaName,
            GETDATE()
        );
    END
    ELSE IF @IsComplete = 1
    BEGIN
        -- Update performance metrics
        UPDATE dba.ExportPerformance
        SET 
            EndTime = GETDATE(),
            RowsProcessed = @RowsProcessed
        WHERE 
            ExportID = @ExportID
            AND TableName = @TableName
            AND SchemaName = @SchemaName;
    END
END;
GO
