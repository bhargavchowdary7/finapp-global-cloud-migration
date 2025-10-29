<#
.SYNOPSIS
    Executes parallel volume migrations based on a migration plan.
.DESCRIPTION
    This script takes a migration plan and performs the migration of each NAS volume to Azure Storage in parallel,
    respecting the maximum number of concurrent migrations specified. It supports using Azure Data Box for large
    volume migrations.
#>

param(
    [Parameter(Mandatory=$true)]
    [array]$MigrationPlan,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [int]$MaxParallelVolumes,
    
    [Parameter(Mandatory=$false)]
    [bool]$UseDataBoxForLargeVolumes = $true
)

try {
    Write-Host "Starting parallel volume migrations" -ForegroundColor Yellow

    $migrationJobs = @()

    foreach ($volume in $MigrationPlan) {
        # Wait if maximum parallel jobs reached
        while (($migrationJobs | Where-Object { $_.State -eq "Running" }).Count -ge $MaxParallelVolumes) {
            Write-Host "  Maximum parallel jobs reached, waiting..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }

        # Start migration job
        Write-Host "  Starting migration: $($volume.VolumeName)" -ForegroundColor Green
        
        $job = Start-Job -ScriptBlock {
            param($volume, $StorageAccountName, $UseDataBox)
            
            try {
                $result = .\Scripts\Invoke-SingleVolumeMigration.ps1 `
                    -Volume $volume `
                    -StorageAccountName $StorageAccountName `
                    -UseDataBox $UseDataBox
                
                return @{ Status = "Completed"; Result = $result }
            }
            catch {
                return @{ Status = "Failed"; Error = $_.Exception.Message }
            }
        } -ArgumentList $volume, $StorageAccountName, $UseDataBoxForLargeVolumes

        $migrationJobs += @{ Volume = $volume; Job = $job }
    }

    # Wait for all jobs to complete
    Write-Host "`nWaiting for all migrations to complete..." -ForegroundColor Yellow
    $migrationJobs | ForEach-Object { $_.Job | Wait-Job }

    # Collect results
    $results = @()
    foreach ($item in $migrationJobs) {
        $result = $item.Job | Receive-Job
        $results += @{ Volume = $item.Volume; Result = $result }
        $item.Job | Remove-Job
    }

    return @{
        Results = $results
        SuccessCount = ($results | Where-Object { $_.Result.Status -eq "Completed" }).Count
        TotalCount = $results.Count
    }

} catch {
    Write-Error "Volume migrations failed: $($_.Exception.Message)"
    throw
}