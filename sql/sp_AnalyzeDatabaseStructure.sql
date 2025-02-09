CREATE OR ALTER PROCEDURE dba.sp_AnalyzeDatabaseStructure
    @MinimumRows int = 1000,              -- Minimum rows for transaction consideration
    @ConfidenceThreshold decimal(5,2) = 0.7,  -- Minimum confidence score (0-1)
    @Debug bit = 0                        -- Enable debug output
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL nvarchar(max);
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @msg nvarchar(max);

    -- Create temporary table to store analysis results
    CREATE TABLE #TableAnalysis (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        TableRowCount bigint,
        DateColumns nvarchar(max),         -- JSON array of date columns
        IndexedDateColumns nvarchar(max),  -- JSON array of indexed date columns
        TransactionConfidence decimal(5,2), -- Confidence score (0-1)
        ReasonCodes nvarchar(max),         -- JSON array of reason codes
        Analysis nvarchar(max)             -- Detailed analysis in JSON
    );

    -- Common transaction-related terms
    DECLARE @TransactionTerms TABLE (Term nvarchar(50));
    INSERT INTO @TransactionTerms (Term)
    VALUES 
        ('Transaction'),('Order'),('Invoice'),('Payment'),
        ('Registration'),('Visit'),('Estimate'),('Appointment'),
        ('Booking'),('Reservation'),('Entry'),('Event');

    -- Common date column names
    DECLARE @DateColumns TABLE (ColumnName nvarchar(50), Weight decimal(5,2));
    INSERT INTO @DateColumns (ColumnName, Weight)
    VALUES 
        ('TransactionDate', 1.0),
        ('OrderDate', 1.0),
        ('InvoiceDate', 1.0),
        ('PaymentDate', 1.0),
        ('VisitDate', 1.0),
        ('EventDate', 1.0),
        ('CreatedDate', 0.8),
        ('CreateDate', 0.8),
        ('ModifiedDate', 0.5),
        ('UpdatedDate', 0.5);

    IF @Debug = 1
    BEGIN
        SET @msg = 'Starting table analysis...';
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END

    -- Get all user tables with their row counts
    INSERT INTO #TableAnalysis (SchemaName, TableName, TableRowCount)
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        p.rows AS TableRowCount
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    WHERE 
        t.is_ms_shipped = 0
        AND i.index_id <= 1
        AND s.name != 'dba'; -- Exclude our own schema

    IF @Debug = 1
    BEGIN
        SET @msg = (
            SELECT STRING_AGG(
                CONCAT(SchemaName, '.', TableName, ' (', TableRowCount, ' rows)'),
                CHAR(13) + CHAR(10)
            )
            FROM #TableAnalysis
        );
        SET @msg = 'Found tables:' + CHAR(13) + CHAR(10) + @msg;
        RAISERROR(@msg, 0, 1) WITH NOWAIT;
    END

    -- Analyze each table
    DECLARE table_cursor CURSOR FOR 
    SELECT SchemaName, TableName 
    FROM #TableAnalysis;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @Confidence decimal(5,2) = 0;
        DECLARE @Reasons nvarchar(max) = '[]';
        DECLARE @DateColsJson nvarchar(max);
        DECLARE @IndexedDateColsJson nvarchar(max);
        DECLARE @Analysis nvarchar(max);

        -- Get date columns
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
        
        IF @Debug = 1
        BEGIN
            SET @msg = CONCAT(
                'Analyzing table: ', @FullTableName, CHAR(13), CHAR(10),
                'Object ID: ', OBJECT_ID(@FullTableName), CHAR(13), CHAR(10),
                'Dynamic SQL:', CHAR(13), CHAR(10), @SQL
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        EXEC sp_executesql @SQL, N'@DateColsJson nvarchar(max) OUTPUT', @DateColsJson OUTPUT;

        IF @Debug = 1 AND @DateColsJson IS NULL
        BEGIN
            SET @msg = 'No date columns found';
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END
        ELSE IF @Debug = 1
        BEGIN
            SET @msg = CONCAT('Date columns found: ', @DateColsJson);
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

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
        
        IF @Debug = 1
        BEGIN
            SET @msg = CONCAT(
                'Getting indexed date columns...', CHAR(13), CHAR(10),
                'Dynamic SQL:', CHAR(13), CHAR(10), @SQL
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        EXEC sp_executesql @SQL, N'@IndexedDateColsJson nvarchar(max) OUTPUT', @IndexedDateColsJson OUTPUT;

        IF @Debug = 1 AND @IndexedDateColsJson IS NULL
        BEGIN
            SET @msg = 'No indexed date columns found';
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END
        ELSE IF @Debug = 1
        BEGIN
            SET @msg = CONCAT('Indexed date columns found: ', @IndexedDateColsJson);
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        -- Calculate confidence score based on multiple factors
        DECLARE @ReasonList TABLE (Reason nvarchar(max));

        -- Check table name for transaction terms
        SELECT @Confidence = @Confidence + 0.3
        FROM @TransactionTerms 
        WHERE @TableName LIKE '%' + Term + '%'
        AND NOT EXISTS (
            SELECT 1 FROM @ReasonList 
            WHERE Reason = 'NamePattern'
        );
        
        IF @Confidence > 0
            INSERT INTO @ReasonList VALUES ('NamePattern');

        -- Check for date columns with transaction-related names
        IF EXISTS (
            SELECT 1
            FROM @DateColumns dc
            CROSS APPLY OPENJSON(@DateColsJson)
            WITH (name nvarchar(128) '$.name')
            WHERE name LIKE '%' + dc.ColumnName + '%'
        )
        BEGIN
            SET @Confidence = @Confidence + 0.3;
            INSERT INTO @ReasonList VALUES ('DateColumnNames');
        END

        -- Check row count
        IF EXISTS (SELECT 1 FROM #TableAnalysis WHERE SchemaName = @SchemaName AND TableName = @TableName AND TableRowCount >= @MinimumRows)
        BEGIN
            SET @Confidence = @Confidence + 0.2;
            INSERT INTO @ReasonList VALUES ('TableRowCount');
        END

        -- Check for indexed date columns
        IF @IndexedDateColsJson IS NOT NULL
        BEGIN
            SET @Confidence = @Confidence + 0.2;
            INSERT INTO @ReasonList VALUES ('IndexedDates');
        END

        -- Build reason codes JSON
        SELECT @Reasons = (SELECT * FROM @ReasonList FOR JSON PATH);

        -- Build analysis JSON
        SET @Analysis = (
            SELECT 
                @Confidence AS confidence,
                JSON_QUERY(@Reasons) AS reasons,
                JSON_QUERY(@DateColsJson) AS dateColumns,
                JSON_QUERY(@IndexedDateColsJson) AS indexedDateColumns,
                TableRowCount AS TableRowCount
            FROM #TableAnalysis 
            WHERE SchemaName = @SchemaName 
            AND TableName = @TableName
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- Update analysis results
        UPDATE #TableAnalysis
        SET 
            DateColumns = @DateColsJson,
            IndexedDateColumns = @IndexedDateColsJson,
            TransactionConfidence = @Confidence,
            ReasonCodes = @Reasons,
            Analysis = @Analysis
        WHERE SchemaName = @SchemaName 
        AND TableName = @TableName;

        -- Debug output
        IF @Debug = 1
        BEGIN
            SET @msg = CONCAT(
                'Analyzed ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                'Confidence: ', @Confidence, CHAR(13), CHAR(10),
                'Analysis: ', @Analysis
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        DELETE FROM @ReasonList;
        FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- First, identify transaction tables
    INSERT INTO dba.ExportConfig (
        SchemaName, 
        TableName, 
        IsTransactionTable,
        DateColumnName
    )
    SELECT 
        t.SchemaName,
        t.TableName,
        1 AS IsTransactionTable,
        JSON_VALUE(t.IndexedDateColumns, '$[0].name') AS DateColumnName
    FROM #TableAnalysis t
    LEFT JOIN dba.ExportConfig e ON t.SchemaName = e.SchemaName AND t.TableName = e.TableName
    WHERE 
        t.TransactionConfidence >= @ConfidenceThreshold
        AND e.ConfigID IS NULL -- Don't insert if already exists
        AND t.IndexedDateColumns IS NOT NULL;

    -- Then, identify and configure parent tables of transaction tables
    WITH TransactionParents AS (
        SELECT DISTINCT 
            fk.referenced_schema_name AS ParentSchema,
            fk.referenced_table_name AS ParentTable
        FROM (
            SELECT 
                OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS referenced_schema_name,
                OBJECT_NAME(fk.referenced_object_id) AS referenced_table_name
            FROM sys.foreign_keys fk
            INNER JOIN dba.ExportConfig ec 
                ON OBJECT_SCHEMA_NAME(fk.parent_object_id) = ec.SchemaName 
                AND OBJECT_NAME(fk.parent_object_id) = ec.TableName
            WHERE ec.IsTransactionTable = 1
        ) fk
    )
    INSERT INTO dba.ExportConfig (
        SchemaName,
        TableName,
        IsTransactionTable,
        DateColumnName,
        ForceFullExport
    )
    SELECT 
        tp.ParentSchema,
        tp.ParentTable,
        0 AS IsTransactionTable,
        NULL AS DateColumnName,
        1 AS ForceFullExport
    FROM TransactionParents tp
    LEFT JOIN dba.ExportConfig e 
        ON tp.ParentSchema = e.SchemaName 
        AND tp.ParentTable = e.TableName
    WHERE e.ConfigID IS NULL;

    -- Return analysis results
    SELECT 
        SchemaName,
        TableName,
        TableRowCount,
        TransactionConfidence,
        DateColumns,
        IndexedDateColumns,
        ReasonCodes,
        Analysis,
        CASE 
            WHEN TransactionConfidence >= @ConfidenceThreshold THEN 'Suggested Transaction Table'
            WHEN TransactionConfidence >= @ConfidenceThreshold * 0.7 THEN 'Possible Transaction Table'
            ELSE 'Likely Not Transaction Table'
        END AS Recommendation
    FROM #TableAnalysis
    WHERE TransactionConfidence > 0
    ORDER BY TransactionConfidence DESC;

    DROP TABLE #TableAnalysis;
END;
GO
