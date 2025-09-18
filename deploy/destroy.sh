#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "[INFO] Destroying Terraform infrastructure in ${TF_DIR}..."
cd "${TF_DIR}"

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "[ERROR] No terraform state found. Nothing to destroy."
    exit 1
fi

# Show what will be destroyed
echo "[INFO] Planning destruction..."
terraform plan -destroy

# Ask for confirmation
echo ""
echo "[WARNING] This will destroy ALL infrastructure resources."
echo "This action cannot be undone!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "[INFO] Destruction cancelled."
    exit 0
fi

echo "[INFO] Destroying infrastructure..."
terraform destroy -auto-approve

echo "[INFO] Infrastructure destruction complete."
echo "[INFO] Cleaning up local state files..."

# Remove state files
rm -f terraform.tfstate
rm -f terraform.tfstate.backup
rm -rf .terraform/
rm -f .terraform.lock.hcl

echo "[INFO] Cleanup complete. All infrastructure has been destroyed."
