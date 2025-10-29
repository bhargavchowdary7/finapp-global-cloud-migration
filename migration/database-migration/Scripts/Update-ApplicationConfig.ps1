<#
.SYNOPSIS
    Updates application configuration after database migration to reflect new connection strings.
.DESCRIPTION
    Updates connection strings and configuration settings in various application config files (such as Web.config, App.config, JSON files)
    to point to the new database location after migration. Backs up original config files and generates a report of changes made.
.PARAMETER ConfigPath
    Path to application configuration files
.PARAMETER OldConnectionString
    Old database connection string
.PARAMETER NewConnectionString
    New database connection string
.PARAMETER BackupOriginal
    Switch to backup original config files
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OldConnectionString,
    
    [Parameter(Mandatory=$true)]
    [string]$NewConnectionString,
    
    [Parameter(Mandatory=$false)]
    [switch]$BackupOriginal
)

function Write-ConfigLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\config-update.log" -Append
}

function Backup-ConfigFile {
    param([string]$FilePath)
    
    try {
        if (Test-Path $FilePath) {
            $backupPath = "$FilePath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $FilePath -Destination $backupPath -Force
            Write-ConfigLog "Backed up $FilePath to $backupPath"
            return $backupPath
        }
        return $null
    }
    catch {
        Write-ConfigLog "Failed to backup $FilePath : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Update-WebConfig {
    param([string]$FilePath, [string]$OldConnString, [string]$NewConnString)
    
    try {
        if (!(Test-Path $FilePath)) {
            Write-ConfigLog "Web.config file not found: $FilePath" -Level "WARNING"
            return $false
        }
        
        Write-ConfigLog "Updating Web.config: $FilePath"
        $content = Get-Content -Path $FilePath -Raw
        
        # Replace connection strings in connectionStrings section
        $pattern = '(<connectionStrings>.*?<add.*?connectionString=")[^"]*(".*?/>.*?</connectionStrings>)'
        $replacement = "`$1$NewConnString`$2"
        $updatedContent = $content -replace $pattern, $replacement
        
        # Also replace in appSettings if present
        $updatedContent = $updatedContent -replace [regex]::Escape($OldConnString), $NewConnString
        
        if ($BackupOriginal) {
            Backup-ConfigFile -FilePath $FilePath
        }
        
        $updatedContent | Set-Content -Path $FilePath -Encoding UTF8
        Write-ConfigLog "Successfully updated Web.config"
        return $true
    }
    catch {
        Write-ConfigLog "Error updating Web.config: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Update-AppConfig {
    param([string]$FilePath, [string]$OldConnString, [string]$NewConnString)
    
    try {
        if (!(Test-Path $FilePath)) {
            Write-ConfigLog "App.config file not found: $FilePath" -Level "WARNING"
            return $false
        }
        
        Write-ConfigLog "Updating App.config: $FilePath"
        $content = Get-Content -Path $FilePath -Raw
        $updatedContent = $content -replace [regex]::Escape($OldConnString), $NewConnString
        
        if ($BackupOriginal) {
            Backup-ConfigFile -FilePath $FilePath
        }
        
        $updatedContent | Set-Content -Path $FilePath -Encoding UTF8
        Write-ConfigLog "Successfully updated App.Config"
        return $true
    }
    catch {
        Write-ConfigLog "Error updating App.config: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Update-JsonConfig {
    param([string]$FilePath, [string]$OldConnString, [string]$NewConnString)
    
    try {
        if (!(Test-Path $FilePath)) {
            Write-ConfigLog "JSON config file not found: $FilePath" -Level "WARNING"
            return $false
        }
        
        Write-ConfigLog "Updating JSON config: $FilePath"
        $jsonContent = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
        
        # Update connection strings in JSON structure
        function Update-JsonObject {
            param($Object, $OldValue, $NewValue)
            
            foreach ($property in $Object.PSObject.Properties) {
                if ($property.Value -is [string] -and $property.Value -eq $OldValue) {
                    $property.Value = $NewValue
                }
                elseif ($property.Value -is [PSCustomObject]) {
                    Update-JsonObject -Object $property.Value -OldValue $OldValue -NewValue $NewValue
                }
                elseif ($property.Value -is [Array]) {
                    foreach ($item in $property.Value) {
                        if ($item -is [PSCustomObject]) {
                            Update-JsonObject -Object $item -OldValue $OldValue -NewValue $NewValue
                        }
                    }
                }
            }
        }
        
        Update-JsonObject -Object $jsonContent -OldValue $OldConnString -NewValue $NewConnString
        
        if ($BackupOriginal) {
            Backup-ConfigFile -FilePath $FilePath
        }
        
        $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8
        Write-ConfigLog "Successfully updated JSON config"
        return $true
    }
    catch {
        Write-ConfigLog "Error updating JSON config: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-ConfigUpdate {
    param([string]$FilePath, [string]$ExpectedConnString)
    
    try {
        if (!(Test-Path $FilePath)) {
            return $false
        }
        
        $content = Get-Content -Path $FilePath -Raw
        return $content -like "*$ExpectedConnString*"
    }
    catch {
        Write-ConfigLog "Error testing config update: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution

# Set default for $BackupOriginal if not specified
if (-not $PSBoundParameters.ContainsKey('BackupOriginal')) {
    $BackupOriginal = $true
}

try {
    Write-ConfigLog "Starting application configuration update"
    Write-ConfigLog "Config Path: $ConfigPath"
    Write-ConfigLog "Old Connection String: $($OldConnectionString.Substring(0, [math]::Min(20, $OldConnectionString.Length)))..."
    Write-ConfigLog "New Connection String: $($NewConnectionString.Substring(0, [math]::Min(20, $NewConnectionString.Length)))..."
    
    if (!(Test-Path $ConfigPath)) {
        throw "Configuration path not found: $ConfigPath"
    }
    
    $updateResults = @{}
    
    # Find and update all configuration files
    $configFiles = Get-ChildItem -Path $ConfigPath -Recurse -Include "web.config", "app.config", "appsettings.json", "config.json"
    
    foreach ($configFile in $configFiles) {
        Write-ConfigLog "Processing config file: $($configFile.FullName)"
        
        switch ($configFile.Extension.ToLower()) {
            ".config" {
                if ($configFile.Name -like "web.*") {
                    $updateResults[$configFile.Name] = Update-WebConfig -FilePath $configFile.FullName -OldConnString $OldConnectionString -NewConnString $NewConnectionString
                } else {
                    $updateResults[$configFile.Name] = Update-AppConfig -FilePath $configFile.FullName -OldConnString $OldConnectionString -NewConnString $NewConnectionString
                }
            }
            ".json" {
                $updateResults[$configFile.Name] = Update-JsonConfig -FilePath $configFile.FullName -OldConnString $OldConnectionString -NewConnString $NewConnectionString
            }
        }
        
        # Verify update
        if ($updateResults[$configFile.Name]) {
            $verification = Test-ConfigUpdate -FilePath $configFile.FullName -ExpectedConnString $NewConnectionString
            if (!$verification) {
                Write-ConfigLog "WARNING: Update verification failed for $($configFile.Name)" -Level "WARNING"
            }
        }
    }
    
    # Generate update report
    $updateReport = @{
        UpdateDate = Get-Date
        ConfigPath = $ConfigPath
        FilesUpdated = $updateResults.Count
        UpdateResults = $updateResults
        SuccessfulUpdates = ($updateResults.Values | Where-Object { $_ -eq $true }).Count
        FailedUpdates = ($updateResults.Values | Where-Object { $_ -eq $false }).Count
    }
    
    # Export report
    $reportPath = ".\Config-Update-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $updateReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath
    
    # Display summary
    Write-Host "`n=== CONFIGURATION UPDATE SUMMARY ===" -ForegroundColor Green
    Write-Host "Config Path: $ConfigPath" -ForegroundColor Yellow
    Write-Host "Files Processed: $($updateResults.Count)" -ForegroundColor Yellow
    Write-Host "Successful Updates: $($updateReport.SuccessfulUpdates)" -ForegroundColor Green
    Write-Host "Failed Updates: $($updateReport.FailedUpdates)" -ForegroundColor $(if ($updateReport.FailedUpdates -eq 0) { "Green" } else { "Red" })
    Write-Host "Report: $reportPath" -ForegroundColor Cyan
    
    if ($updateReport.FailedUpdates -gt 0) {
        Write-Host "`nFailed files:" -ForegroundColor Red
        $updateResults.GetEnumerator() | Where-Object { $_.Value -eq $false } | ForEach-Object {
            Write-Host "  - $($_.Key)" -ForegroundColor Red
        }
        throw "Configuration update completed with errors"
    }
    
    Write-ConfigLog "Application configuration update completed successfully" -Level "SUCCESS"
}
catch {
    Write-ConfigLog "Configuration update failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}