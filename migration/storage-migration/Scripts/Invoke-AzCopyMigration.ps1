<#
.SYNOPSIS
    Executes storage migration using AzCopy with performance optimization and error handling. 
.DESCRIPTION
    Uses AzCopy for high-performance data transfer to Azure Storage with configurable parallelism.
    Monitors progress, handles errors, and generates a detailed migration report including performance metrics.
.PARAMETER SourcePath
    Source storage path
.PARAMETER TargetPath
    Target Azure storage path (SAS URL or storage account)
.PARAMETER MigrationPlan
    Migration plan containing volume details
.PARAMETER ParallelOperations
    Number of parallel operations (default: 32)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,
    
    [Parameter(Mandatory=$true)]
    [hashtable]$MigrationPlan,
    
    [Parameter(Mandatory=$false)]
    [int]$ParallelOperations = 32
)

function Write-AzCopyLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\azcopy-migration.log" -Append
}

function Test-AzCopyInstallation {
    try {
        Write-AzCopyLog "Testing AzCopy installation"
        
        $azCopyPath = Get-Command "azcopy" -ErrorAction SilentlyContinue
        if (!$azCopyPath) {
            # Try to find AzCopy in common installation paths
            $commonPaths = @(
                "$env:USERPROFILE\AppData\Local\Microsoft\Azure Storage Explorer\azcopy",
                "$env:ProgramFiles\Microsoft Azure Storage Explorer\azcopy",
                "$env:USERPROFILE\Downloads\azcopy_windows_amd64_*"
            )
            
            foreach ($path in $commonPaths) {
                if (Test-Path "$path\azcopy.exe") {
                    $env:PATH += ";$path"
                    Write-AzCopyLog "Found AzCopy at: $path"
                    break
                }
            }
        }
        
        # Test AzCopy version
        $versionResult = & azcopy --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-AzCopyLog "AzCopy version: $versionResult"
            return $true
        }
        else {
            throw "AzCopy not found or not working properly"
        }
    }
    catch {
        Write-AzCopyLog "AzCopy test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Initialize-AzCopyMigration {
    param([string]$Source, [string]$Target)
    
    try {
        Write-AzCopyLog "Initializing AzCopy migration"
        Write-AzCopyLog "Source: $Source"
        Write-AzCopyLog "Target: $Target"
        
        # Verify source accessibility
        if (!(Test-Path $Source)) {
            throw "Source path not accessible: $Source"
        }
        
        # Test target connectivity (for Azure Storage)
        if ($Target -like "https://*") {
            Write-AzCopyLog "Testing Azure Storage connectivity"
            # Simple test - try to list containers (if it's a storage account URL)
            $testResult = & azcopy list $Target 2>&1
            if ($LASTEXITCODE -ne 0 -and $testResult -like "*403*") {
                Write-AzCopyLog "Target storage accessible but requires authentication" -Level "WARNING"
            }
        }
        
        return @{
            Source = $Source
            Target = $Target
            StartTime = Get-Date
            Status = "Initialized"
        }
    }
    catch {
        Write-AzCopyLog "AzCopy initialization failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Invoke-AzCopyTransfer {
    param([hashtable]$Context, [hashtable]$Plan, [int]$Parallelism)
    
    try {
        Write-AzCopyLog "Starting AzCopy transfer with $Parallelism parallel operations"
        
        $source = $Context.Source
        $target = $Context.Target
        
        # Build AzCopy command arguments
        $azCopyArgs = @(
            "copy"
            "`"$source`""
            "`"$target`""
            "--recursive=true"
            "--overwrite=ifSourceNewer"
            "--check-length=true"
            "--log-level=INFO"
            "--output-type=json"
        )
        
        # Add performance optimization parameters
        $azCopyArgs += @(
            "--cap-mbps=1000"  # Limit throughput to 1000 Mbps
            "--check-md5=FailIfDifferent"
            "--preserve-smb-info=true"
            "--preserve-smb-permissions=true"
        )
        
        # Add parallel operations
        $azCopyArgs += "--parallelism=$Parallelism"
        
        # Execute AzCopy
        Write-AzCopyLog "Executing AzCopy command..."
        Write-AzCopyLog "Command: azcopy $($azCopyArgs -join ' ')"
        
        $processStartTime = Get-Date
        $process = Start-Process -FilePath "azcopy" `
            -ArgumentList $azCopyArgs `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput ".\azcopy-output.json" `
            -RedirectStandardError ".\azcopy-errors.log"
        
        $processEndTime = Get-Date
        $duration = $processEndTime - $processStartTime
        
        # Parse results
        $transferResults = @{
            ExitCode = $process.ExitCode
            Duration = $duration
            StartTime = $processStartTime
            EndTime = $processEndTime
        }
        
        # Try to read and parse the JSON output
        if (Test-Path ".\azcopy-output.json") {
            try {
                $outputContent = Get-Content -Path ".\azcopy-output.json" -Raw | ConvertFrom-Json
                $transferResults.Output = $outputContent
            }
            catch {
                Write-AzCopyLog "Could not parse AzCopy JSON output" -Level "WARNING"
            }
        }
        
        if ($process.ExitCode -eq 0) {
            Write-AzCopyLog "AzCopy transfer completed successfully" -Level "SUCCESS"
            $transferResults.Success = $true
        }
        else {
            Write-AzCopyLog "AzCopy transfer failed with exit code: $($process.ExitCode)" -Level "ERROR"
            $transferResults.Success = $false
            
            # Read error log for details
            if (Test-Path ".\azcopy-errors.log") {
                $errorContent = Get-Content -Path ".\azcopy-errors.log" -Raw
                $transferResults.Errors = $errorContent
                Write-AzCopyLog "AzCopy errors: $errorContent" -Level "ERROR"
            }
        }
        
        return $transferResults
    }
    catch {
        Write-AzCopyLog "AzCopy transfer execution failed: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
            ExitCode = -1
        }
    }
}

function Watch-AzCopyProgress {
    param([string]$JobId, [int]$CheckInterval = 30)
    
    try {
        Write-AzCopyLog "Monitoring AzCopy job: $JobId"
        
        # In AzCopy v10+, you can monitor jobs using the jobs commands
        $monitoringResults = @()
        
        do {
            # Get job status
            $jobStatus = & azcopy jobs show $JobId --output-type=json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $statusInfo = $jobStatus | ConvertFrom-Json
                $monitoringResults += @{
                    Timestamp = Get-Date
                    Status = $statusInfo.Status
                    TransferredBytes = $statusInfo.BytesTransferred
                    TotalBytes = $statusInfo.TotalBytes
                    Percentage = if ($statusInfo.TotalBytes -gt 0) { 
                        [math]::Round(($statusInfo.BytesTransferred / $statusInfo.TotalBytes) * 100, 2) 
                    } else { 0 }
                }
                
                Write-AzCopyLog "Progress: $($monitoringResults[-1].Percentage)% ($([math]::Round($statusInfo.BytesTransferred/1GB, 2)) GB / $([math]::Round($statusInfo.TotalBytes/1GB, 2)) GB)"
            }
            
            if ($statusInfo.Status -in @("Completed", "Failed", "Cancelled")) {
                break
            }
            
            Start-Sleep -Seconds $CheckInterval
        } while ($true)
        
        return $monitoringResults
    }
    catch {
        Write-AzCopyLog "Progress monitoring failed: $($_.Exception.Message)" -Level "WARNING"
        return @()
    }
}

function Get-AzCopyPerformanceMetrics {
    param([hashtable]$TransferResults, [hashtable]$Plan)
    
    try {
        Write-AzCopyLog "Calculating performance metrics"
        
        $totalSizeGB = $Plan.Timeline.TotalSizeGB
        $durationSeconds = $TransferResults.Duration.TotalSeconds
        
        $metrics = @{
            TotalDataGB = $totalSizeGB
            TransferTimeSeconds = [math]::Round($durationSeconds, 2)
            AverageSpeedMBps = if ($durationSeconds -gt 0) { 
                [math]::Round(($totalSizeGB * 1024) / $durationSeconds, 2) 
            } else { 0 }
            AverageSpeedMegabitsPerSec = if ($durationSeconds -gt 0) { 
                [math]::Round(($totalSizeGB * 8192) / $durationSeconds, 2) 
            } else { 0 }
        }
        
        # Add efficiency rating
        if ($metrics.AverageSpeedMBps -gt 80) {
            $metrics.Efficiency = "Excellent"
        } elseif ($metrics.AverageSpeedMBps -gt 50) {
            $metrics.Efficiency = "Good"
        } elseif ($metrics.AverageSpeedMBps -gt 20) {
            $metrics.Efficiency = "Fair"
        } else {
            $metrics.Efficiency = "Poor"
        }
        
        Write-AzCopyLog "Performance: $($metrics.AverageSpeedMBps) MB/s ($($metrics.Efficiency))"
        
        return $metrics
    }
    catch {
        Write-AzCopyLog "Performance metrics calculation failed: $($_.Exception.Message)" -Level "WARNING"
        return @{}
    }
}

# Main execution
try {
    Write-AzCopyLog "Starting AzCopy migration"
    Write-AzCopyLog "Source: $SourcePath"
    Write-AzCopyLog "Target: $TargetPath"
    Write-AzCopyLog "Total Data: $($MigrationPlan.Timeline.TotalSizeGB) GB"
    
    # Verify AzCopy installation
    if (!(Test-AzCopyInstallation)) {
        throw "AzCopy is not properly installed or configured"
    }
    
    # Initialize migration
    $migrationContext = Initialize-AzCopyMigration -Source $SourcePath -Target $TargetPath
    
    # Execute transfer
    $transferResults = Invoke-AzCopyTransfer -Context $migrationContext -Plan $MigrationPlan -Parallelism $ParallelOperations
    
    # Calculate performance metrics
    $performanceMetrics = Get-AzCopyPerformanceMetrics -TransferResults $transferResults -Plan $MigrationPlan
    
    # Compile final results
    $azCopyResults = @{
        MigrationContext = $migrationContext
        TransferResults = $transferResults
        PerformanceMetrics = $performanceMetrics
        OverallSuccess = $transferResults.Success
        CompletionTime = Get-Date
    }
    
    # Export results
    $resultsFile = ".\azcopy-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $azCopyResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultsFile
    
    # Display summary
    Write-Host "`n=== AZCOPY MIGRATION SUMMARY ===" -ForegroundColor Green
    Write-Host "Source: $SourcePath" -ForegroundColor Yellow
    Write-Host "Target: $TargetPath" -ForegroundColor Yellow
    Write-Host "Success: $($transferResults.Success)" -ForegroundColor $(if ($transferResults.Success) { "Green" } else { "Red" })
    Write-Host "Exit Code: $($transferResults.ExitCode)" -ForegroundColor $(if ($transferResults.ExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "Duration: $([math]::Round($transferResults.Duration.TotalMinutes, 2)) minutes" -ForegroundColor Yellow
    Write-Host "Average Speed: $($performanceMetrics.AverageSpeedMBps) MB/s" -ForegroundColor Cyan
    Write-Host "Efficiency: $($performanceMetrics.Efficiency)" -ForegroundColor Cyan
    Write-Host "Data Transferred: $($performanceMetrics.TotalDataGB) GB" -ForegroundColor Yellow
    
    if (!$transferResults.Success) {
        throw "AzCopy migration failed with exit code: $($transferResults.ExitCode)"
    }
    
    Write-AzCopyLog "AzCopy migration completed successfully" -Level "SUCCESS"
    Write-AzCopyLog "Results saved to: $resultsFile"
    
    return $azCopyResults
}
catch {
    Write-AzCopyLog "AzCopy migration failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}