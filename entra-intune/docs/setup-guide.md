# Entra ID + Intune — setup guide

Step-by-step instructions to reproduce the cloud environment from scratch. Written for someone who has never seen this environment before. Follow each step in order — skipping ahead will cause failures.

---

## Prerequisites

Before starting, confirm you have:

- An Azure free account or Pay-As-You-Go subscription
- A Microsoft Entra tenant (created automatically during Azure signup)
- Entra ID P2 trial activated — portal.azure.com → Microsoft Entra ID → Licences → Try/Buy
- Microsoft Intune trial activated — intune.microsoft.com → start trial
- Ubuntu 22.04+ or any Linux/macOS machine (Windows also works)
- PowerShell 7+ installed

```bash
# Install PowerShell 7 on Ubuntu
sudo snap install powershell --classic
pwsh --version
```

- Microsoft.Graph module installed

```powershell
# Inside pwsh
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Get-Module Microsoft.Graph -ListAvailable | Select-Object Name, Version -First 1
```

- Azure CLI installed

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version
```

- GitHub account with a PAT token (repo scope) for pushing commits

---

## Important — account separation

The Azure signup creates two accounts:

- Personal Microsoft account (`@outlook.com`, `@hotmail.com`) — used to log into the Developer Program or Azure signup page only
- Work/school account (`admin@yourtenantname.onmicrosoft.com`) — used for ALL admin portals

Always use the `onmicrosoft.com` account for:
- admin.microsoft.com
- entra.microsoft.com
- intune.microsoft.com
- portal.azure.com (switch accounts if needed)

Never use your personal account for admin portals — it will always be rejected.

---

## Step 1 — Clone the repo and configure secrets

```bash
git clone https://github.com/YOURUSERNAME/mini-enterprise-lab.git
cd mini-enterprise-lab

# Create your local config file from the template
cp lab.config.template.ps1 lab.config.ps1

# Fill in your values
nano lab.config.ps1
```

Fill in these values in `lab.config.ps1`:

```powershell
$TenantDomain    = "yourtenantname.onmicrosoft.com"
$TenantId        = "your-tenant-id-guid"
$AdminUPN        = "admin@yourtenantname.onmicrosoft.com"
$UsageLocation   = "CA"          # Two-letter country code
$DefaultPassword = "LabUser@2024!"
```

To find your Tenant ID: portal.azure.com → Microsoft Entra ID → Overview → Tenant ID field.

---

## Step 2 — Disable Security Defaults

Security Defaults conflicts with custom Conditional Access policies. Disable it first.

1. Go to **entra.microsoft.com**
2. Left menu → **Identity → Overview → Properties**
3. Scroll to bottom → **Manage security defaults**
4. Toggle to **Disabled**
5. Reason: My organization is using Conditional Access
6. Click **Save**

---

## Step 3 — Connect to Microsoft Graph

```powershell
# Open pwsh
pwsh

# Connect with all required scopes
Connect-MgGraph -Scopes `
    "User.ReadWrite.All",`
    "Group.ReadWrite.All",`
    "Policy.ReadWrite.ConditionalAccess",`
    "Policy.Read.All",`
    "RoleManagement.ReadWrite.Directory",`
    "Directory.ReadWrite.All",`
    "DeviceManagementConfiguration.ReadWrite.All"

# Verify correct tenant
Get-MgContext | Select-Object Account, TenantId
```

Confirm the TenantId matches your tenant before running any scripts.

---

## Step 4 — Create users

```powershell
./entra-intune/scripts/create-users.ps1
```

Expected output:
```
CREATE alex.morgan@yourtenantname.onmicrosoft.com [IT]
CREATE jordan.blake@yourtenantname.onmicrosoft.com [IT]
CREATE taylor.reed@yourtenantname.onmicrosoft.com [HR]
CREATE morgan.ellis@yourtenantname.onmicrosoft.com [HR]
CREATE casey.quinn@yourtenantname.onmicrosoft.com [HR]
CREATE riley.grant@yourtenantname.onmicrosoft.com [Finance]
CREATE avery.stone@yourtenantname.onmicrosoft.com [Finance]
CREATE drew.hale@yourtenantname.onmicrosoft.com [Finance]

Done. Created: 8 | Skipped: 0
```

Verify: entra.microsoft.com → Users → All users — 8 users visible.

---

## Step 5 — Create groups

```powershell
./entra-intune/scripts/create-groups.ps1
```

Expected output:

```
CREATE GRP-IT
CREATE GRP-HR
CREATE GRP-Finance
```

---

## Step 6 — Assign group members

```powershell
./entra-intune/scripts/add-group-members.ps1
```

Expected output:

```
Processing GRP-IT → department: IT

alex.morgan → GRP-IT
jordan.blake → GRP-IT
Added: 2 | Skipped: 0

Processing GRP-HR → department: HR
```

Verify: entra.microsoft.com → Groups → select each group → Members tab.

---

## Step 7 — Assign RBAC roles

```powershell
# Reconnect with role management scope
Disconnect-MgGraph
Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory","User.Read.All"

./entra-intune/scripts/assign-roles.ps1
```
Expected output:

```
ASSIGN alex.morgan@... → Global Reader
ASSIGN jordan.blake@... → Helpdesk Administrator
```


Verify in portal: click each user → Assigned roles tab.

Test Global Reader (alex.morgan):
- Sign into entra.microsoft.com as alex.morgan
- Can view users — cannot create or modify

Test Helpdesk Admin (jordan.blake):
- Sign in as jordan.blake
- Can reset passwords — cannot assign roles

---

## Step 8 — Create Conditional Access policies

```powershell
Disconnect-MgGraph
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","User.Read.All"

./entra-intune/scripts/conditional-access.ps1
```

Expected output:
```
INFO Admin resolved → admin@yourtenantname.onmicrosoft.com (guid)
CREATE CA001-Block-Legacy-Authentication
CREATE CA002-Require-MFA-All-Users
Both policies created in report-only mode.
```

Verify:
1. entra.microsoft.com → Protection → Conditional Access → Policies
2. Both policies visible with status Report-only
3. Sign in as taylor.reed → check sign-in logs → CA tab shows both policies evaluated

---

## Step 9 — Create Intune policies

```powershell
Disconnect-MgGraph
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

./entra-intune/scripts/intune-policies.ps1
```

Verify:
1. intune.microsoft.com → Devices → Compliance → POL-Compliance-Windows11 visible
2. intune.microsoft.com → Devices → Configuration → CFG-Windows11-Baseline visible
3. Both assigned to All devices

---

## Step 10 — Enroll a Windows device

1. On a Windows 11 machine go to **Settings → Accounts → Access work or school**
2. Click **+ Connect**
3. Enter your `onmicrosoft.com` admin account
4. Complete sign-in

Verify: intune.microsoft.com → Devices → All devices → device appears.

---

## Verification checklist

| Item | How to verify |
|---|---|
| 8 users created | entra.microsoft.com → Users → All users |
| 3 groups with members | entra.microsoft.com → Groups → each group → Members |
| Global Reader assigned | alex.morgan → Assigned roles |
| Helpdesk Admin assigned | jordan.blake → Assigned roles |
| CA001 exists | Conditional Access → Policies |
| CA002 exists | Conditional Access → Policies |
| CA policies evaluated | Sign-in logs → CA tab |
| Compliance policy exists | Intune → Devices → Compliance |
| Config profile exists | Intune → Devices → Configuration |
| Device enrolled | Intune → Devices → All devices |

---

## Teardown

To remove all lab resources from your tenant:

```powershell
# Connect with full scopes
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Policy.ReadWrite.ConditionalAccess","RoleManagement.ReadWrite.Directory"

# Remove CA policies
Get-MgIdentityConditionalAccessPolicy -All |
    Where-Object { $_.DisplayName -like "CA00*" } |
    ForEach-Object { Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $_.Id }

# Remove groups
Get-MgGroup -All | Where-Object { $_.DisplayName -like "GRP-*" } |
    ForEach-Object { Remove-MgGroup -GroupId $_.Id }

# Remove users
$users = @("alex.morgan","jordan.blake","taylor.reed","morgan.ellis",
           "casey.quinn","riley.grant","avery.stone","drew.hale")
foreach ($u in $users) {
    $upn = "$u@$TenantDomain"
    $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($user) { Remove-MgUser -UserId $user.Id }
}
```