<#
.SYNOPSIS
    Cleanup Resources Script - Safely Delete Storage Infrastructure
    
.DESCRIPTION
    This script safely removes all Azure resources created by Storage_provisioner_automation.ps1
    Includes confirmation prompts and validates deletion to prevent accidental resource removal.
    
    Use Case: Safe cleanup of File Share Archiving infrastructure
    
.PARAMETER ResourceGroupName
    Name of the Resource Group to delete (default: rg-deptfiles-prod-001)
    
.PARAMETER Force
    Skip confirmation prompts (use with caution!)
    
.PARAMETER DeleteDnsResources
    Also delete associated Private DNS resources (default: $false)
    
.EXAMPLE
    .\cleanup-resources.ps1 -ResourceGroupName "rg-deptfiles-prod-001"
    
.EXAMPLE
    .\cleanup-resources.ps1 -ResourceGroupName "rg-deptfiles-prod-001" -Force -DeleteDnsResources
    
.NOTES
    Author: FinApp Cloud Engineering Team
    Version: 1.0
    Requires: Az.Resources, Az.Storage PowerShell modules
    CAUTION: This script permanently deletes Azure resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-deptfiles-prod-001",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$DeleteDnsResources,
    
    [Parameter(Mandatory = $false)]
    [string]$VNetResourceGroup = ""
)

#Requires -Modules Az.Resources, Az.Storage, Az.Network

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "Azure Resource Cleanup Utility" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

Write-Warning "This script will DELETE Azure resources permanently!"
Write-Warning "This action CANNOT be undone."

# ============================================================================
# STEP 1: VALIDATE PREREQUISITES
# ============================================================================

Write-Host "`n[1/5] Validating prerequisites..." -ForegroundColor Yellow

try {
    # Check Azure login
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged into Azure. Run 'Connect-AzAccount' first."
    }
    Write-Host "   Logged in as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "   Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    
    # Check if Resource Group exists
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Host "`n   Resource Group '$ResourceGroupName' not found. Nothing to delete." -ForegroundColor DarkYellow
        exit 0
    }
    Write-Host "   Resource Group found: $ResourceGroupName" -ForegroundColor Green
    
} catch {
    Write-Error "Prerequisites validation failed: $_"
    exit 1
}

# ============================================================================
# STEP 2: INVENTORY RESOURCES
# ============================================================================

Write-Host "`n[2/5] Inventorying resources in Resource Group..." -ForegroundColor Yellow

try {
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    $resourceCount = $resources.Count
    
    if ($resourceCount -eq 0) {
        Write-Host "  ⚠ No resources found in Resource Group. Proceeding to delete empty group." -ForegroundColor DarkYellow
    } else {
        Write-Host "  ✓ Found $resourceCount resource(s):" -ForegroundColor Green
        
        # Categorize resources
        $storageAccounts = $resources | Where-Object { $_.ResourceType -eq "Microsoft.Storage/storageAccounts" }
        $privateEndpoints = $resources | Where-Object { $_.ResourceType -eq "Microsoft.Network/privateEndpoints" }
        $others = $resources | Where-Object { $_.ResourceType -notin @("Microsoft.Storage/storageAccounts", "Microsoft.Network/privateEndpoints") }
        
        if ($storageAccounts) {
            Write-Host "`n    Storage Accounts ($($storageAccounts.Count)):" -ForegroundColor Cyan
            foreach ($sa in $storageAccounts) {
                Write-Host "      • $($sa.Name)" -ForegroundColor Gray
            }
        }
        
        if ($privateEndpoints) {
            Write-Host "`n    Private Endpoints ($($privateEndpoints.Count)):" -ForegroundColor Cyan
            foreach ($pe in $privateEndpoints) {
                Write-Host "      • $($pe.Name)" -ForegroundColor Gray
            }
        }
        
        if ($others) {
            Write-Host "`n    Other Resources ($($others.Count)):" -ForegroundColor Cyan
            foreach ($res in $others) {
                Write-Host "      • $($res.Name) [$($res.ResourceType)]" -ForegroundColor Gray
            }
        }
    }
    
} catch {
    Write-Error "Failed to inventory resources: $_"
    exit 1
}

# ============================================================================
# STEP 3: CONFIRMATION PROMPT
# ============================================================================

if (-not $Force) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "⚠ CONFIRMATION REQUIRED ⚠" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    
    Write-Host "`nYou are about to DELETE:" -ForegroundColor White
    Write-Host "  • Resource Group: $ResourceGroupName" -ForegroundColor Yellow
    Write-Host "  • Location: $($rg.Location)" -ForegroundColor Yellow
    Write-Host "  • Resources: $resourceCount" -ForegroundColor Yellow
    
    Write-Host "`nThis will permanently delete:" -ForegroundColor White
    Write-Host "  • All Storage Accounts and their data (blobs, files, etc.)" -ForegroundColor Red
    Write-Host "  • All Private Endpoints" -ForegroundColor Red
    Write-Host "  • All associated configurations and metadata" -ForegroundColor Red
    
    Write-Host "`nTags on Resource Group:" -ForegroundColor White
    $rg.Tags.GetEnumerator() | ForEach-Object {
        Write-Host "  • $($_.Key): $($_.Value)" -ForegroundColor Gray
    }
    
    Write-Host "`n========================================" -ForegroundColor Red
    $confirmation = Read-Host "`nType 'DELETE' to confirm deletion of Resource Group '$ResourceGroupName'"
    
    if ($confirmation -ne "DELETE") {
        Write-Host "`n Cleanup cancelled by user." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "`n Confirmation received. Proceeding with deletion..." -ForegroundColor Green
}

# ============================================================================
# STEP 4: DELETE STORAGE ACCOUNTS (WITH SOFT DELETE CHECK)
# ============================================================================

Write-Host "`n[3/5] Preparing Storage Accounts for deletion..." -ForegroundColor Yellow

if ($storageAccounts) {
    foreach ($sa in $storageAccounts) {
        try {
            Write-Host "  • Processing: $($sa.Name)" -ForegroundColor Gray
            
            # Get storage account details
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $sa.Name
            $ctx = $storageAccount.Context
            
            # Check for soft delete
            $blobService = Get-AzStorageBlobServiceProperty -ResourceGroupName $ResourceGroupName -AccountName $sa.Name
            if ($blobService.DeleteRetentionPolicy.Enabled) {
                Write-Host "     Blob soft delete is enabled (retention: $($blobService.DeleteRetentionPolicy.Days) days)" -ForegroundColor DarkYellow
                Write-Host "    i Blobs will be recoverable for $($blobService.DeleteRetentionPolicy.Days) days after deletion" -ForegroundColor DarkYellow
            }
            
            # List containers
            $containers = Get-AzStorageContainer -Context $ctx
            if ($containers) {
                Write-Host "    i Containers to be deleted: $($containers.Count)" -ForegroundColor Gray
                foreach ($container in $containers) {
                    Write-Host "      - $($container.Name)" -ForegroundColor DarkGray
                }
            }
            
            Write-Host "    ✓ Storage Account ready for deletion" -ForegroundColor Green
            
        } catch {
            Write-Warning "Failed to analyze storage account '$($sa.Name)': $_"
        }
    }
}

# ============================================================================
# STEP 5: DELETE RESOURCE GROUP
# ============================================================================

Write-Host "`n[4/5] Deleting Resource Group and all resources..." -ForegroundColor Yellow

try {
    # Remove Resource Group (this deletes all contained resources)
    Write-Host "`n   Deletion in progress... (this may take several minutes)" -ForegroundColor Cyan
    Write-Host "  i Azure will delete resources in the correct dependency order" -ForegroundColor Gray
    
    $startTime = Get-Date
    
    Remove-AzResourceGroup `
        -Name $ResourceGroupName `
        -Force `
        -AsJob | Out-Null
    
    # Monitor deletion job
    $job = Get-Job | Where-Object { $_.Command -like "*Remove-AzResourceGroup*" } | Select-Object -First 1
    
    if ($job) {
        Write-Host "`n   Monitoring deletion progress..." -ForegroundColor Cyan
        
        while ($job.State -eq "Running") {
            $elapsed = (Get-Date) - $startTime
            Write-Host "    • Elapsed time: $([math]::Round($elapsed.TotalSeconds, 0))s" -ForegroundColor Gray
            Start-Sleep -Seconds 10
        }
        
        if ($job.State -eq "Completed") {
            $elapsed = (Get-Date) - $startTime
            Write-Host "`n  ✓ Resource Group deleted successfully!" -ForegroundColor Green
            Write-Host "  ✓ Total time: $([math]::Round($elapsed.TotalMinutes, 1)) minutes" -ForegroundColor Green
        } else {
            Write-Warning "Deletion job ended with state: $($job.State)"
            $job | Receive-Job
        }
        
        Remove-Job -Job $job
    }
    
    # Verify deletion
    $rgCheck = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($rgCheck) {
        Write-Warning "Resource Group still exists. Deletion may still be in progress."
    } else {
        Write-Host "   Verified: Resource Group no longer exists" -ForegroundColor Green
    }
    
} catch {
    Write-Error "Failed to delete Resource Group: $_"
    exit 1
}

# ============================================================================
# STEP 6: CLEANUP DNS RESOURCES (OPTIONAL)
# ============================================================================

if ($DeleteDnsResources -and $VNetResourceGroup) {
    Write-Host "`n[5/5] Cleaning up Private DNS resources..." -ForegroundColor Yellow
    
    try {
        $dnsZoneName = "privatelink.blob.core.windows.net"
        
        # Check if DNS zone exists
        $dnsZone = Get-AzPrivateDnsZone -ResourceGroupName $VNetResourceGroup -Name $dnsZoneName -ErrorAction SilentlyContinue
        
        if ($dnsZone) {
            # List A records for deleted storage accounts
            $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $VNetResourceGroup -ZoneName $dnsZoneName -RecordType A
            
            foreach ($sa in $storageAccounts) {
                $record = $recordSets | Where-Object { $_.Name -eq $sa.Name }
                if ($record) {
                    Remove-AzPrivateDnsRecordSet -ResourceGroupName $VNetResourceGroup -ZoneName $dnsZoneName -Name $sa.Name -RecordType A -Confirm:$false
                    Write-Host "   Deleted DNS A record: $($sa.Name)" -ForegroundColor Green
                }
            }
            
            Write-Host "  i Private DNS Zone '$dnsZoneName' retained (may be used by other resources)" -ForegroundColor Gray
        } else {
            Write-Host "   Private DNS Zone not found. Skipping DNS cleanup." -ForegroundColor DarkYellow
        }
        
    } catch {
        Write-Warning "DNS cleanup encountered non-critical errors: $_"
    }
} else {
    Write-Host "`n[5/5] Skipping DNS cleanup (use -DeleteDnsResources to clean DNS records)" -ForegroundColor Gray
}

# ============================================================================
# CLEANUP SUMMARY
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "CLEANUP COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Deleted Resources:" -ForegroundColor White
Write-Host "   Resource Group: $ResourceGroupName " -ForegroundColor Gray
Write-Host "   Storage Accounts: $($storageAccounts.Count) " -ForegroundColor Gray
Write-Host "   Private Endpoints: $($privateEndpoints.Count) " -ForegroundColor Gray
Write-Host "   Other Resources: $($others.Count) " -ForegroundColor Gray

if ($storageAccounts -and $blobService.DeleteRetentionPolicy.Enabled) {
    Write-Host "`nData Recovery:" -ForegroundColor White
    Write-Host "   Soft delete is enabled on storage accounts" -ForegroundColor Yellow
    Write-Host "  i Deleted blobs are recoverable for $($blobService.DeleteRetentionPolicy.Days) days" -ForegroundColor Gray
    Write-Host "  i Use Azure Portal or 'Undelete-AzStorageBlob' to recover data" -ForegroundColor Gray
}

Write-Host "`nCost Impact:" -ForegroundColor White
Write-Host "   All resources deleted - no ongoing charges" -ForegroundColor Green
Write-Host "  i Final charges may appear in next billing cycle" -ForegroundColor Gray

Write-Host "`nAudit Trail:" -ForegroundColor White
Write-Host "  • Check Azure Activity Log for deletion audit trail" -ForegroundColor Gray
Write-Host "  • Deletion timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "  • Deleted by: $($context.Account.Id)" -ForegroundColor Gray

Write-Host "`n========================================`n" -ForegroundColor Green

# Export cleanup log
$cleanupLog = @{
    Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ResourceGroup     = $ResourceGroupName
    DeletedBy         = $context.Account.Id
    StorageAccounts   = $storageAccounts.Name
    PrivateEndpoints  = $privateEndpoints.Name
    ResourceCount     = $resourceCount
}

$cleanupLog | ConvertTo-Json | Out-File "cleanup-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
Write-Host "Cleanup log saved to: cleanup-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').json`n" -ForegroundColor Green
