<#
.SYNOPSIS
    Retrieves configuration details for storage volumes to be migrated.
.DESCRIPTION
    Gathers information about source storage volumes including size, type, permissions, and structure to aid in migration planning.
    
.PARAMETER SourcePath
    Path to the source storage to analyze
.PARAMETER OutputPath
    Path for configuration reports
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Config"
)

function Write-VolumeLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$OutputPath\volume-config.log" -Append
}

function Get-FileSystemInfo {
    param([string]$Path)
    
    try {
        if (Test-Path $Path) {
            $drive = Get-PSDrive -PSProvider FileSystem | Where-Object { $Path -like "$($_.Root)*" }
            if ($drive) {
                return @{
                    DriveType = $drive.Description
                    Format = $drive.FileSystem
                    TotalSizeGB = [math]::Round($drive.Used + $drive.Free / 1GB, 2)
                    FreeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
                    UsedSpaceGB = [math]::Round($drive.Used / 1GB, 2)
                }
            }
        }
        return $null
    }
    catch {
        Write-VolumeLog "Error getting file system info for $Path : $($_.Exception.Message)" -Level "WARNING"
        return $null
    }
}

function Get-DirectoryStructure {
    param([string]$Path, [int]$MaxDepth = 3)
    
    try {
        Write-VolumeLog "Analyzing directory structure for $Path (Max depth: $MaxDepth)"
        
        function Get-DirectoryInfo {
            param([string]$CurrentPath, [int]$CurrentDepth)
            
            if ($CurrentDepth -gt $MaxDepth) {
                return $null
            }
            
            $dirInfo = @{
                Name = Split-Path $CurrentPath -Leaf
                FullPath = $CurrentPath
                Depth = $CurrentDepth
                ItemCount = 0
                TotalSizeGB = 0
                Subdirectories = @()
                FileTypes = @{}
            }
            
            try {
                $items = Get-ChildItem -Path $CurrentPath -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    if ($item.PSIsContainer) {
                        $subDir = Get-DirectoryInfo -CurrentPath $item.FullName -CurrentDepth ($CurrentDepth + 1)
                        if ($subDir) {
                            $dirInfo.Subdirectories += $subDir
                            $dirInfo.ItemCount += $subDir.ItemCount
                            $dirInfo.TotalSizeGB += $subDir.TotalSizeGB
                        }
                    } else {
                        $dirInfo.ItemCount++
                        $fileSizeGB = [math]::Round($item.Length / 1GB, 4)
                        $dirInfo.TotalSizeGB += $fileSizeGB
                        
                        $fileExtension = $item.Extension.ToLower()
                        if (!$fileExtension) { $fileExtension = "No Extension" }
                        
                        if ($dirInfo.FileTypes.ContainsKey($fileExtension)) {
                            $dirInfo.FileTypes[$fileExtension]++
                        } else {
                            $dirInfo.FileTypes[$fileExtension] = 1
                        }
                    }
                }
            }
            catch {
                # Skip directories that can't be accessed
            }
            
            return $dirInfo
        }
        
        return Get-DirectoryInfo -CurrentPath $Path -CurrentDepth 1
    }
    catch {
        Write-VolumeLog "Error analyzing directory structure: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-PermissionInfo {
    param([string]$Path)
    
    try {
        Write-VolumeLog "Analyzing permissions for $Path"
        
        $permissions = @()
        $acl = Get-Acl -Path $Path
        
        foreach ($access in $acl.Access) {
            $permissions += @{
                Identity = $access.IdentityReference.Value
                FileSystemRights = $access.FileSystemRights
                AccessControlType = $access.AccessControlType
                IsInherited = $access.IsInherited
            }
        }
        
        return $permissions
    }
    catch {
        Write-VolumeLog "Error analyzing permissions: $($_.Exception.Message)" -Level "WARNING"
        return @()
    }
}

function Get-VolumeSummary {
    param([string]$Path)
    
    try {
        Write-VolumeLog "Generating volume summary for $Path"
        
        $fileSystemInfo = Get-FileSystemInfo -Path $Path
        $directoryStructure = Get-DirectoryStructure -Path $Path
        $permissions = Get-PermissionInfo -Path $Path
        
        # Get total file count and size
        $allFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        $totalFiles = $allFiles.Count
        $totalSizeGB = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        
        # Get file type distribution
        $fileTypes = $allFiles | Group-Object -Property Extension | 
                    Sort-Object -Property Count -Descending |
                    Select-Object -First 10 Name, Count, 
                    @{Name="SizeGB"; Expression={[math]::Round(($_.Group | Measure-Object -Property Length -Sum).Sum / 1GB, 2)}}
        
        return @{
            SourcePath = $Path
            AnalysisDate = Get-Date
            FileSystem = $fileSystemInfo
            TotalFiles = $totalFiles
            TotalSizeGB = $totalSizeGB
            TopFileTypes = $fileTypes
            DirectoryStructure = $directoryStructure
            Permissions = $permissions
            Accessibility = @{
                CanRead = $true
                CanWrite = $false
                CanExecute = $true
            }
        }
    }
    catch {
        Write-VolumeLog "Error generating volume summary: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Main execution
try {
    Write-VolumeLog "Starting volume configuration analysis for: $SourcePath"
    
    # Create output directory
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force
    }
    
    # Analyze source path
    if (!(Test-Path $SourcePath)) {
        throw "Source path does not exist: $SourcePath"
    }
    
    $volumeConfig = Get-VolumeSummary -Path $SourcePath
    
    # Export configuration
    $configFile = "$OutputPath\volume-config-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $volumeConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFile
    
    # Display summary
    Write-Host "`n=== VOLUME CONFIGURATION SUMMARY ===" -ForegroundColor Green
    Write-Host "Source Path: $SourcePath" -ForegroundColor Yellow
    Write-Host "File System: $($volumeConfig.FileSystem.DriveType)" -ForegroundColor Yellow
    Write-Host "Total Files: $($volumeConfig.TotalFiles)" -ForegroundColor Yellow
    Write-Host "Total Size: $($volumeConfig.TotalSizeGB) GB" -ForegroundColor Yellow
    Write-Host "Free Space: $($volumeConfig.FileSystem.FreeSpaceGB) GB" -ForegroundColor Yellow
    Write-Host "Top File Types:" -ForegroundColor Cyan
    
    foreach ($fileType in $volumeConfig.TopFileTypes) {
        Write-Host "  $($fileType.Name): $($fileType.Count) files ($($fileType.SizeGB) GB)" -ForegroundColor White
    }
    
    Write-VolumeLog "Volume configuration analysis completed successfully"
    Write-VolumeLog "Configuration saved to: $configFile"
    
    return $volumeConfig
}
catch {
    Write-VolumeLog "Volume configuration analysis failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}