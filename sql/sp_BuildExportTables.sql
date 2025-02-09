CREATE OR ALTER PROCEDURE dba.sp_BuildExportTables
    @StartDate datetime,
    @EndDate datetime = NULL,
    @BatchSize int = 10000,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ExportID int;
    DECLARE @msg nvarchar(max);
    
    -- Get the current ExportID
    SELECT @ExportID = MAX(ExportID)
    FROM dba.ExportLog
    WHERE Status = 'Started'
        AND EndDate IS NULL;
        
    IF @ExportID IS NULL
    BEGIN
        RAISERROR('No active export found', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        -- First process parent tables to maintain referential integrity
        EXEC dba.sp_ProcessParentTables
            @ExportID = @ExportID,
            @Debug = @Debug;
            
        -- Then process transaction tables
        EXEC dba.sp_ProcessTransactionTables
            @ExportID = @ExportID,
            @StartDate = @StartDate,
            @EndDate = @EndDate,
            @Debug = @Debug;
            
        -- Finally process related tables
        EXEC dba.sp_ProcessRelatedTables
            @ExportID = @ExportID,
            @BatchSize = @BatchSize,
            @Debug = @Debug;
            
        -- Update export log
        UPDATE dba.ExportLog
        SET 
            EndDate = GETDATE(),
            Status = 'Completed',
            RowsProcessed = (
                SELECT SUM(RowsProcessed)
                FROM dba.ExportPerformance
                WHERE ExportID = @ExportID
            )
        WHERE ExportID = @ExportID;
    END TRY
    BEGIN CATCH
        -- Log error and re-throw
        DECLARE @ErrorMsg nvarchar(max) = ERROR_MESSAGE();
        
        UPDATE dba.ExportLog
        SET 
            EndDate = GETDATE(),
            Status = 'Failed',
            ErrorMessage = @ErrorMsg
        WHERE ExportID = @ExportID;
        
        THROW;
    END CATCH
END;
GO
