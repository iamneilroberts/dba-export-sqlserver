CREATE OR ALTER PROCEDURE dba.sp_DebugOutput
    @Message nvarchar(max),            -- Message to output
    @Category varchar(50),             -- Category of the message (Relationships, TableAnalysis, etc.)
    @Level varchar(20) = 'INFO',       -- Message level (ERROR, WARN, INFO, DEBUG)
    @IncludeTimestamp bit = 1,         -- Whether to include timestamp in output
    @IncludeCategory bit = 1           -- Whether to include category in output
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Check if this category/level should be output
    IF NOT EXISTS (
        SELECT 1 
        FROM dba.DebugConfiguration 
        WHERE CategoryName = @Category
        AND IsEnabled = 1
        AND (
            -- ERROR messages are always output
            @Level = 'ERROR'
            OR
            -- For other levels, check if configured level includes this level
            CASE @Level
                WHEN 'DEBUG' THEN 4
                WHEN 'INFO' THEN 3
                WHEN 'WARN' THEN 2
                WHEN 'ERROR' THEN 1
            END <= 
            CASE OutputLevel
                WHEN 'DEBUG' THEN 4
                WHEN 'INFO' THEN 3
                WHEN 'WARN' THEN 2
                WHEN 'ERROR' THEN 1
            END
        )
    )
    BEGIN
        -- Don't output anything if this category/level is not enabled
        -- (except ERROR messages, which are always output)
        IF @Level != 'ERROR'
            RETURN;
    END

    DECLARE @FormattedMessage nvarchar(max) = '';
    
    -- Add timestamp if requested
    IF @IncludeTimestamp = 1
        SET @FormattedMessage = CONCAT(
            FORMAT(GETUTCDATE(), 'yyyy-MM-dd HH:mm:ss.fff'),
            ' UTC | '
        );
    
    -- Add level
    SET @FormattedMessage = CONCAT(
        @FormattedMessage,
        '[', @Level, ']'
    );
    
    -- Add category if requested
    IF @IncludeCategory = 1
        SET @FormattedMessage = CONCAT(
            @FormattedMessage,
            ' [', @Category, ']'
    );
    
    -- Add message
    SET @FormattedMessage = CONCAT(
        @FormattedMessage,
        ' ', @Message
    );
    
    -- Output the message
    -- Use RAISERROR with NOWAIT to ensure immediate output
    RAISERROR(@FormattedMessage, 10, 1) WITH NOWAIT;
    
    -- If this is an ERROR message, also log it
    IF @Level = 'ERROR'
    BEGIN
        INSERT INTO dba.ExportProcessingLog
        (
            SchemaName,
            TableName,
            ProcessingPhase,
            StartTime,
            EndTime,
            Status,
            ErrorMessage,
            Details
        )
        VALUES
        (
            'dba',
            'System',
            @Category,
            GETUTCDATE(),
            GETUTCDATE(),
            'Failed',
            @Message,
            JSON_MODIFY('{}', '$.formattedMessage', @FormattedMessage)
        );
    END
END;
GO

-- Helper functions for common debug output scenarios
CREATE OR ALTER PROCEDURE dba.sp_LogError
    @Message nvarchar(max),
    @Category varchar(50)
AS
BEGIN
    EXEC dba.sp_DebugOutput @Message, @Category, 'ERROR';
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_LogWarning
    @Message nvarchar(max),
    @Category varchar(50)
AS
BEGIN
    EXEC dba.sp_DebugOutput @Message, @Category, 'WARN';
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_LogInfo
    @Message nvarchar(max),
    @Category varchar(50)
AS
BEGIN
    EXEC dba.sp_DebugOutput @Message, @Category, 'INFO';
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_LogDebug
    @Message nvarchar(max),
    @Category varchar(50)
AS
BEGIN
    EXEC dba.sp_DebugOutput @Message, @Category, 'DEBUG';
END;
GO