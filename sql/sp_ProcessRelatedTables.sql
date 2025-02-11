CREATE OR ALTER PROCEDURE dba.sp_ProcessRelatedTables
    @ExportID int,
    @BatchSize int = 10000,
    @Debug bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @msg nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @PKColumn nvarchar(128);
    DECLARE @TableSchema nvarchar(128);
    DECLARE @TableName nvarchar(128);
    DECLARE @FullTableName nvarchar(256);
    DECLARE @ExportTableName nvarchar(256);
    DECLARE @StartProcessTime datetime;
    DECLARE @RowCount int;
    DECLARE @BatchNumber int;
    DECLARE @RelationshipLevel int;
    DECLARE @Priority int;
    DECLARE @ParentColumn nvarchar(128);

    -- Get all supporting tables ordered by relationship level
    DECLARE table_cursor CURSOR FOR
    SELECT DISTINCT
        tc.SchemaName,
        tc.TableName,
        tc.Priority - 1 as RelationshipLevel, -- Priority is RelationshipLevel + 1
        tc.Priority -- Include in SELECT for ORDER BY
    FROM dba.TableClassification tc
    WHERE tc.Classification = 'Supporting'
    ORDER BY tc.Priority; -- Process closest relationships first

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableSchema, @TableName, @RelationshipLevel, @Priority;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StartProcessTime = GETDATE();
        SET @FullTableName = QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
        SET @ExportTableName = QUOTENAME('dba') + '.' + QUOTENAME('Export_' + @TableSchema + '_' + @TableName);
        SET @BatchNumber = 1;
        SET @RowCount = 0;

        IF @Debug = 1 
            RAISERROR('Processing supporting table: [%s].[%s] (Priority: %d)', 0, 1, @TableSchema, @TableName, @Priority) WITH NOWAIT;

        -- Get primary key column
        SELECT TOP 1 @PKColumn = c.name
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.is_primary_key = 1
        AND i.object_id = OBJECT_ID(@FullTableName);

        IF @PKColumn IS NULL
        BEGIN
            RAISERROR('No primary key found for table [%s].[%s]', 16, 1, @TableSchema, @TableName);
            CONTINUE;
        END

        -- Check if table is a child or parent in relationships
        DECLARE @IsChild bit = 0;
        DECLARE @IsParent bit = 0;

        -- Check for child relationship
        SELECT TOP 1 @ParentColumn = tr.ParentColumn, @IsChild = 1
        FROM dba.TableRelationships tr
        WHERE tr.ChildSchema = @TableSchema
        AND tr.ChildTable = @TableName
        AND tr.ChildColumn = @PKColumn;

        -- If not a child, check for parent relationship
        IF @ParentColumn IS NULL
        BEGIN
            SELECT TOP 1 @ParentColumn = tr.ChildColumn, @IsParent = 1
            FROM dba.TableRelationships tr
            WHERE tr.ParentSchema = @TableSchema
            AND tr.ParentTable = @TableName
            AND tr.ParentColumn = @PKColumn;

            IF @ParentColumn IS NULL
            BEGIN
                -- If neither child nor parent relationship found, treat as full copy
                UPDATE dba.TableClassification
                SET Classification = 'Full Copy'
                WHERE SchemaName = @TableSchema
                AND TableName = @TableName;
                
                RAISERROR('Table [%s].[%s] has no relationships, reclassifying as Full Copy', 0, 1, @TableSchema, @TableName);
                CONTINUE;
            END
        END

        -- Create export table if it doesn't exist
        IF OBJECT_ID(@ExportTableName, 'U') IS NULL
        BEGIN
            SET @SQL = '
            CREATE TABLE ' + @ExportTableName + ' (
                ExportID int NOT NULL,
                SourceID ' + 
                (
                    SELECT CASE 
                        WHEN t.name IN ('bigint') THEN 'bigint'
                        WHEN t.name IN ('int', 'smallint', 'tinyint') THEN 'int'
                        ELSE 'nvarchar(128)'
                    END
                    FROM sys.columns c
                    JOIN sys.types t ON c.system_type_id = t.system_type_id
                    WHERE c.object_id = OBJECT_ID(@FullTableName)
                    AND c.name = @PKColumn
                ) + ' NOT NULL,
                PRIMARY KEY (ExportID, SourceID)
            )';
            EXEC sp_executesql @SQL;
        END

        -- Build non-recursive query to find all related records
        SET @SQL = '
        SELECT DISTINCT s.' + QUOTENAME(@PKColumn) + ' as SourceID
        FROM ' + @FullTableName + ' s
        WHERE 1=0 ' +
        -- Handle child relationships (table references other tables)
        CASE WHEN @IsChild = 1 THEN '
        OR EXISTS (
            SELECT 1
            FROM dba.TableRelationships tr
            INNER JOIN dba.TableClassification tc
                ON tr.ParentSchema = tc.SchemaName
                AND tr.ParentTable = tc.TableName
            WHERE tr.ChildSchema = ''' + @TableSchema + '''
                AND tr.ChildTable = ''' + @TableName + '''
                AND tr.ChildColumn = ''' + @PKColumn + '''
                AND tc.Classification IN (''Transaction'', ''Supporting'')
                AND EXISTS (
                    SELECT 1
                    FROM dba.[Export_'' + tr.ParentSchema + ''_'' + tr.ParentTable + ''] e
                    WHERE e.ExportID = @ExportID
                    AND e.SourceID = s.' + QUOTENAME(@ParentColumn) + '
                )
        )' ELSE '' END +
        -- Handle parent relationships (table is referenced by other tables)
        CASE WHEN @IsParent = 1 THEN '
        OR EXISTS (
            SELECT 1
            FROM dba.TableRelationships tr
            INNER JOIN dba.TableClassification tc
                ON tr.ChildSchema = tc.SchemaName
                AND tr.ChildTable = tc.TableName
            WHERE tr.ParentSchema = ''' + @TableSchema + '''
                AND tr.ParentTable = ''' + @TableName + '''
                AND tr.ParentColumn = ''' + @PKColumn + '''
                AND tc.Classification IN (''Transaction'', ''Supporting'')
                AND EXISTS (
                    SELECT 1
                    FROM dba.[Export_'' + tr.ChildSchema + ''_'' + tr.ChildTable + ''] e
                    WHERE e.ExportID = @ExportID
                    AND e.SourceID = s.' + QUOTENAME(@ParentColumn) + '
                )
        )' ELSE '' END + '
        )
        INSERT INTO ' + @ExportTableName + ' (ExportID, SourceID)
        SELECT DISTINCT @ExportID, SourceID
        FROM RelatedRecords
        OPTION (MAXRECURSION 0)';

        EXEC sp_executesql @SQL, 
            N'@ExportID int', 
            @ExportID;

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
            @TableName,
            @TableSchema,
            @RowCount,
            DATEDIFF(ms, @StartProcessTime, GETDATE()) / 1000.0,
            @RelationshipLevel,
            @BatchNumber,
            @StartProcessTime,
            GETDATE()
        );

        IF @Debug = 1
        BEGIN
            SET @msg = CONCAT(
                'Processed ', @TableSchema, '.', @TableName, CHAR(13), CHAR(10),
                'Priority: ', @Priority, CHAR(13), CHAR(10),
                'Rows: ', @RowCount, CHAR(13), CHAR(10),
                'Time: ', CAST(DATEDIFF(ms, @StartProcessTime, GETDATE()) / 1000.0 AS varchar(20)), ' seconds'
            );
            RAISERROR(@msg, 0, 1) WITH NOWAIT;
        END

        FETCH NEXT FROM table_cursor INTO @TableSchema, @TableName, @RelationshipLevel, @Priority;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;
END;
GO