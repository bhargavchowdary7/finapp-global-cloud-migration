<#
.SYNOPSIS
    Tests accessibility and permissions for storage volumes to be migrated.
.DESCRIPTION
    Verifies that volumes can be read and assesses any access limitations that may impact migration.
    Tests read, write, and list permissions as applicable. Generates a detailed report of the accessibility
    status for each volume.
.PARAMETER SourcePath
    Path to the source storage to test
.PARAMETER TestTypes
    Types of tests to perform: Read, Write, List, All
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Read", "Write", "List", "All")]
    [string[]]$TestTypes = @("All")
)

function Write-AccessLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\volume-accessibility.log" -Append
}

function Test-PathExistence {
    param([string]$Path)
    
    try {
        return Test-Path $Path
    }
    catch {
        return $false
    }
}

function Test-ReadAccess {
    param([string]$Path)
    
    try {
        Write-AccessLog "Testing read access for: $Path"
        $testFile = Get-ChildItem -Path $Path -ErrorAction Stop | Select-Object -First 1
        if ($testFile) {
            Get-Content -Path $testFile.FullName -TotalCount 1 -ErrorAction Stop | Out-Null
            return $true
        }
        return $false
    }
    catch {
        Write-AccessLog "Read access test failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Test-ListAccess {
    param([string]$Path)
    
    try {
        Write-AccessLog "Testing list access for: $Path"
        $items = Get-ChildItem -Path $Path -ErrorAction Stop
        return ($items.Count -ge 0)
    }
    catch {
        Write-AccessLog "List access test failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Test-WriteAccess {
    param([string]$Path)
    
    try {
        Write-AccessLog "Testing write access for: $Path"
        $testFileName = "MigrationTestFile_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
        $testFilePath = Join-Path $Path $testFileName
        
        # Try to create a test file
        $testContent = "Migration accessibility test - can be deleted"
        $testContent | Out-File -FilePath $testFilePath -ErrorAction Stop
        
        # Verify file was created
        if (Test-Path $testFilePath) {
            # Clean up test file
            Remove-Item -Path $testFilePath -Force -ErrorAction SilentlyContinue
            return $true
        }
        return $false
    }
    catch {
        Write-AccessLog "Write access test failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Test-NetworkConnectivity {
    param([string]$Path)
    
    try {
        if ($Path -match '^\\\\') {
            # UNC path - extract server name
            $server = $Path -replace '^\\\\([^\\]+).*', '$1'
            Write-AccessLog "Testing network connectivity to: $server"
            
            $pingResult = Test-Connection -ComputerName $server -Count 2 -Quiet
            return $pingResult
        }
        return $true  # Local path, no network test needed
    }
    catch {
        Write-AccessLog "Network connectivity test failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Get-PermissionAnalysis {
    param([string]$Path)
    
    try {
        Write-AccessLog "Analyzing permissions for: $Path"
        
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        $permissions = @()
        
        foreach ($access in $acl.Access) {
            $permissions += @{
                Identity = $access.IdentityReference.Value
                FileSystemRights = $access.FileSystemRights.ToString()
                AccessControlType = $access.AccessControlType.ToString()
                IsInherited = $access.IsInherited
            }
        }
        
        return $permissions
    }
    catch {
        Write-AccessLog "Permission analysis failed: $($_.Exception.Message)" -Level "WARNING"
        return @()
    }
}

function Get-StoragePerformance {
    param([string]$Path)
    
    try {
        Write-AccessLog "Testing storage performance for: $Path"
        
        $testFile = "PerformanceTest_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
        $testPath = Join-Path $Path $testFile
        
        # Write performance test
        $writeStart = Get-Date
        $testData = "x" * 1024 * 1024  # 1MB of test data
        1..10 | ForEach-Object { $testData | Out-File -FilePath $testPath -Append }
        $writeEnd = Get-Date
        
        # Read performance test
        $readStart = Get-Date
        Get-Content -Path $testPath -Raw | Out-Null
        $readEnd = Get-Date
        
        # Clean up
        Remove-Item -Path $testPath -Force -ErrorAction SilentlyContinue
        
        $writeTime = ($writeEnd - $writeStart).TotalSeconds
        $readTime = ($readEnd - $readStart).TotalSeconds
        
        return @{
            WriteSpeedMBps = [math]::Round(10 / $writeTime, 2)  # 10MB total written
            ReadSpeedMBps = [math]::Round(10 / $readTime, 2)    # 10MB total read
            WriteTimeSeconds = [math]::Round($writeTime, 2)
            ReadTimeSeconds = [math]::Round($readTime, 2)
        }
    }
    catch {
        Write-AccessLog "Storage performance test failed: $($_.Exception.Message)" -Level "WARNING"
        return @{
            WriteSpeedMBps = 0
            ReadSpeedMBps = 0
            WriteTimeSeconds = 0
            ReadTimeSeconds = 0
        }
    }
}

# Main execution
try {
    Write-AccessLog "Starting volume accessibility testing for: $SourcePath"
    
    # Determine test types
    if ($TestTypes -contains "All") {
        $TestTypes = @("Read", "Write", "List")
    }
    
    # Perform tests
    $testResults = @{
        SourcePath = $SourcePath
        TestDate = Get-Date
        PathExists = Test-PathExistence -Path $SourcePath
        NetworkConnectivity = Test-NetworkConnectivity -Path $SourcePath
        Tests = @{}
        Permissions = @()
        Performance = @{}
    }
    
    if ($testResults.PathExists) {
        # Basic access tests
        if ($TestTypes -contains "List") {
            $testResults.Tests.ListAccess = Test-ListAccess -Path $SourcePath
        }
        
        if ($TestTypes -contains "Read") {
            $testResults.Tests.ReadAccess = Test-ReadAccess -Path $SourcePath
        }
        
        if ($TestTypes -contains "Write") {
            $testResults.Tests.WriteAccess = Test-WriteAccess -Path $SourcePath
        }
        
        # Additional analysis
        $testResults.Permissions = Get-PermissionAnalysis -Path $SourcePath
        $testResults.Performance = Get-StoragePerformance -Path $SourcePath
        
        # Overall accessibility
        $testResults.IsAccessible = ($testResults.Tests.Values -contains $false) -eq $false
    }
    else {
        $testResults.IsAccessible = $false
        Write-AccessLog "Source path does not exist: $SourcePath" -Level "ERROR"
    }
    
    # Export results
    $resultsFile = ".\volume-accessibility-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $testResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultsFile
    
    # Display summary
    Write-Host "`n=== VOLUME ACCESSIBILITY SUMMARY ===" -ForegroundColor Green
    Write-Host "Source Path: $SourcePath" -ForegroundColor Yellow
    Write-Host "Path Exists: $($testResults.PathExists)" -ForegroundColor $(if ($testResults.PathExists) { "Green" } else { "Red" })
    Write-Host "Network Connectivity: $($testResults.NetworkConnectivity)" -ForegroundColor $(if ($testResults.NetworkConnectivity) { "Green" } else { "Red" })
    Write-Host "Overall Accessible: $($testResults.IsAccessible)" -ForegroundColor $(if ($testResults.IsAccessible) { "Green" } else { "Red" })
    
    if ($testResults.PathExists) {
        Write-Host "`nAccess Tests:" -ForegroundColor Cyan
        foreach ($test in $testResults.Tests.GetEnumerator()) {
            $statusColor = if ($test.Value) { "Green" } else { "Red" }
            Write-Host "  $($test.Key): $($test.Value)" -ForegroundColor $statusColor
        }
        
        Write-Host "`nPerformance:" -ForegroundColor Cyan
        Write-Host "  Write Speed: $($testResults.Performance.WriteSpeedMBps) MB/s" -ForegroundColor White
        Write-Host "  Read Speed: $($testResults.Performance.ReadSpeedMBps) MB/s" -ForegroundColor White
        
        Write-Host "`nPermissions:" -ForegroundColor Cyan
        foreach ($perm in $testResults.Permissions) {
            Write-Host "  $($perm.Identity): $($perm.FileSystemRights)" -ForegroundColor Gray
        }
    }
    
    if (!$testResults.IsAccessible) {
        throw "Volume is not accessible for migration. Check permissions and network connectivity."
    }
    
    Write-AccessLog "Volume accessibility testing completed successfully"
    Write-AccessLog "Results saved to: $resultsFile"
    
    return $testResults
}
catch {
    Write-AccessLog "Volume accessibility testing failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}