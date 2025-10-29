<#
.SYNOPSIS
    Retrieves migration secrets from Azure Key Vault securely for database migration. 
.DESCRIPTION
    Fetches database connection strings, credentials, and other secrets from Azure Key Vault 
    for use in migration scripts. Supports both managed identity and service principal authentication. 
    Validates access to Key Vault and the retrieved secrets, and can output them as environment variables or export to a secure file.
.PARAMETER KeyVaultName
    Name of the Azure Key Vault
.PARAMETER SecretNames
    Array of secret names to retrieve
.PARAMETER UseManagedIdentity
    Switch to use managed identity instead of service principal
.PARAMETER OutputAsEnvironmentVariables
    Switch to output secrets as environment variables
.PARAMETER SecretMapping
    Hashtable mapping secret names to environment variable names
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string[]]$SecretNames,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseManagedIdentity,
    
    [Parameter(Mandatory=$false)]
    [switch]$OutputAsEnvironmentVariables,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$SecretMapping = @{}
)

function Write-SecretLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath ".\get-secrets.log" -Append
}

function Test-AzConnection {
    try {
        Write-SecretLog "Testing Azure connection"
        $context = Get-AzContext
        if ($context) {
            Write-SecretLog "Connected to Azure as: $($context.Account.Id)" -Level "SUCCESS"
            return $true
        }
        return $false
    }
    catch {
        Write-SecretLog "Azure connection test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Connect-AzWithManagedIdentity {
    try {
        Write-SecretLog "Attempting to connect using Managed Identity"
        
        # Check if we're in Azure environment
        $imdsEndpoint = "http://169.254.169.254/metadata/identity/oauth2/token"
        $response = Invoke-WebRequest -Uri $imdsEndpoint -Method GET -Headers @{"Metadata" = "true"} -UseBasicParsing -ErrorAction SilentlyContinue
        
        if ($response.StatusCode -eq 200) {
            Connect-AzAccount -Identity -ErrorAction Stop
            Write-SecretLog "Successfully connected using Managed Identity" -Level "SUCCESS"
            return $true
        }
        else {
            Write-SecretLog "Managed Identity not available in current environment" -Level "WARNING"
            return $false
        }
    }
    catch {
        Write-SecretLog "Managed Identity connection failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Connect-AzWithServicePrincipal {
    try {
        Write-SecretLog "Attempting to connect using Service Principal"
        
        # Check for environment variables
        $requiredVars = @("AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID")
        $missingVars = $requiredVars | Where-Object { -not (Get-Item "Env:$_" -ErrorAction SilentlyContinue) }
        
        if ($missingVars.Count -gt 0) {
            Write-SecretLog "Missing required environment variables: $($missingVars -join ', ')" -Level "ERROR"
            return $false
        }
        
        $secureSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, $secureSecret)
        
        Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $env:AZURE_TENANT_ID -ErrorAction Stop
        Write-SecretLog "Successfully connected using Service Principal" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-SecretLog "Service Principal connection failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-SecretFromKeyVault {
    param([string]$VaultName, [string]$SecretName)
    
    try {
        Write-SecretLog "Retrieving secret: $SecretName"
        
        $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -ErrorAction Stop
        
        if ($secret.Enabled -eq $false) {
            Write-SecretLog "Secret $SecretName is disabled" -Level "WARNING"
            return $null
        }
        
        $secretValue = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText -ErrorAction Stop
        
        if ([string]::IsNullOrEmpty($secretValue)) {
            Write-SecretLog "Secret $SecretName has empty value" -Level "WARNING"
            return $null
        }
        
        Write-SecretLog "Successfully retrieved secret: $SecretName" -Level "SUCCESS"
        
        return @{
            Name = $secret.Name
            Value = $secretValue
            Enabled = $secret.Enabled
            Created = $secret.Created
            Updated = $secret.Updated
            ContentType = $secret.ContentType
        }
    }
    catch {
        Write-SecretLog "Failed to retrieve secret $SecretName : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Set-EnvironmentVariableFromSecret {
    param([string]$SecretName, [string]$SecretValue, [hashtable]$Mapping)
    
    try {
        $envVarName = if ($Mapping.ContainsKey($SecretName)) {
            $Mapping[$SecretName]
        } else {
            # Convert secret name to environment variable format
            $SecretName.ToUpper().Replace("-", "_").Replace(".", "_")
        }
        
        Write-SecretLog "Setting environment variable: $envVarName"
        
        # Set process-level environment variable
        [Environment]::SetEnvironmentVariable($envVarName, $SecretValue, "Process")
        
        # Also set for current session
        Set-Item -Path "Env:$envVarName" -Value $SecretValue
        
        Write-SecretLog "Environment variable set successfully: $envVarName" -Level "SUCCESS"
        
        return $envVarName
    }
    catch {
        Write-SecretLog "Failed to set environment variable for $SecretName : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Test-DatabaseConnectionFromSecret {
    param([string]$ConnectionString)
    
    try {
        Write-SecretLog "Testing database connection using retrieved secret"
        
        if ([string]::IsNullOrEmpty($ConnectionString)) {
            Write-SecretLog "Connection string is empty" -Level "WARNING"
            return $false
        }
        
        # Test SQL connection
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        $serverVersion = $connection.ServerVersion
        $connection.Close()
        
        Write-SecretLog "Database connection test successful. Server version: $serverVersion" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-SecretLog "Database connection test failed: $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

function Export-SecretsToFile {
    param([hashtable]$Secrets, [string]$OutputPath)
    
    try {
        Write-SecretLog "Exporting secrets to secure file"
        
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        $secretsFile = Join-Path $OutputPath "migration-secrets-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        
        # Create a sanitized version for logging (without actual values)
        $sanitizedSecrets = @{}
        foreach ($secret in $Secrets.GetEnumerator()) {
            $sanitizedSecrets[$secret.Key] = @{
                Name = $secret.Value.Name
                Enabled = $secret.Value.Enabled
                Created = $secret.Value.Created
                Updated = $secret.Value.Updated
                ContentType = $secret.Value.ContentType
                Value = "***HIDDEN***"
            }
        }
        
        $sanitizedSecrets | ConvertTo-Json -Depth 5 | Out-File -FilePath $secretsFile
        
        Write-SecretLog "Secrets metadata exported to: $secretsFile" -Level "SUCCESS"
        return $secretsFile
    }
    catch {
        Write-SecretLog "Failed to export secrets to file: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Main execution
try {
    Write-SecretLog "Starting migration secrets retrieval"
    Write-SecretLog "Key Vault: $KeyVaultName"
    Write-SecretLog "Secrets requested: $($SecretNames -join ', ')"
    
    # Import required module
    Import-Module Az.KeyVault -ErrorAction Stop
    
    # Establish Azure connection
    if (!(Test-AzConnection)) {
        if ($UseManagedIdentity) {
            if (!(Connect-AzWithManagedIdentity)) {
                throw "Failed to connect using Managed Identity"
            }
        } else {
            if (!(Connect-AzWithServicePrincipal)) {
                throw "Failed to connect using Service Principal. Please ensure AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID are set."
            }
        }
    }
    
    # Verify Key Vault access
    Write-SecretLog "Testing access to Key Vault: $KeyVaultName"
    Get-AzKeyVaultSecret -VaultName $KeyVaultName -Count 1 -ErrorAction Stop | Out-Null
    Write-SecretLog "Key Vault access verified successfully" -Level "SUCCESS"
    
    # Retrieve secrets
    $retrievedSecrets = @{}
    $environmentVariables = @()
    
    foreach ($secretName in $SecretNames) {
        $secret = Get-SecretFromKeyVault -VaultName $KeyVaultName -SecretName $secretName
        
        if ($secret) {
            $retrievedSecrets[$secretName] = $secret
            
            # Set as environment variable if requested
            if ($OutputAsEnvironmentVariables) {
                $envVarName = Set-EnvironmentVariableFromSecret -SecretName $secretName -SecretValue $secret.Value -Mapping $SecretMapping
                if ($envVarName) {
                    $environmentVariables += $envVarName
                }
            }
            
            # Test database connection if this is a connection string
            if ($secretName -like "*connectionstring*" -or $secretName -like "*connstring*") {
                $connectionTest = Test-DatabaseConnectionFromSecret -ConnectionString $secret.Value
                if (!$connectionTest) {
                    Write-SecretLog "WARNING: Database connection test failed for $secretName" -Level "WARNING"
                }
            }
        } else {
            Write-SecretLog "Secret $secretName could not be retrieved" -Level "ERROR"
        }
    }
    
    # Export secrets metadata to file
    $exportedFile = Export-SecretsToFile -Secrets $retrievedSecrets -OutputPath ".\Secrets"
    
    # Generate summary report
    $summaryReport = @{
        RetrievalDate = Get-Date
        KeyVaultName = $KeyVaultName
        TotalSecretsRequested = $SecretNames.Count
        SuccessfullyRetrieved = $retrievedSecrets.Count
        FailedRetrievals = $SecretNames.Count - $retrievedSecrets.Count
        RetrievedSecrets = $retrievedSecrets.Keys
        EnvironmentVariablesSet = $environmentVariables
        AuthenticationMethod = if ($UseManagedIdentity) { "Managed Identity" } else { "Service Principal" }
        ExportFile = $exportedFile
    }
    
    # Display summary
    Write-Host "`n=== SECRETS RETRIEVAL SUMMARY ===" -ForegroundColor Green
    Write-Host "Key Vault: $KeyVaultName" -ForegroundColor Yellow
    Write-Host "Secrets Requested: $($SecretNames.Count)" -ForegroundColor Yellow
    Write-Host "Successfully Retrieved: $($retrievedSecrets.Count)" -ForegroundColor Green
    Write-Host "Failed: $($summaryReport.FailedRetrievals)" -ForegroundColor $(if ($summaryReport.FailedRetrievals -eq 0) { "Green" } else { "Red" })
    Write-Host "Authentication: $($summaryReport.AuthenticationMethod)" -ForegroundColor Cyan
    
    if ($environmentVariables.Count -gt 0) {
        Write-Host "Environment Variables Set:" -ForegroundColor Cyan
        foreach ($envVar in $environmentVariables) {
            Write-Host "  - $envVar" -ForegroundColor White
        }
    }
    
    Write-Host "`nRetrieved Secrets:" -ForegroundColor Cyan
    foreach ($secretName in $retrievedSecrets.Keys) {
        Write-Host "  - $secretName" -ForegroundColor White
    }
    
    if ($summaryReport.FailedRetrievals -gt 0) {
        $failedSecrets = $SecretNames | Where-Object { $_ -notin $retrievedSecrets.Keys }
        Write-Host "`nFailed Secrets:" -ForegroundColor Red
        foreach ($failed in $failedSecrets) {
            Write-Host "  - $failed" -ForegroundColor Red
        }
        throw "One or more secrets could not be retrieved"
    }
    
    Write-SecretLog "Migration secrets retrieval completed successfully" -Level "SUCCESS"
    
    return $summaryReport
}
catch {
    Write-SecretLog "Migration secrets retrieval failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}