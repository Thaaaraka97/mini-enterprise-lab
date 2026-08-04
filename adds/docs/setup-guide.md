# AD DS — setup guide

Step-by-step instructions to reproduce the on-premises Active Directory environment hosted on Azure. Follow each step in order — the scripts depend on each other and must be run sequentially.

---

## Prerequisites

- Azure subscription with Owner role assigned
- Azure CLI installed and authenticated

```bash
az login
az account show  # confirm correct subscription
```

- Remmina RDP client (Ubuntu)

```bash
sudo apt install remmina remmina-plugin-rdp -y
```

- Your public IP address

```bash
curl ifconfig.me
```

---

## Step 1 — Configure deployment wrapper

```bash
cd ~/mini-enterprise-lab/adds/bicep

# Copy template and fill in values
cp deploy.template.sh deploy.sh
nano deploy.sh
```

Fill in:

```bash
ADMIN_PASSWORD="YourStrongPassword@2024"
ALLOW_RDP_FROM_IP="your.public.ip.here"  # from curl ifconfig.me
```

---

## Step 2 — Deploy Domain Controller VM

```bash
bash ~/mini-enterprise-lab/adds/bicep/deploy.sh dc
```

This deploys:
- Resource group: `rg-lab-adds`
- VNet: `lab-vnet-adds` (10.0.0.0/16)
- Subnet: `snet-dc` (10.0.1.0/24)
- NSG: RDP from your IP only + internal subnet allow-all
- VM: `lab-dc-01` Windows Server 2022, static IP 10.0.1.4
- Auto-shutdown: 7PM Eastern daily

Expected output ends with:

```
"provisioningState": "Succeeded"
```

Get the public IP:
```bash
az vm show \
    --resource-group rg-lab-adds \
    --name lab-dc-01 \
    --show-details \
    --query publicIps \
    --output tsv
```

---

## Step 3 — RDP into DC and install AD DS

Open Remmina → new RDP connection:
- Server: DC public IP
- Username: `labadmin`
- Password: your VM password

Once connected, open PowerShell as Administrator and run:

```powershell
New-Item -ItemType Directory -Path C:\Scripts -Force
```

Copy `adds/scripts/install-ad.ps1` content into `C:\Scripts\install-ad.ps1` then run:

```powershell
Set-ExecutionPolicy RemoteSigned -Force
& "C:\Scripts\install-ad.ps1"
```

The script prompts for the DSRM (Safe Mode) password — enter and confirm a strong password and save it somewhere safe. The server reboots automatically.

Wait 3-5 minutes then RDP back in as `CORP\labadmin`.

Verify:
```powershell
Get-ADDomain
Get-Service adws,kdc,netlogon,dns | Select-Object Name, Status
Resolve-DnsName corp.local
```

All four services should show Running. DNS should resolve to 10.0.1.4.

---

## Step 4 — Create OU structure, users and groups

Copy `adds/scripts/create-ou.ps1` to `C:\Scripts\create-ou.ps1` then run:

```powershell
& "C:\Scripts\create-ou.ps1"
```

Expected output:

```
CREATE OU=IT
CREATE OU=HR
CREATE OU=Finance
CREATE alex.morgan in OU=IT
...
CREATE GRP-IT
CREATE GRP-HR
CREATE GRP-Finance
CREATE GRP-Helpdesk
DELEGATE GRP-Helpdesk -> Reset Password on OU=HR
```

Verify in Active Directory Users and Computers:
- Server Manager → Tools → Active Directory Users and Computers
- Expand corp.local — three OUs visible
- Each OU contains users and a group

Test delegation:
```powershell
# jordan.blake should be able to reset taylor.reed's password
Set-ADAccountPassword -Identity "taylor.reed" `
    -NewPassword (ConvertTo-SecureString "NewPass@2024!" -AsPlainText -Force) -Reset
```

---

## Step 5 — Create Group Policy objects

Copy `adds/scripts/gpo-config.ps1` to `C:\Scripts\gpo-config.ps1` then run:

```powershell
& "C:\Scripts\gpo-config.ps1"
```

Expected output:

```
SET Domain password policy
CREATE + LINK GPO-Login-Banner -> corp.local
CREATE GPO-Lock-Screen
LINK GPO-Lock-Screen -> OU=IT
LINK GPO-Lock-Screen -> OU=HR
LINK GPO-Lock-Screen -> OU=Finance
CREATE + LINK GPO-USB-Restriction -> OU=Finance
```

Verify login banner immediately — lock the DC and log back in. The banner should appear before the login screen.

Verify password policy:
```powershell
Get-ADDefaultDomainPasswordPolicy -Identity "corp.local" |
    Select-Object MinPasswordLength, ComplexityEnabled, MaxPasswordAge, LockoutThreshold
```

---

## Step 6 — Deploy client VM

Back on Ubuntu:

```bash
bash ~/mini-enterprise-lab/adds/bicep/deploy.sh client
```

This deploys a Windows 11 Pro VM at static IP 10.0.1.5 in the same VNet as the DC.

---

## Step 7 — Domain join client VM

RDP into client VM as `labadmin`. Open PowerShell as Administrator:

```powershell
# Step 1 — Set DNS to DC
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "10.0.1.4"

# Step 2 — Add hosts entry
Add-Content "C:\Windows\System32\drivers\etc\hosts" "10.0.1.4 lab-dc-01.corp.local lab-dc-01"

# Step 3 — Flush DNS and verify
ipconfig /flushdns
Resolve-DnsName corp.local   # must return 10.0.1.4 before proceeding

# Step 4 — Disable firewall temporarily
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Step 5 — Join domain (GUI recommended)
# Settings → System → About → Domain or workgroup → Change
# Domain: corp.local
# Username: CORP\labadmin
# Password: your VM password
# Restart when prompted
```

After restart, log back in as `CORP\labadmin` then:

```powershell
# Add domain users to RDP
net localgroup "Remote Desktop Users" "CORP\Domain Users" /add

# Disable force password change on all users
$users = @("taylor.reed","morgan.ellis","casey.quinn",
           "riley.grant","avery.stone","drew.hale",
           "alex.morgan","jordan.blake")
foreach ($u in $users) {
    Set-ADAccountPassword -Identity $u `
        -NewPassword (ConvertTo-SecureString "LabUser@2024!" -AsPlainText -Force) -Reset
    Set-ADUser -Identity $u -ChangePasswordAtLogon $false
}
```

---

## Step 8 — Verify GPOs on client

RDP into client as a domain user (e.g. `CORP\taylor.reed` / `LabUser@2024!`):

```powershell
# Force GPO refresh
gpupdate /force

# Show all applied GPOs
gpresult /r
```

Look for in Applied Group Policy Objects:
- `GPO-Login-Banner` ✓
- `GPO-Lock-Screen` ✓

For Finance users (`riley.grant`) also verify:
- `GPO-USB-Restriction` appears in gpresult

---

## Verification checklist

| Item | How to verify |
|---|---|
| Forest promoted | Get-ADDomain returns corp.local |
| DNS working | Resolve-DnsName corp.local returns 10.0.1.4 |
| All AD services running | Get-Service adws,kdc,netlogon,dns |
| 3 OUs created | Active Directory Users and Computers |
| 8 users in correct OUs | ADUC → expand each OU |
| 4 groups created | ADUC → each OU |
| Helpdesk delegation | jordan.blake resets taylor.reed password |
| Login banner | Visible on DC and client login |
| Password policy | Get-ADDefaultDomainPasswordPolicy |
| GPOs applied on client | gpresult /r shows GPO-Lock-Screen |
| Client domain joined | ADUC → Computers container or OU=IT |

---

## Cost management

Stop VMs when not in use to conserve Azure credits:

```bash
# Stop DC
az vm deallocate --resource-group rg-lab-adds --name lab-dc-01

# Stop client
az vm deallocate --resource-group rg-lab-adds --name lab-client-01

# Start DC
az vm start --resource-group rg-lab-adds --name lab-dc-01

# Start client
az vm start --resource-group rg-lab-adds --name lab-client-01
```

Auto-shutdown at 7PM Eastern is configured on both VMs via the Bicep template.

---

## Teardown

```bash
# Delete entire resource group — removes all VMs, disks, NICs, NSGs, VNet
az group delete --name rg-lab-adds --yes
```

To rebuild from scratch after teardown, start from Step 1.