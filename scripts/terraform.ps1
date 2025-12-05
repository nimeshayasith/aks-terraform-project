# terraform.ps1
# PowerShell equivalent of scripts/terraform.sh
# Usage: .\scripts\terraform.ps1 plan|apply|...
# With backend: .\scripts\terraform.ps1 init -backend-config=backend-configs/dev.tfbackend

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# Determine current workspace
$envWorkspace = (& terraform workspace show 2>$null) -replace "\r|\n", ""
if ([string]::IsNullOrEmpty($envWorkspace) -or $envWorkspace -eq "default") { 
    $envWorkspace = "dev" 
}
Write-Host "Current workspace: $envWorkspace"

$varFile = "envs/$envWorkspace/terraform.tfvars"
$backendConfig = "backend-configs/$envWorkspace.tfbackend"

# Ensure Azure subscription is available for the azurerm provider.
# If ARM_SUBSCRIPTION_ID isn't set, try to detect it from `az account show`.
if (-not $env:ARM_SUBSCRIPTION_ID) {
    if (Get-Command az -ErrorAction SilentlyContinue) {
        try {
            $detected = (az account show --query id -o tsv 2>$null) -replace "\r|\n", ""
        } catch {
            $detected = ""
        }
        if (-not [string]::IsNullOrEmpty($detected)) {
            $env:ARM_SUBSCRIPTION_ID = $detected.Trim()
            Write-Host "Detected Azure subscription."
        } else {
            Write-Error "ARM_SUBSCRIPTION_ID not set and no logged-in Azure account found. Run 'az login' to authenticate, or set the ARM_SUBSCRIPTION_ID environment variable."
            exit 1
        }
    } else {
        Write-Error "ARM_SUBSCRIPTION_ID not set and Azure CLI ('az') not found. Install Azure CLI or set ARM_SUBSCRIPTION_ID environment variable."
        exit 1
    }
}

# Build terraform args
$tfCmd = $RemainingArgs[0]
$tfArgs = @()

if ($tfCmd -eq "init") {
    # For init command, check if backend config exists and should be used
    $hasBackendConfigArg = $RemainingArgs -join " " | Select-String -Pattern "backend-config" -Quiet
    
    if ((Test-Path $backendConfig) -and -not $hasBackendConfigArg) {
        Write-Host "Using backend config: $backendConfig" -ForegroundColor Cyan
        $tfArgs += $RemainingArgs
        $tfArgs += "-backend-config=$backendConfig"
    } else {
        $tfArgs += $RemainingArgs
    }
    
    & terraform @tfArgs
} elseif ($tfCmd -in @("plan", "apply", "destroy", "import", "refresh")) {
    # For these commands, append -var-file
    $tfArgs += $RemainingArgs
    $tfArgs += "-var-file=$varFile"
    
    & terraform @tfArgs
} else {
    # Pass through all other commands as-is
    if ($RemainingArgs) {
        & terraform @RemainingArgs
    } else {
        & terraform
    }
}

# Forward exit code
exit $LASTEXITCODE
