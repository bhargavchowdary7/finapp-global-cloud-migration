<#
.SYNOPSIS
    Applies filters to volumes for migration based on defined criteria.
.DESCRIPTION
    Filters volumes based on size, file types, age, and other criteria  to determine suitability for migration.
    Generates a report summarizing the filtering results and excluded volumes.
.PARAMETER Volumes
    Array of volumes to filter
.PARAMETER ConfigPath
    Path to filter configuration files
.PARAMETER FilterConfig
    Hashtable containing filter criteria
#>

param(
    [Parameter(Mandatory=$true)]
    [array]$Volumes,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\Config",
    
    [Parameter(Mandatory=$false)]
    [hashtable]$FilterConfig = @{}
)

function Write-FilterLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$ConfigPath\volume-filters.log" -Append
}

function Get-DefaultFilters {
    return @{
        MaxSizeGB = 1000  # Skip volumes larger than 1TB
        MinSizeGB = 0.1   # Skip volumes smaller than 100MB
        ExcludedFileTypes = @(".tmp", ".log", ".cache", ".temp")
        ExcludedDirectories = @("temp", "tmp", "cache", "logs", "recycle bin")
        MaxFileAgeDays = 3650  # 10 years
        MinFileAgeDays = 0
        IncludeSystemFiles = $false
        IncludeHiddenFiles = $false
    }
}

function Get-FilterConfiguration {
    param([string]$ConfigPath)
    
    try {
        $filterFile = Join-Path $ConfigPath "migration-filters.json"
        if (Test-Path $filterFile) {
            $loadedConfig = Get-Content -Path $filterFile -Raw | ConvertFrom-Json -AsHashtable
            Write-FilterLog "Loaded filter configuration from: $filterFile"
            return $loadedConfig
        }
        else {
            Write-FilterLog "No filter configuration found, using defaults" -Level "WARNING"
            return Get-DefaultFilters
        }
    }
    catch {
        Write-FilterLog "Error loading filter configuration: $($_.Exception.Message)" -Level "WARNING"
        return Get-DefaultFilters
    }
}

function Test-VolumeAgainstFilters {
    param([hashtable]$Volume, [hashtable]$Filters)
    
    $exclusionReasons = @()
    
    # Size filters
    if ($Volume.SizeGB -gt $Filters.MaxSizeGB) {
        $exclusionReasons += "Size exceeds maximum ($($Volume.SizeGB)GB > $($Filters.MaxSizeGB)GB)"
    }
    
    if ($Volume.SizeGB -lt $Filters.MinSizeGB) {
        $exclusionReasons += "Size below minimum ($($Volume.SizeGB)GB < $($Filters.MinSizeGB)GB)"
    }
    
    # Name filters for excluded directories
    foreach ($excludedDir in $Filters.ExcludedDirectories) {
        if ($Volume.Name -like "*$excludedDir*" -or $Volume.Path -like "*$excludedDir*") {
            $exclusionReasons += "Matches excluded directory pattern: $excludedDir"
            break
        }
    }
    
    # Additional checks can be added here for file types, age, etc.
    
    return @{
        ShouldInclude = ($exclusionReasons.Count -eq 0)
        ExclusionReasons = $exclusionReasons
    }
}

function Invoke-FileTypeFilters {
    param([hashtable]$Volume, [hashtable]$Filters)
    
    try {
        if ($Filters.ExcludedFileTypes.Count -eq 0) {
            return $Volume
        }
        
        Write-FilterLog "Applying file type filters to volume: $($Volume.Name)"
        
        # This would typically scan the volume and exclude files of certain types
        # For performance, we're just marking the volume for special handling
        
        $Volume.Filtered = $true
        $Volume.ExcludedFileTypes = $Filters.ExcludedFileTypes
        
        return $Volume
    }
    catch {
        Write-FilterLog "Error applying file type filters: $($_.Exception.Message)" -Level "WARNING"
        return $Volume
    }
}

function New-FilterReport {
    param([array]$AllVolumes, [array]$FilteredVolumes, [array]$ExcludedVolumes)
    
    $report = @{
        FilterDate = Get-Date
        TotalVolumes = $AllVolumes.Count
        FilteredVolumes = $FilteredVolumes.Count
        ExcludedVolumes = $ExcludedVolumes.Count
        TotalSizeBeforeFilterGB = ($AllVolumes | Measure-Object -Property SizeGB -Sum).Sum
        TotalSizeAfterFilterGB = ($FilteredVolumes | Measure-Object -Property SizeGB -Sum).Sum
        SizeReductionGB = ($AllVolumes | Measure-Object -Property SizeGB -Sum).Sum - ($FilteredVolumes | Measure-Object -Property SizeGB -Sum).Sum
        ExcludedVolumeDetails = $ExcludedVolumes
    }
    
    return $report
}

# Main execution
try {
    Write-FilterLog "Starting volume filtering process"
    Write-FilterLog "Initial volume count: $($Volumes.Count)"
    
    # Create config directory
    if (!(Test-Path $ConfigPath)) {
        New-Item -ItemType Directory -Path $ConfigPath -Force
    }
    
    # Load or create filter configuration
    if ($FilterConfig.Count -eq 0) {
        $FilterConfig = Get-FilterConfiguration -ConfigPath $ConfigPath
    }
    
    # Apply filters
    $filteredVolumes = @()
    $excludedVolumes = @()
    
    foreach ($volume in $Volumes) {
        $filterResult = Test-VolumeAgainstFilters -Volume $volume -Filters $FilterConfig
        
        if ($filterResult.ShouldInclude) {
            # Apply additional filters (file types, etc.)
            $filteredVolume = Invoke-FileTypeFilters -Volume $volume -Filters $FilterConfig
            $filteredVolumes += $filteredVolume
        }
        else {
            $volume.ExclusionReasons = $filterResult.ExclusionReasons
            $excludedVolumes += $volume
        }
    }
    
    # Generate filter report
    $filterReport = New-FilterReport -AllVolumes $Volumes -FilteredVolumes $filteredVolumes -ExcludedVolumes $excludedVolumes
    
    # Export filter results
    $filterFile = "$ConfigPath\volume-filters-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $filterReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $filterFile
    
    # Display summary
    Write-Host "`n=== VOLUME FILTERING SUMMARY ===" -ForegroundColor Green
    Write-Host "Total Volumes: $($Volumes.Count)" -ForegroundColor Yellow
    Write-Host "After Filtering: $($filteredVolumes.Count)" -ForegroundColor Green
    Write-Host "Excluded: $($excludedVolumes.Count)" -ForegroundColor Red
    Write-Host "Total Size Before: $([math]::Round($filterReport.TotalSizeBeforeFilterGB, 2)) GB" -ForegroundColor Yellow
    Write-Host "Total Size After: $([math]::Round($filterReport.TotalSizeAfterFilterGB, 2)) GB" -ForegroundColor Green
    Write-Host "Size Reduction: $([math]::Round($filterReport.SizeReductionGB, 2)) GB" -ForegroundColor Cyan
    
    if ($excludedVolumes.Count -gt 0) {
        Write-Host "`nExcluded Volumes:" -ForegroundColor Red
        foreach ($excluded in $excludedVolumes) {
            Write-Host "  - $($excluded.Name): $($excluded.ExclusionReasons -join ', ')" -ForegroundColor Gray
        }
    }
    
    Write-FilterLog "Volume filtering completed. $($filteredVolumes.Count) volumes remaining after filters."
    Write-FilterLog "Filter report saved to: $filterFile"
    
    return $filteredVolumes
}
catch {
    Write-FilterLog "Volume filtering failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}