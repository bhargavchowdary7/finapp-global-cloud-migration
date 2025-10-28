# Financial Application - Azure Infrastructure

This repository contains Terraform code for deploying a global financial application infrastructure on Azure, supporting real-time trading platforms across North America, Europe, and Asia with strict data sovereignty compliance.



### Use Case 1: Global Financial Application Migration
- **50TB** on-premises relational database → **Azure PostgreSQL Flexible Server**
- **100TB** NAS-based transaction logs/archive → **Azure Storage**
- **Regions**: East US 2 (North America), UK South (Europe), Southeast Asia (Asia)
- **Data Sovereignty**: No cross-region replication, isolated deployments
- **Latency**: Sub-50ms for database operations
- **DR**: RTO < 1 hours, RPO < 5 minutes

### Use Case 2: File Share Archiving
- Secure departmental files storage with automated tiering
- Private endpoints only, no public internet access
- Lifecycle management for cost optimization

##  Architecture

### Multi-Region Deployment