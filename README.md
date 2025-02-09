# SQL Server Date-Based Data Export System

A system for exporting subsets of SQL Server databases based on date criteria while maintaining referential integrity.

## Overview

This system analyzes SQL Server databases to identify and export:
1. Transaction data within a specified date range
2. Related data necessary for referential integrity
3. Full content of non-transaction tables

## Core Components

### Configuration Tables

- `dba.ExportConfig`: Configures export behavior for each table
  - Transaction table identification
  - Date column specifications
  - Export priorities and batch sizes
  - Relationship depth controls

- `dba.TableRelationships`: Maps table relationships
  - Parent-child relationships
  - Relationship levels
  - Relationship chains

- `dba.ExportLog`: Tracks export operations
  - Start/end times
  - Status and error tracking
  - Row counts

- `dba.ExportPerformance`: Monitors export performance
  - Per-table metrics
  - Batch processing stats
  - Relationship depth impact

### Key Features

1. Automated Transaction Table Detection
   - Analyzes table characteristics
   - Uses naming patterns (e.g., Registrations, Visits, Estimates)
   - Configurable through ExportConfig

2. Relationship Management
   - Direct foreign key relationships
   - Configurable relationship depth
   - Performance-optimized for large databases

3. Performance Optimization
   - Batch processing for large tables
   - Progress tracking
   - Performance monitoring
   - Indexed operations

4. Flexible Configuration
   - Per-table export settings
   - Force full table exports when needed
   - Configurable batch sizes
   - Adjustable relationship depths

## Usage

1. Initial Setup
   ```sql
   -- Run the initial setup script
   EXEC sp_executesql @sql = N'path/to/initial_setup.sql'
   ```

2. Configure Export Settings
   ```sql
   -- Example configuration
   INSERT INTO dba.ExportConfig (TableName, SchemaName, IsTransactionTable, DateColumnName)
   VALUES ('Orders', 'dbo', 1, 'OrderDate')
   ```

3. Run Export Analysis
   (Stored procedures to be implemented)

## Design Considerations

1. Large Database Support
   - Designed for databases 600GB+
   - Batch processing
   - Performance monitoring
   - Resource usage optimization

2. Relationship Handling
   - Initial implementation uses direct relationships
   - Extensible for recursive relationships if needed
   - Configurable relationship depth

3. Error Handling
   - Comprehensive logging
   - Error tracking
   - Recovery mechanisms

## Implementation Status

- [x] Core table structure
- [x] Initial setup script
- [ ] Analysis stored procedures
- [ ] Export table generation
- [ ] Data extraction procedures
- [ ] Performance monitoring
- [ ] Error handling
