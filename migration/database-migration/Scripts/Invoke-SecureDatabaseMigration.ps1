<#
.SYNOPSIS
    Orchestrates secure database migration using Key Vault for credentials  and performs assessment, schema migration, and data validation.
.DESCRIPTION
    Main controller script that coordinates assessment, schema migration, and data validation phases
    for migrating a SQL Server database from a source to a target instance. Utilizes Azure Key Vault
    to securely retrieve connection strings and credentials. Generates a comprehensive migration report.
.PARAMETER SourceServer
    Source SQL Server instance
.PARAMETER TargetServer
    Target SQL Server instance
.PARAMETER DatabaseName
    Database name to migrate
.PARAMETER KeyVaultName
    Azure Key Vault containing connection secrets
.PARAMETER RunAssessment
    Switch to run database assessment
.PARAMETER RunSchemaMigration
    Switch to run schema migration
.PARAMETER RunDataValidation
    Switch to run data validation
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceServer,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$false)]
    [switch]$RunAssessment,
    
    [Parameter(Mandatory=$false)]
    [switch]$RunSchemaMigration,
    
    [Parameter(Mandatory=$false)]
    [switch]$RunDataValidation
)

function Write-MigrationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "SUCCESS") { "Green" } else { "White" })
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\secure-migration.log" -Append
}

function Get-SecretFromKeyVault {
    param([string]$VaultName, [string]$SecretName)
    
    try {
        return Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText
    }
    catch {
        Write-MigrationLog "Failed to retrieve secret $SecretName from Key Vault: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Invoke-DatabaseAssessmentPhase {
    Write-MigrationLog "=== STARTING DATABASE ASSESSMENT PHASE ===" -Level "INFO"
    
    try {
        $assessmentParams = @{
            SourceServer = $SourceServer
            DatabaseName = $DatabaseName
            OutputPath = ".\Assessment"
        }
        
        .\Invoke-DatabaseAssessment.ps1 @assessmentParams
        
        Write-MigrationLog "Database assessment completed successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-MigrationLog "Database assessment failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Invoke-SchemaMigrationPhase {
    Write-MigrationLog "=== STARTING SCHEMA MIGRATION PHASE ===" -Level "INFO"
    
    try {
        $schemaParams = @{
            SourceServer = $SourceServer
            TargetServer = $TargetServer
            DatabaseName = $DatabaseName
            ExportPath = ".\SchemaExport"
        }
        
        .\Invoke-SchemaMigration.ps1 @schemaParams
        
        Write-MigrationLog "Schema migration completed successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-MigrationLog "Schema migration failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Invoke-DataValidationPhase {
    Write-MigrationLog "=== STARTING DATA VALIDATION PHASE ===" -Level "INFO"
    
    try {
        $validationParams = @{
            SourceServer = $SourceServer
            TargetServer = $TargetServer
            DatabaseName = $DatabaseName
            SampleSize = 1000
        }
        
        .\Invoke-DataValidation.ps1 @validationParams
        
        Write-MigrationLog "Data validation completed successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-MigrationLog "Data validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-KeyVaultSecretsPhase {
    Write-MigrationLog "=== STARTING KEY VAULT VALIDATION PHASE ===" -Level "INFO"
    
    try {
        # Define expected secrets
        $expectedSecrets = @(
            "$SourceServer-$DatabaseName-connectionstring",
            "$TargetServer-$DatabaseName-connectionstring", 
            "$SourceServer-username",
            "$SourceServer-password",
            "$TargetServer-username",
            "$TargetServer-password"
        )
        
        $keyVaultParams = @{
            KeyVaultName = $KeyVaultName
            SecretNames = $expectedSecrets
        }
        
        .\Test-KeyVaultSecrets.ps1 @keyVaultParams
        
        Write-MigrationLog "Key Vault validation completed successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-MigrationLog "Key Vault validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-MigrationLog "Starting secure database migration for $DatabaseName"
    Write-MigrationLog "Source: $SourceServer" -Level "INFO"
    Write-MigrationLog "Target: $TargetServer" -Level "INFO"
    Write-MigrationLog "Key Vault: $KeyVaultName" -Level "INFO"
    
    $startTime = Get-Date
    $phaseResults = @{}
    
    # Phase 1: Key Vault Validation
    Write-MigrationLog "`nPhase 1: Key Vault Secrets Validation" -Level "INFO"
    $phaseResults.KeyVault = Test-KeyVaultSecretsPhase
    
    if (!$phaseResults.KeyVault) {
        throw "Key Vault validation failed - cannot proceed with migration"
    }
    
    # Phase 2: Database Assessment
    if ($RunAssessment) {
        Write-MigrationLog "`nPhase 2: Database Assessment" -Level "INFO"
        $phaseResults.Assessment = Invoke-DatabaseAssessmentPhase
        
        if (!$phaseResults.Assessment) {
            throw "Database assessment failed - cannot proceed with migration"
        }
    }
    
    # Phase 3: Schema Migration
    if ($RunSchemaMigration) {
        Write-MigrationLog "`nPhase 3: Schema Migration" -Level "INFO"
        $phaseResults.SchemaMigration = Invoke-SchemaMigrationPhase
        
        if (!$phaseResults.SchemaMigration) {
            throw "Schema migration failed - cannot proceed"
        }
    }
    
    # Phase 4: Data Validation
    if ($RunDataValidation) {
        Write-MigrationLog "`nPhase 4: Data Validation" -Level "INFO"
        $phaseResults.DataValidation = Invoke-DataValidationPhase
        
        if (!$phaseResults.DataValidation) {
            throw "Data validation failed"
        }
    }
    
    # Calculate duration
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Generate final report
    $migrationReport = @{
        MigrationDate = Get-Date
        SourceServer = $SourceServer
        TargetServer = $TargetServer
        DatabaseName = $DatabaseName
        KeyVaultName = $KeyVaultName
        Phases = $phaseResults
        Duration = @{
            TotalMinutes = [math]::Round($duration.TotalMinutes, 2)
            StartTime = $startTime
            EndTime = $endTime
        }
        OverallStatus = if ($phaseResults.Values -contains $false) { "FAILED" } else { "SUCCESS" }
    }
    
    # Export final report
    $reportPath = ".\$DatabaseName-Migration-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $migrationReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath
    
    # Display final summary
    Write-Host "`n" + "="*50 -ForegroundColor Green
    Write-Host "SECURE DATABASE MIGRATION COMPLETED" -ForegroundColor Green
    Write-Host "="*50 -ForegroundColor Green
    Write-Host "Database: $DatabaseName" -ForegroundColor Yellow
    Write-Host "Source: $SourceServer" -ForegroundColor Yellow
    Write-Host "Target: $TargetServer" -ForegroundColor Yellow
    Write-Host "Duration: $([math]::Round($duration.TotalMinutes, 2)) minutes" -ForegroundColor Yellow
    Write-Host "Overall Status: $($migrationReport.OverallStatus)" -ForegroundColor $(if ($migrationReport.OverallStatus -eq "SUCCESS") { "Green" } else { "Red" })
    Write-Host "Report: $reportPath" -ForegroundColor Cyan
    
    Write-Host "`nPhase Results:" -ForegroundColor Cyan
    foreach ($phase in $phaseResults.GetEnumerator()) {
        $statusColor = if ($phase.Value) { "Green" } else { "Red" }
        Write-Host "  $($phase.Key): $($phase.Value)" -ForegroundColor $statusColor
    }
    
    if ($migrationReport.OverallStatus -eq "SUCCESS") {
        Write-MigrationLog "Secure database migration completed successfully" -Level "SUCCESS"
    } else {
        throw "Migration completed with errors"
    }
}
catch {
    Write-MigrationLog "Secure database migration failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}