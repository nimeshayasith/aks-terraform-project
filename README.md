# 🚀 Azure Kubernetes Service (AKS) Terraform Project

## Project Overview

This project provisions an **Azure Kubernetes Service (AKS)** cluster and all supporting infrastructure using **Terraform**. It provides a robust, secure, and repeatable cloud environment setup, including:

* **Multi-Environment Support:** Dedicated configurations for **Dev**, **Stage**, and **Prod** environments.
* **Secure Networking:** VNet with 4 subnets per environment (2 public, 2 private) for proper network segregation and AKS security.
* **Data Tier:** **Azure MySQL Flexible Server** secured with a **private endpoint**.
* **Container Management:** **Azure Container Registry (ACR)** for storing application images.
* **Secret Management:** **Azure Key Vault** for securely storing application secrets and configuration data.
* **CI/CD Friendly:** Designed for seamless integration with modern CI/CD pipelines using **Terraform Workspaces**.

---

## 🏗️ Project Structure

The repository is structured to separate reusable modules from environment-specific configurations.

```bash
aks-terraform-project/
├─ modules/
│  ├─ network/      # Reusable VNet and Subnet module
│  ├─ aks/          # Reusable AKS cluster module
│  ├─ mysql/        # Reusable Azure MySQL Flexible Server module
│  ├─ acr/          # Reusable Azure Container Registry module
│  └─ keyvault/     # Reusable Azure Key Vault module
├─ envs/
│  ├─ dev/          # Dev environment variables and specific configurations
│  ├─ stage/        # Stage environment variables and specific configurations
│  └─ prod/         # Prod environment variables and specific configurations
├─ scripts/
│  ├─ get-kubeconfig.sh # Utility to fetch the kubeconfig after deployment
│  ├─ terraform.sh      # Wrapper script for simplified Terraform execution (Bash/Linux)
│  └─ terraform.ps1     # Wrapper script for simplified Terraform execution (PowerShell/Windows)
├─ providers.tf    # Cloud provider configuration (Azure)
├─ variables.tf    # Global variable definitions
├─ main.tf         # Main entry point for module calls
├─ outputs.tf      # Defines the deployment outputs
├─ README.md       # This file
├─ DEVELOPER_GUIDE.md # Detailed guide for local development and setup
└─ DEPLOYMENT.md   # Detailed guide for pipeline deployment
```


## 🗺️ Architecture Diagram

The following diagram illustrates the high-level infrastructure components and their connectivity within a single environment (e.g., Prod) provisioned by this Terraform project.

![Azure AKS Architecture Diagram](images\architecure.jpg)

*This visual shows how the AKS cluster, secured in **private subnets**, connects internally to the **Azure MySQL Private Endpoint** and **Key Vault**, while external traffic is managed via a load balancer/ingress component.*



## 🚦 FULL TRAFFIC MATRIX

This matrix details the required network flows, protocols, and security actions for the entire AKS ecosystem, including application, control plane, and development access.

| Source | Destination | Port/Protocol | Direction | Action | Reason |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **User (Internet)** | Public Subnet (AGW / Ingress IP) | 80, 443 | Inbound | Allow | App Gateway/Ingress must serve apps |
| Public Subnet User | Internet | 80, 443 | Outbound | Allow | Response traffic |
| **AKS Nodes** | API Server | 443 | Outbound | Allow | Required for AKS cluster operations |
| **API Server** | AKS Nodes | 443 | Inbound | Allow | Managed by Azure automatically |
| AKS Nodes | AKS Nodes | 10250, 443, VXLAN | Both | Allow | Node-to-node communication |
| **AKS Pods** | MySQL DB Private Endpoint | 3306 | Outbound | Allow | App reads/writes DB |
| MySQL Private Endpoint | AKS Pods | 3306 | Inbound | Allow | Response |
| **AKS Nodes** | Key Vault | 443 | Outbound | Allow | Fetch secrets for app or CSI driver |
| **AKS Nodes** | ACR | 443 | Outbound | Allow | Node pulls images |
| Dev Workstation | MySQL (Dev Only) | 3306 | Inbound | Allow | Debugging/testing DB access |
| Dev Workstation | AKS API Server | 443 | Outbound | Allow | Secure `kubectl` access |
| Stage/Prod Workstation | DB | 3306 | Inbound | Deny | Security — no direct DB access |
| Public Subnets | Private Subnets | Any | Inbound | Deny | No inbound from public to private |

## ⚙️ Automatic Environment Variable Workflow

This project utilizes **Terraform Workspaces** to isolate state files and variables for each environment. The wrapper script automatically identifies the current workspace and loads the corresponding `.tfvars` file. 

| Workspace | Variables File Loaded |
| :-------- | :-------------------- |
| `dev`     | `envs/dev/terraform.tfvars` |
| `stage`   | `envs/stage/terraform.tfvars` |
| `prod`    | `envs/prod/terraform.tfvars` |

> 🔑 This eliminates all interactive prompts for variables during plan/apply.

### Example Usage

#### Select or Create a Workspace:

```bash
# Select the 'dev' workspace. If it doesn't exist, create it.
terraform workspace select dev || terraform workspace new dev
```
### Plan Deployment:

```bash
# The script automatically loads the correct .tfvars file
./scripts/terraform.sh plan
```

### Apply Deployment::

```bash
# Executes the deployment for the selected workspace
./scripts/terraform.sh apply
```

## 📥 Outputs

Upon successful deployment, the following key infrastructure identifiers are provided in the output:

* **Networking:** VNet ID, all Subnet IDs, Network Security Group (NSG) IDs, and User Defined Route (UDR) IDs.
* **AKS:** AKS cluster name and the required **kubeconfig**.
* **Data Tier:** MySQL Fully Qualified Domain Name (FQDN) and private endpoint ID.
* **ACR:** The ACR login server name.

