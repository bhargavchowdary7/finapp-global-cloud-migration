<#
.SYNOPSIS
    Retrieves database migration secrets from Azure Key Vault.
.DESCRIPTION
    Securely fetches necessary credentials for database migration from Azure Key Vault.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

try {
    Write-Host "Retrieving database migration secrets from Key Vault: $KeyVaultName" -ForegroundColor Yellow

    $requiredSecrets = @(
        "source-db-server", "source-db-name", "source-db-username", "source-db-password",
        "target-pgsql-server", "target-pgsql-database", "target-pgsql-username", "target-pgsql-password"
    )

    $secrets = @{}

    foreach ($secretName in $requiredSecrets) {
        Write-Host "  Retrieving: $secretName" -ForegroundColor Gray
        try {
            $secretValue = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -AsPlainText)
            
            switch ($secretName) {
                "source-db-server" { $secrets.SourceServer = $secretValue }
                "source-db-name" { $secrets.SourceDatabase = $secretValue }
                "source-db-username" { $secrets.SourceUsername = $secretValue }
                "source-db-password" { $secrets.SourcePassword = $secretValue }
                "target-pgsql-server" { $secrets.TargetServer = $secretValue }
                "target-pgsql-database" { $secrets.TargetDatabase = $secretValue }
                "target-pgsql-username" { $secrets.TargetUsername = $secretValue }
                "target-pgsql-password" { $secrets.TargetPassword = $secretValue }
            }
            
            Write-Host "    ✓ Retrieved" -ForegroundColor Green
        }
        catch {
            Write-Warning "    ⚠ Secret '$secretName' not found"
        }
    }

    return $secrets

} catch {
    Write-Error "Failed to retrieve secrets: $($_.Exception.Message)"
    throw
}