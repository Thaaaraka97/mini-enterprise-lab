# Troubleshooting log

22 blockers encountered and resolved during this build.
Full documented log available in the session summary.

## Key lessons

- Domain unjoin and rejoin each require a full reboot — cannot be combined
- Always add hosts file entry before domain join in Azure VNets
- NetBIOS is unreliable in cloud environments — use explicit DC hostname
- Kerberos requires clock sync within 5 minutes — add startup time sync task
- NSG allow-all from internal subnet is cleaner than per-port AD rules
- Portal UI access does not equal service entitlement — verify in Billing
- Intune compliance policies require scheduledActionsForRule in API calls
- Use Invoke-MgGraphRequest for assignments when Graph cmdlets fail