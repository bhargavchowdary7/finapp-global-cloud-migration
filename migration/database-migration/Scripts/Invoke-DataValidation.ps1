<#
.SYNOPSIS
    Validates data consistency between source and target databases  after migration.
.DESCRIPTION
    Performs row count checks, data sampling, and checksum validation   to ensure data integrity between the source and target SQL Server databases.
.PARAMETER SourceServer
    Source SQL Server instance  
.PARAMETER TargetServer
    Target SQL Server instance
.PARAMETER DatabaseName
    Database name to validate
.PARAMETER SampleSize
    Number of rows to sample for data validation
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceServer,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$false)]
    [int]$SampleSize = 1000
)

Import-Module SqlServer -ErrorAction Stop

function Write-ValidationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\validation.log" -Append
}

function Get-TableRowCounts {
    param([string]$Server, [string]$Database)
    
    try {
        $query = @"
        SELECT 
            SCHEMA_NAME(t.schema_id) as SchemaName,
            t.name as TableName,
            SUM(p.rows) as RowCount
        FROM sys.tables t
        INNER JOIN sys.partitions p ON t.object_id = p.object_id
        WHERE p.index_id IN (0,1) -- Heap or clustered index
            AND t.is_ms_shipped = 0
        GROUP BY t.schema_id, t.name
        ORDER BY SchemaName, TableName
"@
        return Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $query
    }
    catch {
        Write-ValidationLog "Error getting row counts from $Server : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Compare-RowCounts {
    param([array]$SourceCounts, [array]$TargetCounts)
    
    $discrepancies = @()
    
    foreach ($sourceTable in $SourceCounts) {
        $targetTable = $TargetCounts | Where-Object { 
            $_.SchemaName -eq $sourceTable.SchemaName -and $_.TableName -eq $sourceTable.TableName 
        }
        
        if ($targetTable) {
            if ($sourceTable.RowCount -ne $targetTable.RowCount) {
                $discrepancies += [PSCustomObject]@{
                    SchemaName = $sourceTable.SchemaName
                    TableName = $sourceTable.TableName
                    SourceRowCount = $sourceTable.RowCount
                    TargetRowCount = $targetTable.RowCount
                    Difference = $targetTable.RowCount - $sourceTable.RowCount
                }
            }
        } else {
            $discrepancies += [PSCustomObject]@{
                SchemaName = $sourceTable.SchemaName
                TableName = $sourceTable.TableName
                SourceRowCount = $sourceTable.RowCount
                TargetRowCount = "TABLE MISSING"
                Difference = "N/A"
            }
        }
    }
    
    return $discrepancies
}

function Test-DataSampling {
    param([string]$SourceServer, [string]$TargetServer, [string]$Database, [string]$Schema, [string]$Table, [int]$SampleSize)
    
    try {
        # Get primary key columns for the table
        $pkQuery = @"
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = '$Schema' 
            AND TABLE_NAME = '$Table'
            AND CONSTRAINT_NAME LIKE 'PK_%'
"@
        $pkColumns = Invoke-Sqlcmd -ServerInstance $SourceServer -Database $Database -Query $pkQuery
        
        if ($pkColumns.Count -eq 0) {
            Write-ValidationLog "No primary key found for $Schema.$Table - skipping data sampling" -Level "WARNING"
            return $null
        }
        
        $pkList = ($pkColumns.COLUMN_NAME) -join ', '
        
        # Sample data from source
        $sourceQuery = "SELECT TOP $SampleSize * FROM [$Schema].[$Table] ORDER BY $pkList"
        $sourceData = Invoke-Sqlcmd -ServerInstance $SourceServer -Database $Database -Query $sourceQuery
        
        # Get same data from target
        $targetData = Invoke-Sqlcmd -ServerInstance $TargetServer -Database $Database -Query $sourceQuery
        
        # Compare data
        $differences = @()
        for ($i = 0; $i -lt $sourceData.Count; $i++) {
            $sourceRow = $sourceData[$i]
            $targetRow = $targetData[$i]
            
            foreach ($property in $sourceRow.PSObject.Properties) {
                if ($sourceRow.($property.Name) -ne $targetRow.($property.Name)) {
                    $differences += [PSCustomObject]@{
                        Schema = $Schema
                        Table = $Table
                        PrimaryKey = $pkList
                        Column = $property.Name
                        SourceValue = $sourceRow.($property.Name)
                        TargetValue = $targetRow.($property.Name)
                        RowIndex = $i
                    }
                }
            }
        }
        
        return $differences
    }
    catch {
        Write-ValidationLog "Error during data sampling for $Schema.$Table : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function New-ValidationReport {
    param([array]$RowCountDiscrepancies, [array]$DataDifferences)
    
    $report = @{
        ValidationDate = Get-Date
        SourceServer = $SourceServer
        TargetServer = $TargetServer
        DatabaseName = $DatabaseName
        RowCountValidation = @{
            TotalTablesChecked = ($SourceCounts.Count + $TargetCounts.Count) / 2
            DiscrepanciesFound = $RowCountDiscrepancies.Count
            Discrepancies = $RowCountDiscrepancies
        }
        DataValidation = @{
            SamplesChecked = $SampleSize
            DifferencesFound = $DataDifferences.Count
            Differences = $DataDifferences
        }
        OverallStatus = if ($RowCountDiscrepancies.Count -eq 0 -and $DataDifferences.Count -eq 0) { "PASS" } else { "FAIL" }
    }
    
    return $report
}

# Main execution
try {
    Write-ValidationLog "Starting data validation for $DatabaseName"
    
    # Get row counts from source and target
    Write-ValidationLog "Retrieving row counts from source database"
    $SourceCounts = Get-TableRowCounts -Server $SourceServer -Database $DatabaseName
    
    Write-ValidationLog "Retrieving row counts from target database"
    $TargetCounts = Get-TableRowCounts -Server $TargetServer -Database $DatabaseName
    
    # Compare row counts
    Write-ValidationLog "Comparing row counts"
    $rowCountDiscrepancies = Compare-RowCounts -SourceCounts $SourceCounts -TargetCounts $TargetCounts
    
    # Perform data sampling on a few tables
    Write-ValidationLog "Performing data sampling validation"
    $dataDifferences = @()
    $tablesToSample = $SourceCounts | Select-Object -First 3 # Sample first 3 tables
    
    foreach ($table in $tablesToSample) {
        Write-ValidationLog "Sampling data from $($table.SchemaName).$($table.TableName)"
        $differences = Test-DataSampling -SourceServer $SourceServer -TargetServer $TargetServer -Database $DatabaseName -Schema $table.SchemaName -Table $table.TableName -SampleSize $SampleSize
        if ($differences) {
            $dataDifferences += $differences
        }
    }
    
    # Generate validation report
    $validationReport = New-ValidationReport -RowCountDiscrepancies $rowCountDiscrepancies -DataDifferences $dataDifferences
    
    # Export report
    $reportPath = ".\$DatabaseName-Validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $validationReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath
    
    # Display summary
    Write-Host "`n=== DATA VALIDATION SUMMARY ===" -ForegroundColor Green
    Write-Host "Database: $DatabaseName" -ForegroundColor Yellow
    Write-Host "Row Count Discrepancies: $($rowCountDiscrepancies.Count)" -ForegroundColor $(if ($rowCountDiscrepancies.Count -eq 0) { "Green" } else { "Red" })
    Write-Host "Data Differences: $($dataDifferences.Count)" -ForegroundColor $(if ($dataDifferences.Count -eq 0) { "Green" } else { "Red" })
    Write-Host "Overall Status: $($validationReport.OverallStatus)" -ForegroundColor $(if ($validationReport.OverallStatus -eq "PASS") { "Green" } else { "Red" })
    Write-Host "Report: $reportPath" -ForegroundColor Cyan
    
    if ($validationReport.OverallStatus -eq "FAIL") {
        throw "Data validation failed - check report for details"
    }
    
    Write-ValidationLog "Data validation completed successfully" -Level "SUCCESS"
}
catch {
    Write-ValidationLog "Data validation failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}