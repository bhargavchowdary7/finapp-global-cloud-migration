# FinApp Global Cloud Migration to Azure

##  Overview

This repository contains the complete infrastructure-as-code (Terraform) and migration scripts (PowerShell) for migrating FinApp's global financial services application to Microsoft Azure with strict **data sovereignty compliance** and **sub-50ms latency optimization**.

---

##  Key Requirements Implemented 

✅ **Data Sovereignty**: Zone-Redundant Storage (ZRS) - data stays within region boundaries  
✅ **Private Endpoints**: All storage and database traffic over private network (no public internet)  
✅ **Lifecycle Management**: Automated data tiering (cool tier: 90 days, archive tier: 365 days)  
✅ **Latency Optimization**: PostgreSQL read replicas across availability zones (<50ms read latency)  
✅ **Security**: Azure Key Vault integration with managed identities  
✅ **Compliance**: Customer-managed encryption keys (CMK) for all data

---

##  Repository Structure

```
finapp-global-cloud-migration/
│
├── infrastructure/
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

##  Architecture Overview


┌─────────────────────────────────────────────────────────────┐
│                    Azure Region (East US 2)                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Virtual Network (VNet)                 │    │
│  │                                                     │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │    │
│  │  │ Subnet       │  │ Subnet       │  │ Subnet    │  │    │
│  │  │ (App)        │  │ (Database)   │  │ (Storage) │  │    │
│  │  │ AZ1, AZ2, AZ3│  │ AZ1, AZ2, AZ3│  │ Private   │  │    │
│  │  └──────────────┘  └──────────────┘  │ Endpoints │  │    |
│  │                                      └───────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │     PostgreSQL Flexible Server (Primary - AZ1)      │    │
│  │     + Read Replica (AZ2) + Read Replica (AZ3)       │    │
│  │     ✓ Private Endpoint                              │    │
│  │     ✓ CMK Encryption                                │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │     Storage Account (ZRS - Zone Redundant)          │    │
│  │     ✓ Blob Private Endpoint                         │    │
│  │     ✓ File Private Endpoint                         │    │
│  │     ✓ Lifecycle Management (Cool: 30d, Archive: 90d)│    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │     Azure Key Vault                                 │    │
│  │     ✓ Database credentials                          │    │
│  │     ✓ Storage connection strings                    │    │
│  │     ✓ Customer-managed keys (CMK)                   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘


---

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

# Lifecycle Management 
cool_tier_days    = 90   # Move to Cool tier after 90 days
archive_tier_days = 365  # Move to Archive tier after 365 days

# Storage Replication: ZRS (Data Sovereignty)
storage_replication_type = "ZRS"

# Read Replicas for Latency Optimization
- Primary DB: Availability Zone 1
- Read Replica 1: Availability Zone 2
- Read Replica 2: Availability Zone 3

---

### `infrastructure/terraform/modules/storage/main.tf`

**Purpose**: Storage Account module with private endpoints

**What It Does**:
- Creates Storage Account with ZRS replication
- Configures blob and file services
- Creates Private Endpoints for blob and file
- Sets up Private DNS zones for name resolution
- Implements lifecycle management policy (cool/archive tiers)
- Enables blob versioning and soft delete

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


---

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


---

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
| **`COOL_TIER_DAYS`** | **`90`** | **📋 Days before moving to Cool storage tier (per PDF)** |
| **`ARCHIVE_TIER_DAYS`** | **`365`** | **📋 Days before moving to Archive storage tier (per PDF)** |

---

#### **Group 2: `migration-secrets`** (Sensitive - Link to Key Vault)

**⚠️ IMPORTANT**: Enable "**Link secrets from an Azure key vault as variables**" and select your Key Vault

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

# ✅ ADD VARIABLE GROUPS HERE
variables:
  - group: migration-config-production
  - group: migration-secrets

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
## 🚀 Deployment Instructions

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
| **Data Sovereignty** | ZRS replication (data within region) | ✅ Compliant |
| **Network Security** | Private Endpoints (no public internet) | ✅ Compliant |
| **Latency Target** | <50ms reads via 3 read replicas | ✅ Compliant |
| **Encryption** | CMK + TLS 1.2+ for all data | ✅ Compliant |
| **Lifecycle Management** | Cool (90d) + Archive (365d) | ✅ Compliant |
| **High Availability** | Multi-AZ deployment (99.95% SLA) | ✅ Compliant |

---

## Important Notes

1. **Data Sovereignty**: The `infrastructure/terraform/terraform.tfvars` file uses `ZRS` (Zone-Redundant Storage) for all storage accounts. **Do NOT change to GRS/GZRS** as it violates data sovereignty requirements (cross-region replication).

2. **Private Endpoints**: All database and storage traffic flows through private endpoints. Ensure NSG rules allow traffic from application subnets.

3. **Read Replicas**: The `infrastructure/terraform/modules/database/main.tf` creates 2 read replicas (AZ2 and AZ3) automatically. Application connection strings should use read replicas for SELECT queries to achieve <50ms latency.

4. **Key Vault Access**: Service Principal used in Azure DevOps must have `Key Vault Secrets User` role.

5. **Migration Validation**: Always run validation tests using `Invoke-DataValidation.ps1` and `Invoke-StorageValidation.ps1` post-migration before decommissioning source systems.

6. **Lifecycle Policy**: Storage lifecycle management is configured for **Cool tier at 90 days** and **Archive tier at 365 days** . This is defined in `infrastructure/terraform/modules/storage/main.tf`.

---


##  References

- [Azure PostgreSQL Flexible Server Documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Azure Storage Private Endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

