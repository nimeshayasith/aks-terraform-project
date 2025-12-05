# Terraform Backend Configuration

This directory contains backend configuration files for different environments.

## Files
- `dev.tfbackend` - Development environment state
- `stage.tfbackend` - Staging environment state  
- `prod.tfbackend` - Production environment state

## Usage

### Initialize with backend config
```bash
# For dev environment
terraform init -backend-config=backend-configs/dev.tfbackend

# For production
terraform init -backend-config=backend-configs/prod.tfbackend
```

### Authentication
Set the storage account access key as an environment variable:

**Bash/Zsh:**
```bash
export ARM_ACCESS_KEY="<storage-account-key>"
```

**Fish:**
```fish
set -x ARM_ACCESS_KEY "<storage-account-key>"
```

## Security Notes
- Never commit `.tfbackend` files to git if they contain sensitive data
- Use Azure RBAC or service principals in CI/CD pipelines
- Enable soft delete and versioning on the storage account
