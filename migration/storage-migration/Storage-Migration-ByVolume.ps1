<#
.SYNOPSIS
    Migrates NAS volumes to Azure Storage with volume-level control.
.DESCRIPTION
    This script orchestrates the migration of NAS volumes to Azure Storage accounts. It validates volume accessibility,
    creates a migration plan, executes the migrations in parallel, and generates a report of the results.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$Region,
    
    [Parameter(Mandatory=$true)]
    [array]$VolumeConfigurations,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxParallelVolumes = 2,
    
    [Parameter(Mandatory=$false)]
    [bool]$UseDataBoxForLargeVolumes = $true
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "=== STORAGE MIGRATION (Volume-Based) ===" -ForegroundColor Green
    Write-Host "Total Volumes: $($VolumeConfigurations.Count)" -ForegroundColor Yellow
    Write-Host "Max Parallel: $MaxParallelVolumes" -ForegroundColor Yellow
    Write-Host "Data Box for Large: $UseDataBoxForLargeVolumes" -ForegroundColor Yellow

    # 1. Validate volume configurations
    Write-Host "`nStep 1: Validating volumes" -ForegroundColor Cyan
    $validatedVolumes = .\Scripts\Test-VolumeAccessibility.ps1 -VolumeConfigurations $VolumeConfigurations

    # 2. Create migration plan
    Write-Host "`nStep 2: Creating migration plan" -ForegroundColor Cyan
    $migrationPlan = .\Scripts\New-MigrationPlan.ps1 -Volumes $validatedVolumes

    # 3. Execute migrations
    Write-Host "`nStep 3: Executing volume migrations" -ForegroundColor Cyan
    $migrationResults = .\Scripts\Start-VolumeMigrations.ps1 `
        -MigrationPlan $migrationPlan `
        -StorageAccountName $StorageAccountName `
        -MaxParallelVolumes $MaxParallelVolumes `
        -UseDataBoxForLargeVolumes $UseDataBoxForLargeVolumes

    # 4. Generate report
    Write-Host "`nStep 4: Generating migration report" -ForegroundColor Cyan
    .\Scripts\New-MigrationReport.ps1 -MigrationResults $migrationResults

    Write-Host "`n=== STORAGE MIGRATION COMPLETED ===" -ForegroundColor Green
    Write-Host "Successfully migrated $($migrationResults.SuccessCount)/$($VolumeConfigurations.Count) volumes" -ForegroundColor White

    return $migrationResults

} catch {
    Write-Error "Storage migration failed: $($_.Exception.Message)"
    throw
}