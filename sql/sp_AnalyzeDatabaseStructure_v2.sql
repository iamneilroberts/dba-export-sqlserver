CREATE OR ALTER PROCEDURE dba.sp_AnalyzeDatabaseStructure
    @MinimumRows int = 1000,              -- Minimum rows for transaction consideration
    @ConfidenceThreshold decimal(5,2) = 0.7,  -- Minimum confidence score (0-1)
    @Debug bit = 0                        -- Enable debug output
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Initialize metadata and debug configuration
    EXEC dba.sp_InitializeMetadata 
        @ClearExistingData = 1,
        @ResetConfiguration = 0,
        @InitialClassification = 1;

    -- Create temporary table to store analysis results
    CREATE TABLE #TableAnalysis (
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        TableRowCount bigint,
        DateColumns nvarchar(max),         -- JSON array of date columns
        IndexedDateColumns nvarchar(max),  -- JSON array of indexed date columns
        TransactionConfidence decimal(5,2), -- Confidence score (0-1)
        ReasonCodes nvarchar(max),         -- JSON array of reason codes with weights
        Analysis nvarchar(max),            -- Detailed analysis in JSON
        Classification varchar(50),         -- Current classification
        ClassificationReason nvarchar(max)  -- Reason for classification
    );

    -- Get all user tables with their row counts
    INSERT INTO #TableAnalysis (
        SchemaName, 
        TableName, 
        TableRowCount,
        Classification,
        ClassificationReason
    )
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        SUM(p.rows) AS TableRowCount,
        CASE 
            WHEN SUM(p.rows) < 100 THEN 'Lookup'
            ELSE 'Unclassified'
        END AS Classification,
        CASE 
            WHEN SUM(p.rows) < 100 THEN 'Small table (< 100 rows)'
            ELSE NULL
        END AS ClassificationReason
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.partitions p ON t.object_id = p.object_id
    WHERE 
        t.is_ms_shipped = 0
        AND s.name != 'dba'
        AND p.index_id IN (0,1)
    GROUP BY s.name, t.name;

    -- Log initial table count
    DECLARE @InitialCount int = (SELECT COUNT(*) FROM #TableAnalysis);
    DECLARE @CountMsg nvarchar(100) = 'Found ' + CAST(@InitialCount AS nvarchar(10)) + ' user tables to analyze';
    EXEC dba.sp_LogInfo @Message = @CountMsg, @Category = 'TableAnalysis';

    -- Analyze each table for transaction patterns
    DECLARE @SQL nvarchar(max);
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    DECLARE @FullTableName nvarchar(500);
    DECLARE @Confidence decimal(5,2);
    DECLARE @Reasons nvarchar(max);
    DECLARE @DateColsJson nvarchar(max);
    DECLARE @IndexedDateColsJson nvarchar(max);
    DECLARE @Analysis nvarchar(max);
    DECLARE @ClassificationReason nvarchar(max);
    DECLARE @ReasonList TABLE (Reason varchar(50), Weight decimal(5,2), Description nvarchar(max));

    DECLARE table_cursor CURSOR FOR 
    SELECT SchemaName, TableName 
    FROM #TableAnalysis
    WHERE Classification = 'Unclassified'
    AND TableRowCount >= @MinimumRows
    ORDER BY TableRowCount DESC; -- Analyze largest tables first

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @FullTableName = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
        SET @Confidence = 0;
        SET @Reasons = '[]';
        DELETE FROM @ReasonList;
        
        -- Get date columns
        SET @SQL = N'
        SELECT @DateColsJson = (
            SELECT 
                c.name AS [name],
                t.name AS [dataType],
                CASE 
                    WHEN c.name LIKE ''%Transaction%'' THEN 1.0
                    WHEN c.name LIKE ''%Date%'' THEN 0.8
                    ELSE 0.5
                END AS [weight]
            FROM sys.columns c
            INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
            WHERE c.object_id = OBJECT_ID(@SchemaTable)
            AND t.name IN (''datetime'', ''datetime2'', ''date'')
            FOR JSON PATH
        )';

        SET @SQL = REPLACE(@SQL, '@SchemaTable', '''' + @FullTableName + '''');
        EXEC sp_executesql @SQL, N'@DateColsJson nvarchar(max) OUTPUT', @DateColsJson OUTPUT;

        -- Get indexed date columns
        SET @SQL = N'
        SELECT @IndexedDateColsJson = (
            SELECT DISTINCT 
                c.name AS [name],
                i.name AS [indexName],
                i.type_desc AS [indexType]
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
            WHERE i.object_id = OBJECT_ID(@SchemaTable)
            AND t.name IN (''datetime'', ''datetime2'', ''date'')
            FOR JSON PATH
        )';

        SET @SQL = REPLACE(@SQL, '@SchemaTable', '''' + @FullTableName + '''');
        EXEC sp_executesql @SQL, N'@IndexedDateColsJson nvarchar(max) OUTPUT', @IndexedDateColsJson OUTPUT;

        -- High row count is a strong indicator (0.3)
        IF EXISTS (SELECT 1 FROM #TableAnalysis WHERE SchemaName = @SchemaName AND TableName = @TableName AND TableRowCount >= 100000)
        BEGIN
            SET @Confidence = @Confidence + 0.3;
            INSERT INTO @ReasonList 
            SELECT 'HighVolume', 0.3, 'Table has ' + FORMAT(TableRowCount, 'N0') + ' rows'
            FROM #TableAnalysis 
            WHERE SchemaName = @SchemaName AND TableName = @TableName;
        END
        ELSE IF EXISTS (SELECT 1 FROM #TableAnalysis WHERE SchemaName = @SchemaName AND TableName = @TableName AND TableRowCount >= 10000)
        BEGIN
            SET @Confidence = @Confidence + 0.2;
            INSERT INTO @ReasonList 
            SELECT 'MediumVolume', 0.2, 'Table has ' + FORMAT(TableRowCount, 'N0') + ' rows'
            FROM #TableAnalysis 
            WHERE SchemaName = @SchemaName AND TableName = @TableName;
        END

        -- Date columns (up to 0.3)
        IF @DateColsJson IS NOT NULL
        BEGIN
            DECLARE @DateScore decimal(5,2) = (
                SELECT MAX(CAST(JSON_VALUE(value, '$.weight') AS decimal(5,2)))
                FROM OPENJSON(@DateColsJson)
            );
            
            SET @Confidence = @Confidence + (@DateScore * 0.3);

            DECLARE @DateColNames nvarchar(max) = (
                SELECT STRING_AGG(JSON_VALUE(value, '$.name'), ', ')
                FROM OPENJSON(@DateColsJson)
            );

            INSERT INTO @ReasonList 
            VALUES ('DateColumns', @DateScore * 0.3, 
                'Has date columns: ' + @DateColNames + 
                ' (Score: ' + FORMAT(@DateScore * 0.3, 'N2') + ')'
            );
        END

        -- Indexed date columns (0.2)
        IF @IndexedDateColsJson IS NOT NULL
        BEGIN
            SET @Confidence = @Confidence + 0.2;

            DECLARE @IndexedColNames nvarchar(max) = (
                SELECT STRING_AGG(JSON_VALUE(value, '$.name'), ', ')
                FROM OPENJSON(@IndexedDateColsJson)
            );

            INSERT INTO @ReasonList 
            VALUES ('IndexedDates', 0.2,
                'Has indexed date columns: ' + @IndexedColNames
            );
        END

        -- Transaction-related name patterns (0.2)
        IF @TableName LIKE '%Transaction%' OR 
           @TableName LIKE '%Order%' OR 
           @TableName LIKE '%Invoice%' OR 
           @TableName LIKE '%Payment%' OR
           @TableName LIKE '%Event%' OR
           @TableName LIKE '%History%'
        BEGIN
            SET @Confidence = @Confidence + 0.2;
            INSERT INTO @ReasonList 
            VALUES ('NamePattern', 0.2, 'Table name suggests transactional data');
        END

        -- Build reason codes JSON
        SET @Reasons = (SELECT * FROM @ReasonList FOR JSON PATH);

        -- Build analysis JSON
        SET @Analysis = (
            SELECT 
                @Confidence AS confidence,
                @Reasons AS reasons,
                @DateColsJson AS dateColumns,
                @IndexedDateColsJson AS indexedDateColumns,
                TableRowCount
            FROM #TableAnalysis 
            WHERE SchemaName = @SchemaName 
            AND TableName = @TableName
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- Get classification reason
        SET @ClassificationReason = (
            SELECT STRING_AGG(Description, CHAR(13) + CHAR(10))
            FROM @ReasonList
        );

        -- Update analysis results
        UPDATE #TableAnalysis
        SET 
            DateColumns = @DateColsJson,
            IndexedDateColumns = @IndexedDateColsJson,
            TransactionConfidence = @Confidence,
            ReasonCodes = @Reasons,
            Analysis = @Analysis,
            Classification = CASE 
                WHEN @Confidence >= @ConfidenceThreshold THEN 'Transaction'
                WHEN @Confidence >= @ConfidenceThreshold * 0.7 THEN 'PossibleTransaction'
                ELSE 'NonTransaction'
            END,
            ClassificationReason = @ClassificationReason
        WHERE SchemaName = @SchemaName 
        AND TableName = @TableName;

        -- Log analysis result
        DECLARE @LogMsg nvarchar(max) = 
            'Analyzed ' + @FullTableName + CHAR(13) + CHAR(10) +
            'Confidence: ' + FORMAT(@Confidence, 'P1') + CHAR(13) + CHAR(10) +
            'Classification: ' + 
            CASE 
                WHEN @Confidence >= @ConfidenceThreshold THEN 'Transaction'
                WHEN @Confidence >= @ConfidenceThreshold * 0.7 THEN 'PossibleTransaction'
                ELSE 'NonTransaction'
            END + CHAR(13) + CHAR(10) +
            'Reasons:' + CHAR(13) + CHAR(10) + @ClassificationReason;

        EXEC dba.sp_LogDebug @Message = @LogMsg, @Category = 'TableAnalysis';

        FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName;
    END;

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- Output results
    -- First show transaction tables
    SELECT 
        SchemaName,
        TableName,
        FORMAT(TableRowCount, 'N0') AS RecordCount,
        CASE Classification
            WHEN 'Transaction' THEN 'Definite Transaction Table'
            WHEN 'PossibleTransaction' THEN 'Possible Transaction Table'
            ELSE Classification
        END AS Classification,
        FORMAT(TransactionConfidence, 'P1') AS Confidence,
        ClassificationReason
    FROM #TableAnalysis
    WHERE Classification IN ('Transaction', 'PossibleTransaction')
    ORDER BY 
        CASE Classification
            WHEN 'Transaction' THEN 1
            WHEN 'PossibleTransaction' THEN 2
            ELSE 3
        END,
        TableRowCount DESC;

    -- Then show large tables that weren't classified as transactions
    SELECT 
        SchemaName,
        TableName,
        FORMAT(TableRowCount, 'N0') AS RecordCount,
        Classification,
        FORMAT(TransactionConfidence, 'P1') AS Confidence,
        ClassificationReason
    FROM #TableAnalysis
    WHERE 
        Classification NOT IN ('Transaction', 'PossibleTransaction', 'Lookup')
        AND TableRowCount >= @MinimumRows
    ORDER BY TableRowCount DESC;

    DROP TABLE #TableAnalysis;
END;
GO