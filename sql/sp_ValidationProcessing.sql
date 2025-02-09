-- Validation procedures for the DateExport system

-- Create user-defined table type for validation errors
IF TYPE_ID('dba.ValidationErrorType') IS NULL
BEGIN
    CREATE TYPE dba.ValidationErrorType AS TABLE (
        ErrorType varchar(50),
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        Description nvarchar(max)
    );
END
GO

CREATE OR ALTER PROCEDURE dba.sp_ValidateTableExistence
    @ExportID int,
    @Debug bit = 0,
    @ValidationErrors dba.ValidationErrorType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Return validation results directly
    SELECT 
        'Required Table Missing' as ErrorType,
        SchemaName,
        TableName,
        'Transaction table export is required but missing' as Description
    FROM dba.ExportConfig ec
    WHERE ec.IsTransactionTable = 1
    AND NOT EXISTS (
        SELECT 1
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = 'dba'
        AND t.name = 'Export_' + ec.SchemaName + '_' + ec.TableName
    );
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_ValidateRelationshipIntegrity
    @ExportID int,
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @Debug bit = 0,
    @ValidationErrors dba.ValidationErrorType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create temp table to store results
    CREATE TABLE #ValidationErrors (
        ErrorType varchar(50),
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        Description nvarchar(max)
    );
    
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @ParentChecks nvarchar(max);
    DECLARE @OrphanCount int;

    -- Get primary key column
    EXEC dba.sp_GetTablePrimaryKey
        @SchemaName = @SchemaName,
        @TableName = @TableName,
        @PKColumn = @PKColumn OUTPUT;

    -- Build validation query for each parent relationship
    SET @SQL = N'
    SELECT @OrphanCount = COUNT(*)
    FROM [dba].[Export_' + @SchemaName + '_' + @TableName + '] e
    INNER JOIN ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
        ON t.' + QUOTENAME(@PKColumn) + ' = e.SourceID
    WHERE e.ExportID = @ExportID
    AND NOT EXISTS (';

    WITH NumberedRelationships AS (
        SELECT 
            tr.ParentSchema,
            tr.ParentTable,
            tr.ParentColumn,
            tr.ChildColumn,
            ROW_NUMBER() OVER (ORDER BY tr.RelationshipLevel) as RowNum
        FROM dba.TableRelationships tr
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
        SET @SQL = @SQL + @ParentChecks + ')';
        
        IF @Debug = 1
        BEGIN
            DECLARE @msg nvarchar(max) = CONCAT(
                'Validating relationships for ', @SchemaName, '.', @TableName, CHAR(13), CHAR(10),
                'SQL:', CHAR(13), CHAR(10), @SQL
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        EXEC sp_executesql @SQL, 
            N'@ExportID int, @OrphanCount int OUTPUT',
            @ExportID, @OrphanCount OUTPUT;

        IF @OrphanCount > 0
        BEGIN
            INSERT INTO #ValidationErrors (
                ErrorType,
                SchemaName,
                TableName,
                Description
            )
            VALUES (
                'Orphaned Records', 
                @SchemaName, 
                @TableName, 
                'Found ' + CAST(@OrphanCount AS varchar(20)) + ' records without parent references'
            );
        END
    END

    -- Return results
    SELECT * FROM #ValidationErrors;
    DROP TABLE #ValidationErrors;
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_ValidateDataConsistency
    @ExportID int,
    @SchemaName nvarchar(128),
    @TableName nvarchar(128),
    @Debug bit = 0,
    @ValidationErrors dba.ValidationErrorType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create temp table to store results
    CREATE TABLE #ValidationErrors (
        ErrorType varchar(50),
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        Description nvarchar(max)
    );
    
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @InvalidRecords int;

    -- Get primary key column
    EXEC dba.sp_GetTablePrimaryKey
        @SchemaName = @SchemaName,
        @TableName = @TableName,
        @PKColumn = @PKColumn OUTPUT;

    -- Validate data consistency
    SET @SQL = N'
    SELECT @InvalidRecords = COUNT(*)
    FROM [dba].[Export_' + @SchemaName + '_' + @TableName + '] e
    WHERE e.ExportID = @ExportID
    AND NOT EXISTS (
        SELECT 1 
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
        WHERE t.' + QUOTENAME(@PKColumn) + ' = e.SourceID
    )';

    EXEC sp_executesql @SQL,
        N'@ExportID int, @InvalidRecords int OUTPUT',
        @ExportID, @InvalidRecords OUTPUT;

    IF @InvalidRecords > 0
    BEGIN
        INSERT INTO #ValidationErrors (
            ErrorType,
            SchemaName,
            TableName,
            Description
        )
        VALUES (
            'Invalid Records', 
            @SchemaName, 
            @TableName, 
            'Found ' + CAST(@InvalidRecords AS varchar(20)) + ' records that do not exist in source table'
        );
    END

    -- Return results
    SELECT * FROM #ValidationErrors;
    DROP TABLE #ValidationErrors;
END;
GO

CREATE OR ALTER PROCEDURE dba.sp_GenerateValidationReport
    @ExportID int,
    @ThrowError bit = 1,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ValidationErrors TABLE (
        ErrorType varchar(50),
        SchemaName nvarchar(128),
        TableName nvarchar(128),
        Description nvarchar(max)
    );

    -- Create empty table for READONLY parameters
    DECLARE @EmptyErrors dba.ValidationErrorType;

    -- Collect table existence errors
    INSERT INTO @ValidationErrors
    EXEC dba.sp_ValidateTableExistence 
        @ExportID = @ExportID,
        @Debug = @Debug,
        @ValidationErrors = @EmptyErrors;

    -- Process each table
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    
    DECLARE table_cursor CURSOR FOR
    SELECT DISTINCT 
        t.name AS TableName,
        s.name AS SchemaName
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_ms_shipped = 0
    AND s.name != 'dba'
    ORDER BY s.name, t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check relationship integrity
        INSERT INTO @ValidationErrors
        EXEC dba.sp_ValidateRelationshipIntegrity 
            @ExportID = @ExportID,
            @SchemaName = @SchemaName,
            @TableName = @TableName,
            @Debug = @Debug,
            @ValidationErrors = @EmptyErrors;

        -- Check data consistency
        INSERT INTO @ValidationErrors
        EXEC dba.sp_ValidateDataConsistency
            @ExportID = @ExportID,
            @SchemaName = @SchemaName,
            @TableName = @TableName,
            @Debug = @Debug,
            @ValidationErrors = @EmptyErrors;

        FETCH NEXT FROM table_cursor INTO @TableName, @SchemaName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- Update export log with validation status
    UPDATE dba.ExportLog
    SET Status = CASE 
            WHEN EXISTS (SELECT 1 FROM @ValidationErrors) THEN 'Validation Failed'
            ELSE 'Validation Passed'
        END
    WHERE ExportID = @ExportID;

    -- Return validation results
    SELECT 
        ErrorType,
        SchemaName,
        TableName,
        Description
    FROM @ValidationErrors
    ORDER BY 
        CASE ErrorType
            WHEN 'Required Table Missing' THEN 1
            WHEN 'Missing Table' THEN 2
            WHEN 'Orphaned Records' THEN 3
            WHEN 'Invalid Records' THEN 4
            ELSE 5
        END,
        SchemaName,
        TableName;

    -- Throw error if validation failed and requested
    IF @ThrowError = 1 AND EXISTS (SELECT 1 FROM @ValidationErrors)
    BEGIN
        DECLARE @ErrorMsg nvarchar(max) = (
            SELECT STRING_AGG(
                CONCAT(
                    ErrorType, ': ',
                    SchemaName, '.', TableName,
                    ' - ', Description
                ),
                CHAR(13) + CHAR(10)
            )
            FROM @ValidationErrors
        );

        RAISERROR(@ErrorMsg, 16, 1);
    END
END;
GO
