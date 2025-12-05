# 🚀 Azure Kubernetes Service (AKS) Terraform Project

## DEPLOYMENT INSTRUCTIONS

This guide provides the steps for initializing, deploying, verifying, and cleaning up the infrastructure across **Dev**, **Stage**, and **Prod** environments using the provided Terraform scripts and workspace workflow.

---

### 1. Prerequisites

Ensure you have the following tools installed and configured locally:

* **Azure subscription**
* **Terraform** (version $\geq 1.6$)
* **Azure CLI** (Authenticated to your target subscription)
* **kubectl** (Kubernetes command-line tool)

---

### 2. Initialize Terraform

Navigate to the root directory of the project (`aks-terraform-project/`) and initialize the backend and provider plugins.

```bash
terraform init
```

### 3. Select or Create Workspace

Use **Terraform Workspaces** to isolate the state for each environment. You must select the target workspace before running `plan` or `apply`.

```bash
# List all available workspaces
terraform workspace list

# Select the 'dev' workspace. If it doesn't exist, create it.
terraform workspace new dev || terraform workspace select dev

```

### 4. Deploy Using Wrapper Script

The wrapper scripts (`terraform.ps1` or `terraform.sh`) automatically load the correct **.tfvars** file based on the currently selected workspace, eliminating manual variable input.

#### 🖥️ PowerShell (Windows)

```powershell
.\scripts\terraform.ps1 plan
.\scripts\terraform.ps1 apply -auto-approve
```

#### 🐧 Bash / Linux / macOS
```bash
./scripts/terraform.sh plan
./scripts/terraform.sh apply -auto-approve
```

💡 The script automatically loads the correct ".tfvars" file based on the workspace.

Here is the content for the "Verify Deployment" section, correctly formatted in Markdown, which is suitable for your `DEPLOYMENT.md` file:


### 5. Verify Deployment

After a successful deployment (`apply`), use the following steps to verify the cluster connectivity and access to core services in the **Dev** environment.

1.  **Fetch Kubeconfig:** Use the utility script to fetch the cluster configuration required for `kubectl` access.

    ```bash
    ./scripts/get-kubeconfig.sh cloudproj-dev-rg cloudproj-dev-aks
    #                        |-----------------| |-------------------|
    #                             resource group      kubernetes cluster
    ```

2.  **Verify Cluster Status:** Confirm that the AKS nodes are healthy and system pods are running.

    ```bash
    kubectl get nodes
    kubectl get pods -A
    ```
3.  **TAG A LOCAL IMAGE FOR TESTING ACR:** Tag an existing local image (placeholder).

    ```bash
    docker pull nginx:latest
    docker tag nginx:latest <acr_login_server>/frontend:dev
    ```
3.  **Test MySQL connection:** Test the connection to MySQL database

    ```bash
    kubectl run mysql-test --rm -it --image=mysql:8.0 --restart=Never -- bash 
    
    # Run the following command inside the MySQL prompt
    mysql -h <mysql_fqdn> -u adminuser -p

    # Once prompted, supply the password: DevStrongPassword123!

    # Once inside the database, RUN:
     SHOW DATABASES;
    ```

4.  **Login to ACR:** Authenticate to the Azure Container Registry (ACR) to confirm identity access.

    ```bash
    az acr login --name <acr_name>
    ```

5.  **Push the placeholder image:**

    ```bash
    docker push <acr_login_server>/frontend:dev
    ```

6.  **Verify repository and tags in ACR:**

    ```bash
    az acr repository list --name <acr_name> --output table
    az acr repository show-tags --name <acr_name> --repository frontend --output table
    ```

### 5.1. Deploy Application Using kubectl CLI

#### Option A: Deploy from Docker Hub (Simple)

```bash
# Deploy nginx web server
kubectl create deployment nginx-app --image=nginx:latest

# Expose it with a LoadBalancer (gets public IP)
kubectl expose deployment nginx-app --type=LoadBalancer --port=80 --target-port=80 --name=nginx-service

# Watch for external IP (takes 2-3 minutes)
kubectl get svc nginx-service -w
```

#### Step 4: Access Your Application

Your configuration supports 3 access methods:

**Method 1: External Access (Public Internet) ✅**

```bash
# Get the LoadBalancer IP
EXTERNAL_IP=$(kubectl get svc sample-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Access via browser or curl
curl http://$EXTERNAL_IP

# Or open in browser (Windows)
start http://$EXTERNAL_IP
```

**Method 2: Internal Access (Within Cluster) ✅**

```bash
# Access from another pod in the cluster
kubectl run test-pod --rm -it --image=curlimages/curl -- curl http://sample-app-service
```

**Method 3: Port Forwarding (Local Development) ✅**

```bash
# Forward to your local machine
kubectl port-forward svc/sample-app-service 8080:80

# Access at http://localhost:8080
```

#### Step 5: Manage Your Application

```bash
# Scale your application
kubectl scale deployment sample-app --replicas=5

# Update the application
kubectl set image deployment/sample-app app=nginx:latest

# View logs
kubectl logs -l app=sample-app --tail=50 -f

# Check resource usage
kubectl top pods -l app=sample-app
kubectl top nodes

# Delete the application
kubectl delete -f k8s/sample-app.yaml
# Or
kubectl delete deployment sample-app
kubectl delete service sample-app-service
```

 ### 6. Deploy Stage / Prod

Repeat the deployment steps for Stage and Production environments. Ensure you switch the active **Terraform Workspace** before running the plan and apply commands for each target environment.

#### Deploy Stage

```bash
terraform workspace select stage || terraform workspace new stage
./scripts/terraform.sh plan
./scripts/terraform.sh apply
```

#### Deploy Production

```bash
terraform workspace select prod || terraform workspace new prod
./scripts/terraform.sh plan
./scripts/terraform.sh apply
```
⚠️ Stage and Prod environments are highly restricted. They should typically be deployed via automated CI/CD pipelines using service principals, NOT via direct developer workstation access.


### 7. Clean-up (Optional)

To destroy all deployed infrastructure and avoid incurring further Azure costs, use the `destroy` command via the wrapper script.

1.  **Select Target Environment:** Switch to the workspace you wish to destroy.

    ```bash
    terraform workspace select dev
    ```

2.  **Execute Destroy:** The script will automatically load the correct variables and prompt you to confirm the destruction of all resources defined in that workspace state.

    ```bash
    ./scripts/terraform.sh destroy
    ```

*Repeat the `select` and `destroy` steps for the **Stage** and **Prod** workspaces if required.*

### 8. Best Practices 🛡️

Following these practices ensures a secure, maintainable, and repeatable deployment process:

* Always use **Terraform workspaces** for environment isolation (Dev, Stage, Prod).
* Avoid **hardcoding credentials** in configuration files; use **Azure Key Vault** for secure secret storage and dynamic retrieval.
* Verify **NSG (Network Security Group) and UDR (User-Defined Route)** rules after deployment to ensure secure network flow matches the traffic matrix.
* Always perform a careful review of the comprehensive **`terraform plan`** output before executing **`terraform apply`**.

This robust setup ensures fully automated, repeatable deployments without prompting for the variables manually.