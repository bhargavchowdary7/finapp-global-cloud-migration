<#
.SYNOPSIS
    Migrates a single volume using the specified method with progress tracking and error handling.
.DESCRIPTION
    Handles the migration of individual volumes with progress tracking and error handling using either AzCopy or Robocopy.
    Validates the migration results and generates a detailed report for each volume migrated.
.PARAMETER Volume
    Volume object to migrate
.PARAMETER MigrationPlan
    Overall migration plan containing configuration
.PARAMETER LogPath
    Path for migration logs
#>

param(
    [Parameter(Mandatory=$true)]
    [hashtable]$Volume,
    
    [Parameter(Mandatory=$true)]
    [hashtable]$MigrationPlan,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\Logs"
)

function Write-VolumeLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$LogPath\volume-$($Volume.Name)-migration.log" -Append
}

function Initialize-VolumeMigration {
    param([hashtable]$Volume, [hashtable]$Plan)
    
    try {
        Write-VolumeLog "Initializing migration for volume: $($Volume.Name)"
        
        # Verify source accessibility
        if (!(Test-Path $Volume.Path)) {
            throw "Source path not accessible: $($Volume.Path)"
        }
        
        # Create target directory structure
        $targetPath = Join-Path $Plan.TargetPath $Volume.Name
        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Write-VolumeLog "Created target directory: $targetPath"
        }
        
        # Calculate checksum for source (if feasible)
        $sourceChecksum = Get-SourceChecksum -Path $Volume.Path
        
        return @{
            SourcePath = $Volume.Path
            TargetPath = $targetPath
            SourceChecksum = $sourceChecksum
            StartTime = Get-Date
            Status = "Initialized"
        }
    }
    catch {
        Write-VolumeLog "Volume migration initialization failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Get-SourceChecksum {
    param([string]$Path)
    
    try {
        Write-VolumeLog "Calculating source checksum for: $Path"
        
        # For large volumes, we'll use a sampling approach
        $sampleFiles = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue | 
                      Select-Object -First 10
        
        $checksumData = @()
        foreach ($file in $sampleFiles) {
            try {
                $hash = Get-FileHash -Path $file.FullName -Algorithm MD5
                $checksumData += @{
                    File = $file.Name
                    Checksum = $hash.Hash
                    Size = $file.Length
                }
            }
            catch {
                # Skip files that can't be hashed
            }
        }
        
        return $checksumData
    }
    catch {
        Write-VolumeLog "Checksum calculation failed: $($_.Exception.Message)" -Level "WARNING"
        return @()
    }
}

function Invoke-AzCopyVolumeMigration {
    param([hashtable]$MigrationContext, [hashtable]$Plan)
    
    try {
        Write-VolumeLog "Starting AzCopy migration for: $($MigrationContext.SourcePath)"
        
        $sourcePath = $MigrationContext.SourcePath
        $targetPath = $MigrationContext.TargetPath
        
        # Build AzCopy command
        $azCopyArgs = @(
            "copy"
            "`"$sourcePath`""
            "`"$targetPath`""
            "--recursive=true"
            "--check-length=true"
            "--log-level=INFO"
            "--overwrite=prompt"
        )
        
        # Execute AzCopy
        Write-VolumeLog "Executing: azcopy $($azCopyArgs -join ' ')"
        $process = Start-Process -FilePath "azcopy" -ArgumentList $azCopyArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-VolumeLog "AzCopy migration completed successfully" -Level "SUCCESS"
            return @{
                Success = $true
                ExitCode = $process.ExitCode
                Method = "AzCopy"
            }
        }
        else {
            throw "AzCopy failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-VolumeLog "AzCopy migration failed: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
            Method = "AzCopy"
        }
    }
}

function Invoke-RobocopyVolumeMigration {
    param([hashtable]$MigrationContext, [hashtable]$Plan)
    
    try {
        Write-VolumeLog "Starting Robocopy migration for: $($MigrationContext.SourcePath)"
        
        $sourcePath = $MigrationContext.SourcePath
        $targetPath = $MigrationContext.TargetPath
        
        # Build Robocopy command
        $robocopyArgs = @(
            "`"$sourcePath`""
            "`"$targetPath`""
            "/E"  # Copy subdirectories, including empty ones
            "/ZB"  # Use restartable mode; if access denied, use backup mode
            "/R:3" # Retry 3 times (default is 1 million)
            "/W:5" # Wait 5 seconds between retries (default is 30)
            "/MT:8" # Multi-threaded with 8 threads
            "/V"   # Produce verbose output
            "/TEE" # Output to console and log file
            "/LOG:`"$LogPath\robocopy-$($Volume.Name).log`""
        )
        
        # Execute Robocopy
        Write-VolumeLog "Executing: robocopy $($robocopyArgs -join ' ')"
        $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
        
        # Robocopy exit codes: https://ss64.com/nt/robocopy-exit.html
        $successCodes = @(0,1,2,3)  # 0=No files copied; 1=Files copied successfully; 2=Extra files; 3=Copy + Extra
        
        if ($process.ExitCode -in $successCodes) {
            Write-VolumeLog "Robocopy migration completed successfully" -Level "SUCCESS"
            return @{
                Success = $true
                ExitCode = $process.ExitCode
                Method = "Robocopy"
            }
        }
        else {
            throw "Robocopy failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-VolumeLog "Robocopy migration failed: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
            Method = "Robocopy"
        }
    }
}

function Test-VolumeMigration {
    param([hashtable]$MigrationContext)
    
    try {
        Write-VolumeLog "Testing migration results for: $($MigrationContext.TargetPath)"
        
        $testResults = @{
            TargetAccessible = Test-Path $MigrationContext.TargetPath
            FileCountMatch = $false
            SampleChecksumsMatch = $false
        }
        
        # Compare file counts
        $sourceFiles = @(Get-ChildItem -Path $MigrationContext.SourcePath -Recurse -File -ErrorAction SilentlyContinue)
        $targetFiles = @(Get-ChildItem -Path $MigrationContext.TargetPath -Recurse -File -ErrorAction SilentlyContinue)
        
        $testResults.FileCountMatch = ($sourceFiles.Count -eq $targetFiles.Count)
        Write-VolumeLog "File count check: Source=$($sourceFiles.Count), Target=$($targetFiles.Count), Match=$($testResults.FileCountMatch)"
        
        # Verify sample checksums
        if ($MigrationContext.SourceChecksum.Count -gt 0) {
            $checksumMatches = 0
            foreach ($sourceChecksum in $MigrationContext.SourceChecksum) {
                $targetFile = Join-Path $MigrationContext.TargetPath $sourceChecksum.File
                if (Test-Path $targetFile) {
                    $targetHash = Get-FileHash -Path $targetFile -Algorithm MD5
                    if ($targetHash.Hash -eq $sourceChecksum.Checksum) {
                        $checksumMatches++
                    }
                }
            }
            
            $testResults.SampleChecksumsMatch = ($checksumMatches -eq $MigrationContext.SourceChecksum.Count)
            Write-VolumeLog "Checksum verification: $checksumMatches/$($MigrationContext.SourceChecksum.Count) files match"
        }
        
        $testResults.OverallSuccess = ($testResults.TargetAccessible -and $testResults.FileCountMatch -and $testResults.SampleChecksumsMatch)
        
        return $testResults
    }
    catch {
        Write-VolumeLog "Migration test failed: $($_.Exception.Message)" -Level "ERROR"
        return @{
            TargetAccessible = $false
            FileCountMatch = $false
            SampleChecksumsMatch = $false
            OverallSuccess = $false
            Error = $_.Exception.Message
        }
    }
}

# Main execution
try {
    Write-VolumeLog "Starting migration for volume: $($Volume.Name)"
    Write-VolumeLog "Source: $($Volume.Path)"
    Write-VolumeLog "Size: $($Volume.SizeGB) GB"
    Write-VolumeLog "Items: $($Volume.ItemCount)"
    
    # Create log directory
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force
    }
    
    # Initialize migration
    $migrationContext = Initialize-VolumeMigration -Volume $Volume -Plan $MigrationPlan
    
    # Execute migration based on type
    $migrationResult = $null
    switch ($MigrationPlan.MigrationType) {
        "AzCopy" {
            $migrationResult = Invoke-AzCopyVolumeMigration -MigrationContext $migrationContext -Plan $MigrationPlan
        }
        default {
            $migrationResult = Invoke-RobocopyVolumeMigration -MigrationContext $migrationContext -Plan $MigrationPlan
        }
    }
    
    # Test migration results
    $testResults = Test-VolumeMigration -MigrationContext $migrationContext
    
    # Compile final results
    $volumeResults = @{
        VolumeName = $Volume.Name
        MigrationStart = $migrationContext.StartTime
        MigrationEnd = Get-Date
        MigrationDuration = (Get-Date) - $migrationContext.StartTime
        MigrationResult = $migrationResult
        TestResults = $testResults
        OverallSuccess = ($migrationResult.Success -and $testResults.OverallSuccess)
    }
    
    # Export results
    $resultsFile = "$LogPath\volume-$($Volume.Name)-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $volumeResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultsFile
    
    # Display summary
    Write-Host "`n=== VOLUME MIGRATION SUMMARY ===" -ForegroundColor Green
    Write-Host "Volume: $($Volume.Name)" -ForegroundColor Yellow
    Write-Host "Migration Method: $($migrationResult.Method)" -ForegroundColor Yellow
    Write-Host "Migration Success: $($migrationResult.Success)" -ForegroundColor $(if ($migrationResult.Success) { "Green" } else { "Red" })
    Write-Host "Test Results: $($testResults.OverallSuccess)" -ForegroundColor $(if ($testResults.OverallSuccess) { "Green" } else { "Red" })
    Write-Host "Duration: $([math]::Round($volumeResults.MigrationDuration.TotalMinutes, 2)) minutes" -ForegroundColor Yellow
    Write-Host "File Count Match: $($testResults.FileCountMatch)" -ForegroundColor $(if ($testResults.FileCountMatch) { "Green" } else { "Red" })
    Write-Host "Checksums Match: $($testResults.SampleChecksumsMatch)" -ForegroundColor $(if ($testResults.SampleChecksumsMatch) { "Green" } else { "Red" })
    
    if (!$volumeResults.OverallSuccess) {
        throw "Volume migration failed or validation tests did not pass"
    }
    
    Write-VolumeLog "Volume migration completed successfully" -Level "SUCCESS"
    Write-VolumeLog "Results saved to: $resultsFile"
    
    return $volumeResults
}
catch {
    Write-VolumeLog "Volume migration failed: $($_.Exception.Message)" -Level "ERROR"
    
    # Export failure details
    $failureResults = @{
        VolumeName = $Volume.Name
        Error = $_.Exception.Message
        StackTrace = $_.ScriptStackTrace
        Timestamp = Get-Date
    }
    $failureFile = "$LogPath\volume-$($Volume.Name)-failure-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $failureResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $failureFile
    
    throw
}