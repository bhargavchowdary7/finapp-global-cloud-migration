<#
.SYNOPSIS
    Migrates 50TB on-premises database to Azure PostgreSQL using Key Vault for secure credential management.
.DESCRIPTION
    Secure database migration with credentials from Azure Key Vault.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Region,
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSizeGB = 500
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "=== DATABASE MIGRATION (50TB) ===" -ForegroundColor Green
    Write-Host "Key Vault: $KeyVaultName" -ForegroundColor Yellow
    Write-Host "Region: $Region" -ForegroundColor Yellow
    Write-Host "Batch Size: $BatchSizeGB GB" -ForegroundColor Yellow

    # 1. Retrieve credentials from Key Vault
    Write-Host "`nStep 1: Retrieving credentials from Key Vault" -ForegroundColor Cyan
    $secrets = .\Scripts\Get-MigrationSecrets.ps1 -KeyVaultName $KeyVaultName -ResourceGroupName $ResourceGroupName

    # 2. Validate we have all required secrets
    .\Scripts\Test-KeyVaultSecrets.ps1 -Secrets $secrets

    # 3. Pre-migration assessment
    Write-Host "`nStep 2: Pre-migration assessment" -ForegroundColor Cyan
    .\Scripts\Invoke-DatabaseAssessment.ps1 -SourceServer $secrets.SourceServer -SourceDatabase $secrets.SourceDatabase

    # 4. Schema migration
    Write-Host "`nStep 3: Schema migration" -ForegroundColor Cyan
    .\Scripts\Invoke-SchemaMigration.ps1 `
        -SourceServer $secrets.SourceServer `
        -SourceDatabase $secrets.SourceDatabase `
        -TargetServer $secrets.TargetServer `
        -TargetDatabase $secrets.TargetDatabase

    # 5. Data migration in batches (50TB)
    Write-Host "`nStep 4: Data migration (50TB in batches)" -ForegroundColor Cyan
    $totalBatches = [math]::Ceiling(50000 / $BatchSizeGB)
    Write-Host "Total batches to process: $totalBatches" -ForegroundColor Yellow

    for ($batch = 1; $batch -le $totalBatches; $batch++) {
        Write-Host "Processing batch $batch of $totalBatches ($BatchSizeGB GB)" -ForegroundColor Green
        
        .\Scripts\Invoke-DataMigrationBatch.ps1 `
            -SourceServer $secrets.SourceServer `
            -SourceDatabase $secrets.SourceDatabase `
            -TargetServer $secrets.TargetServer `
            -TargetDatabase $secrets.TargetDatabase `
            -BatchNumber $batch `
            -BatchSizeGB $BatchSizeGB `
            -LogFile "migration-batch-$batch.log"
        
        $progress = [math]::Round(($batch / $totalBatches) * 100, 2)
        Write-Progress -Activity "Data Migration" -Status "Progress: $progress%" -PercentComplete $progress
    }

    # 6. Data validation
    Write-Host "`nStep 5: Data validation" -ForegroundColor Cyan
    .\Scripts\Invoke-DataValidation.ps1 `
        -SourceServer $secrets.SourceServer `
        -SourceDatabase $secrets.SourceDatabase `
        -TargetServer $secrets.TargetServer `
        -TargetDatabase $secrets.TargetDatabase

    # 7. Update application configuration
    Write-Host "`nStep 6: Updating application configuration" -ForegroundColor Cyan
    .\Scripts\Update-ApplicationConfig.ps1 -NewConnectionString "Host=$($secrets.TargetServer);Database=$($secrets.TargetDatabase);Username=$($secrets.TargetUsername)"

    Write-Host "`n=== DATABASE MIGRATION COMPLETED SUCCESSFULLY ===" -ForegroundColor Green
    Write-Host "50TB database migrated to Azure PostgreSQL" -ForegroundColor White
    Write-Host "All credentials secured via Azure Key Vault" -ForegroundColor White

} catch {
    Write-Error "Database migration failed: $($_.Exception.Message)"
    throw
}