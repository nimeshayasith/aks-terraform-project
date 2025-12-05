# Quick Start: Remote Backend

## Setup (One-Time)

```bash
# Run the automated setup
.\scripts\setup-remote-backend.sh

# This creates:
# - Azure Storage Account with versioning
# - Blob container for state files  
# - Backend config files for each environment
# - Sets ARM_ACCESS_KEY environment variable
```

## Initialize Terraform with Remote Backend

```bash
# Backup local state first (if exists)
cp terraform.tfstate terraform.tfstate.local.backup

# Initialize with remote backend
terraform init -reconfigure -backend-config=backend-configs/dev.tfbackend

# Answer "yes" when asked to migrate existing state
```

## Daily Usage

```bash
# Everything works the same, but state is now remote:

# Plan
./scripts/terraform.sh plan 

# Apply
./scripts/terraform.sh apply 

# State commands
terraform state list
```

## Team Members Setup

Share with team:
1. Storage account name: `<from setup output>`
2. Container: `tfstate`

Team members run:
```powershell
# Set access key (get from Azure portal or team lead)
$env:ARM_ACCESS_KEY = "<storage-account-key>"

# Initialize
terraform init -backend-config=backend-configs/dev.tfbackend

# Verify
terraform state list
```

## Common Commands

```bash
# View remote state
terraform state list

# Refresh from remote
terraform refresh

# Download state for inspection
terraform state pull > state.json

# Force unlock (if stuck)
terraform force-unlock <lock-id>
```

## Troubleshooting

**Error: Failed to get credentials**
```powershell
$env:ARM_ACCESS_KEY = "<your-storage-key>"
```

**Error: Backend configuration changed**
```bash
terraform init -reconfigure
```

**State locked by another user**
- Wait for them to finish
- Or force unlock: `terraform force-unlock <lock-id>` (use carefully!)

## More Details

See `BACKEND_SETUP.md` for complete documentation.
