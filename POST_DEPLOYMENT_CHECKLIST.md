# Azure Post-Deployment Readiness Checklist
## Infrastructure: vm-app | vm-db | vm-win | Azure Bastion Basic
### Deployment Region: eastus | Resource Group: rg-ailab-sathish

**Validation Date:** ___________  
**Validated By:** ___________  
**Deployment Status:** ☐ READY FOR PRODUCTION | ☐ BLOCKED - ISSUES FOUND

---

## ⚠️ SECURITY CHECKS (Priority: CRITICAL)

### Check 1: NSG — SSH Access Restricted to Bastion Subnet Only
**Category:** SECURITY  
**Check:** Verify SSH rule on app subnet NSG blocks all sources except Bastion (10.0.3.0/27)

**Command:**
```bash
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --name "AllowSSH" \
  --query "{Name:name, SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange, Access:access}" \
  -o table
```

**Expected:**
```
Name      SourcePrefix    DestPort    Access
--------  ---------------  ----------  --------
AllowSSH  10.0.3.0/27      22          Allow
```

**Tower Note:** SSH is the primary access vector to Linux compute. Restricting to Bastion-only eliminates direct internet exposure and enforces jump-host architecture. Misconfiguration here is a critical security breach.

---

### Check 2: NSG — No Public SSH Access (Deny All Others)
**Category:** SECURITY  
**Check:** Confirm no inbound rule allows SSH from 0.0.0.0/0 or internet

**Command:**
```bash
az network nsg rule list \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --query "[?destinationPortRange=='22' || destinationPortRange=='*'].{Name:name, Direction:direction, Access:access, SourcePrefix:sourceAddressPrefix}" \
  -o table
```

**Expected:**
```
Name         Direction    Access    SourcePrefix
-----------  -----------  --------  ----------------
AllowSSH     Inbound      Allow     10.0.3.0/27
DenyAllIn    Inbound      Deny      0.0.0.0/0    (implied default)
```
No rules with `access=Allow` from `0.0.0.0/0` on port 22.

**Tower Note:** Open SSH to the internet is exploitation vector #1. Validation prevents common misconfiguration where rules get added "temporarily" and forgotten.

---

### Check 3: NSG — RDP Access Restricted to Bastion Subnet Only
**Category:** SECURITY  
**Check:** Verify RDP rule on app subnet NSG blocks all sources except Bastion (10.0.3.0/27)

**Command:**
```bash
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --name "AllowRDP" \
  --query "{Name:name, SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange, Access:access}" \
  -o table
```

**Expected:**
```
Name      SourcePrefix    DestPort    Access
--------  ---------------  ----------  --------
AllowRDP  10.0.3.0/27      3389        Allow
```

**Tower Note:** Windows compute access must follow the same restricted model as Linux. RDP is high-value target; Bastion-only ensures audit trail through Azure Bastion logging.

---

### Check 4: NSG — Database PostgreSQL Access Limited to App Subnet
**Category:** SECURITY  
**Check:** Verify PostgreSQL port 5432 on db subnet only allows traffic from app subnet (10.0.1.0/24)

**Command:**
```bash
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-db" \
  --name "AllowPostgres" \
  --query "{Name:name, SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange, Access:access}" \
  -o table
```

**Expected:**
```
Name             SourcePrefix    DestPort    Access
---------------  ---------------  ----------  --------
AllowPostgres    10.0.1.0/24      5432        Allow
```

**Tower Note:** Database isolation is fundamental to defense-in-depth. Only app-tier should reach DB. Prevents lateral movement if app VM is compromised.

---

### Check 5: Network Interfaces — No Public IP on Any VM
**Category:** SECURITY  
**Check:** Confirm vm-app, vm-db, vm-win NICs have no public IP assignments

**Command:**
```bash
az network nic show \
  --resource-group "rg-ailab-sathish" \
  --name "nic-app" \
  --query "ipConfigurations[].publicIpAddress" \
  -o json
```

**Expected:**
```json
[null]
```

Repeat for `nic-db` and `nic-win` — all should return `[null]`

**Command (verify all at once):**
```bash
for nic in nic-app nic-db nic-win; do
  echo "=== $nic ===" 
  az network nic show \
    --resource-group "rg-ailab-sathish" \
    --name "$nic" \
    --query "ipConfigurations[0].publicIpAddress" 2>/dev/null || echo "NONE"
done
```

**Expected:**
```
=== nic-app === 
NONE
=== nic-db === 
NONE
=== nic-win === 
NONE
```

**Tower Note:** Public IPs defeat Bastion architecture. Detection prevents accidental exposure and ensures all access flows through audited jump host.

---

### Check 6: Azure Bastion — Service Active and Ready
**Category:** SECURITY | CONNECTIVITY  
**Check:** Verify Bastion host is deployed, provisioned, and available

**Command:**
```bash
az network bastion show \
  --resource-group "rg-ailab-sathish" \
  --name "bastion-ailab" \
  --query "{Name:name, Sku:sku.name, State:provisioningState, PublicIP:ipConfigurations[0].publicIpAddress}" \
  -o table
```

**Expected:**
```
Name            Sku      State       PublicIP
--------------  -------  ----------  -----------------
bastion-ailab   Basic    Succeeded   1.2.3.4 (real IP)
```
`State=Succeeded` and a public IP assigned.

**Tower Note:** Bastion is the **single point of access**. Failure here blocks all connectivity. Validation before relying on it prevents access lockout.

---

### Check 7: Storage Account — Encryption at Rest (Default)
**Category:** SECURITY  
**Check:** Confirm storage account uses Azure-managed encryption (default for StorageV2)

**Command:**
```bash
az storage account show \
  --resource-group "rg-ailab-sathish" \
  --name "stailab-sathish" \
  --query "{Name:name, Kind:kind, Encryption:encryption.services.blob.enabled}" \
  -o table
```

**Expected:**
```
Name                    Kind       Encryption
----------------------  ---------  ----------
stailab{name}           StorageV2  true
```

**Tower Note:** Boot diagnostics and VM logs stored here. Default encryption is sufficient for lab; production requires customer-managed keys (CMK).

---

### Check 8: Storage Account — Soft Delete Enabled (7 days)
**Category:** SECURITY | BACKUP  
**Check:** Verify blob soft-delete policy is enabled with 7-day retention

**Command:**
```bash
az storage account blob-service-properties show \
  --resource-group "rg-ailab-sathish" \
  --account-name "stailab-sathish" \
  --query "deleteRetentionPolicy" \
  -o json
```

**Expected:**
```json
{
  "days": 7,
  "enabled": true
}
```

**Tower Note:** Soft delete protects against accidental/malicious blob deletion. 7-day window allows recovery of boot diagnostics and VM logs in case of incident investigation needs.

---

## 🔗 CONNECTIVITY CHECKS (Priority: CRITICAL)

### Check 9: VM Network Connectivity — App VM Can Reach Database VM
**Category:** CONNECTIVITY  
**Check:** From vm-app, verify TCP connectivity to vm-db on PostgreSQL port 5432

**Command (run via Bastion to vm-app):**
```bash
# Via Bastion connection to vm-app
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10

# Once on vm-app, run:
nc -zv 10.0.2.10 5432
```

**Expected:**
```
Connection to 10.0.2.10 5432 port [tcp/*] succeeded!
```

**Alternative (if nc unavailable):**
```bash
# Check DNS resolution
nslookup vm-db.internal.cloudapp.net
ping -c 1 10.0.2.10
telnet 10.0.2.10 5432
```

**Tower Note:** This validates network routing and NSG rules are correctly applied. Fails if subnets are misconfigured or routes are missing. Critical for app-to-DB communication.

---

### Check 10: Azure Bastion Connection Test — Linux VM
**Category:** CONNECTIVITY  
**Check:** Attempt SSH connection to vm-app via Azure Bastion in portal or CLI

**Command:**
```bash
# Verify Bastion can route to app VM
az network bastion ssh \
  --resource-group "rg-ailab-sathish" \
  --name "bastion-ailab" \
  --target-resource-id "$(az vm show -g rg-ailab-sathish -n vm-app --query id -o tsv)" \
  --username "labadmin"
```

**Expected:**
- SSH session established
- Shell prompt: `labadmin@vm-app:~$`

**Tower Note:** Bastion is sole access path. Failure here means entire infrastructure is unreachable. Must validate before declaring deployment complete.

---

### Check 11: Azure Bastion Connection Test — Windows VM
**Category:** CONNECTIVITY  
**Check:** Attempt RDP connection to vm-win via Azure Bastion

**Command:**
```bash
# Verify Bastion can route to Windows VM
az network bastion rdp \
  --resource-group "rg-ailab-sathish" \
  --name "bastion-ailab" \
  --target-resource-id "$(az vm show -g rg-ailab-sathish -n vm-win --query id -o tsv)" \
  --username "labadmin"
```

**Expected:**
- RDP file downloaded or connection established
- Windows logon successful

**Tower Note:** Validates Windows compute path through Bastion. Different protocol from Linux; separate validation ensures both paths are functional.

---

### Check 12: Subnet Routing — Verify UDRs Not Interfering
**Category:** CONNECTIVITY  
**Check:** Confirm no user-defined routes (UDRs) on app/db subnets that block inter-subnet traffic

**Command:**
```bash
az network route-table list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, ID:id}" \
  -o table
```

**Expected:**
```
(Empty table — no custom route tables)
```

If route tables exist, verify no 0.0.0.0/0 or 10.0.x.x routes block VNET routes.

**Tower Note:** Default system routes allow intra-VNET communication. Custom routes can silently break connectivity. Absence of UDRs in this deployment is expected; their presence requires explicit validation.

---

### Check 13: VM Boot Diagnostics — Storage Connection Active
**Category:** CONNECTIVITY | MONITORING  
**Check:** Verify all three VMs can write to storage account for boot diagnostics

**Command:**
```bash
# Check if boot diagnostics URI is configured
for vm in vm-app vm-db vm-win; do
  echo "=== $vm ===" 
  az vm get-instance-view \
    --resource-group "rg-ailab-sathish" \
    --name "$vm" \
    --query "bootDiagnostics" \
    -o json
done
```

**Expected:**
```json
{
  "enabled": true,
  "storageUri": "https://stailabsathish.blob.core.windows.net/"
}
```

**Tower Note:** Boot diagnostics must be active for troubleshooting VM startup issues. Storage connection failure is silent but means no logs are captured on failures.

---

## 📊 MONITORING & PERFORMANCE CHECKS

### Check 14: VM Performance Metrics Available
**Category:** MONITORING | PERFORMANCE  
**Check:** Verify Azure Monitor metrics are flowing for all VMs (CPU, network, disk)

**Command:**
```bash
# Get CPU percentage metric for vm-app in last hour
az monitor metrics list \
  --resource-group "rg-ailab-sathish" \
  --resource-type "Microsoft.Compute/virtualMachines" \
  --resource-names "vm-app" \
  --metric "Percentage CPU" \
  --start-time "$(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
  --interval "PT5M" \
  --aggregation "Average" \
  --query "value[0].timeseries[:2]"
```

**Expected:**
```
Array with 1+ metric data points with timestamp and value entries
```

Repeat for `vm-db` and `vm-win`.

**Tower Note:** Metrics visibility is prerequisite for incident response. If metrics don't arrive within 5–10 minutes of deployment, diagnostic pipeline is broken.

---

### Check 15: Auto-Shutdown Schedules Active
**Category:** MONITORING | PERFORMANCE  
**Check:** Confirm auto-shutdown is configured for all VMs at 08:00 UTC daily (cost control)

**Command:**
```bash
for vm in vm-app vm-db vm-win; do
  echo "=== $vm ===" 
  az vm auto-shutdown-schedule show \
    --resource-group "rg-ailab-sathish" \
    --name "$vm" \
    --query "{Enabled:enabled, Time:dailyRecurrenceTime, Timezone:timezone}" \
    -o table
done
```

**Expected:**
```
=== vm-app === 
Enabled    Time    Timezone
---------  ------  --------
True       0800    UTC

=== vm-db === 
...same...

=== vm-win === 
...same...
```

**Tower Note:** Auto-shutdown prevents runaway compute costs. This is a cost-control baseline, not a security measure, but missing schedules can inflate cloud bills rapidly.

---

### Check 16: PostgreSQL Service Status on vm-db
**Category:** MONITORING | PERFORMANCE  
**Check:** Verify PostgreSQL 14 is installed, running, and configured correctly

**Command (run on vm-db via Bastion):**
```bash
ssh -J labadmin@10.0.3.0 labadmin@10.0.2.10

# Once connected to vm-db:
sudo systemctl status postgresql --no-pager
```

**Expected:**
```
● postgresql.service - PostgreSQL RDBMS
     Loaded: loaded (/lib/systemd/system/postgresql.service; enabled; vendor preset: enabled)
     Active: active (exited) since [date]; [uptime]
```

**Verify database and user created:**
```bash
sudo -u postgres psql -c "\du"  # List users
sudo -u postgres psql -c "\l"   # List databases
```

**Expected:**
```
                            List of roles
 Role name |                         Attributes                          | Member of
-----------+----------------------------------------------------------+-----------
 labuser   |                                                              | {}
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
```

**Tower Note:** cloud-init script initializes database on first boot. Failure indicates custom data injection failed—a common source of deployment issues.

---

### Check 17: Disk Space on All VMs
**Category:** PERFORMANCE | MONITORING  
**Check:** Confirm adequate free disk space (>50% available) on OS disks

**Command (run on each VM via Bastion):**
```bash
# On vm-app and vm-db (Linux):
df -h / | tail -1

# On vm-win (Windows PowerShell):
Get-Volume -DriveLetter C | select Size, SizeRemaining
```

**Expected (Linux):**
```
/dev/sda1        30G   8.5G  19.5G  31% /
```
≥50% available (here: 69% free is PASS).

**Expected (Windows):**
```
Size          SizeRemaining
----          ---------------
128GB         100GB+
```

**Tower Note:** Disk pressure causes VM performance degradation and application failures. Terraform provisions 30GB Linux, 128GB Windows; adequate for base OS but monitoring growth is critical.

---

## ✅ BACKUP & DISASTER RECOVERY CHECKS

### Check 18: Storage Account Soft-Delete Container Policy
**Category:** BACKUP  
**Check:** Verify container-level soft delete enabled (complements blob soft delete)

**Command:**
```bash
az storage account blob-service-properties show \
  --resource-group "rg-ailab-sathish" \
  --account-name "stailab-sathish" \
  --query "containerDeleteRetentionPolicy" \
  -o json
```

**Expected:**
```json
{
  "days": 7,
  "enabled": true
}
```

**Tower Note:** Container soft delete prevents accidental deletion of entire containers. Combined with blob soft delete, provides defense against ransomware scenarios.

---

### Check 19: Snapshot Capability Verified
**Category:** BACKUP  
**Check:** Confirm managed disks support snapshots (prerequisite for backup strategy)

**Command:**
```bash
# List managed disks attached to VMs
az disk list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, Size:diskSizeGb, Tier:sku.tier, State:diskState}" \
  -o table
```

**Expected:**
```
Name                    Size    Tier      State
----------------------  ------  --------  -------
vm-app_OsDisk_1         30      Standard  Attached
vm-db_OsDisk_1          30      Standard  Attached
vm-win_OsDisk_1         128     Standard  Attached
```

**Tower Note:** Managed disks are snapshottable. Ensure no legacy unmanaged disks. Compute team responsibility to initiate backup policies; validation confirms foundation is present.

---

## 🔐 COMPLIANCE & AUDIT CHECKS

### Check 20: Resource Tags Applied
**Category:** SECURITY | MONITORING  
**Check:** Verify all resources tagged with owner per Terraform locals

**Command:**
```bash
# Check tags on resource group
az group show \
  --name "rg-ailab-sathish" \
  --query "tags" \
  -o json

# Check tags on VMs
for vm in vm-app vm-db vm-win; do
  echo "=== $vm ===" 
  az vm show \
    --resource-group "rg-ailab-sathish" \
    --name "$vm" \
    --query "tags" \
    -o json
done
```

**Expected:**
```json
{
  "owner": "sathish"
}
```

**Tower Note:** Tags enable cost allocation, automated shutdowns, and compliance audits. Missing tags indicate infrastructure deployed outside version control—potential governance gap.

---

## FINAL VALIDATION SUMMARY

| Category | Checks | Status | Issues Found |
|----------|--------|--------|-------------|
| SECURITY | 8 | ☐ PASS / ☐ BLOCK | |
| CONNECTIVITY | 5 | ☐ PASS / ☐ BLOCK | |
| MONITORING | 3 | ☐ PASS / ☐ BLOCK | |
| BACKUP | 2 | ☐ PASS / ☐ BLOCK | |
| COMPLIANCE | 2 | ☐ PASS / ☐ BLOCK | |

### Deployment Sign-Off
- [ ] All 20 checks executed
- [ ] No SECURITY checks blocked
- [ ] No CONNECTIVITY checks blocked  
- [ ] Issues documented in Jira/ServiceNow ticket
- [ ] Stakeholders notified of production readiness

**Approved for Production:** ☐ YES | ☐ NO  
**By:** _________________  
**Date:** _________________

---

## TROUBLESHOOTING REFERENCE

### If Bastion Connectivity Fails
1. Verify Bastion public IP is assigned: `az network public-ip show -g rg-ailab-sathish -n pip-bastion`
2. Check Bastion NSG allows 443 (HTTPS) outbound from Bastion subnet
3. Confirm VM subnet NSG allows traffic from Bastion subnet (10.0.3.0/27)

### If PostgreSQL Connection Fails
1. SSH to vm-db and run: `sudo systemctl status postgresql`
2. Check listen address: `sudo -u postgres psql -c "SHOW listen_addresses;"`
3. Should be: `10.0.2.10` (or `*` if all interfaces OK)
4. Verify pg_hba.conf allows app subnet: `sudo cat /etc/postgresql/14/main/pg_hba.conf | grep 10.0.1`

### If Storage Account Unreachable
1. Verify NSG allows outbound on 443 to Azure Storage service tag
2. Check firewall rules on storage account (should allow all networks if not configured)
3. Verify managed identity (if used) has Storage Blob Data Contributor role

### If Metrics Not Appearing
1. Wait 5–10 minutes after VM creation
2. Verify Log Analytics agent is deployed (check Extensions on VM blade)
3. Confirm VM has managed identity with Reader role on resource group

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-16  
**Next Review:** Post-deployment + 7 days
