# FinApp Global Cloud Migration to Azure

##  Overview

This repository contains the complete infrastructure-as-code (Terraform), and provides two PowerShell scripts that implement a complete lifecycle for secure Azure with strict **data sovereignty compliance** and **sub-50ms latency optimization** 

  ## Storage infrastructure:
1. **Storage_provisioner_automation.ps1** - Provisions all secured infrastructure components
2. **Cleanup-Resources.ps1** - Safely removes all provisioned resources
The solution implements **Zero Trust architecture** with private endpoints only, automated tiering policies, and comprehensive audit trails.

---

##  Key Requirements Implemented 

✅ **Data Sovereignty**: ZRS for transactional data, GRS for archival  
✅ **Security**: Azure Key Vault integration with managed identities 
✅ **Compliance**: Customer-managed encryption keys (CMK) for all data
✅ **Private Endpoints**: All storage and database traffic over private network (no public internet)  
✅ **Latency Optimization**: PostgreSQL read replicas across availability zones (<50ms read latency)   
✅ **Lifecycle Management**: Automated data tiering (cool tier: 90 days, archive tier: 365 days)  



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
# Automation Scripts Overview

This project includes two fully automated PowerShell Infrastructure-as-Code (IaC) scripts designed to provision and manage a secure Azure Storage infrastructure for departmental file archiving and lifecycle management.

## Storage_provisioner_automation.ps1 

This script automates the deployment of a secure and compliant Azure Storage environment using private networking and lifecycle management policies.

### Key Features:

  - Validates Azure login, VNet, Subnet, and naming prerequisites
  - Creates a Resource Group with standardized governance tags
  - Provisions a Geo-Redundant (GRS) Storage Account with public access disabled
  - Creates blob containers: dept-files-active and dept-files-archive
  - Configures Private Endpoint and integrates with Private DNS Zone
  - Implements Lifecycle Management (Cool Tier: 90 days, Archive Tier: 365 days)
  - Exports a detailed deployment summary and JSON report for auditing

 **Purpose**: Ensure all storage traffic remains private, compliant, and cost-optimized while supporting data lifecycle automation.

## Cleanup-resources.ps1

This companion script safely and completely removes all Azure resources created by the provisioner script.

 ### Key Features:

   - Validates Azure session and ensures safe execution
   - Inventories all resources in the target Resource Group
   - Performs a controlled deletion of Storage Accounts, Private Endpoints, and other dependencies
   - Supports optional removal of Private DNS records
   - Detects and honors soft-delete retention policies
   - Generates a cleanup log (JSON) for audit and compliance reporting

**Purpose**: Provide a safe rollback and decommissioning mechanism, ensuring a clean, auditable Azure environment post-deployment.


# Terraform script for infracstructure creation

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

### `infrastructure/terraform/modules/monitoring/main.tf`

**Purpose**: Centralized Monitoring, Logging, and Alerting for Azure Resources

**What It Does**:
  - Creates a Log Analytics Workspace for unified telemetry storage (30-day retention)
  - Configures Diagnostic Settings for PostgreSQL and Storage Accounts
  - Sets up Performance Alerts for CPU, Memory, Storage Usage, and Latency (sub-50 ms)
  - Creates Action Groups for critical and warning email notifications
  - Deploys Application Insights for end-to-end application performance tracking

**Observability & Compliance**:  Ensures proactive performance monitoring, SLA compliance, and full traceability through centralized logging and Azure Monitor integration

**Alert Coverage**: Includes real-time alerts for CPU (>80 %), Memory (>85 %), Latency (>50 ms), and Storage Capacity (>90 %) thresholds

---

### `infrastructure/terraform/backend.tf`

**Purpose**: Remote Terraform State Management in Azure

**What It Does**:
  - Stores Terraform state file (financial-app.tfstate) securely in an Azure Storage Account
  - Enables team collaboration and state locking to prevent configuration drift
  - Ensures disaster recovery through durable Azure Blob Storage
  - Facilitates consistent deployments across environments (e.g., Dev, QA, Prod)

**Best Practice**:  Keep backend configuration separate and protect storage account access with Azure RBAC and private endpoints for secure IaC state management.

---

### `infrastructure/terraform/main.tf`

**Purpose**: Multi-Region Orchestrator for Financial Application Deployment

**What It Does**:

  - Generates secure random PostgreSQL admin passwords and stores them in Azure Key Vault per region
  - Creates Resource Groups and Key Vaults in each defined region (ensuring data sovereignty)
  - Retrieves existing Virtual Networks and Subnets for private deployment (no public exposure)
  - Invokes reusable Terraform modules:
      - database → Deploys PostgreSQL Flexible Server with HA
      - storage → Deploys storage accounts with lifecycle management
      - monitoring → Enables Log Analytics, Application Insights, and alerting
  - Adds a dedicated GRS-replicated Storage Account for departmental file archiving (East US 2)

  
**Security & Compliance Highlights**:

   - Secrets managed in Azure Key Vault (Premium SKU) with purge protection enabled
   - Implements Zero-Trust networking (private subnets only)
   - Enforces data sovereignty — each region deploys independently (no cross-region replication)
   - Uses Terraform remote state and consistent tag governance for cost visibility

**Key Components Created**:

  - Random password + Key Vault Secret (postgresql-admin-password)
  - Resource Groups: One per region (e.g., rg-finapp-northamerica-prod)
  - PostgreSQL Servers (via module.database)
  - Storage Accounts (via module.storage and module.storage_dept_files)
  - Log Analytics, Alerts, and Application Insights (via module.monitoring)

**Best Practice**:  Keep terraform.tfvars environment-specific and use for_each for true multi-region scalability.

```
---


##  References

- [Azure PostgreSQL Flexible Server Documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Azure Storage Private Endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

```
---
