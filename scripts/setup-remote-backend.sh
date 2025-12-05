#!/bin/bash
# Setup Azure Storage backend for Terraform state with locking

set -e

# Default values
RESOURCE_GROUP="${1:-terraform-state-rg}"
STORAGE_ACCOUNT="${2:-tfstate$RANDOM}"
CONTAINER="${3:-tfstate}"
LOCATION="${4:-australiacentral}"

echo ""
echo "=== Setup Terraform Remote Backend ==="
echo "This will create Azure Storage for remote state with locking"
echo ""

# Check Azure CLI login
echo "[1/6] Verifying Azure CLI authentication..."
if ! az account show &>/dev/null; then
    echo "Not logged in to Azure. Running 'az login'..."
    az login
fi

ACCOUNT_NAME=$(az account show --query name -o tsv)
ACCOUNT_ID=$(az account show --query id -o tsv)
USER_NAME=$(az account show --query user.name -o tsv)

echo "✓ Logged in as: $USER_NAME"
echo "  Subscription: $ACCOUNT_NAME ($ACCOUNT_ID)"

# Create resource group for state
echo ""
echo "[2/6] Creating resource group for Terraform state..."
if az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
    echo "✓ Resource group '$RESOURCE_GROUP' already exists"
else
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    echo "✓ Created resource group: $RESOURCE_GROUP"
fi

# Create storage account
echo ""
echo "[3/6] Creating storage account..."
if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo "✓ Storage account '$STORAGE_ACCOUNT' already exists"
else
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --encryption-services blob \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --output none
    
    if [ $? -eq 0 ]; then
        echo "✓ Created storage account: $STORAGE_ACCOUNT"
    else
        echo "Error creating storage account"
        exit 1
    fi
fi

# Enable versioning for state history
echo ""
echo "[4/6] Enabling blob versioning..."
az storage account blob-service-properties update \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --enable-versioning true \
    --output none

echo "✓ Blob versioning enabled"

# Create container
echo ""
echo "[5/6] Creating blob container..."
CONTAINER_EXISTS=$(az storage container exists \
    --name "$CONTAINER" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --output tsv 2>/dev/null)

if [ "$CONTAINER_EXISTS" = "True" ]; then
    echo "✓ Container '$CONTAINER' already exists"
else
    az storage container create \
        --name "$CONTAINER" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --output none
    
    echo "✓ Created container: $CONTAINER"
fi

# Get storage account key
echo ""
echo "[6/6] Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT" \
    --query "[0].value" \
    --output tsv)

echo "✓ Retrieved access key"

# Generate backend configuration
echo ""
echo "=== Backend Configuration ==="

BACKEND_CONFIG="terraform {
  backend \"azurerm\" {
    resource_group_name  = \"$RESOURCE_GROUP\"
    storage_account_name = \"$STORAGE_ACCOUNT\"
    container_name       = \"$CONTAINER\"
    key                  = \"terraform.tfstate\"
  }
}"

echo ""
echo "Add this to your providers.tf file:"
echo "$BACKEND_CONFIG"

# Create backend.tf file
BACKEND_FILE="backend.tf"
echo "$BACKEND_CONFIG" > "$BACKEND_FILE"

echo ""
echo "✓ Created $BACKEND_FILE"

# Create backend config for environments
mkdir -p backend-configs

cat > backend-configs/dev.tfbackend <<EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STORAGE_ACCOUNT"
container_name       = "$CONTAINER"
key                  = "dev/terraform.tfstate"
EOF

cat > backend-configs/stage.tfbackend <<EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STORAGE_ACCOUNT"
container_name       = "$CONTAINER"
key                  = "stage/terraform.tfstate"
EOF

cat > backend-configs/prod.tfbackend <<EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STORAGE_ACCOUNT"
container_name       = "$CONTAINER"
key                  = "prod/terraform.tfstate"
EOF

echo "✓ Created environment-specific backend configs in backend-configs/"

# Set environment variable for authentication
echo ""
echo "=== Environment Variables ==="
echo "Setting environment variable for backend authentication..."

export ARM_ACCESS_KEY="$STORAGE_KEY"

# Add to shell profile if possible
SHELL_RC=""
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "ARM_ACCESS_KEY.*$STORAGE_ACCOUNT" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# Terraform backend access key (added by setup-remote-backend.sh)" >> "$SHELL_RC"
        echo "export ARM_ACCESS_KEY=\"$STORAGE_KEY\"" >> "$SHELL_RC"
        echo "✓ Added ARM_ACCESS_KEY to $SHELL_RC"
        echo "  Run: source $SHELL_RC (or restart your shell)"
    else
        echo "✓ ARM_ACCESS_KEY already in $SHELL_RC"
    fi
else
    echo "⚠ Could not detect shell profile. Set manually:"
    echo "  export ARM_ACCESS_KEY=\"$STORAGE_KEY\""
fi

echo "✓ ARM_ACCESS_KEY set in current session"

# Create/update .gitignore
echo ""
if [ -f ".gitignore" ]; then
    if ! grep -q "terraform.tfstate" .gitignore 2>/dev/null; then
        cat >> .gitignore <<EOF

# Terraform state files (now in remote backend)
*.tfstate
*.tfstate.*
terraform.tfstate.d/

# Backend config with sensitive data
backend-configs/*.tfbackend
!backend-configs/.gitkeep

# Environment variables
.env
*.env
EOF
        echo "✓ Updated .gitignore"
    else
        echo "✓ .gitignore already configured"
    fi
else
    cat > .gitignore <<EOF
# Terraform state files (now in remote backend)
*.tfstate
*.tfstate.*
terraform.tfstate.d/

# Backend config with sensitive data
backend-configs/*.tfbackend
!backend-configs/.gitkeep

# Environment variables
.env
*.env
EOF
    echo "✓ Created .gitignore"
fi

# Create README for backend configs
cat > backend-configs/README.md <<EOF
# Terraform Backend Configuration

This directory contains backend configuration files for different environments.

## Files
- \`dev.tfbackend\` - Development environment state
- \`stage.tfbackend\` - Staging environment state  
- \`prod.tfbackend\` - Production environment state

## Usage

### Initialize with backend config
\`\`\`bash
# For dev environment
terraform init -backend-config=backend-configs/dev.tfbackend

# For production
terraform init -backend-config=backend-configs/prod.tfbackend
\`\`\`

### Authentication
Set the storage account access key as an environment variable:

**Bash/Zsh:**
\`\`\`bash
export ARM_ACCESS_KEY="<storage-account-key>"
\`\`\`

**Fish:**
\`\`\`fish
set -x ARM_ACCESS_KEY "<storage-account-key>"
\`\`\`

## Security Notes
- Never commit \`.tfbackend\` files to git if they contain sensitive data
- Use Azure RBAC or service principals in CI/CD pipelines
- Enable soft delete and versioning on the storage account
EOF

# Summary
echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Remote backend details:"
echo "  Resource Group:    $RESOURCE_GROUP"
echo "  Storage Account:   $STORAGE_ACCOUNT"
echo "  Container:         $CONTAINER"
echo "  Location:          $LOCATION"

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Backup your local state (if it exists):"
echo "   cp terraform.tfstate terraform.tfstate.local.backup"

echo ""
echo "2. Initialize Terraform with the new backend:"
echo "   # Using default state file"
echo "   terraform init -reconfigure"
echo ""
echo "   # OR using environment-specific backend"
echo "   terraform init -reconfigure -backend-config=backend-configs/dev.tfbackend"

echo ""
echo "3. Terraform will ask if you want to migrate existing state. Answer 'yes'"

echo ""
echo "4. Verify state is in remote backend:"
echo "   terraform state list"

echo ""
echo "5. Delete local state files (after confirming remote state works):"
echo "   rm terraform.tfstate*"

echo ""
echo "=== Team Collaboration ==="
echo "Share these with your team:"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Container: $CONTAINER"
echo "  They need to run: terraform init -backend-config=backend-configs/dev.tfbackend"

echo ""
echo "Team members should set ARM_ACCESS_KEY:"
echo "  export ARM_ACCESS_KEY='<get-from-azure-portal>'"
echo "  Or use Azure RBAC (recommended for production)"

echo ""
echo "=== Security Recommendations ==="
echo "✓ Blob versioning: Enabled (state history)"
echo "✓ HTTPS only: Enabled"
echo "✓ Public access: Disabled"
echo "✓ Encryption: Enabled (Microsoft-managed keys)"

echo ""
echo "Consider enabling:"
echo "- Soft delete for blob recovery"
echo "- Customer-managed encryption keys"
echo "- Private endpoint for storage account"
echo "- Azure RBAC instead of access keys"

echo ""
echo "For more information, see BACKEND_SETUP.md"
echo ""
