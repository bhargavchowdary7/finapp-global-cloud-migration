# FinApp Global Cloud Migration to Azure

##  Overview

This repository contains the complete infrastructure-as-code (Terraform), and migration scripts (PowerShell) for migrating FinApp's global financial services application to Microsoft Azure with strict **data sovereignty compliance** and **sub-50ms latency optimization** and provides two PowerShell scripts that implement a complete lifecycle for secure Azure Storage infrastructure:
1. **Storage_provisioner_automation.ps1** - Provisions all secured infrastructure components
2. **Cleanup-Resources.ps1** - Safely removes all provisioned resources
The solution implements **Zero Trust architecture** with private endpoints only, automated tiering policies, and comprehensive audit trails.

---

##  Key Requirements Implemented 

✅ **Data Sovereignty**: ZRS for transactional data, GRS for archival  
✅ **Private Endpoints**: All storage and database traffic over private network (no public internet)  
✅ **Lifecycle Management**: Automated data tiering (cool tier: 90 days, archive tier: 365 days)  
✅ **Latency Optimization**: PostgreSQL read replicas across availability zones (<50ms read latency)  
✅ **Security**: Azure Key Vault integration with managed identities  
✅ **Compliance**: Customer-managed encryption keys (CMK) for all data

---
##  Repository Structure

```
finapp-global-cloud-migration/
   └── infrastructure/
      ├── automation/
      │   ├── storage_provisioner_automation.ps1   
      │   └── cleanup-resources.ps1
      ├── pipelines/
      │   ├── infra-create.yml           # Azure DevOps pipeline for infrastructure creation
      │   ├── infra-destroy.yml          # Azure DevOps pipeline for infrastructure destruction
      │   └── templates/
      │       └── terraform.yml          # Reusable Terraform template
      │
      └── terraform/
          ├── main.tf                    # Root configuration
          ├── variables.tf               # Global variables
          ├── terraform.tfvars           # Environment-specific values
          ├── providers.tf               # Azure provider configuration
          ├── backend.tf                 # Terraform state backend configuration
          ├── outputs.tf                 # Root outputs
          │
          └── modules/
              ├── storage/               # Storage Accounts with Private Endpoints
              │   ├── main.tf
              │   ├── variables.tf
              │   └── outputs.tf
              │
              ├── database/              # PostgreSQL Flexible Server + Read Replicas
              │   ├── main.tf
              │   ├── variables.tf
              │   └── outputs.tf
              │
              └── monitoring/            # Azure Monitor and Log Analytics
                  ├── main.tf
                  ├── variables.tf
                  └── outputs.tf

```
---

## Azure Resources Deployed

### Use Case 1: Multi-Region Financial Application

#### Per-Region Resources (Deployed in 3 regions: East US 2, UK South, Southeast Asia)

"I selected these specific Azure regions based on their alignment with the requirements:

**Selected Regions:**

| Region | Purpose | Compliance |
|--------|---------|-----------|
| **East US 2** | North America (Primary) | SOX compliance |
| **UK South** | Europe | GDPR compliance |
| **Southeast Asia** | Singapore | MAS compliance |

> These regions support availability zones for zone-redundant high availability, meeting RTO < 1 hour requirements.

---

### Per-Region Resources (3 Regions)

| # | Resource | Configuration | Purpose |
|---|----------|--------------|---------|
| **1** | **Resource Group** | `rg-finapp-{region}-prod` | Logical container for regional resources, enables independent lifecycle management |
| **2** | **PostgreSQL Flexible Server** | SKU: GP_Standard_D16s_v3<br>Storage: 50TB Premium SSD<br>HA: Zone-Redundant | High-performance OLTP database (20K IOPS)<br>Sub-50ms latency, zone-level DR (RTO <1hr, RPO <5min) |
| **3** | **Storage Account (Transactional)** | Tier: Standard<br>Replication: ZRS<br>Public Access: Disabled | 100TB transaction logs with data sovereignty<br>99.9999999999% durability within region |
| **4** | **File Shares (Premium)** | `transaction-logs-share`: 50TB<br>`archive-logs-share`: 50TB<br>Protocol: SMB 3.0 | High-throughput shared storage<br>Legacy NAS migration path |
| **5** | **Blob Containers** | `dept-files-active`: Hot tier<br>`dept-files-archive`: Archive tier<br>Lifecycle: Cool@90d, Archive@365d | Cost-optimized long-term retention<br>Automated tiering |
| **6** | **Private Endpoints** | 4 per region:<br>• Blob Storage<br>• File Storage<br>• PostgreSQL<br>• Key Vault | Zero public internet exposure<br>All traffic over private Azure backbone |
| **7** | **Private DNS Zones** | • privatelink.postgres.database.azure.com<br>• privatelink.blob.core.windows.net<br>• privatelink.file.core.windows.net | Automatic DNS resolution for private endpoints |
| **8** | **Azure Key Vault** | SKU: Standard<br>Secrets: DB passwords, connection strings | Centralized secret management with audit logging |
| **9** | **Virtual Network** | Address: 10.{region-id}.0.0/19<br>Subnets: database, storage, app | Network isolation and private endpoint hosting |
| **10** | **Network Security Groups** | Database NSG: Port 5432<br>Storage NSG: Port 445, 443 | Layer 4 firewall rules (defense-in-depth) |

---

### Use Case 2: Department Files Archive 

| # | Resource | Configuration | Purpose |
|---|----------|--------------|---------|
| **11** | **Storage Account (Archive)** | Name: `rg-deptfiles-prod-001`<br>Tier: Standard GRS<br>Public Access: Disabled<br>Tags: Environment=Production, Project=Research, CostCenter=9876 | Departmental files with geo-replication for DR<br>(Different from financial data sovereignty) |
| **12** | **Private Endpoint (Archive)** | Service: Blob | Secure access from on-premises via VPN/ExpressRoute |

---

### Global Resources 

| # | Resource | Configuration | Purpose |
|---|----------|--------------|---------|
| **13** | **Azure Monitor & Log Analytics** | Retention: 90 days<br>Metrics: DB CPU, Storage IOPS, Replication lag | Centralized monitoring and alerting |
| **14** | **Application Insights** | APM enabled | Track API latency, transaction traces, dependencies |

---


##  Resource Selection Rationale

| Decision | Rationale |
|----------|-----------|
| **PostgreSQL over SQL Server** | • Strong JSON/JSONB support for trading data<br>• MVCC for high concurrency transaction processing<br>• Better cloud-native support<br>• Open-source, lower licensing costs |
| **ZRS over GRS (Main App)** | • Data sovereignty requirement: no cross-region replication<br>• 3-AZ redundancy sufficient for RTO < 1h, RPO < 5min<br>• GDPR, MAS, SOX compliance for regional data residency |
| **GRS for Department Archive** | • Non-sensitive data allows geo-replication<br>• Cost optimization through tiering (Cool/Archive)<br>• Disaster recovery without sovereignty constraints |
| **Private Endpoints Everywhere** | • Zero public internet access requirement<br>• All traffic traverses Azure private backbone<br>• Reduces attack surface for financial application |
| **Read Replicas (3 AZs)** | • Distributes read load across availability zones<br>• Achieves <50ms read latency target<br>• Automatic failover for high availability |

---

##  Cost Optimization Strategies

| Strategy | Implementation | Savings |
|----------|---------------|---------|
| **Storage Lifecycle Policies** | Auto-tier to Cool (90d) and Archive (365d) | Up to 89% for archived data |
| **Reserved Instances** | 3-year reserved capacity for database | Up to 65% savings |
| **ZRS over GRS** | Regional replication only (where compliant) | ~40% lower storage costs |
| **Right-sizing** | GP tier with Zone-Redundant HA (no BC tier) | Optimal performance/cost ratio |

**Example Cost Breakdown:**

| Storage Tier | Cost per TB/Month | Savings vs Hot Tier |
|--------------|-------------------|---------------------|
| **Hot Tier** | $18.40 | Baseline |
| **Cool Tier** | $10.00 | 46% savings |
| **Archive Tier** | $2.00 | 89% savings |

---

##  Compliance & Security

| Compliance Area | Implementation | Details |
|----------------|----------------|---------|
| **GDPR** | UK South region | No cross-border data transfer |
| **MAS** | Southeast Asia (Singapore) | Data residency compliance |
| **SOX** | East US 2 | Audit logging enabled |
| **Encryption (Transit)** | TLS 1.2+ | All connections HTTPS only |
| **Encryption (At-Rest)** | AES-256 | All storage and databases |
| **RBAC** | Azure AD integration | Least-privilege access model |
| **Network Security** | Private endpoints only | No public IPs, NSG rules enforced |

---

## Total Resource Count per Region

- Compute: 1 PostgreSQL Flexible Server (HA mode = 2 nodes)
- Storage: 2 Storage Accounts, 2 File Shares, 2 Blob Containers
- Network: 1 VNet, 3 Subnets, 4 Private Endpoints, 3 Private DNS Zones, 2 NSGs
- Security: 1 Key Vault
- Monitoring: 1 Log Analytics Workspace (shared)

**Total across 3 regions: 45+ Azure resources**

##  Architecture Overview


┌─────────────────────────────────────────────────────────────────┐
│                    Azure Region (East US 2)                     │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │              Virtual Network (VNet)                 │        │ 
│  │                                                     │        │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │        │
│  │  │ Subnet       │  │ Subnet       │  │ Subnet    │  │        │
│  │  │ (App)        │  │ (Database)   │  │ (Storage) │  │        │
│  │  │ AZ1, AZ2, AZ3│  │ AZ1, AZ2, AZ3│  │ Private   │  │        │
│  │  └──────────────┘  └──────────────┘  │ Endpoints │  │        |
│  │                                      └───────────┘  │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │     PostgreSQL Flexible Server (Primary - AZ1)      │        │
│  │     + Read Replica (AZ2) + Read Replica (AZ3)       │        │
│  │     ✓ Private Endpoint                              │        │
│  │     ✓ CMK Encryption                                │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │ Storage Account (ZRS for transactional data, GRS for archival)         
│  │     ✓ Blob Private Endpoint                         │        │
│  │     ✓ File Private Endpoint                         │        │
│  │     ✓ Lifecycle Management (Cool: 90d, Archive: 365d)│       │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │     Azure Key Vault                                 │        │
│  │     ✓ Database credentials                          │        │
│  │     ✓ Storage connection strings                    │        │
│  │     ✓ Customer-managed keys (CMK)                   │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘


---

# DR Architecture & Failover Plan

Comprehensive disaster recovery strategy meeting RTO < 1 hour and RPO < 5 minutes

## RTO (Recovery Time Objective) : < 1 Hour
- Zone-Redundant HA: Automatic failover in <120 seconds across availability zones
- Read Replicas: Standby databases in separate zones ready for immediate promotion

## RPO (Recovery Point Objective): < 5 Minutes
- Continuous WAL Backups: PostgreSQL Write-Ahead Logs replicated in <1 minute
- ZRS Storage: Synchronous replication across 3 availability zones

# Replication Mechanisms

1. ## Database Replication (PostgreSQL)
   ### Primary-Replica Architecture:
      - Primary database in Availability Zone 1
      - Synchronous read replica in Availability Zone 2 (hot standby)
      - Synchronous read replica in Availability Zone 3 (hot standby)
      - All replicas can serve read traffic, reducing primary load
      - Write-Ahead Log (WAL) Streaming:

    ### Continuous WAL streaming from primary to replicas
      - Replication lag typically <100ms within same region
      - Automatic log archival to Azure Blob Storage (ZRS)

    ### Automated Backups:
      - Daily full backups retained for 7-35 days (configurable)
      - Transaction log backups every 5 minutes
      - Backup storage uses Zone-Redundant Storage (ZRS)

2. ## Storage Replication (Azure Storage)
    ### Zone-Redundant Storage (ZRS) for Financial Data:    
       - Data synchronously replicated across 3 availability zones
       - No cross-region replication (maintains data sovereignty)
       - Protects against datacenter-level failures
       - RPO effectively 0 seconds (synchronous replication)

    ### Geo-Redundant Storage (GRS) for Department Files:  
      - Asynchronous replication to paired region (300+ miles away)
      - Only for non-regulated department archive files
      - RPO typically <15 minutes for cross-region replication

3. ## Network Redundancy
      - Private endpoints deployed across multiple availability zones
      - Multiple Private DNS zones for automatic failover
      - Virtual network peering with redundant paths

# Failover Procedures

 ## Scenario 1: Single Availability Zone Failure:
 
 **Trigger:** Zone-level outage detected (compute, networking, or power failure)
 ### Automatic Actions (0-120 seconds):
   1. Azure health checks detect primary database unavailability
   2. Zone-Redundant HA automatically promotes replica in healthy zone
   3. Private endpoint DNS records updated to new primary IP
   4. Application connections automatically re-establish to new primary
   5. Expected Downtime: <120 seconds

**Data Loss:** None (synchronous replication)

## Scenario 2 Complete Regional Outage: 

**trigger:** All availability zones in a region become unavailable
### Manual Failover Procedure (15-45 minutes):
   1. Declare Disaster (0-5 min): Operations team confirms regional outage
   2. Execute DR Runbook (5-15 min):
      - Restore latest database backup in alternate region (North America → Europe or Asia)
      - Restore Point-in-Time to latest available transaction log
      - Deploy application tier to alternate region using Infrastructure-as-Code
   3. DNS Failover (15-20 min): Update Traffic Manager to route to alternate region
   4. Validation (20-35 min): Run DR validation scripts, verify data integrity
   5. Resume Operations (35-45 min): Notify users, monitor performance
**Expected Downtime:** 45-60 minutes (well within RTO <1h)
**Data Loss:** <5 minutes of transactions (RPO met)

### Data Sovereignty Note:
Regional failover violates data sovereignty requirements. In practice, North America data would NEVER failover to Europe/Asia. Instead:
 - Restore from backups within the same region when recovered
 - Accept extended downtime if all zones fail (rare Azure SLA event)
 - Regional disasters are covered by Azure's 99.99% multi-zone SLA

 ## Scenario 3 Data Corruption / Logical Failure

 **Trigger:** Application bug, malicious activity, or accidental data deletion
### Point-in-Time Recovery (10-30 minutes):
   1. Identify timestamp of corruption event
   2. Initiate Point-in-Time Restore to moment before corruption
   3. Restore to new PostgreSQL instance (preserves original for forensics)
   4. Validate restored data, switch application connection strings
   5. Expected Downtime: 10-30 minutes

**Data Loss:** None (restores to exact point in time)

----

##  Infrastructure Scripts (Terraform)

### `infrastructure/terraform/main.tf`

**Purpose**: Root Terraform configuration that orchestrates all Azure resources

**Key Features**:
- Provisions Virtual Network with 3 subnets (App, Database, Storage)
- Creates Storage Account with ZRS replication
- Deploys PostgreSQL Flexible Server with read replicas
- Configures Private Endpoints for storage (blob + file) and database
- Sets up Azure Key Vault with managed identity
- Implements lifecycle management for blob storage

**Critical Configurations**:

## Lifecycle Management 
lifecycle_cool_tier_days    = 90   # Move to Cool tier after 90 days
lifecycle_archive_tier_days = 365  # Move to Archive tier after 365 days

## Storage Replication
 ZRS for transactional data (Data Sovereignty)
 GRS for archival data (File Share Archiving use case)
storage_replication_type_transactional = "ZRS"
storage_replication_type_archival      = "GRS" 

## Read Replicas for Latency Optimization
- Primary DB: Availability Zone 1
- Read Replica 1: Availability Zone 2
- Read Replica 2: Availability Zone 3

---

### `infrastructure/terraform/modules/storage/main.tf`

**Purpose**: Storage Account module with private endpoints

**What It Does**:
 Creates Storage Account with ZRS replication (transactional data)
- Creates Storage Account with GRS replication 
- Configures blob and file services
- Creates Private Endpoints for blob and file 
- Sets up Private DNS zones for name resolution ( Public Access: Disabled )
- Implements lifecycle management policy ( cool: 90 days, archive: 365 days) 
- Enables blob versioning and soft delete
- Creates containers: `dept-files-active`, `dept-files-archive`
- Applies tags: ** Environment=Production, Project=Research, CostCenter=9876**

**Data Sovereignty Compliance**: ✅ ZRS ensures data never leaves the region

---

### `infrastructure/terraform/modules/database/main.tf`

**Purpose**: PostgreSQL Flexible Server with high availability

**What It Does**:
- Deploys PostgreSQL Flexible Server (Primary) in AZ1
- Creates Read Replica in AZ2
- Creates Read Replica in AZ3
- Configures Private Endpoint for secure access
- Integrates with Key Vault for credentials
- Enables CMK encryption

**Latency Optimization**: ✅ Read replicas across 3 AZs provide <50ms read latency

**Read Replica Configuration**: Creates 2 additional read replicas for load distribution

---

### `infrastructure/terraform/modules/network/main.tf`

**Purpose**: Network infrastructure with security controls

**What It Does**:
- Creates Virtual Network (VNet)
- Provisions 3 subnets with service endpoints
- Configures Network Security Groups (NSGs)
- Enables subnet delegation for PostgreSQL
- Sets up Private Endpoint subnet

---

### `infrastructure/terraform/modules/keyvault/main.tf`

**Purpose**: Azure Key Vault for secrets management

**What It Does**:
- Creates Key Vault with soft delete and purge protection
- Stores database credentials
- Stores storage connection strings
- Manages customer-managed encryption keys (CMK)
- Configures RBAC access policies

---


##  Migration Scripts (PowerShell)

### Database Migration Scripts

#### `migration/database-migration/Database-Migration-WithKeyVault.ps1`

**Purpose**: Secure database migration using Azure Key Vault credentials

**What It Does**:
1. Retrieves source database credentials from Key Vault
2. Retrieves target Azure PostgreSQL credentials from Key Vault
3. Performs pg_dump from source database
4. Restores data to Azure PostgreSQL Flexible Server
5. Validates data integrity post-migration
6. Logs all operations with timestamps

**Key Features**:
- Zero credentials in code (all from Key Vault)
- Transaction log handling
- Error handling and rollback
- Progress monitoring

**Usage**:
```powershell
.\Database-Migration-WithKeyVault.ps1 `
    -KeyVaultName "kv-migration-eastus2-abc123" `
    -SourceDbSecretName "source-db-connection" `
    -TargetDbSecretName "azure-postgresql-connection" `
    -DatabaseName "finapp_production"

```
---

## Migration Scripts (PowerShell)

### Database Migration Scripts

#### `migration/database-migration/Start-SecureDatabaseMigration.ps1`

**Purpose**: Orchestrator script for database migration process

**What It Does**:
1. Pre-migration validation (network, Key Vault access, disk space)
2. Creates backup of source database
3. Uploads backup to Azure Blob Storage (via Private Endpoint)
4. Initiates database restore to Azure PostgreSQL
5. Runs post-migration validation tests
6. Generates migration report

**Key Features**:
- Automated rollback on failure
- Email notifications
- Detailed logging
- Health checks

---

#### Database Migration Helper Scripts

The `migration/database-migration/Scripts/` folder contains modular helper scripts:

- **Get-MigrationSecrets.ps1**: Retrieves database credentials from Azure Key Vault securely
- **Invoke-DatabaseAssessment.ps1**: Performs pre-migration assessment (compatibility checks, size estimation)
- **Invoke-SchemaMigration.ps1**: Migrates database schema (tables, indexes, constraints)
- **Invoke-DataMigrationBatch.ps1**: Migrates data in batches for large tables
- **Invoke-DataValidation.ps1**: Validates data integrity post-migration (row counts, checksums)
- **Test-KeyVaultSecrets.ps1**: Tests Key Vault connectivity and secret accessibility
- **Update-ApplicationConfig.ps1**: Updates application connection strings post-migration

---

### Storage Migration Scripts

#### `migration/storage-migration/Start-SecureStorageMigration.ps1`

**Purpose**: Orchestrator for storage migration from NAS to Azure Storage

**What It Does**:
1. Connects to NAS share using secure credentials
2. Retrieves Azure Storage connection string from Key Vault
3. Uses AzCopy to transfer files to Azure Blob Storage
4. Validates file integrity (checksums)
5. Tracks migration progress and failures
6. Generates migration report

**Key Features**:
- Parallel file transfers
- Resume capability for failed transfers
- Bandwidth throttling
- Detailed error logs

**Usage**:
```powershell
.\Start-SecureStorageMigration.ps1 `
    -KeyVaultName "kv-migration-eastus2-abc123" `
    -NasPath "\\nas-server\transaction-logs" `
    -StorageAccountName "stfinappeastus2abc123" `
    -ContainerName "transaction-logs"

```
---
### Storage Migration

#### `migration/storage-migration/Storage-Migration-ByVolume.ps1`

**Purpose**: Volume-based storage migration with granular control

**What It Does**:
1. Scans source NAS volume/share
2. Creates corresponding container in Azure Storage
3. Migrates files using AzCopy with retry logic
4. Validates each file post-migration
5. Updates migration status tracking
6. Handles large files (>100GB) specially

**Key Features**:
- Volume-level parallel processing
- Incremental migration support
- Large file optimization
- Detailed progress tracking

---

#### Storage Migration Helper Scripts

The `migration/storage-migration/Scripts/` folder contains modular helper scripts:

- **Get-VolumeConfigurations.ps1**: Retrieves volume configurations from JSON file
- **Apply-VolumeFilters.ps1**: Applies filtering rules (file types, sizes, dates)
- **Test-VolumeAccessibility.ps1**: Tests source NAS volume accessibility
- **Initialize-AzureFileSync.ps1**: Sets up Azure File Sync for hybrid scenarios
- **Invoke-AzCopyMigration.ps1**: Uses AzCopy for high-performance file transfers
- **Invoke-DataBoxMigration.ps1**: Handles large-scale migrations (>40TB) via Azure Data Box
- **Invoke-SingleVolumeMigration.ps1**: Migrates a single volume/share
- **Invoke-StorageValidation.ps1**: Validates file integrity post-migration (checksums, metadata)
- **New-MigrationPlan.ps1**: Generates migration plan with timeline and resource estimates
- **New-MigrationReport.ps1**: Generates detailed migration report
- **New-MigrationDashboard.ps1**: Creates HTML dashboard for migration tracking
- **Show-VolumeSelection.ps1**: Interactive volume selection UI
- **Start-VolumeMigrations.ps1**: Orchestrates parallel volume migrations
- **New-VolumeConfiguration.ps1**: Creates new volume configuration

---

## Azure DevOps Pipeline Configuration

### Where to Add Azure DevOps Variables

Azure DevOps variables are **NOT** added in code files - they're configured in the **Azure DevOps Portal**.

#### Location in Azure DevOps Portal:
```
Azure DevOps → Your Project → Pipelines → Library → Variable groups
```

---

### Variable Groups Setup

#### **Group 1: `migration-config-production`** (Non-sensitive configuration)

| Variable Name | Example Value | Description |
|--------------|---------------|-------------|
| `KEY_VAULT_NAME` | `kv-migration-eastus2-abc123` | Azure Key Vault name for storing secrets |
| `RESOURCE_GROUP` | `rg-finapp-north-america-production` | Azure Resource Group for all resources |
| `PRIMARY_REGION` | `East US 2` | Primary Azure region (data sovereignty boundary) |
| `NAS_PATH` | `\\nas-server\transaction-logs` | Source NAS share path for file migration |
| `STORAGE_ACCOUNT_NAME` | `stfinappeastus2abc123` | Target Azure Storage Account name |
| `MIGRATION_SCRIPTS_STORAGE` | `stmigrationseastus2xyz456` | Storage account for migration logs/scripts |
| `VNET_NAME` | `vnet-finapp-eastus2-prod` | Virtual Network name |
| `SUBNET_APP_NAME` | `subnet-app-eastus2` | Application subnet name |
| `SUBNET_DB_NAME` | `subnet-database-eastus2` | Database subnet name |
| `SUBNET_STORAGE_NAME` | `subnet-storage-eastus2` | Storage private endpoint subnet name |
| `POSTGRESQL_SERVER_NAME` | `psql-finapp-eastus2-prod` | PostgreSQL Flexible Server name |
| `POSTGRESQL_DATABASE_NAME` | `finapp_production` | Database name for migration |
| `SOURCE_DB_HOST` | `onprem-db-server.company.local` | Source database hostname |
| `SOURCE_DB_PORT` | `5432` | Source database port |
| `AZURE_SUBSCRIPTION_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Azure Subscription ID |
| `TERRAFORM_STATE_STORAGE` | `sttfstateeastus2xyz789` | Storage account for Terraform state files |
| `TERRAFORM_STATE_CONTAINER` | `tfstate` | Container name for Terraform state |
| `AZURE_TENANT_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Azure AD Tenant ID |
| `MIGRATION_BATCH_SIZE` | `10000` | Number of rows per batch for data migration |
| `AZCOPY_CONCURRENCY` | `16` | Number of concurrent AzCopy transfers |
| `VOLUME_CONFIG_PATH` | `migration/configs/volume-configs.json` | Path to volume configuration file |
| `LOG_ANALYTICS_WORKSPACE_NAME` | `law-finapp-eastus2-prod` | Log Analytics workspace for monitoring |
| **`COOL_TIER_DAYS`** | **`90`** | **📋 Days before moving to Cool storage tier ** |
| **`ARCHIVE_TIER_DAYS`** | **`365`** | **📋 Days before moving to Archive storage tier ** |

---

#### **Group 2: `migration-secrets`** (Sensitive - Link to Key Vault)

**IMPORTANT**: Enable "**Link secrets from an Azure key vault as variables**" and select your Key Vault

| Variable Name | Description |
|--------------|-------------|
| `AZURE_CLIENT_ID` | Service Principal Client ID for automation |
| `AZURE_CLIENT_SECRET` | Service Principal Client Secret |
| `NAS_USERNAME` | NAS share username |
| `NAS_PASSWORD` | NAS share password |
| `SOURCE_DB_USERNAME` | Source database admin username |
| `SOURCE_DB_PASSWORD` | Source database admin password |
| `POSTGRESQL_ADMIN_PASSWORD` | Azure PostgreSQL admin password |

**Best Practice**: All secrets above should be stored in Azure Key Vault and referenced via Key Vault-linked variables in Azure DevOps. Pipeline variables should only contain Key Vault secret names, not actual credentials.

---

### How to Use Variable Groups in Azure Pipelines

Add the variable groups at the **top of your pipeline YAML file** using the `variables` section:

#### **Example 1: Infrastructure Pipeline** (`infrastructure/pipelines/infra-create.yml`)

```yaml
# infrastructure/pipelines/infra-create.yml

trigger:
  branches:
    include:
      - main
      - develop

# ADD VARIABLE GROUPS HERE
variables:
  - group: migration-config-production
  - group: migration-secrets

```
---

###  Steps to Configure Variable Groups in Azure DevOps

1. **Navigate to Variable Groups**:
   ```
   Azure DevOps → Your Project → Pipelines → Library
   ```

2. **Create Variable Group 1** (`migration-config-production`):
   - Click **+ Variable group**
   - Name: `migration-config-production`
   - Add all non-sensitive variables listed above
   - Click **Save**

3. **Create Variable Group 2** (`migration-secrets`):
   - Click **+ Variable group**
   - Name: `migration-secrets`
   - Enable **Link secrets from an Azure key vault as variables**
   - Select your Azure Subscription
   - Select your Key Vault name (e.g., `kv-migration-eastus2-abc123`)
   - Click **Authorize** if prompted
   - Add variables by selecting secrets from Key Vault:
     - `AZURE_CLIENT_ID`
     - `AZURE_CLIENT_SECRET`
     - `NAS_USERNAME`
     - `NAS_PASSWORD`
     - `SOURCE_DB_USERNAME`
     - `SOURCE_DB_PASSWORD`
     - `POSTGRESQL_ADMIN_PASSWORD`
   - Click **Save**

4. **Use Variable Groups in Pipelines**:
   - Add the following at the top of your pipeline YAML:
     ```yaml
     variables:
       - group: migration-config-production
       - group: migration-secrets
     ```
---
## Deployment Instructions

### 1. Infrastructure Deployment (Terraform)

```bash
# Navigate to Terraform directory
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment (review changes)
terraform plan -var-file="terraform.tfvars"

# Apply infrastructure
cd infrastructure/terraform
terraform init
terraform apply -var-file="terraform.tfvars" -auto-approve


### 2. Database Migration

# Navigate to migration directory
cd migration

# Run database migration
.\Start-SecureDatabaseMigration.ps1 `
    -KeyVaultName "kv-migration-eastus2-abc123" `
    -ResourceGroup "rg-finapp-north-america-production" `
    -Region "East US 2"


### 3. Storage Migration

# Run storage migration
.\Start-SecureStorageMigration.ps1 `
    -KeyVaultName "kv-migration-eastus2-abc123" `
    -NasPath "\\nas-server\transaction-logs" `
    -StorageAccountName "stfinappeastus2abc123"

---

##  Key Metrics & Compliance

| Requirement | Implementation | Status |
|------------|----------------|--------|
| **Data Sovereignty** | ZRS (transactional), GRS (archival ) | ✅ Compliant |
| **Network Security** | Private Endpoints (no public internet) | ✅ Compliant |
| **Latency Target** | <50ms reads via 3 read replicas | ✅ Compliant |
| **Encryption** | CMK + TLS 1.2+ for all data | ✅ Compliant |
| **Lifecycle Management** | Cool (90d) + Archive (365d) | ✅ Compliant |
| **High Availability** | Multi-AZ deployment (99.95% SLA) | ✅ Compliant |
| **DR Requirements** | 📋 RTO < 1 hour, RPO < 5 minutes | ✅ Compliant |  

---

## Important Notes

| Topic | Details |
|-------|---------|
| **Data Sovereignty** | `terraform.tfvars` uses **ZRS** for transactional storage<br>**GRS** for File Share Archiving use case only |
| **Private Endpoints** | All database/storage traffic flows through private endpoints<br>Ensure NSG rules allow traffic from application subnets |
| **Read Replicas** | Database module creates 2 read replicas (AZ2, AZ3) automatically<br>Application should use read replicas for SELECT queries (<50ms latency) |
| **Key Vault Access** | Service Principal needs `Key Vault Secrets User` role |
| **Migration Validation** | Always run validation tests post-migration:<br>`Invoke-DataValidation.ps1`<br>`Invoke-StorageValidation.ps1` |
| **Lifecycle Policy** | Configured for Cool tier @ 90 days, Archive @ 365 days<br>Defined in `modules/storage/main.tf` |

---

##  Complete Repository Structure

```
finapp-global-cloud-migration/
│
├── infrastructure/
|   ├── automation/
|   │   ├── storage_provisioner_automation.ps1   
|   │   └── cleanup-resources.ps1
│   ├── pipelines/
│   │   ├── infra-create.yml           # Azure DevOps pipeline for infrastructure creation
│   │   ├── infra-destroy.yml          # Azure DevOps pipeline for infrastructure destruction
│   │   └── templates/
│   │       └── terraform.yml          # Reusable Terraform template
│   │
│   └── terraform/
│       ├── main.tf                    # Root configuration
│       ├── variables.tf               # Global variables
│       ├── terraform.tfvars           # Environment-specific values
│       ├── providers.tf               # Azure provider configuration
│       ├── backend.tf                 # Terraform state backend configuration
│       ├── outputs.tf                 # Root outputs
│       │
│       └── modules/
│           ├── storage/               # Storage Accounts with Private Endpoints
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   └── outputs.tf
│           │
│           ├── database/              # PostgreSQL Flexible Server + Read Replicas
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   └── outputs.tf
│           │
│           └── monitoring/            # Azure Monitor and Log Analytics
│               ├── main.tf
│               ├── variables.tf
│               └── outputs.tf
│
└── migration/
    ├── configs/
    │   └── volume-configs.json        # Volume migration configurations
    │
    ├── database-migration/
    │   ├── Database-Migration-WithKeyVault.ps1  # Secure DB migration with Key Vault
    │   ├── Start-SecureDatabaseMigration.ps1    # Database migration orchestrator
    │   └── Scripts/
    │       ├── Get-MigrationSecrets.ps1         # Retrieve secrets from Key Vault
    │       ├── Invoke-DataMigrationBatch.ps1    # Batch data migration
    │       ├── Invoke-DataValidation.ps1        # Post-migration data validation
    │       ├── Invoke-DatabaseAssessment.ps1    # Pre-migration database assessment
    │       ├── Invoke-SchemaMigration.ps1       # Schema migration
    │       ├── Invoke-SecureDatabaseMigration.ps1 # Secure database migration
    │       ├── Test-KeyVaultSecrets.ps1         # Validate Key Vault access
    │       └── Update-ApplicationConfig.ps1     # Update application configuration
    │
    ├── storage-migration/
    │   ├── Start-SecureStorageMigration.ps1     # Storage migration orchestrator
    │   ├── Storage-Migration-ByVolume.ps1       # Volume-based storage migration
    │   └── Scripts/
    │       ├── Apply-VolumeFilters.ps1          # Apply volume filtering rules
    │       ├── Get-VolumeConfigurations.ps1     # Retrieve volume configurations
    │       ├── Initialize-AzureFileSync.ps1     # Initialize Azure File Sync
    │       ├── Invoke-AzCopyMigration.ps1       # AzCopy-based migration
    │       ├── Invoke-DataBoxMigration.ps1      # Azure Data Box migration
    │       ├── Invoke-SingleVolumeMigration.ps1 # Single volume migration
    │       ├── Invoke-StorageValidation.ps1     # Post-migration storage validation
    │       ├── New-MigrationDashboard.ps1       # Generate migration dashboard
    │       ├── New-MigrationPlan.ps1            # Generate migration plan
    │       ├── New-MigrationReport.ps1          # Generate migration report
    │       ├── New-VolumeConfiguration.ps1      # Create volume configuration
    │       ├── Show-VolumeSelection.ps1         # Interactive volume selection
    │       ├── Start-VolumeMigrations.ps1       # Start volume migrations
    │       └── Test-VolumeAccessibility.ps1     # Test volume accessibility
    │
    ├── pipelines/
    │   ├── azure-pipelines-database-migration.yml  # Database migration pipeline
    │   ├── azure-pipelines-storage-migration.yml   # Storage migration pipeline
    │   └── templates/
    │       ├── powershell-steps.yml              # Reusable PowerShell steps
    │       └── terraform-steps.yml               # Reusable Terraform steps
    │
    └── terraform/
        ├── main.tf                    # Migration infrastructure (temp VMs, etc.)
        ├── variables.tf               # Migration-specific variables
        ├── terraform.tfvars           # Migration environment values
        ├── providers.tf               # Azure provider configuration
        ├── backend.tf                 # Terraform state backend
        └── outputs.tf                 # Migration infrastructure outputs
```

---


##  References

- [Azure PostgreSQL Flexible Server Documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Azure Storage Private Endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

```
---
