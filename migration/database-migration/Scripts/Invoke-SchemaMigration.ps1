<#
.SYNOPSIS
    Migrates database schema from source to target SQL Server.
.DESCRIPTION
    Extracts schema from source database and deploys to target database. Validates the migration by comparing schema objects.
.PARAMETER SourceServer
    Source SQL Server instance
.PARAMETER TargetServer
    Target SQL Server instance
.PARAMETER DatabaseName
    Database name (same for source and target)
.PARAMETER ExportPath
    Path for schema export files
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceServer,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\SchemaExport"
)

# Import required modules
Import-Module SqlServer -ErrorAction Stop

function Write-MigrationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$ExportPath\schema-migration.log" -Append
}

function Export-DatabaseSchema {
    param([string]$Server, [string]$Database, [string]$OutputPath)
    
    try {
        Write-MigrationLog "Exporting schema from $Server\$Database"
        
        # Create SMO objects
        $serverConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection($Server)
        $serverInstance = New-Object Microsoft.SqlServer.Management.Smo.Server($serverConnection)
        $database = $serverInstance.Databases[$Database]
        
        # Create scripter object
        $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($serverInstance)
        $scripter.Options.ScriptDrops = $false
        $scripter.Options.WithDependencies = $true
        $scripter.Options.IncludeIfNotExists = $false
        $scripter.Options.ScriptSchema = $true
        $scripter.Options.ScriptData = $false
        
        # Script tables
        $tablesPath = "$OutputPath\Tables"
        if (!(Test-Path $tablesPath)) {
            New-Item -ItemType Directory -Path $tablesPath -Force
        }
        
        foreach ($table in $database.Tables) {
            if ($table.IsSystemObject -eq $false) {
                $tableScript = $scripter.Script($table)
                $tableScript | Out-File -FilePath "$tablesPath\$($table.Name).sql" -Encoding UTF8
            }
        }
        
        # Script stored procedures
        $proceduresPath = "$OutputPath\StoredProcedures"
        if (!(Test-Path $proceduresPath)) {
            New-Item -ItemType Directory -Path $proceduresPath -Force
        }
        
        foreach ($procedure in $database.StoredProcedures) {
            if ($procedure.IsSystemObject -eq $false) {
                $procedureScript = $scripter.Script($procedure)
                $procedureScript | Out-File -FilePath "$proceduresPath\$($procedure.Name).sql" -Encoding UTF8
            }
        }
        
        # Script views
        $viewsPath = "$OutputPath\Views"
        if (!(Test-Path $viewsPath)) {
            New-Item -ItemType Directory -Path $viewsPath -Force
        }
        
        foreach ($view in $database.Views) {
            if ($view.IsSystemObject -eq $false) {
                $viewScript = $scripter.Script($view)
                $viewScript | Out-File -FilePath "$viewsPath\$($view.Name).sql" -Encoding UTF8
            }
        }
        
        Write-MigrationLog "Schema export completed successfully"
        return $true
    }
    catch {
        Write-MigrationLog "Error exporting schema: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Import-DatabaseSchema {
    param([string]$Server, [string]$Database, [string]$SchemaPath)
    
    try {
        Write-MigrationLog "Importing schema to $Server\$Database"
        
        # Execute SQL files in correct order
        $executionOrder = @('Tables', 'Views', 'StoredProcedures')
        
        foreach ($objectType in $executionOrder) {
            $objectPath = "$SchemaPath\$objectType"
            if (Test-Path $objectPath) {
                $sqlFiles = Get-ChildItem -Path $objectPath -Filter "*.sql"
                foreach ($sqlFile in $sqlFiles) {
                    try {
                        Write-MigrationLog "Executing: $($sqlFile.Name)"
                        $sqlContent = Get-Content -Path $sqlFile.FullName -Raw
                        Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $sqlContent -QueryTimeout 0
                    }
                    catch {
                        Write-MigrationLog "Error executing $($sqlFile.Name): $($_.Exception.Message)" -Level "WARNING"
                    }
                }
            }
        }
        
        Write-MigrationLog "Schema import completed successfully"
        return $true
    }
    catch {
        Write-MigrationLog "Error importing schema: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-SchemaMigration {
    param([string]$SourceServer, [string]$TargetServer, [string]$DatabaseName)
    
    try {
        Write-MigrationLog "Validating schema migration"
        
        # Compare table counts
        $sourceTablesQuery = "SELECT COUNT(*) as TableCount FROM sys.tables WHERE is_ms_shipped = 0"
        $targetTablesQuery = "SELECT COUNT(*) as TableCount FROM sys.tables WHERE is_ms_shipped = 0"
        
        $sourceTables = Invoke-Sqlcmd -ServerInstance $SourceServer -Database $DatabaseName -Query $sourceTablesQuery
        $targetTables = Invoke-Sqlcmd -ServerInstance $TargetServer -Database $DatabaseName -Query $targetTablesQuery
        
        if ($sourceTables.TableCount -eq $targetTables.TableCount) {
            Write-MigrationLog "Table count validation passed: $($sourceTables.TableCount) tables"
            return $true
        } else {
            Write-MigrationLog "Table count validation failed: Source=$($sourceTables.TableCount), Target=$($targetTables.TableCount)" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-MigrationLog "Error during schema validation: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-MigrationLog "Starting schema migration for $DatabaseName"
    
    # Create export directory
    if (!(Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force
    }
    
    # Export schema from source
    if (!(Export-DatabaseSchema -Server $SourceServer -Database $DatabaseName -OutputPath $ExportPath)) {
        throw "Schema export failed"
    }
    
    # Import schema to target
    if (!(Import-DatabaseSchema -Server $TargetServer -Database $DatabaseName -SchemaPath $ExportPath)) {
        throw "Schema import failed"
    }
    
    # Validate migration
    if (!(Test-SchemaMigration -SourceServer $SourceServer -TargetServer $TargetServer -DatabaseName $DatabaseName)) {
        throw "Schema validation failed"
    }
    
    Write-MigrationLog "Schema migration completed successfully" -Level "SUCCESS"
}
catch {
    Write-MigrationLog "Schema migration failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}