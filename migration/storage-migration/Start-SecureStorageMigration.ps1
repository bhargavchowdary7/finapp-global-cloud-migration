<#
.SYNOPSIS
    Main controller script for secure storage migration using Azure services.
.DESCRIPTION
    Orchestrates the entire storage migration process including assessment, planning, execution, and validation phases.
    Utilizes Azure Storage, AzCopy, and Azure File Sync as needed. Generates comprehensive reports and dashboards.
.PARAMETER SourcePath
    Source storage path or share to migrate
.PARAMETER TargetPath
    Target Azure storage path
.PARAMETER MigrationType
    Type of migration: AzCopy, DataBox, or AzureFileSync
.PARAMETER ConfigPath
    Path to migration configuration files
.PARAMETER LogPath
    Path for migration logs and reports
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("AzCopy", "DataBox", "AzureFileSync")]
    [string]$MigrationType,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\Config",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\Logs"
)

function Write-MigrationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" } 
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$LogPath\storage-migration.log" -Append
}

function Initialize-MigrationEnvironment {
    try {
        Write-MigrationLog "Initializing migration environment"
        
        # Create necessary directories
        @($LogPath, $ConfigPath, ".\Reports", ".\Backups") | ForEach-Object {
            if (!(Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
            }
        }
        
        # Verify required modules
        $requiredModules = @("Az.Storage", "Az.Accounts")
        foreach ($module in $requiredModules) {
            if (!(Get-Module -ListAvailable -Name $module)) {
                Write-MigrationLog "Installing required module: $module"
                Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
            }
            Import-Module $module -Force
        }
        
        # Verify AzCopy availability
        $azCopyPath = Get-Command "azcopy" -ErrorAction SilentlyContinue
        if (!$azCopyPath) {
            Write-MigrationLog "AzCopy not found in PATH. Please ensure AzCopy is installed." -Level "WARNING"
        }
        
        Write-MigrationLog "Migration environment initialized successfully"
        return $true
    }
    catch {
        Write-MigrationLog "Failed to initialize migration environment: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Invoke-AssessmentPhase {
    try {
        Write-MigrationLog "=== STARTING ASSESSMENT PHASE ==="
        
        # Get volume configurations
        Write-MigrationLog "Analyzing source storage configuration"
        $volumeConfig = .\Scripts\Get-VolumeConfigurations.ps1 -SourcePath $SourcePath
        
        # Test accessibility
        Write-MigrationLog "Testing source storage accessibility"
        $accessibility = .\Scripts\Test-VolumeAccessibility.ps1 -SourcePath $SourcePath
        
        if (!$accessibility.IsAccessible) {
            throw "Source path is not accessible: $SourcePath"
        }
        
        # Show volume selection (if interactive)
        Write-MigrationLog "Preparing volume selection"
        $selectedVolumes = .\Scripts\Show-VolumeSelection.ps1 -SourcePath $SourcePath -ConfigPath $ConfigPath
        
        Write-MigrationLog "Assessment phase completed successfully" -Level "SUCCESS"
        return @{
            VolumeConfig = $volumeConfig
            Accessibility = $accessibility
            SelectedVolumes = $selectedVolumes
        }
    }
    catch {
        Write-MigrationLog "Assessment phase failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Invoke-PlanningPhase {
    param($AssessmentData)
    
    try {
        Write-MigrationLog "=== STARTING PLANNING PHASE ==="
        
        # Apply filters to volumes
        Write-MigrationLog "Applying volume filters"
        $filteredVolumes = .\Scripts\Apply-VolumeFilters.ps1 -Volumes $AssessmentData.SelectedVolumes -ConfigPath $ConfigPath
        
        # Create migration plan
        Write-MigrationLog "Creating migration plan"
        $migrationPlan = .\Scripts\New-MigrationPlan.ps1 -SourcePath $SourcePath -TargetPath $TargetPath -Volumes $filteredVolumes -MigrationType $MigrationType
        
        Write-MigrationLog "Planning phase completed successfully" -Level "SUCCESS"
        return @{
            FilteredVolumes = $filteredVolumes
            MigrationPlan = $migrationPlan
        }
    }
    catch {
        Write-MigrationLog "Planning phase failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Invoke-ExecutionPhase {
    param($PlanningData)
    
    try {
        Write-MigrationLog "=== STARTING EXECUTION PHASE ==="
        
        $executionResults = @{}
        
        switch ($MigrationType) {
            "AzCopy" {
                Write-MigrationLog "Starting AzCopy migration"
                $executionResults.Migration = .\Scripts\Invoke-AzCopyMigration.ps1 -SourcePath $SourcePath -TargetPath $TargetPath -MigrationPlan $PlanningData.MigrationPlan
            }
            "DataBox" {
                Write-MigrationLog "Starting DataBox migration"
                $executionResults.Migration = .\Scripts\Invoke-DataBoxMigration.ps1 -SourcePath $SourcePath -TargetPath $TargetPath -MigrationPlan $PlanningData.MigrationPlan
            }
            "AzureFileSync" {
                Write-MigrationLog "Starting Azure File Sync setup"
                $executionResults.Migration = .\Scripts\Initialize-AzureFileSync.ps1 -SourcePath $SourcePath -TargetPath $TargetPath -MigrationPlan $PlanningData.MigrationPlan
            }
        }
        
        # Execute single volume migration for each volume
        foreach ($volume in $PlanningData.FilteredVolumes) {
            Write-MigrationLog "Migrating volume: $($volume.Name)"
            $volumeResult = .\Scripts\Invoke-SingleVolumeMigration.ps1 -Volume $volume -MigrationPlan $PlanningData.MigrationPlan
            $executionResults."Volume_$($volume.Name)" = $volumeResult
        }
        
        Write-MigrationLog "Execution phase completed successfully" -Level "SUCCESS"
        return $executionResults
    }
    catch {
        Write-MigrationLog "Execution phase failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Invoke-ValidationPhase {
    param($ExecutionResults)
    
    try {
        Write-MigrationLog "=== STARTING VALIDATION PHASE ==="
        
        # Perform storage validation
        Write-MigrationLog "Validating migrated data"
        $validationResults = .\Scripts\Invoke-StorageValidation.ps1 -SourcePath $SourcePath -TargetPath $TargetPath -ExecutionResults $ExecutionResults
        
        Write-MigrationLog "Validation phase completed successfully" -Level "SUCCESS"
        return $validationResults
    }
    catch {
        Write-MigrationLog "Validation phase failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Invoke-ReportingPhase {
    param($AssessmentData, $PlanningData, $ExecutionResults, $ValidationResults)
    
    try {
        Write-MigrationLog "=== STARTING REPORTING PHASE ==="
        
        # Generate migration report
        Write-MigrationLog "Generating migration report"
        $report = .\Scripts\New-MigrationReport.ps1 -AssessmentData $AssessmentData -PlanningData $PlanningData -ExecutionResults $ExecutionResults -ValidationResults $ValidationResults
        
        # Create dashboard
        Write-MigrationLog "Creating migration dashboard"
        $dashboard = .\Scripts\New-MigrationDashboard.ps1 -MigrationReport $report -OutputPath ".\Reports"
        
        Write-MigrationLog "Reporting phase completed successfully" -Level "SUCCESS"
        return @{
            Report = $report
            Dashboard = $dashboard
        }
    }
    catch {
        Write-MigrationLog "Reporting phase failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Main execution
try {
    $startTime = Get-Date
    Write-MigrationLog "Starting secure storage migration"
    Write-MigrationLog "Source: $SourcePath"
    Write-MigrationLog "Target: $TargetPath"
    Write-MigrationLog "Migration Type: $MigrationType"
    
    # Initialize environment
    if (!(Initialize-MigrationEnvironment)) {
        throw "Failed to initialize migration environment"
    }
    
    # Execute migration phases
    $assessmentData = Invoke-AssessmentPhase
    $planningData = Invoke-PlanningPhase -AssessmentData $assessmentData
    $executionResults = Invoke-ExecutionPhase -PlanningData $planningData
    $validationResults = Invoke-ValidationPhase -ExecutionResults $executionResults
    $reportingResults = Invoke-ReportingPhase -AssessmentData $assessmentData -PlanningData $planningData -ExecutionResults $executionResults -ValidationResults $validationResults
    
    # Calculate duration
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Final summary
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "STORAGE MIGRATION COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green
    Write-Host "Source: $SourcePath" -ForegroundColor Yellow
    Write-Host "Target: $TargetPath" -ForegroundColor Yellow
    Write-Host "Migration Type: $MigrationType" -ForegroundColor Yellow
    Write-Host "Duration: $([math]::Round($duration.TotalMinutes, 2)) minutes" -ForegroundColor Yellow
    Write-Host "Total Data Migrated: $($reportingResults.Report.TotalDataMigrated)" -ForegroundColor Yellow
    Write-Host "Success Rate: $($reportingResults.Report.SuccessRate)%" -ForegroundColor Green
    Write-Host "Reports: .\Reports\" -ForegroundColor Cyan
    
    Write-MigrationLog "Secure storage migration completed successfully" -Level "SUCCESS"
}
catch {
    Write-MigrationLog "Storage migration failed: $($_.Exception.Message)" -Level "ERROR"
    
    # Generate failure report
    try {
        $failureReport = @{
            MigrationDate = Get-Date
            SourcePath = $SourcePath
            TargetPath = $TargetPath
            MigrationType = $MigrationType
            Error = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
        }
        $failureReport | ConvertTo-Json -Depth 5 | Out-File -FilePath "$LogPath\migration-failure.json"
    }
    catch {
        Write-MigrationLog "Failed to generate failure report: $($_.Exception.Message)" -Level "ERROR"
    }
    
    throw
}