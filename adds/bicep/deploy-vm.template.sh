#!/bin/bash
# ============================================================
# deploy.sh
# Deploys any VM using the generic deploy-vm.bicep template
# Usage:
#   bash deploy.sh dc       → deploys domain controller
#   bash deploy.sh client   → deploys Windows 11 client
# ============================================================

# ── Shared config ─────────────────────────────────────────────
RESOURCE_GROUP="rg-lab-adds"
LOCATION="eastus"
TEMPLATE="$(dirname "$0")/deploy-vm.bicep"
ADMIN_USERNAME="labadmin"
ADMIN_PASSWORD=""          # Fill in — never commit
ALLOW_RDP_FROM_IP=""       # Your public IP — curl ifconfig.me

# ── VM profiles ───────────────────────────────────────────────
deploy_dc() {
  echo "Deploying Domain Controller VM..."
  az deployment group create \
    --resource-group  "$RESOURCE_GROUP" \
    --template-file   "$TEMPLATE" \
    --name            "deploy-dc-$(date +%Y%m%d%H%M%S)" \
    --parameters \
        vmName="lab-dc-01" \
        adminUsername="$ADMIN_USERNAME" \
        adminPassword="$ADMIN_PASSWORD" \
        allowRdpFromIp="$ALLOW_RDP_FROM_IP" \
        privateIpAddress="10.0.1.4" \
        imagePublisher="MicrosoftWindowsServer" \
        imageOffer="WindowsServer" \
        imageSku="2022-datacenter-azure-edition" \
        vmSize="Standard_D2als_v7" \
        autoShutdownTime="1900"
}

deploy_client() {
  echo "Deploying Windows 11 Client VM..."
  az deployment group create \
    --resource-group  "$RESOURCE_GROUP" \
    --template-file   "$TEMPLATE" \
    --name            "deploy-client-$(date +%Y%m%d%H%M%S)" \
    --parameters \
        vmName="lab-client-01" \
        adminUsername="$ADMIN_USERNAME" \
        adminPassword="$ADMIN_PASSWORD" \
        allowRdpFromIp="$ALLOW_RDP_FROM_IP" \
        privateIpAddress="10.0.1.5" \
        imagePublisher="MicrosoftWindowsDesktop" \
        imageOffer="Windows-11" \
        imageSku="win11-24h2-pro" \
        vmSize="Standard_D2als_v7" \
        autoShutdownTime="1900"
}

# ── Safety checks ─────────────────────────────────────────────
if [ -z "$ADMIN_PASSWORD" ] || [ -z "$ALLOW_RDP_FROM_IP" ]; then
  echo "ERROR: Fill in ADMIN_PASSWORD and ALLOW_RDP_FROM_IP before running"
  exit 1
fi

# ── Create resource group if needed ───────────────────────────
echo "Ensuring resource group exists: $RESOURCE_GROUP"
az group create \
  --name     "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output   none

# ── Route to correct VM profile ───────────────────────────────
case "$1" in
  dc)
    deploy_dc
    ;;
  client)
    deploy_client
    ;;
  *)
    echo "Usage: bash deploy.sh [dc|client]"
    echo ""
    echo "  dc      → Windows Server 2022 Domain Controller (10.0.1.4)"
    echo "  client  → Windows 11 Pro Client (10.0.1.5)"
    exit 1
    ;;
esac

echo ""
echo "Done. Check outputs above for public IP and RDP command."