CREATE OR ALTER PROCEDURE dba.sp_InitializeMetadata
    @ClearExistingData bit = 1,        -- Whether to clear existing export tables
    @ResetConfiguration bit = 0,        -- Whether to reset debug configuration to defaults
    @InitialClassification bit = 1      -- Whether to perform initial table classification
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @msg nvarchar(max);
    DECLARE @SQL nvarchar(max);
    DECLARE @TableName nvarchar(128);
    DECLARE @SchemaName nvarchar(128);
    
    -- Ensure metadata tables exist
    EXEC dba.sp_CreateMetadataTables;

    -- Clear existing data if requested
    IF @ClearExistingData = 1
    BEGIN
        -- Clear classification history
        TRUNCATE TABLE dba.TableClassificationHistory;
        
        -- Clear dual-role table configuration
        TRUNCATE TABLE dba.DualRoleTables;
        
        -- Clear export processing log
        TRUNCATE TABLE dba.ExportProcessingLog;
        
        -- Drop existing export tables
        DECLARE export_tables CURSOR FOR
        SELECT 
            s.name AS SchemaName,
            t.name AS TableName
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE 
            s.name = 'dba'
            AND t.name LIKE 'Export_%';
        
        OPEN export_tables;
        FETCH NEXT FROM export_tables INTO @SchemaName, @TableName;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @SQL = CONCAT('DROP TABLE ', QUOTENAME(@SchemaName), '.', QUOTENAME(@TableName));
            EXEC sp_executesql @SQL;
            
            FETCH NEXT FROM export_tables INTO @SchemaName, @TableName;
        END
        
        CLOSE export_tables;
        DEALLOCATE export_tables;
    END

    -- Reset debug configuration if requested
    IF @ResetConfiguration = 1
    BEGIN
        DELETE FROM dba.DebugConfiguration;
        
        -- Reinsert default configuration
        INSERT INTO dba.DebugConfiguration (CategoryName, OutputLevel, IsEnabled, MaxOutputRows)
        VALUES 
            ('Relationships', 'WARN', 1, 1000),
            ('TableAnalysis', 'WARN', 1, 1000),
            ('Classification', 'WARN', 1, 1000),
            ('ExportTables', 'WARN', 1, 1000),
            ('Validation', 'WARN', 1, 1000);
    END

    -- Clear and rebuild relationship metadata
    DELETE FROM dba.TableRelationships;
    
    -- Reset relationship types if needed
    IF @ResetConfiguration = 1
    BEGIN
        DELETE FROM dba.RelationshipTypes;
        
        INSERT INTO dba.RelationshipTypes (TypeName, Description, Priority)
        VALUES 
            ('PrimaryForeignKey', 'Direct foreign key relationship', 100),
            ('SecondaryForeignKey', 'Indirect foreign key relationship through another table', 90),
            ('Manual', 'Manually defined relationship', 80),
            ('Logical', 'Logical relationship based on data patterns', 70);
    END

    -- Perform initial classification if requested
    IF @InitialClassification = 1
    BEGIN
        -- Create temporary table for initial classification
        CREATE TABLE #InitialClassification
        (
            SchemaName nvarchar(128),
            TableName nvarchar(128),
            Classification varchar(50),
            ConfidenceScore decimal(5,2),
            DateColumnName nvarchar(128),
            ReasonCodes nvarchar(max),
            TableRowCount bigint
        );

        -- Get all user tables
        INSERT INTO #InitialClassification (SchemaName, TableName, TableRowCount)
        SELECT 
            s.name AS SchemaName,
            t.name AS TableName,
            SUM(p.rows) AS TableRowCount
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.partitions p ON t.object_id = p.object_id
        WHERE 
            t.is_ms_shipped = 0
            AND s.name != 'dba'
            AND p.index_id IN (0,1)
        GROUP BY s.name, t.name;

        -- Mark small tables (less than 100 rows) as lookup tables
        UPDATE #InitialClassification
        SET 
            Classification = 'Lookup',
            ConfidenceScore = 1.0,
            ReasonCodes = JSON_MODIFY('[]', 'append', JSON_QUERY('{"reason": "SmallTable", "score": 1.0}'))
        WHERE TableRowCount < 100;

        -- Insert classifications into history
        INSERT INTO dba.TableClassificationHistory
        (
            SchemaName,
            TableName,
            PreviousClassification,
            NewClassification,
            ConfidenceScore,
            ReasonCodes,
            Notes
        )
        SELECT
            SchemaName,
            TableName,
            NULL AS PreviousClassification,
            Classification,
            ConfidenceScore,
            ReasonCodes,
            'Initial classification during metadata initialization'
        FROM #InitialClassification
        WHERE Classification IS NOT NULL;

        DROP TABLE #InitialClassification;
    END

    -- Log initialization
    INSERT INTO dba.ExportProcessingLog
    (
        SchemaName,
        TableName,
        ProcessingPhase,
        StartTime,
        EndTime,
        Status,
        Details
    )
    VALUES
    (
        'dba',
        'System',
        'Initialization',
        GETUTCDATE(),
        GETUTCDATE(),
        'Completed',
        JSON_MODIFY('{}', '$.parameters', JSON_QUERY(CONCAT(
            '{',
            '"ClearExistingData":', CAST(@ClearExistingData AS varchar(5)), ',',
            '"ResetConfiguration":', CAST(@ResetConfiguration AS varchar(5)), ',',
            '"InitialClassification":', CAST(@InitialClassification AS varchar(5)),
            '}'
        )))
    );
END;
GO