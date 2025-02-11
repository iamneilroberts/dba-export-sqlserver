-- Table analysis procedures for the DateExport system

CREATE OR ALTER PROCEDURE dba.sp_AnalyzeTableCharacteristics
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @MinimumRows int,
    @TableRowCount bigint OUTPUT,
    @TransactionConfidence decimal(5,2) OUTPUT,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Get row count
    SELECT @TableRowCount = p.rows
    FROM sys.tables t
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    WHERE t.name = @TableName
    AND SCHEMA_NAME(t.schema_id) = @SchemaName
    AND i.index_id <= 1;

    -- Initialize confidence score
    SET @TransactionConfidence = 0;

    -- Common transaction-related terms
    IF EXISTS (
        SELECT 1
        FROM (VALUES 
            ('Transaction'),('Order'),('Invoice'),('Payment'),
            ('Registration'),('Visit'),('Estimate'),('Appointment'),
            ('Booking'),('Reservation'),('Entry'),('Event')
        ) AS Terms(Term)
        WHERE @TableName LIKE '%' + Term + '%'
    )
    BEGIN
        SET @TransactionConfidence = @TransactionConfidence + 0.3;
    END

    -- Check row count threshold
    IF @TableRowCount >= @MinimumRows
    BEGIN
        SET @TransactionConfidence = @TransactionConfidence + 0.2;
    END

    IF @Debug = 1
    BEGIN
        DECLARE @msg nvarchar(max) = CONCAT(
            'Analyzed table characteristics:', CHAR(13), CHAR(10),
            'Table: ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
            'Row count: ', @TableRowCount, CHAR(13), CHAR(10),
            'Initial confidence: ', @TransactionConfidence
        );
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_IdentifyDateColumns
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @TransactionConfidence decimal(5,2) OUTPUT,
    @DateColumns nvarchar(max) OUTPUT,
    @IndexedDateColumns nvarchar(max) OUTPUT,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL nvarchar(max);
    DECLARE @msg nvarchar(max);

    -- Get all date columns
    SET @SQL = N'
    SELECT @DateColsJson = (
        SELECT 
            c.name AS [name],
            t.name AS [dataType]
        FROM sys.columns c
        INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
        WHERE c.object_id = OBJECT_ID(@SchemaTable)
        AND t.name IN (''datetime'', ''datetime2'', ''date'')
        FOR JSON PATH
    )';

    DECLARE @FullTableName nvarchar(500) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    SET @SQL = REPLACE(@SQL, '@SchemaTable', '''' + @FullTableName + '''');
    
    EXEC sp_executesql @SQL, 
        N'@DateColsJson nvarchar(max) OUTPUT', 
        @DateColsJson = @DateColumns OUTPUT;

    -- Get indexed date columns
    SET @SQL = N'
    SELECT @IndexedDateColsJson = (
        SELECT DISTINCT c.name AS [name]
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
        WHERE i.object_id = OBJECT_ID(@SchemaTable)
        AND t.name IN (''datetime'', ''datetime2'', ''date'')
        FOR JSON PATH
    )';

    SET @SQL = REPLACE(@SQL, '@SchemaTable', '''' + @FullTableName + '''');
    
    EXEC sp_executesql @SQL, 
        N'@IndexedDateColsJson nvarchar(max) OUTPUT', 
        @IndexedDateColsJson = @IndexedDateColumns OUTPUT;

    -- Check for date columns with transaction-related names
    IF EXISTS (
        SELECT 1
        FROM (VALUES 
            ('TransactionDate', 1.0),
            ('OrderDate', 1.0),
            ('InvoiceDate', 1.0),
            ('PaymentDate', 1.0),
            ('VisitDate', 1.0),
            ('EventDate', 1.0),
            ('CreatedDate', 0.8),
            ('CreateDate', 0.8),
            ('ModifiedDate', 0.5),
            ('UpdatedDate', 0.5)
        ) AS DateCols(ColumnName, Weight)
        CROSS APPLY OPENJSON(@DateColumns)
        WITH (name nvarchar(128) '$.name')
        WHERE name LIKE '%' + ColumnName + '%'
    )
    BEGIN
        SET @TransactionConfidence = @TransactionConfidence + 0.3;
    END

    -- Add confidence for indexed date columns
    IF @IndexedDateColumns IS NOT NULL
    BEGIN
        SET @TransactionConfidence = @TransactionConfidence + 0.2;
    END

    IF @Debug = 1
    BEGIN
        SET @msg = CONCAT(
            'Date column analysis:', CHAR(13), CHAR(10),
            'Date columns: ', ISNULL(@DateColumns, 'None'), CHAR(13), CHAR(10),
            'Indexed date columns: ', ISNULL(@IndexedDateColumns, 'None'), CHAR(13), CHAR(10),
            'Updated confidence: ', @TransactionConfidence
        );
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_UpdateExportConfig
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @TransactionConfidence decimal(5,2),
    @ConfidenceThreshold decimal(5,2),
    @IndexedDateColumns nvarchar(max),
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Only update config if confidence meets threshold
    IF @TransactionConfidence >= @ConfidenceThreshold
    BEGIN
        -- Don't insert if already exists
        IF NOT EXISTS (
            SELECT 1 
            FROM dba.ExportConfig 
            WHERE SchemaName = @SchemaName 
            AND TableName = @TableName
        )
        BEGIN
            INSERT INTO dba.ExportConfig (
                SchemaName, 
                TableName, 
                IsTransactionTable,
                DateColumnName
            )
            SELECT 
                @SchemaName,
                @TableName,
                1 AS IsTransactionTable,
                JSON_VALUE(@IndexedDateColumns, '$[0].name') AS DateColumnName
            WHERE @IndexedDateColumns IS NOT NULL;

            IF @Debug = 1
            BEGIN
                DECLARE @msg nvarchar(max) = CONCAT(
                    'Added to ExportConfig:', CHAR(13), CHAR(10),
                    'Table: ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                    'Date Column: ', JSON_VALUE(@IndexedDateColumns, '$[0].name')
                );
                RAISERROR(@msg, 0, 1) WITH NOWAIT;
            END
        END
    END
END;
GO