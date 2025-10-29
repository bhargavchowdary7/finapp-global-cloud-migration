<#
.SYNOPSIS
    Assesses source database for migration readiness and compatibility.
.DESCRIPTION
    Performs comprehensive assessment of SQL Server database including compatibility checks,
    object inventory, and migration recommendations. Generates a detailed report for migration planning.
.PARAMETER SourceServer
    Source SQL Server instance name
.PARAMETER DatabaseName
    Name of the database to assess
.PARAMETER OutputPath
    Path for assessment reports
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\AssessmentReports"
)

# Import required modules
Import-Module SqlServer -ErrorAction Stop

function Write-MigrationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    
    # Log to file
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$OutputPath\migration.log" -Append
}

function Test-DatabaseConnectivity {
    param([string]$Server, [string]$Database)
    
    try {
        Write-MigrationLog "Testing connectivity to $Server\$Database"
        $connectionString = "Server=$Server;Database=$Database;Integrated Security=True;Connection Timeout=30"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $connection.Close()
        return $true
    }
    catch {
        Write-MigrationLog "Failed to connect to $Server\$Database : $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-DatabaseCompatibility {
    param([string]$Server, [string]$Database)
    
    try {
        $query = @"
        SELECT 
            compatibility_level,
        FROM sys.databases 
        WHERE name = '$Database'
"@
        $result = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $query
        return $result
    }
    catch {
        Write-MigrationLog "Error checking compatibility level: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-DatabaseObjectsInventory {
    param([string]$Server, [string]$Database)
    
    $objects = @{
        Tables = @()
        Views = @()
        StoredProcedures = @()
        Functions = @()
        Triggers = @()
    }
    
    try {
        # Get tables count and size
        $tablesQuery = @"
        SELECT 
            COUNT(*) as TableCount,
            SUM(CAST(size * 8.0 / 1024 AS DECIMAL(18,2))) as TotalSizeMB
        FROM sys.tables t
        INNER JOIN sys.partitions p ON t.object_id = p.object_id
        INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
"@
        $objects.Tables = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $tablesQuery
        
        # Get other objects counts
        $objectsQuery = @"
        SELECT 
            (SELECT COUNT(*) FROM sys.views) as ViewCount,
            (SELECT COUNT(*) FROM sys.procedures) as ProcedureCount,
            (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF')) as FunctionCount,
            (SELECT COUNT(*) FROM sys.triggers) as TriggerCount
"@
        $otherObjects = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $objectsQuery
        $objects.Views = $otherObjects.ViewCount
        $objects.StoredProcedures = $otherObjects.ProcedureCount
        $objects.Functions = $otherObjects.FunctionCount
        $objects.Triggers = $otherObjects.TriggerCount
        
        return $objects
    }
    catch {
        Write-MigrationLog "Error inventorying database objects: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-DatabaseSize {
    param([string]$Server, [string]$Database)
    
    try {
        $sizeQuery = @"
        SELECT 
            name as DatabaseName,
            SUM(size) * 8.0 / 1024 as SizeMB
        FROM sys.master_files
        WHERE database_id = DB_ID('$Database')
        GROUP BY name
"@
        return Invoke-Sqlcmd -ServerInstance $Server -Database 'master' -Query $sizeQuery
    }
    catch {
        Write-MigrationLog "Error getting database size: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Main execution
try {
    Write-MigrationLog "Starting database assessment for $SourceServer\$DatabaseName"
    
    # Create output directory
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force
    }
    
    # Test connectivity
    if (!(Test-DatabaseConnectivity -Server $SourceServer -Database $DatabaseName)) {
        throw "Cannot connect to source database"
    }
    
    # Gather assessment data
    Write-MigrationLog "Gathering database compatibility information"
    $compatibility = Get-DatabaseCompatibility -Server $SourceServer -Database $DatabaseName
    
    Write-MigrationLog "Inventorying database objects"
    $objects = Get-DatabaseObjectsInventory -Server $SourceServer -Database $DatabaseName
    
    Write-MigrationLog "Calculating database size"
    $size = Get-DatabaseSize -Server $SourceServer -Database $DatabaseName
    
    # Generate assessment report
    $assessmentReport = @{
        AssessmentDate = Get-Date
        SourceServer = $SourceServer
        DatabaseName = $DatabaseName
        CompatibilityLevel = $compatibility.compatibility_level
        ObjectCounts = $objects
        DatabaseSizeMB = $size.SizeMB
        Recommendations = @()
    }
    
    # Add recommendations based on assessment
    if ($compatibility.compatibility_level -lt 130) {
        $assessmentReport.Recommendations += "Consider upgrading compatibility level before migration"
    }
    
    if ($objects.Tables.TotalSizeMB -gt 10240) { # 10GB
        $assessmentReport.Recommendations += "Large database detected - consider using Azure Data Migration Service for minimal downtime"
    }
    
    # Export report
    $reportPath = "$OutputPath\$DatabaseName-Assessment-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $assessmentReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath
    
    Write-MigrationLog "Assessment completed successfully. Report saved to: $reportPath"
    
    # Display summary
    Write-Host "`n=== DATABASE ASSESSMENT SUMMARY ===" -ForegroundColor Green
    Write-Host "Database: $DatabaseName" -ForegroundColor Yellow
    Write-Host "Server: $SourceServer" -ForegroundColor Yellow
    Write-Host "Compatibility Level: $($compatibility.compatibility_level)" -ForegroundColor Yellow
    Write-Host "Total Tables: $($objects.Tables.TableCount)" -ForegroundColor Yellow
    Write-Host "Total Size: $([math]::Round($size.SizeMB, 2)) MB" -ForegroundColor Yellow
    Write-Host "Recommendations: $($assessmentReport.Recommendations.Count)" -ForegroundColor Yellow
    
    if ($assessmentReport.Recommendations.Count -gt 0) {
        Write-Host "`nRecommendations:" -ForegroundColor Cyan
        foreach ($recommendation in $assessmentReport.Recommendations) {
            Write-Host "  - $recommendation" -ForegroundColor White
        }
    }
}
catch {
    Write-MigrationLog "Assessment failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}