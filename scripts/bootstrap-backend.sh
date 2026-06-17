#!/usr/bin/env bash
# Bootstrap the Terraform azurerm remote state backend.
#
# Chicken-and-egg: terraform/backend.tf points at a storage account that does not
# exist on a fresh subscription. Run this ONCE (idempotently) before the first
# `terraform init`. It creates the RG, the state storage account, and the tfstate
# container, then prints the backend config. Auth is your current `az login`/OIDC
# session; no keys are stored (the backend uses use_oidc + use_azuread_auth).
set -euo pipefail

LOCATION="${LOCATION:-swedencentral}"
RG="rg-newcode-cv"
SA="stnewcodecvtf"
CONTAINER="tfstate"

command -v az >/dev/null || { echo "az CLI not found" >&2; exit 1; }

echo ">> Resource group: ${RG}"
az group create --name "${RG}" --location "${LOCATION}" --output none

echo ">> Storage account: ${SA}"
# TLS1.2 min, no public blob, key access disabled -> data-plane auth is AAD only.
az storage account create \
  --name "${SA}" \
  --resource-group "${RG}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --output none

# Shared-key access is disabled, so the container + Terraform state use AAD
# data-plane auth. Your az-login identity needs the DATA role on this account —
# subscription Owner is control-plane only and is NOT enough on its own.
echo ">> Granting your user 'Storage Blob Data Contributor' on ${SA}"
CALLER_ID=$(az ad signed-in-user show --query id -o tsv)
SA_ID=$(az storage account show --name "${SA}" --resource-group "${RG}" --query id -o tsv)
az role assignment create \
  --assignee "${CALLER_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "${SA_ID}" \
  --output none 2>/dev/null || echo "   (role already assigned)"
echo ">> Waiting ~30s for RBAC to propagate before touching the data plane..."
sleep 30

echo ">> Container: ${CONTAINER}"
az storage container create \
  --name "${CONTAINER}" \
  --account-name "${SA}" \
  --auth-mode login \
  --output none

cat <<EOF

Backend ready. terraform/backend.tf is already configured as:

  resource_group_name  = "${RG}"
  storage_account_name = "${SA}"
  container_name       = "${CONTAINER}"
  key                  = "cv.tfstate"

Now run:  terraform -chdir=terraform init
EOF
