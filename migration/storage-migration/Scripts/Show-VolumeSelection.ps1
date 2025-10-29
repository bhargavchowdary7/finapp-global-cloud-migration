<#
.SYNOPSIS
    Provides interactive volume selection for migration from a source path.
.DESCRIPTION
    Displays available volumes and allows selection of which volumes to migrate from the specified source path.
    Generates a summary report of the selected volumes including total size and item count.
.PARAMETER SourcePath
    Source storage path
.PARAMETER ConfigPath
    Path to configuration files
.PARAMETER AutoSelect
    Switch to auto-select all volumes without prompting
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".\Config",
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoSelect = $false
)

function Write-SelectionLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$ConfigPath\volume-selection.log" -Append
}

function Get-AvailableVolumes {
    param([string]$Path)
    
    try {
        Write-SelectionLog "Discovering volumes at: $Path"
        
        $volumes = @()
        
        if (Test-Path $Path) {
            # Check if path is a drive root
            if ($Path -match '^[A-Z]:\\$') {
                $volumes += @{
                    Name = "Root"
                    Path = $Path
                    Type = "DriveRoot"
                    SizeGB = (Get-PSDrive -Name $Path[0]).Used / 1GB
                    ItemCount = (Get-ChildItem -Path $Path -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
                }
            }
            
            # Get top-level directories as potential volumes
            $directories = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
            
            foreach ($dir in $directories) {
                $dirSize = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                           Measure-Object -Property Length -Sum).Sum / 1GB
                $itemCount = (Get-ChildItem -Path $dir.FullName -Recurse -ErrorAction SilentlyContinue | 
                             Measure-Object).Count
                
                $volumes += @{
                    Name = $dir.Name
                    Path = $dir.FullName
                    Type = "Directory"
                    SizeGB = [math]::Round($dirSize, 2)
                    ItemCount = $itemCount
                    LastModified = $dir.LastWriteTime
                }
            }
        }
        
        return $volumes
    }
    catch {
        Write-SelectionLog "Error discovering volumes: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Show-VolumeSelectionMenu {
    param([array]$Volumes)
    
    try {
        Write-Host "`n" + "="*50 -ForegroundColor Cyan
        Write-Host "VOLUME SELECTION" -ForegroundColor Cyan
        Write-Host "="*50 -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $Volumes.Count; $i++) {
            $volume = $Volumes[$i]
            Write-Host "$($i + 1). $($volume.Name)" -ForegroundColor Yellow
            Write-Host "    Path: $($volume.Path)" -ForegroundColor Gray
            Write-Host "    Size: $($volume.SizeGB) GB" -ForegroundColor Gray
            Write-Host "    Items: $($volume.ItemCount)" -ForegroundColor Gray
            Write-Host "    Type: $($volume.Type)" -ForegroundColor Gray
            Write-Host ""
        }
        
        Write-Host "Select volumes to migrate (comma-separated numbers, 'all', or 'none'):" -ForegroundColor Green
        $selection = Read-Host "Selection"
        
        $selectedVolumes = @()
        
        if ($selection -eq "all") {
            $selectedVolumes = $Volumes
        }
        elseif ($selection -eq "none") {
            $selectedVolumes = @()
        }
        else {
            $selectedIndices = $selection -split ',' | ForEach-Object { [int]$_ - 1 }
            foreach ($index in $selectedIndices) {
                if ($index -ge 0 -and $index -lt $Volumes.Count) {
                    $selectedVolumes += $Volumes[$index]
                }
            }
        }
        
        return $selectedVolumes
    }
    catch {
        Write-SelectionLog "Error in volume selection menu: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Export-VolumeSelection {
    param([array]$SelectedVolumes, [string]$OutputPath)
    
    try {
        $selectionReport = @{
            SelectionDate = Get-Date
            SourcePath = $SourcePath
            SelectedVolumes = $SelectedVolumes
            TotalSelectedSizeGB = ($SelectedVolumes | Measure-Object -Property SizeGB -Sum).Sum
            TotalSelectedItems = ($SelectedVolumes | Measure-Object -Property ItemCount -Sum).Sum
        }
        
        $selectionFile = "$OutputPath\volume-selection-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $selectionReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $selectionFile
        
        return $selectionFile
    }
    catch {
        Write-SelectionLog "Error exporting volume selection: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Main execution
try {
    Write-SelectionLog "Starting volume selection process"
    
    # Create config directory
    if (!(Test-Path $ConfigPath)) {
        New-Item -ItemType Directory -Path $ConfigPath -Force
    }
    
    # Get available volumes
    $availableVolumes = Get-AvailableVolumes -Path $SourcePath
    
    if ($availableVolumes.Count -eq 0) {
        Write-SelectionLog "No volumes found at source path: $SourcePath" -Level "WARNING"
        return @()
    }
    
    # Select volumes
    if ($AutoSelect) {
        $selectedVolumes = $availableVolumes
        Write-SelectionLog "Auto-selected all $($availableVolumes.Count) volumes"
    }
    else {
        $selectedVolumes = Show-VolumeSelectionMenu -Volumes $availableVolumes
    }
    
    # Export selection
    $selectionFile = Export-VolumeSelection -SelectedVolumes $selectedVolumes -OutputPath $ConfigPath
    
    # Display summary
    Write-Host "`n=== VOLUME SELECTION SUMMARY ===" -ForegroundColor Green
    Write-Host "Total Available Volumes: $($availableVolumes.Count)" -ForegroundColor Yellow
    Write-Host "Selected Volumes: $($selectedVolumes.Count)" -ForegroundColor Yellow
    Write-Host "Total Selected Size: $(($selectedVolumes | Measure-Object -Property SizeGB -Sum).Sum) GB" -ForegroundColor Yellow
    Write-Host "Total Selected Items: $(($selectedVolumes | Measure-Object -Property ItemCount -Sum).Sum)" -ForegroundColor Yellow
    
    if ($selectedVolumes.Count -gt 0) {
        Write-Host "`nSelected Volumes:" -ForegroundColor Cyan
        foreach ($volume in $selectedVolumes) {
            Write-Host "  - $($volume.Name) ($($volume.SizeGB) GB)" -ForegroundColor White
        }
    }
    
    Write-SelectionLog "Volume selection completed. $($selectedVolumes.Count) volumes selected."
    Write-SelectionLog "Selection saved to: $selectionFile"
    
    return $selectedVolumes
}
catch {
    Write-SelectionLog "Volume selection failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}