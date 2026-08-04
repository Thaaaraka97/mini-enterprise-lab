# AD DS — architecture decisions

This document explains the design choices made in the on-premises Active Directory environment hosted on Azure. Each decision reflects a real trade-off that comes up in enterprise environments.

---

## 1. Why corp.local instead of a routable domain name

**Decision:** Used `corp.local` as the forest root domain name.

**Reasoning:** A `.local` suffix is a non-routable internal name — it has no presence on the public internet and cannot conflict with any external DNS zone. Simple to set up, no domain ownership required, no public DNS configuration needed.

**Trade-off:** `.local` names cannot be used with Microsoft Entra Connect for hybrid sync without additional configuration. Entra Connect requires a routable UPN suffix that matches a verified domain in Entra ID. To enable hybrid sync with `corp.local`, you add a routable UPN suffix (e.g. `yourdomain.com`) in AD Domains and Trusts, then assign it to users before syncing.

**Production preference:** A routable subdomain like `ad.yourdomain.com` or `internal.yourdomain.com` is the recommended approach for new AD DS deployments. It enables seamless Entra Connect integration, supports future cloud expansion, and avoids the UPN suffix workaround entirely.

---

## 2. Why a single domain controller

**Decision:** One DC (`lab-dc-01`) holds all five FSMO roles — Schema Master, Domain Naming Master, PDC Emulator, RID Pool Manager, Infrastructure Master.

**Reasoning:** A single DC is sufficient for a lab environment with no high availability requirement. All FSMO roles on one machine simplifies the setup — no replication topology to configure, no FSMO transfer procedures to manage.

**Trade-off:** A single DC is a single point of failure. If `lab-dc-01` goes down, the entire domain is unavailable. In production, a minimum of two DCs in different availability zones is standard — one holds the FSMO roles, the second is a read-write replica for redundancy. For Azure-hosted AD DS, Microsoft recommends deploying DCs across two availability zones within the same region.

---

## 3. Why a static private IP for the DC

**Decision:** The DC is assigned static private IP `10.0.1.4` via the Bicep template.

**Reasoning:** DNS is the foundation of Active Directory. Every domain-joined machine points its DNS server at the DC's IP address. If the DC's IP changes — which happens with dynamic allocation when a VM is deallocated and reallocated — every domain-joined machine loses DNS resolution and domain connectivity breaks. A static IP guarantees DNS stability regardless of how many times the VM is stopped and started.

**Trade-off:** Static IP addresses require manual management and documentation. In a large environment with many VMs, static IPs create administrative overhead. The production approach is to use Azure Private DNS zones or DHCP reservations rather than static assignments, but for a single DC a static IP is the simplest reliable solution.

---

## 4. Why the Bicep template is generic and parameterised

**Decision:** `deploy-vm.bicep` is a single generic template. `deploy.sh` passes different parameter sets to deploy the DC or the client VM.

**Reasoning:** A template that only deploys one specific VM is not infrastructure as code — it is a documented manual process. A parameterised template that can deploy any VM in the environment by changing the inputs demonstrates real IaC thinking. It is also more maintainable — changes to the template (adding a new NSG rule, changing disk type) apply to all VM deployments automatically.

**Trade-off:** A generic template requires more upfront design — every VM-specific value must become a parameter. The complexity is worth it because the template is reusable, reviewable, and version-controlled. Anyone can clone the repo and deploy the same infrastructure by filling in `deploy.sh`.

---

## 5. Why OU structure mirrors departments

**Decision:** Three OUs — IT, HR, Finance — mirroring the department structure of the user population.

**Reasoning:** OUs are the unit of Group Policy application and administrative delegation. Structuring OUs by department means GPOs can be applied to exactly the right population — the USB restriction applies to Finance users only, not to IT or HR. Delegation can be scoped — Helpdesk can reset passwords in HR without touching IT. A flat structure with all users in one OU would require complex GPO filtering to achieve the same result.

**Trade-off:** A department-based OU structure is simple but inflexible. A role-based structure (e.g. OU=Workstations, OU=Servers, OU=ServiceAccounts) is often preferred in large environments because GPOs more commonly need to target device types than departments. The production approach depends on whether GPOs are primarily user-targeted or computer-targeted.

---

## 6. Why delegation instead of Domain Admin for Helpdesk

**Decision:** GRP-Helpdesk is granted password reset rights on OU=HR only via `dsacls`. They have no rights on IT or Finance OUs.

**Reasoning:** This is the principle of least privilege applied to Active Directory. A helpdesk operator needs to reset passwords for the users they support — they do not need to modify group memberships, create users, or reset passwords for IT administrators. Giving helpdesk Domain Admin rights to solve a password reset problem is a common misconfiguration that creates a significant privilege escalation risk.

**Trade-off:** Delegation requires careful documentation. If a new OU is added, the delegation must be explicitly configured on the new OU — it does not inherit automatically unless the delegation is set at the domain level. In production, delegation is typically managed via a Group Policy or an Identity Governance solution rather than manual `dsacls` commands.

---

## 7. Why Set-ADDefaultDomainPasswordPolicy instead of GPO for password policy

**Decision:** Password policy is set via `Set-ADDefaultDomainPasswordPolicy` directly on the domain object, not via a GPO registry value.

**Reasoning:** GPO registry values for password settings (MinimumPasswordLength etc.) only affect local account passwords on machines that receive the GPO. Domain account passwords in Active Directory are governed by the Default Domain Password Policy stored in the AD domain object itself — not by GPO registry keys. Setting password policy via GPO registry is a common mistake that appears to work but has no effect on domain users.

**Trade-off:** The Default Domain Password Policy applies to all domain users equally. For different password requirements for different groups (e.g. admins require 16 characters, standard users require 12), you need Fine-Grained Password Policies (PSOs) applied to security groups. PSOs are more complex to configure but provide the per-group granularity that the Default Domain Policy cannot.

---

## 8. Why USB restriction targets both logical and physical GUIDs

**Decision:** The GPO-USB-Restriction policy sets `Deny_Write` on both `{53f5630d}` (Removable Disks — logical) and `{53f56311}` (Removable Disk Devices — physical).

**Reasoning:** The storage stack has two layers. Blocking only the logical layer (the drive letter in Explorer) leaves the physical device layer accessible — an attacker with the right tools can write directly to the raw device without going through the filesystem. Blocking only the physical layer has edge cases where some drivers expose the logical volume before the physical block applies. Blocking both layers closes all write paths.

**Trade-off:** Two GUIDs must be maintained and documented. Additional GUIDs exist for other device classes — `{53f56308}` for CD/DVD, `{6AC27878}` for Windows Portable Devices (phones, cameras). A comprehensive removable storage policy in production would include all relevant GUIDs, not just USB flash drives.

---

## 9. Why auto-shutdown is enabled on all VMs

**Decision:** Both VMs have auto-shutdown configured at 7PM Eastern via the Bicep template.

**Reasoning:** Azure charges for VM compute time whether or not the VM is in use. A Standard_D2als_v3 running 24/7 costs approximately $30/month. The same VM running only during active lab sessions (8 hours/day) costs approximately $8/month. Auto-shutdown prevents the common lab mistake of leaving VMs running overnight and consuming the entire Azure free credit in days.

**Trade-off:** Auto-shutdown means the lab is unavailable outside working hours unless VMs are manually started. In production, VMs running AD DS or other infrastructure services must never be auto-shutdown — domain controllers need to be available 24/7 for authentication requests. Auto-shutdown is a lab-only pattern.