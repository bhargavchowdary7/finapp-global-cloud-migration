<#
.SYNOPSIS
    Storage Provisioner Automation - IaC Script for Secure Departmental File Storage
    
.DESCRIPTION
    This script provisions a highly secured Azure Storage infrastructure for departmental files
    with complete isolation from public internet, automated lifecycle management, and cost optimization.
   
 
    Key Features:
    - Creates Resource Group with standardized tagging
    - Provisions GRS Storage Account with Public Access DISABLED
    - Creates blob containers (dept-files-active, dept-files-archive)
    - Configures Private Endpoint for secure access
    - Implements Lifecycle Management Policy (Cool: 90d, Archive: 365d)
    - Integrates with existing VNet/Subnet for private connectivity
    
.PARAMETER ResourceGroupName
    Name of the Resource Group (default: rg-deptfiles-prod-001)
    
.PARAMETER Location
    Azure region for deployment (default: East US 2)
    
.PARAMETER StorageAccountName
    Name of the Storage Account (must be globally unique, 3-24 lowercase alphanumeric characters)
    
.PARAMETER VNetName
    Name of the existing Virtual Network for Private Endpoint
    
.PARAMETER SubnetName
    Name of the existing Subnet for Private Endpoint
    
.PARAMETER VNetResourceGroup
    Resource Group containing the Virtual Network
    
.EXAMPLE
    .\storage_provisioner_automation.ps1 -StorageAccountName "stdeptfiles001" -VNetName "finapp-vnet" -SubnetName "private-endpoints" -VNetResourceGroup "rg-network-prod"
    
.NOTES
    Requires: Az.Storage, Az.Network, Az.Resources PowerShell modules
    Security: Implements Zero Trust architecture with private endpoints only
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-deptfiles-prod-001",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US 2",
    
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $true)]
    [string]$VNetName,
    
    [Parameter(Mandatory = $true)]
    [string]$SubnetName,
    
    [Parameter(Mandatory = $true)]
    [string]$VNetResourceGroup,
    
    [Parameter(Mandatory = $false)]
    [int]$CoolTierDays = 90,
    
    [Parameter(Mandatory = $false)]
    [int]$ArchiveTierDays = 365
)

#Requires -Modules Az.Storage, Az.Network, Az.Resources

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# Standardized tags as per requirements
$Tags = @{
    Environment = "Production"
    Project     = "Research"
    CostCenter  = "9876"
    ManagedBy   = "PowerShell-IaC"
    CreatedDate = (Get-Date -Format "yyyy-MM-dd")
}

# Container names
$ContainerActive = "dept-files-active"
$ContainerArchive = "dept-files-archive"

# Private Endpoint configuration
$PrivateEndpointName = "pe-$StorageAccountName-blob"
$PrivateDnsZoneName = "privatelink.blob.core.windows.net"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Storage Provisioner Automation" -ForegroundColor Cyan
Write-Host "File Share Archiving - Secure IaC" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================================================
# STEP 1: VALIDATE PREREQUISITES
# ============================================================================

Write-Host "[1/8] Validating prerequisites..." -ForegroundColor Yellow

try {
    # Check Azure login
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged into Azure. Run 'Connect-AzAccount' first."
    }
    Write-Host "   Logged in as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "   Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    
    # Validate VNet exists
    $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $VNetResourceGroup -ErrorAction SilentlyContinue
    if (-not $vnet) {
        throw "Virtual Network '$VNetName' not found in resource group '$VNetResourceGroup'"
    }
    Write-Host "   Virtual Network found: $VNetName" -ForegroundColor Green
    
    # Validate Subnet exists
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -ErrorAction SilentlyContinue
    if (-not $subnet) {
        throw "Subnet '$SubnetName' not found in VNet '$VNetName'"
    }
    Write-Host "   Subnet found: $SubnetName" -ForegroundColor Green
    
    # Check storage account name availability
    $nameAvailable = Get-AzStorageAccountNameAvailability -Name $StorageAccountName
    if (-not $nameAvailable.NameAvailable) {
        throw "Storage account name '$StorageAccountName' is not available: $($nameAvailable.Reason)"
    }
    Write-Host "   Storage account name available: $StorageAccountName" -ForegroundColor Green
    
} catch {
    Write-Error "Prerequisites validation failed: $_"
    exit 1
}

# ============================================================================
# STEP 2: CREATE RESOURCE GROUP
# ============================================================================

Write-Host "`n[2/8] Creating Resource Group..." -ForegroundColor Yellow

try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($rg) {
        Write-Host "   Resource Group already exists: $ResourceGroupName" -ForegroundColor DarkYellow
    } else {
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags
        Write-Host "   Resource Group created: $ResourceGroupName" -ForegroundColor Green
    }
    Write-Host "   Location: $Location" -ForegroundColor Green
    Write-Host "   Tags applied: Environment=$($Tags.Environment), Project=$($Tags.Project), CostCenter=$($Tags.CostCenter)" -ForegroundColor Green
} catch {
    Write-Error "Failed to create Resource Group: $_"
    exit 1
}

# ============================================================================
# STEP 3: CREATE STORAGE ACCOUNT (GRS, PUBLIC ACCESS DISABLED)
# ============================================================================

Write-Host "`n[3/8] Creating Storage Account (GRS, Public Access Disabled)..." -ForegroundColor Yellow

try {
    $storageParams = @{
        ResourceGroupName      = $ResourceGroupName
        Name                   = $StorageAccountName
        Location               = $Location
        SkuName               = "Standard_GRS"  # Geo-Redundant Storage for DR
        Kind                  = "StorageV2"     # General-Purpose V2
        AccessTier            = "Hot"           # Default access tier
        AllowBlobPublicAccess = $false         # ✓ CRITICAL: Disable public access
        PublicNetworkAccess   = "Disabled"     # ✓ CRITICAL: No public internet access
        MinimumTlsVersion     = "TLS1_2"       # Enforce TLS 1.2+
        EnableHttpsTrafficOnly = $true         # HTTPS only
        Tag                   = $Tags
    }
    
    $storageAccount = New-AzStorageAccount @storageParams
    Write-Host "   Storage Account created: $StorageAccountName" -ForegroundColor Green
    Write-Host "   SKU: Standard_GRS (Geo-Redundant)" -ForegroundColor Green
    Write-Host "   Public Network Access: Disabled ✓" -ForegroundColor Green
    Write-Host "   Allow Blob Public Access: Disabled ✓" -ForegroundColor Green
    Write-Host "   HTTPS Only: Enabled ✓" -ForegroundColor Green
    
    # Get storage context
    $ctx = $storageAccount.Context
    
} catch {
    Write-Error "Failed to create Storage Account: $_"
    exit 1
}

# ============================================================================
# STEP 4: CREATE BLOB CONTAINERS
# ============================================================================

Write-Host "`n[4/8] Creating Blob Containers..." -ForegroundColor Yellow

try {
    # Create dept-files-active container
    $containerActiveParams = @{
        Name    = $ContainerActive
        Context = $ctx
        Permission = "Off"  # No public access
    }
    New-AzStorageContainer @containerActiveParams | Out-Null
    Write-Host "   Container created: $ContainerActive (Public Access: Off)" -ForegroundColor Green
    
    # Create dept-files-archive container
    $containerArchiveParams = @{
        Name    = $ContainerArchive
        Context = $ctx
        Permission = "Off"  # No public access
    }
    New-AzStorageContainer @containerArchiveParams | Out-Null
    Write-Host "   Container created: $ContainerArchive (Public Access: Off)" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create containers: $_"
    exit 1
}

# ============================================================================
# STEP 5: CONFIGURE LIFECYCLE MANAGEMENT POLICY
# ============================================================================

Write-Host "`n[5/8] Configuring Lifecycle Management Policy..." -ForegroundColor Yellow

try {
    # Define lifecycle rule for dept-files-active
    $rule = [PSCustomObject]@{
        name    = "MoveToArchiveTiers"
        enabled = $true
        type    = "Lifecycle"
        definition = [PSCustomObject]@{
            filters = [PSCustomObject]@{
                blobTypes = @("blockBlob")
                prefixMatch = @("$ContainerActive/")
            }
            actions = [PSCustomObject]@{
                baseBlob = [PSCustomObject]@{
                    tierToCool = [PSCustomObject]@{
                        daysAfterModificationGreaterThan = $CoolTierDays
                    }
                    tierToArchive = [PSCustomObject]@{
                        daysAfterModificationGreaterThan = $ArchiveTierDays
                    }
                }
            }
        }
    }
    
    $policy = [PSCustomObject]@{
        rules = @($rule)
    }
    
    # Convert to JSON and apply
    $policyJson = $policy | ConvertTo-Json -Depth 10
    
    Set-AzStorageAccountManagementPolicy `
        -ResourceGroupName $ResourceGroupName `
        -AccountName $StorageAccountName `
        -Rule $policyJson
    
    Write-Host "   Lifecycle Policy applied to container: $ContainerActive" -ForegroundColor Green
    Write-Host "   Rule: Move to Cool tier after $CoolTierDays days" -ForegroundColor Green
    Write-Host "   Rule: Move to Archive tier after $ArchiveTierDays days" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to configure lifecycle policy: $_"
    exit 1
}

# ============================================================================
# STEP 6: DISABLE PRIVATE ENDPOINT NETWORK POLICIES ON SUBNET
# ============================================================================

Write-Host "`n[6/8] Configuring Subnet for Private Endpoint..." -ForegroundColor Yellow

try {
    # Disable private endpoint network policies on the subnet
    $subnet.PrivateEndpointNetworkPolicies = "Disabled"
    $vnet | Set-AzVirtualNetwork | Out-Null
    
    Write-Host "   Private Endpoint network policies disabled on subnet" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to configure subnet: $_"
    exit 1
}

# ============================================================================
# STEP 7: CREATE PRIVATE ENDPOINT FOR BLOB SERVICE
# ============================================================================

Write-Host "`n[7/8] Creating Private Endpoint for Blob Service..." -ForegroundColor Yellow

try {
    # Create Private Link Service Connection
    $privateLinkConnection = New-AzPrivateLinkServiceConnection `
        -Name "$PrivateEndpointName-connection" `
        -PrivateLinkServiceId $storageAccount.Id `
        -GroupId "blob"
    
    # Create Private Endpoint
    $privateEndpoint = New-AzPrivateEndpoint `
        -ResourceGroupName $ResourceGroupName `
        -Name $PrivateEndpointName `
        -Location $Location `
        -Subnet $subnet `
        -PrivateLinkServiceConnection $privateLinkConnection `
        -Tag $Tags
    
    Write-Host "   Private Endpoint created: $PrivateEndpointName" -ForegroundColor Green
    Write-Host "   Service: Blob Storage (blob)" -ForegroundColor Green
    Write-Host "   Subnet: $SubnetName" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create private endpoint: $_"
    exit 1
}

# ============================================================================
# STEP 8: CONFIGURE PRIVATE DNS ZONE (Optional but Recommended)
# ============================================================================

Write-Host "`n[8/8] Configuring Private DNS Zone..." -ForegroundColor Yellow

try {
    # Check if Private DNS Zone exists
    $dnsZone = Get-AzPrivateDnsZone -ResourceGroupName $VNetResourceGroup -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue
    
    if (-not $dnsZone) {
        # Create Private DNS Zone
        $dnsZone = New-AzPrivateDnsZone `
            -ResourceGroupName $VNetResourceGroup `
            -Name $PrivateDnsZoneName `
            -Tag $Tags
        Write-Host "   Private DNS Zone created: $PrivateDnsZoneName" -ForegroundColor Green
    } else {
        Write-Host "   Private DNS Zone already exists: $PrivateDnsZoneName" -ForegroundColor DarkYellow
    }
    
    # Link DNS Zone to VNet
    $dnsLink = Get-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $VNetResourceGroup `
        -ZoneName $PrivateDnsZoneName `
        -Name "$VNetName-link" `
        -ErrorAction SilentlyContinue
    
    if (-not $dnsLink) {
        $dnsLink = New-AzPrivateDnsVirtualNetworkLink `
            -ResourceGroupName $VNetResourceGroup `
            -ZoneName $PrivateDnsZoneName `
            -Name "$VNetName-link" `
            -VirtualNetworkId $vnet.Id `
            -Tag $Tags
        Write-Host "   DNS Zone linked to VNet: $VNetName" -ForegroundColor Green
    } else {
        Write-Host "   DNS Zone already linked to VNet" -ForegroundColor DarkYellow
    }
    
    # Create DNS A record for storage account
    $privateEndpointIp = ($privateEndpoint.CustomDnsConfigs | Where-Object {$_.Fqdn -like "*blob.core.windows.net"}).IpAddresses[0]
    
    if ($privateEndpointIp) {
        New-AzPrivateDnsRecordSet `
            -ResourceGroupName $VNetResourceGroup `
            -ZoneName $PrivateDnsZoneName `
            -Name $StorageAccountName `
            -RecordType A `
            -Ttl 3600 `
            -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $privateEndpointIp) `
            -ErrorAction SilentlyContinue | Out-Null
        
        Write-Host "   DNS A record created: $StorageAccountName.$PrivateDnsZoneName -> $privateEndpointIp" -ForegroundColor Green
    }
    
} catch {
    Write-Warning "DNS configuration encountered non-critical errors: $_"
    Write-Host "   You may need to configure DNS manually" -ForegroundColor DarkYellow
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Resource Summary:" -ForegroundColor White
Write-Host "   Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "   Storage Account: $StorageAccountName (Standard_GRS)" -ForegroundColor Gray
Write-Host "   Containers: $ContainerActive, $ContainerArchive" -ForegroundColor Gray
Write-Host "   Private Endpoint: $PrivateEndpointName" -ForegroundColor Gray
Write-Host "   DNS Zone: $PrivateDnsZoneName" -ForegroundColor Gray

Write-Host "`nSecurity Features:" -ForegroundColor White
Write-Host "   Public Network Access: DISABLED" -ForegroundColor Green
Write-Host "   Blob Public Access: DISABLED" -ForegroundColor Green
Write-Host "   Private Endpoint: CONFIGURED" -ForegroundColor Green
Write-Host "   HTTPS Only: ENABLED" -ForegroundColor Green
Write-Host "   TLS 1.2+: ENFORCED" -ForegroundColor Green

Write-Host "`nCost Optimization:" -ForegroundColor White
Write-Host "   Lifecycle Policy: Cool tier @ $CoolTierDays days" -ForegroundColor Green
Write-Host "   Lifecycle Policy: Archive tier @ $ArchiveTierDays days" -ForegroundColor Green

Write-Host "`nCompliance:" -ForegroundColor White
Write-Host "   Tags Applied: Environment=Production, Project=Research, CostCenter=9876" -ForegroundColor Green
Write-Host "   GRS Replication: Enabled for DR" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor White
Write-Host "  1. Verify private endpoint connectivity from your VNet" -ForegroundColor Gray
Write-Host "  2. Configure RBAC roles for user access" -ForegroundColor Gray
Write-Host "  3. Upload files to $ContainerActive container" -ForegroundColor Gray
Write-Host "  4. Monitor lifecycle policy execution in Azure Portal" -ForegroundColor Gray

Write-Host "`n========================================`n" -ForegroundColor Cyan

# Export deployment information
$deploymentInfo = @{
    Timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ResourceGroup      = $ResourceGroupName
    StorageAccount     = $StorageAccountName
    Location           = $Location
    PrivateEndpoint    = $PrivateEndpointName
    ContainerActive    = $ContainerActive
    ContainerArchive   = $ContainerArchive
    CoolTierDays       = $CoolTierDays
    ArchiveTierDays    = $ArchiveTierDays
}

$deploymentInfo | ConvertTo-Json | Out-File "deployment-info-$StorageAccountName.json"
Write-Host "Deployment info saved to: deployment-info-$StorageAccountName.json`n" -ForegroundColor Green
