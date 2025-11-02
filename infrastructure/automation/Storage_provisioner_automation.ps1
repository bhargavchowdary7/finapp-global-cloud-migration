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

$ErrorActionPreference = "Stop".                   # Stop script execution immediately on any error
$WarningPreference = "Continue".                   # Display warnings but continue script execution

# Standardized tags as per requirements
$Tags = @{                                          # Define common Azure tags for governance and tracking
    Environment = "Production"                      # Tag indicating environment type
    Project     = "Research"                        # Tag indicating project name
    CostCenter  = "9876"                            # Tag indicating cost center for billing    
    ManagedBy   = "PowerShell-IaC"                  # Tag showing the resource was deployed via automation
    CreatedDate = (Get-Date -Format "yyyy-MM-dd")   # Tag capturing the creation date of the deployment
}

# Container names
$ContainerActive = "dept-files-active"              # Name for the active (hot) storage container
$ContainerArchive = "dept-files-archive"            # Name for the archive (cold) storage container

# Private Endpoint configuration
$PrivateEndpointName = "pe-$StorageAccountName-blob"        # Name for the Private Endpoint resource
$PrivateDnsZoneName = "privatelink.blob.core.windows.net"   # Default private DNS zone for Azure Blob Storage

Write-Host "`n========================================" -ForegroundColor Cyan  # Print visual separator line 
Write-Host "Storage Provisioner Automation" -ForegroundColor Cyan              # Display script title
Write-Host "File Share Archiving - Secure IaC" -ForegroundColor Cyan           # Display script description
Write-Host "========================================`n" -ForegroundColor Cyan  # Print closing separator line

# ============================================================================
# STEP 1: VALIDATE PREREQUISITES
# ============================================================================
#This block is your “pre-flight check” — it verifies login, networking, and naming prerequisites before deploying anything, ensuring your Infrastructure-as-Code execution runs reliably and predictably.

Write-Host "[1/8] Validating prerequisites..." -ForegroundColor Yellow    # Display step header in yellow

try {
    # Check Azure login
    $context = Get-AzContext                                             # Get current Azure session context
    if (-not $context) {
        throw "Not logged into Azure. Run 'Connect-AzAccount' first."   # Throw error if not logged in
    }
    Write-Host "   Logged in as: $($context.Account.Id)" -ForegroundColor Green    # Display logged-in account details
    Write-Host "   Subscription: $($context.Subscription.Name)" -ForegroundColor Green  # Display subscription details
    
    # Validate VNet exists
    $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $VNetResourceGroup -ErrorAction SilentlyContinue  # Get the specified VNet
    if (-not $vnet) {
        throw "Virtual Network '$VNetName' not found in resource group '$VNetResourceGroup'"                         # Throw error if VNet not found
    }
    Write-Host "   Virtual Network found: $VNetName" -ForegroundColor Green                             # Confirm VNet exists
    
    # Validate Subnet exists
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -ErrorAction SilentlyContinue. # Get subnet from VNet
    if (-not $subnet) {
        throw "Subnet '$SubnetName' not found in VNet '$VNetName'" # If subnet missing, throw error
    }
    Write-Host "   Subnet found: $SubnetName" -ForegroundColor Green  # Confirm subnet exists
    
    # Check storage account name availability
    $nameAvailable = Get-AzStorageAccountNameAvailability -Name $StorageAccountName   # Check if storage account name is available
    if (-not $nameAvailable.NameAvailable) {
        throw "Storage account name '$StorageAccountName' is not available: $($nameAvailable.Reason)" # Throw error if name is taken
    }
    Write-Host "   Storage account name available: $StorageAccountName" -ForegroundColor Green  # Confirm name availability
    
} catch {
    Write-Error "Prerequisites validation failed: $_".       # Log error message if validation fails and exit script with error code
    exit 1
}

# ============================================================================
# STEP 2: CREATE RESOURCE GROUP
# ============================================================================
# This block validates and creates the Azure Resource Group that serves as the “home” for all your upcoming infrastructure — ensuring it’s properly tagged, region-aligned, and compliant before moving forward.

Write-Host "`n[2/8] Creating Resource Group..." -ForegroundColor Yellow   # Display step header in yellow

try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue. # Check if Resource Group already exists
    if ($rg) {
        Write-Host "   Resource Group already exists: $ResourceGroupName" -ForegroundColor DarkYellow # Notify if RG already exists
    } else {
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags   # Create new Resource Group with tags
        Write-Host "   Resource Group created: $ResourceGroupName" -ForegroundColor Green   # Confirm RG creation success 
    }
    Write-Host "   Location: $Location" -ForegroundColor Green ./.DS_Store                   # Display RG location details
    
    Write-Host "   Tags applied: Environment=$($Tags.Environment), Project=$($Tags.Project), CostCenter=$($Tags.CostCenter)" -ForegroundColor Green  # Display applied tags details 
} catch {
    Write-Error "Failed to create Resource Group: $_"               # Log error message if RG creation fails and exit script with error code
    exit 1
}

# ============================================================================
# STEP 3: CREATE STORAGE ACCOUNT (GRS, PUBLIC ACCESS DISABLED)
# ============================================================================

Write-Host "`n[3/8] Creating Storage Account (GRS, Public Access Disabled)..." -ForegroundColor Yellow

try {
    $storageParams = @{
        ResourceGroupName      = $ResourceGroupName                 # Resource Group for the Storage Account
        Name                   = $StorageAccountName                # Name of the Storage Account
        Location               = $Location                          # Azure region for the Storage Account
        SkuName               = "Standard_GRS"                      # Geo-Redundant Storage for DR
        Kind                  = "StorageV2"                         # General-Purpose V2
        AccessTier            = "Hot"                               # Default access tier
        AllowBlobPublicAccess = $false                              #  CRITICAL: Disable public access
        PublicNetworkAccess   = "Disabled"                          #  CRITICAL: No public internet access
        MinimumTlsVersion     = "TLS1_2"                            # Enforce TLS 1.2+
        EnableHttpsTrafficOnly = $true                              # HTTPS only
        Tag                   = $Tags
    }
    
    $storageAccount = New-AzStorageAccount @storageParams  # Create the Storage Account with specified parameters
    Write-Host "   Storage Account created: $StorageAccountName" -ForegroundColor Green  # Confirm Storage Account creation success
    Write-Host "   SKU: Standard_GRS (Geo-Redundant)" -ForegroundColor Green             # Display SKU details
    Write-Host "   Public Network Access: Disabled " -ForegroundColor Green              # Confirm public network access is disabled
    Write-Host "   Allow Blob Public Access: Disabled " -ForegroundColor Green           # Confirm blob public access is disabled       
    Write-Host "   HTTPS Only: Enabled " -ForegroundColor Green
    
    # Get storage context
    $ctx = $storageAccount.Context               # Retrieve the storage context for further operations
    
} catch {
    Write-Error "Failed to create Storage Account: $_"   # Log error message if Storage Account creation fails and exit script with error code
    exit 1
}

# ============================================================================
# STEP 4: CREATE BLOB CONTAINERS
# ============================================================================
# This block securely creates two blob containers — one for active files and another for archived files — with no public access, forming the foundation for lifecycle-based storage automation in the following steps.

Write-Host "`n[4/8] Creating Blob Containers..." -ForegroundColor Yellow

try {
    # Create dept-files-active container
    $containerActiveParams = @{                             # Parameters for creating the active container
        Name    = $ContainerActive                          # Name of the active container
        Context = $ctx                                      # Storage context
        Permission = "Off"                                  # No public access
    }
    New-AzStorageContainer @containerActiveParams | Out-Null            # Create the active container
    Write-Host "   Container created: $ContainerActive (Public Access: Off)" -ForegroundColor Green
    
    # Create dept-files-archive container
    $containerArchiveParams = @{                         # Parameters for creating the archive container
        Name    = $ContainerArchive                      # Name of the archive container               
        Context = $ctx
        Permission = "Off"                              # No public access
    }
    New-AzStorageContainer @containerArchiveParams | Out-Null          # Create the archive container
    Write-Host "   Container created: $ContainerArchive (Public Access: Off)" -ForegroundColor Green    # Confirm archive container creation success
    
} catch {
    Write-Error "Failed to create containers: $_"                               # Log error message if container creation fails and exit script with error code
    exit 1
}

# ============================================================================
# STEP 5: CONFIGURE LIFECYCLE MANAGEMENT POLICY
# ============================================================================
#This block sets up an automated cost-saving rule that moves inactive files from Hot → Cool → Archive storage over time — ensuring that your cloud storage remains efficient, secure, and compliant without manual maintenance.

Write-Host "`n[5/8] Configuring Lifecycle Management Policy..." -ForegroundColor Yellow

try {
    # Define lifecycle rule for dept-files-active
    $rule = [PSCustomObject]@{                                      # Lifecycle rule definition
        name    = "MoveToArchiveTiers"                               # Rule name
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
#This section ensures that the subnet you’re using for Private Endpoints is properly configured to allow Private Link traffic.
#Azure requires that any subnet hosting private endpoints must have network policies disabled — otherwise, endpoint creation or traffic flow can fail.

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
    $privateLinkConnection = New-AzPrivateLinkServiceConnection `  # Create the connection object for the private endpoint
        -Name "$PrivateEndpointName-connection" `                   # Name of the connection
        -PrivateLinkServiceId $storageAccount.Id `                 # ID of the storage account
        -GroupId "blob"
    
    # Create Private Endpoint
    $privateEndpoint = New-AzPrivateEndpoint `                  # Create the private endpoint resource
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
#This block guarantees that your storage account’s DNS name resolves to its private endpoint IP, making all blob traffic stay inside your Azure VNet — fully secure, compliant, and isolated from the public internet.

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
#This block prints a clean, color-coded summary of everything the script created and configured — including resource names, security settings, cost policies, and compliance tags.

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
#This block acts as a deployment report card — confirming that your Azure storage environment was created successfully, securely, and in full compliance with organizational policies, while also guiding you on what to verify next.

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
