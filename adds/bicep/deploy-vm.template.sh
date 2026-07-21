#!/bin/bash
# ============================================================
# deploy-vm.sh
# Wrapper to deploy the AD DS Domain Controller VM
# Usage: bash deploy-vm.sh
# Reads sensitive values from lab.config.ps1 equivalents
# ============================================================

RESOURCE_GROUP="rg-lab-adds"
LOCATION="eastus"
TEMPLATE="$(dirname "$0")/deploy-vm.bicep"

# ── Your values ───────────────────────────────────────────────
ADMIN_USERNAME="labadmin"
ADMIN_PASSWORD=""        # Fill in before running — never commit
ALLOW_RDP_FROM_IP=""     # Your public IP — check whatismyip.com

# ── Safety checks ─────────────────────────────────────────────
if [ -z "$ADMIN_PASSWORD" ] || [ -z "$ALLOW_RDP_FROM_IP" ]; then
  echo "ERROR: Fill in ADMIN_PASSWORD and ALLOW_RDP_FROM_IP before running"
  exit 1
fi

# ── Create resource group if it doesn't exist ─────────────────
echo "Creating resource group: $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

# ── Deploy ────────────────────────────────────────────────────
echo "Deploying Domain Controller VM..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters \
      adminUsername="$ADMIN_USERNAME" \
      adminPassword="$ADMIN_PASSWORD" \
      allowRdpFromIp="$ALLOW_RDP_FROM_IP" \
  --name "deploy-dc-$(date +%Y%m%d%H%M%S)"

echo "Done. Check outputs above for public IP and RDP command."