<#
.SYNOPSIS
    Tests Azure Key Vault secrets required for database migration connections.
.DESCRIPTION
    Validates existence and accessibility of secrets for database connections in Azure Key Vault.
    Tests connectivity to databases using the retrieved secrets. Generates a summary report of the validation results.
.PARAMETER KeyVaultName
    Name of the Azure Key Vault
.PARAMETER SecretNames
    Array of secret names to test
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string[]]$SecretNames
)

function Write-KeyVaultLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\keyvault-test.log" -Append
}

function Test-KeyVaultAccess {
    param([string]$VaultName)
    
    try {
        Write-KeyVaultLog "Testing access to Key Vault: $VaultName"
        $context = Get-AzContext
        if (!$context) {
            throw "Not authenticated to Azure. Please run Connect-AzAccount first."
        }
        
        # Test by listing secrets (limited to 1 for performance)
        Get-AzKeyVaultSecret -VaultName $VaultName -Count 1 -ErrorAction Stop
        Write-KeyVaultLog "Successfully accessed Key Vault: $VaultName"
        return $true
    }
    catch {
        Write-KeyVaultLog "Failed to access Key Vault $VaultName : $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-KeyVaultSecret {
    param([string]$VaultName, [string]$SecretName)
    
    try {
        Write-KeyVaultLog "Testing secret: $SecretName"
        $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -ErrorAction Stop
        
        if ($secret.Enabled -eq $false) {
            Write-KeyVaultLog "Secret $SecretName is disabled" -Level "WARNING"
            return $false
        }
        
        # Test retrieving secret value
        $secretValue = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText -ErrorAction Stop
        
        if ([string]::IsNullOrEmpty($secretValue)) {
            Write-KeyVaultLog "Secret $SecretName has empty value" -Level "WARNING"
            return $false
        }
        
        Write-KeyVaultLog "Secret $SecretName is accessible and valid"
        return @{
            Name = $secret.Name
            Enabled = $secret.Enabled
            Created = $secret.Created
            Updated = $secret.Updated
            HasValue = ![string]::IsNullOrEmpty($secretValue)
        }
    }
    catch {
        Write-KeyVaultLog "Failed to access secret $SecretName : $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-DatabaseConnectionFromSecret {
    param([string]$VaultName, [string]$ConnectionStringSecretName)
    
    try {
        Write-KeyVaultLog "Testing database connection using secret: $ConnectionStringSecretName"
        
        $connectionString = Get-AzKeyVaultSecret -VaultName $VaultName -Name $ConnectionStringSecretName -AsPlainText
        
        # Test SQL connection
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $serverVersion = $connection.ServerVersion
        $connection.Close()
        
        Write-KeyVaultLog "Database connection test successful. Server version: $serverVersion"
        return $true
    }
    catch {
        Write-KeyVaultLog "Database connection test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-KeyVaultLog "Starting Key Vault secrets validation"
    
    # Import Azure module
    Import-Module Az.KeyVault -ErrorAction Stop
    
    # Test Key Vault access
    if (!(Test-KeyVaultAccess -VaultName $KeyVaultName)) {
        throw "Cannot access Key Vault: $KeyVaultName"
    }
    
    # Test individual secrets
    $secretResults = @()
    $allSecretsValid = $true
    
    foreach ($secretName in $SecretNames) {
        $secretResult = Test-KeyVaultSecret -VaultName $KeyVaultName -SecretName $secretName
        if ($secretResult -eq $false) {
            $allSecretsValid = $false
        }
        $secretResults += [PSCustomObject]@{
            SecretName = $secretName
            Status = if ($secretResult -ne $false) { "VALID" } else { "INVALID" }
            Details = $secretResult
        }
    }
    
    # Test database connections if connection string secrets exist
    $connectionSecrets = $SecretNames | Where-Object { $_ -like "*connectionstring*" -or $_ -like "*connstring*" }
    foreach ($connSecret in $connectionSecrets) {
        if ($secretResults | Where-Object { $_.SecretName -eq $connSecret -and $_.Status -eq "VALID" }) {
            $connTestResult = Test-DatabaseConnectionFromSecret -VaultName $KeyVaultName -ConnectionStringSecretName $connSecret
            if (!$connTestResult) {
                $allSecretsValid = $false
                ($secretResults | Where-Object { $_.SecretName -eq $connSecret }).Status = "CONNECTION_FAILED"
            }
        }
    }
    
    # Generate summary report
    $validationReport = @{
        ValidationDate = Get-Date
        KeyVaultName = $KeyVaultName
        SecretsTested = $SecretNames
        Results = $secretResults
        OverallStatus = if ($allSecretsValid) { "PASS" } else { "FAIL" }
    }
    
    # Export report
    $reportPath = ".\KeyVault-Validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $validationReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath
    
    # Display summary
    Write-Host "`n=== KEY VAULT VALIDATION SUMMARY ===" -ForegroundColor Green
    Write-Host "Key Vault: $KeyVaultName" -ForegroundColor Yellow
    Write-Host "Secrets Tested: $($SecretNames.Count)" -ForegroundColor Yellow
    Write-Host "Valid Secrets: $(($secretResults | Where-Object { $_.Status -eq 'VALID' }).Count)" -ForegroundColor Green
    Write-Host "Invalid Secrets: $(($secretResults | Where-Object { $_.Status -ne 'VALID' }).Count)" -ForegroundColor Red
    Write-Host "Overall Status: $($validationReport.OverallStatus)" -ForegroundColor $(if ($validationReport.OverallStatus -eq "PASS") { "Green" } else { "Red" })
    
    Write-Host "`nDetailed Results:" -ForegroundColor Cyan
    $secretResults | Format-Table SecretName, Status -AutoSize
    
    if (!$allSecretsValid) {
        throw "Key Vault validation failed - check the report for details"
    }
    
    Write-KeyVaultLog "Key Vault secrets validation completed successfully" -Level "SUCCESS"
}
catch {
    Write-KeyVaultLog "Key Vault validation failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}