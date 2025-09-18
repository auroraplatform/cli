#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
COPY_SCRIPT="${SCRIPT_DIR}/scripts/copy-files-to-web-app.sh"

prompt_openai_key() {
    local tfvars_file="$1"
    
    echo
    echo "🔑 OpenAI API Key Configuration"
    echo "================================"
    echo "The Aurora web application requires an OpenAI API key to function."
    echo "Please enter your OpenAI API key."
    echo
    read -p "OpenAI API Key: " -s openai_key
    echo
    echo
    
    # Validate that the key is not empty
    if [ -z "$openai_key" ]; then
        echo "[ERROR] OpenAI API key cannot be empty. Please try again."
        exit 1
    fi
    
    # Update the terraform.tfvars file with the provided key
    if command -v sed >/dev/null 2>&1; then
        # Use sed to replace the placeholder value
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed
            sed -i '' "s/your-openai-api-key-here/$openai_key/" "$tfvars_file"
        else
            # Linux sed
            sed -i "s/your-openai-api-key-here/$openai_key/" "$tfvars_file"
        fi
    else
        echo "[ERROR] sed command not found. Cannot update terraform.tfvars file."
        exit 1
    fi
    
    echo "[SUCCESS] OpenAI API key saved to terraform.tfvars"
}

# Step 1: Create terraform.tfvars from example if it doesn't exist
echo "[INFO] Setting up Terraform configuration..."
cd "${TF_DIR}"

if [ ! -f "terraform.tfvars" ]; then
    if [ -f "terraform.tfvars.example" ]; then
        echo "[INFO] Creating terraform.tfvars from terraform.tfvars.example..."
        cp terraform.tfvars.example terraform.tfvars
        echo "[SUCCESS] terraform.tfvars created"
        
        # Prompt for OpenAI API key and update the file
        prompt_openai_key "terraform.tfvars"
    else
        echo "[ERROR] terraform.tfvars.example not found!"
        exit 1
    fi

else
    echo "[INFO] terraform.tfvars already exists"
    
    # Check if the OpenAI key is still the placeholder
    if grep -q "your-openai-api-key-here" terraform.tfvars; then
        echo "[INFO] OpenAI API key placeholder detected, updating..."
        prompt_openai_key "terraform.tfvars"
    else
        echo "[INFO] OpenAI API key already configured"
    fi

fi

# Step 2: Continue with the rest of deployment
echo "[INFO] Running Terraform in ${TF_DIR}..."
cd "${TF_DIR}"

terraform init -input=false

# Run terraform apply but suppress the output (including deployment_summary)
echo "[INFO] Executing terraform apply..."
terraform apply -auto-approve > /dev/null 2>&1

echo "[INFO] Terraform apply complete. Running post-deploy copy-files-to-web-app script..."
cd "${SCRIPT_DIR}"

if ! "${COPY_SCRIPT}"; then
    echo "[ERROR] Copy script failed"
    exit 1
fi

# After copy script completes, wait for web app and show summary
echo "[INFO] Waiting for web app to be ready..."
WEB_APP_IP=$(cd terraform && terraform output -raw web_app_public_ip 2>/dev/null || echo "")

if [ -n "$WEB_APP_IP" ]; then
    for i in {1..60}; do
        if curl -s -f "http://$WEB_APP_IP:8000" >/dev/null 2>&1; then
            echo "[SUCCESS] Web app is ready!"
            break
        fi
        echo "[INFO] Waiting for web app... (attempt $i/60)"
        sleep 30
    done

fi

# Now show the deployment summary
cd terraform
terraform output z_deployment_summary
