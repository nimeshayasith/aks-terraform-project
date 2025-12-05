# Remote Backend Setup Guide

This guide explains how to configure and use Azure Storage as a remote backend for Terraform state management with state locking.

## Why Remote Backend?

✅ **State Locking**: Prevents concurrent modifications  
✅ **Team Collaboration**: Shared state across team members  
✅ **State History**: Versioning and recovery via blob versioning  
✅ **Security**: Encrypted at rest, access controlled via Azure RBAC  
✅ **Disaster Recovery**: Centralized backup and geo-redundancy options  

## Quick Setup

### Step 1: Run the Setup Script

```powershell
# Run the automated setup script
.\scripts\setup-remote-backend.ps1

# Or with custom parameters
.\scripts\setup-remote-backend.ps1 `
  -ResourceGroup "my-tfstate-rg" `
  -StorageAccount "mytfstate1234" `
  -Container "tfstate" `
  -Location "australiacentral"
```

This script will:
- Create Azure Storage Account with security best practices
- Enable blob versioning for state history
- Create containers for state files
- Generate backend configuration files
- Set environment variables for authentication

### Step 2: Migrate Existing State (if you have local state)

```bash
# Backup your local state first
cp terraform.tfstate terraform.tfstate.local.backup

# Initialize with new backend (will prompt to migrate)
./scripts/terraform.sh init -reconfigure

# Or for specific environment
terraform init -reconfigure -backend-config=backend-configs/dev.tfbackend

# Terraform will ask: "Do you want to copy existing state to the new backend?"
# Answer: yes
```

### Step 3: Verify Remote State

```bash
# List resources (should work from remote state)
terraform state list

# Check the Azure portal or CLI
az storage blob list \
  --account-name <storage-account-name> \
  --container-name tfstate \
  --output table
```

### Step 4: Clean Up Local State Files

```bash
# After confirming remote state works, delete local files
rm terraform.tfstate
rm terraform.tfstate.backup
rm -rf terraform.tfstate.d/
```

## Backend Configuration Files

The setup creates environment-specific backend configs:

```
backend-configs/
├── dev.tfbackend       # Development state
├── stage.tfbackend     # Staging state
├── prod.tfbackend      # Production state
└── README.md
```

### Example: dev.tfbackend
```hcl
resource_group_name  = "terraform-state-rg"
storage_account_name = "tfstate1234"
container_name       = "tfstate"
key                  = "dev/terraform.tfstate"
```

## Usage

### Initialize with Backend

```bash
# Using helper script (auto-detects environment)
./scripts/terraform.sh init

# Manual initialization with specific environment
terraform init -backend-config=backend-configs/dev.tfbackend

# Reconfigure (switch backends or migrate state)
terraform init -reconfigure -backend-config=backend-configs/prod.tfbackend
```

### Regular Operations

```bash
# Plan (uses remote state automatically)
./scripts/terraform.sh plan -var-file=envs/dev/terraform.tfvars

# Apply
./scripts/terraform.sh apply -var-file=envs/dev/terraform.tfvars

# State commands work with remote state
terraform state list
terraform state show azurerm_kubernetes_cluster.aks
```

## Authentication

### Option 1: Access Key (Quick Start)

```powershell
# Set in current session
$env:ARM_ACCESS_KEY = "<storage-account-key>"

# Set permanently for user
[Environment]::SetEnvironmentVariable("ARM_ACCESS_KEY", "<key>", "User")
```

```bash
# Bash
export ARM_ACCESS_KEY="<storage-account-key>"
```

Get the key from:
```bash
az storage account keys list \
  --resource-group terraform-state-rg \
  --account-name <storage-account-name> \
  --query "[0].value" -o tsv
```

### Option 2: Azure AD / Managed Identity (Recommended for Production)

Update `backend.tf`:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstate1234"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true  # Use Azure AD instead of access key
  }
}
```

Grant permissions:
```bash
# Get your user object ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign Storage Blob Data Contributor role
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $USER_ID \
  --scope "/subscriptions/<subscription-id>/resourceGroups/terraform-state-rg/providers/Microsoft.Storage/storageAccounts/<storage-account-name>"
```

### Option 3: Service Principal (CI/CD)

```bash
# Create service principal
az ad sp create-for-rbac \
  --name "terraform-backend-sp" \
  --role "Storage Blob Data Contributor" \
  --scopes "/subscriptions/<subscription-id>/resourceGroups/terraform-state-rg"

# Set in CI/CD pipeline
export ARM_CLIENT_ID="<appId>"
export ARM_CLIENT_SECRET="<password>"
export ARM_TENANT_ID="<tenant>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

## State Locking

Azure Storage backend provides **automatic state locking** using blob leases:

```bash
# When you run terraform apply, the state file is locked
terraform apply

# If another user tries to run apply simultaneously:
# Error: Error acquiring the state lock
# Lock Info:
#   ID:        <lease-id>
#   Path:      tfstate/terraform.tfstate
#   Operation: OperationTypeApply
#   Who:       user@domain.com
#   Created:   2025-12-04 10:30:00
```

### Force Unlock (Use with Caution)

```bash
# Only if lock is stuck after a crash
terraform force-unlock <lock-id>
```

## Multi-Environment Setup

### Separate State Files per Environment

```
Container: tfstate
├── dev/terraform.tfstate
├── stage/terraform.tfstate
└── prod/terraform.tfstate
```

### Switch Environments

```bash
# Initialize for dev
terraform init -backend-config=backend-configs/dev.tfbackend

# Plan for dev
./scripts/terraform.sh plan -var-file=envs/dev/terraform.tfvars

# Switch to production
terraform init -reconfigure -backend-config=backend-configs/prod.tfbackend

# Plan for production
./scripts/terraform.sh plan -var-file=envs/prod/terraform.tfvars
```

## State Management

### View State

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show azurerm_kubernetes_cluster.aks

# Pull state to local file (for inspection)
terraform state pull > current-state.json
```

### Backup and Recovery

```bash
# Download specific state version
az storage blob download \
  --account-name <storage-account> \
  --container-name tfstate \
  --name dev/terraform.tfstate \
  --file terraform.tfstate.backup \
  --version-id <version-id>

# List all versions
az storage blob list \
  --account-name <storage-account> \
  --container-name tfstate \
  --include v \
  --query "[?name=='dev/terraform.tfstate'].{Name:name, VersionId:versionId, LastModified:properties.lastModified}" \
  --output table
```

### Restore from Backup

```bash
# Push a specific version back as current state
terraform state push terraform.tfstate.backup
```

## Security Best Practices

### Storage Account Configuration

✅ **Enabled by setup script:**
- HTTPS only
- Minimum TLS 1.2
- Blob versioning
- No public access
- Encryption at rest

### Additional Hardening

```bash
# Enable soft delete (30-day recovery)
az storage account blob-service-properties update \
  --account-name <storage-account> \
  --enable-delete-retention true \
  --delete-retention-days 30

# Enable infrastructure encryption (double encryption)
az storage account update \
  --name <storage-account> \
  --resource-group terraform-state-rg \
  --encryption-key-source Microsoft.Storage \
  --require-infrastructure-encryption

# Restrict network access
az storage account update \
  --name <storage-account> \
  --resource-group terraform-state-rg \
  --default-action Deny

az storage account network-rule add \
  --account-name <storage-account> \
  --resource-group terraform-state-rg \
  --ip-address <your-ip>
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Terraform

on:
  push:
    branches: [main]
  pull_request:

jobs:
  terraform:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Terraform Init
      run: terraform init -backend-config=backend-configs/dev.tfbackend
      env:
        ARM_ACCESS_KEY: ${{ secrets.TF_STATE_ACCESS_KEY }}
    
    - name: Terraform Plan
      run: terraform plan -var-file=envs/dev/terraform.tfvars
      
    - name: Terraform Apply
      if: github.ref == 'refs/heads/main'
      run: terraform apply -auto-approve -var-file=envs/dev/terraform.tfvars
```

### Azure DevOps Example

```yaml
trigger:
  branches:
    include:
    - main

pool:
  vmImage: 'ubuntu-latest'

variables:
- group: terraform-backend-vars  # Contains ARM_ACCESS_KEY

steps:
- task: TerraformInstaller@0
  inputs:
    terraformVersion: 'latest'

- task: TerraformTaskV2@2
  displayName: 'Terraform Init'
  inputs:
    command: 'init'
    backendServiceArm: 'Azure-ServiceConnection'
    backendAzureRmResourceGroupName: 'terraform-state-rg'
    backendAzureRmStorageAccountName: 'tfstate1234'
    backendAzureRmContainerName: 'tfstate'
    backendAzureRmKey: 'dev/terraform.tfstate'

- task: TerraformTaskV2@2
  displayName: 'Terraform Plan'
  inputs:
    command: 'plan'
    commandOptions: '-var-file=envs/dev/terraform.tfvars'
```

## Troubleshooting

### Error: Backend configuration changed

```bash
# Reinitialize backend
terraform init -reconfigure
```

### Error: Failed to acquire state lock

```bash
# Check who has the lock
terraform plan
# Error will show lock info

# Force unlock (only if lock is stuck)
terraform force-unlock <lock-id>
```

### Error: No valid credential sources

```bash
# Ensure ARM_ACCESS_KEY is set
echo $ARM_ACCESS_KEY

# Or use Azure AD authentication
az login
```

### State file not found

```bash
# Check if state exists in storage
az storage blob exists \
  --account-name <storage-account> \
  --container-name tfstate \
  --name dev/terraform.tfstate

# Initialize if new environment
terraform init -backend-config=backend-configs/dev.tfbackend
```

## Migration Checklist

- [ ] Run `.\scripts\setup-remote-backend.ps1`
- [ ] Backup local state: `cp terraform.tfstate terraform.tfstate.local.backup`
- [ ] Review generated `backend.tf`
- [ ] Initialize: `terraform init -reconfigure`
- [ ] Confirm migration: Answer "yes" to copy state
- [ ] Verify: `terraform state list`
- [ ] Test: `terraform plan` (should see no changes)
- [ ] Clean up: `rm terraform.tfstate*`
- [ ] Update `.gitignore` (done by script)
- [ ] Share backend config with team
- [ ] Document authentication method for team

## Team Onboarding

Share with new team members:

1. **Storage Account Details:**
   - Resource Group: `terraform-state-rg`
   - Storage Account: `<storage-account-name>`
   - Container: `tfstate`

2. **Authentication:**
   ```powershell
   $env:ARM_ACCESS_KEY = "<get-from-team-lead>"
   ```

3. **Initialize:**
   ```bash
   terraform init -backend-config=backend-configs/dev.tfbackend
   ```

4. **Verify:**
   ```bash
   terraform state list
   ```

## References

- [Terraform Azure Backend Documentation](https://www.terraform.io/language/settings/backends/azurerm)
- [Azure Storage Security Best Practices](https://docs.microsoft.com/azure/storage/common/storage-security-guide)
- [State Locking](https://www.terraform.io/language/state/locking)
