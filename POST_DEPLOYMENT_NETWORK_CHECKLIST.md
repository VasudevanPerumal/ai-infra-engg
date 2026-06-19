# Azure Post-Deployment Network Readiness Checklist
## Infrastructure: vm-app | vm-db | vm-win | Azure Bastion Basic
### Network Region: eastus | VNET: vnet-ailab (10.0.0.0/16) | Resource Group: rg-ailab-sathish

**Validation Date:** ___________  
**Validated By:** ___________  
**Network Status:** ☐ READY FOR PRODUCTION | ☐ BLOCKED - ISSUES FOUND

---

## ⚠️ SECURITY CHECKS (Priority: CRITICAL)

### Check 1: VNET Address Space Validation
**Category:** SECURITY | CONNECTIVITY  
**Check:** Verify VNET address space is correctly configured and doesn't overlap with on-premises or peered networks

**Command:**
```bash
az network vnet show \
  --resource-group "rg-ailab-sathish" \
  --name "vnet-ailab" \
  --query "{Name:name, AddressSpace:addressSpace.addressPrefixes[0], Location:location}" \
  -o table
```

**Expected:**
```
Name         AddressSpace    Location
-----------  ---------------  --------
vnet-ailab   10.0.0.0/16      eastus
```

**Tower Note:** VNET address space is the network foundation. Misconfiguration here cascades to all subnets. Critical to validate no overlaps with corporate networks or future peering requirements. A /16 provides 65,536 usable IPs—sufficient for this topology.

---

### Check 2: Subnet Segmentation — App Subnet (10.0.1.0/24)
**Category:** SECURITY | CONNECTIVITY  
**Check:** Verify app subnet exists with correct CIDR and NSG association

**Command:**
```bash
az network vnet subnet show \
  --resource-group "rg-ailab-sathish" \
  --vnet-name "vnet-ailab" \
  --name "snet-app" \
  --query "{Name:name, AddressPrefix:addressPrefix, NSG:networkSecurityGroup.id}" \
  -o table
```

**Expected:**
```
Name       AddressPrefix    NSG
---------  ---------------  /subscriptions/.../nsg-app
snet-app   10.0.1.0/24      (fully populated ID)
```

**Tower Note:** Network segmentation enforces defense-in-depth. App subnet isolation from DB is critical for limiting blast radius if app tier is compromised. /24 provides 254 usable IPs; sufficient for app workloads.

---

### Check 3: Subnet Segmentation — Database Subnet (10.0.2.0/24)
**Category:** SECURITY | CONNECTIVITY  
**Check:** Verify database subnet exists with correct CIDR and NSG association

**Command:**
```bash
az network vnet subnet show \
  --resource-group "rg-ailab-sathish" \
  --vnet-name "vnet-ailab" \
  --name "snet-db" \
  --query "{Name:name, AddressPrefix:addressPrefix, NSG:networkSecurityGroup.id}" \
  -o table
```

**Expected:**
```
Name      AddressPrefix    NSG
--------  ---------------  /subscriptions/.../nsg-db
snet-db   10.0.2.0/24      (fully populated ID)
```

**Tower Note:** Dedicated database subnet enforces network-layer separation. Prevents accidental communication between app and DB outside of NSG rules. Critical network boundary for audit and compliance.

---

### Check 4: Subnet Segmentation — Bastion Subnet (10.0.3.0/27)
**Category:** SECURITY | CONNECTIVITY  
**Check:** Verify Bastion subnet exists with correct CIDR (must be 10.0.3.0/27 minimum per Azure requirement)

**Command:**
```bash
az network vnet subnet show \
  --resource-group "rg-ailab-sathish" \
  --vnet-name "vnet-ailab" \
  --name "AzureBastionSubnet" \
  --query "{Name:name, AddressPrefix:addressPrefix, Purpose:note}" \
  -o table
```

**Expected:**
```
Name                   AddressPrefix    Purpose
---------------------  ---------------  --------
AzureBastionSubnet     10.0.3.0/27      (Bastion subnet)
```

**Tower Note:** Azure Bastion requires minimum /27 subnet. This provides only 30 usable IPs—sufficient for Bastion gateway itself. Smaller subnets cause deployment failures. Non-negotiable network constraint.

---

### Check 5: NSG — App Subnet SSH Rule Source Validation
**Category:** SECURITY  
**Check:** Verify SSH ingress rule restricts source to Bastion subnet (10.0.3.0/27) only

**Command:**
```bash
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --name "AllowSSH" \
  --query "{Name:name, Direction:direction, Protocol:protocol, SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange, Access:access}" \
  -o json
```

**Expected:**
```json
{
  "Name": "AllowSSH",
  "Direction": "Inbound",
  "Protocol": "Tcp",
  "SourcePrefix": "10.0.3.0/27",
  "DestPort": "22",
  "Access": "Allow"
}
```

**Tower Note:** SSH rule scope is network security critical path. Source must be ONLY Bastion subnet (/27), not 0.0.0.0/0 or any larger CIDR. This is foundational to zero-trust access model. Rule priority and any deny rules also matter.

---

### Check 6: NSG — App Subnet RDP Rule Source Validation
**Category:** SECURITY  
**Check:** Verify RDP ingress rule restricts source to Bastion subnet (10.0.3.0/27) only

**Command:**
```bash
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --name "AllowRDP" \
  --query "{Name:name, Direction:direction, Protocol:protocol, SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange, Access:access}" \
  -o json
```

**Expected:**
```json
{
  "Name": "AllowRDP",
  "Direction": "Inbound",
  "Protocol": "Tcp",
  "SourcePrefix": "10.0.3.0/27",
  "DestPort": "3389",
  "Access": "Allow"
}
```

**Tower Note:** Windows Server access via RDP must be equally restricted to Linux SSH. Bastion-only enforcement creates single audit trail for all interactive access. Critical for compliance and incident investigation.

---

### Check 7: NSG — Database Subnet PostgreSQL Isolation
**Category:** SECURITY  
**Check:** Verify PostgreSQL port 5432 on DB subnet is restricted to app subnet (10.0.1.0/24) only

**Command:**
```bash
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-db" \
  --name "AllowPostgres" \
  --query "{Name:name, Direction:direction, Protocol:protocol, SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange, Access:access}" \
  -o json
```

**Expected:**
```json
{
  "Name": "AllowPostgres",
  "Direction": "Inbound",
  "Protocol": "Tcp",
  "SourcePrefix": "10.0.1.0/24",
  "DestPort": "5432",
  "Access": "Allow"
}
```

**Tower Note:** Three-tier network isolation: Bastion→App→DB. Database must NEVER be directly accessible from Bastion or external. This rule validates tier-2 network boundary. Prevents direct database compromise even if Bastion is breached.

---

### Check 8: NSG — Deny All Inbound (Default Deny)
**Category:** SECURITY  
**Check:** Confirm implicit/explicit deny-all inbound rules on all NSGs (no open inbound except explicit allows)

**Command:**
```bash
# Check app NSG rules
az network nsg rule list \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --query "[?direction=='Inbound'].{Name:name, Access:access, Priority:priority, SourcePrefix:sourceAddressPrefix}" \
  -o table

# Check db NSG rules
az network nsg rule list \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-db" \
  --query "[?direction=='Inbound'].{Name:name, Access:access, Priority:priority, SourcePrefix:sourceAddressPrefix}" \
  -o table
```

**Expected:**
```
# App NSG inbound
Name      Access    Priority    SourcePrefix
--------  --------  ----------  ---------------
AllowSSH  Allow     100         10.0.3.0/27
AllowRDP  Allow     110         10.0.3.0/27

# DB NSG inbound
Name             Access    Priority    SourcePrefix
---------------  --------  ----------  ---------------
AllowPostgres    Allow     100         10.0.1.0/24
```
No rules with `Access=Allow` from `0.0.0.0/0` or unexpected CIDRs.

**Tower Note:** Default-deny is foundational to zero-trust. Absence of unexpected Allow rules validates security posture. Azure implicitly denies unlisted traffic; explicit validation prevents misconfiguration surprise.

---

### Check 9: Network Interfaces — Static IP Assignment Verification
**Category:** CONNECTIVITY  
**Check:** Confirm all VM NICs have static private IPs (not dynamic allocation)

**Command:**
```bash
# Check all NICs
for nic in nic-app nic-db nic-win; do
  echo "=== $nic ===" 
  az network nic show \
    --resource-group "rg-ailab-sathish" \
    --name "$nic" \
    --query "ipConfigurations[0].{Name:name, PrivateIP:privateIpAddress, AllocationMethod:privateIpAllocationMethod, Subnet:subnet.id}" \
    -o table
done
```

**Expected:**
```
=== nic-app === 
Name       PrivateIP    AllocationMethod    Subnet
---------  -----------  -----------------  /subscriptions/.../snet-app
internal   10.0.1.10    Static              (full ID)

=== nic-db === 
Name       PrivateIP    AllocationMethod    Subnet
---------  -----------  -----------------  /subscriptions/.../snet-db
internal   10.0.2.10    Static              (full ID)

=== nic-win === 
Name       PrivateIP    AllocationMethod    Subnet
---------  -----------  -----------------  /subscriptions/.../snet-app
internal   10.0.1.20    Static              (full ID)
```

**Tower Note:** Static IPs are network operations requirement. Dynamic allocation causes DNS/firewall rule mismatches when VMs are deallocated/reallocated. Critical for operations stability and audit trail accuracy. NSG rules are tied to static IPs.

---

### Check 10: DNS Resolution — Private DNS Enablement
**Category:** CONNECTIVITY  
**Check:** Verify VNET DNS settings and ability to resolve VM hostnames internally

**Command:**
```bash
# Check VNET DNS configuration
az network vnet show \
  --resource-group "rg-ailab-sathish" \
  --name "vnet-ailab" \
  --query "{Name:name, DnsServers:dhcpOptions.dnsServers}" \
  -o json

# Attempt DNS resolution from vm-app
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10 'nslookup vm-db.internal.cloudapp.net'
```

**Expected (DNS config):**
```json
{
  "Name": "vnet-ailab",
  "DnsServers": []
}
```
(Empty = using Azure default DNS 168.63.129.16)

**Expected (DNS resolution from vm-app):**
```
Server:     168.63.129.16
Address:    168.63.129.16#53

Name:    vm-db.internal.cloudapp.net
Address: 10.0.2.10
```

**Tower Note:** Azure-managed DNS (168.63.129.16) is built-in to VNET. Validates internal hostname resolution for service discovery. Empty dnsServers array confirms using Azure defaults—correct for this deployment.

---

## 🔗 CONNECTIVITY CHECKS (Priority: CRITICAL)

### Check 11: Intra-VNET Routing — System Routes Active
**Category:** CONNECTIVITY  
**Check:** Verify system routes allow communication between subnets (10.0.0.0/16 destinations routed to VNET)

**Command:**
```bash
# Check effective routes on app NIC
az network nic show-effective-route-table \
  --resource-group "rg-ailab-sathish" \
  --name "nic-app" \
  --query "[?contains(addressPrefix, '10.0')].{Source:source, State:state, AddressPrefix:addressPrefix, NextHopType:nextHopType}" \
  -o table
```

**Expected:**
```
Source          State    AddressPrefix    NextHopType
--------------  -------  ---------------  -----------
Default         Active   10.0.0.0/16      VnetLocal
```

**Tower Note:** System routes enable inter-subnet communication. VnetLocal routes on 10.0.0.0/16 are automatic—validates routing engine is active. Absence indicates corrupted network configuration.

---

### Check 12: End-to-End Connectivity — App to Database
**Category:** CONNECTIVITY  
**Check:** From vm-app, verify Layer-3 connectivity to vm-db on port 5432 (PostgreSQL)

**Command:**
```bash
# SSH to vm-app via Bastion, then test DB connectivity
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10 'nc -zv 10.0.2.10 5432'
```

**Expected:**
```
Connection to 10.0.2.10 5432 port [tcp/*] succeeded!
```

**Alternative command (if nc unavailable):**
```bash
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10 'timeout 3 bash -c "</dev/tcp/10.0.2.10/5432" && echo "Connected" || echo "Connection failed"'
```

**Tower Note:** Validates end-to-end network path: App NIC→App NSG→VNET routing→DB NSG→DB NIC. Failure indicates NSG rule misconfiguration or routing issue. Must succeed before application deployment.

---

### Check 13: Bastion Connectivity — Path to App VM
**Category:** CONNECTIVITY  
**Check:** Verify Azure Bastion can reach vm-app on SSH port 22 from Bastion subnet

**Command:**
```bash
# Test Bastion→App connectivity via CLI
az network bastion ssh \
  --resource-group "rg-ailab-sathish" \
  --name "bastion-ailab" \
  --target-resource-id "$(az vm show -g rg-ailab-sathish -n vm-app --query id -o tsv)" \
  --username "labadmin" \
  --query ""

# Or manually check NSG allows Bastion→App on port 22
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --name "AllowSSH" \
  --query "{SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange}"
```

**Expected (NSG rule):**
```
SourcePrefix    DestPort
--------------  ----------
10.0.3.0/27     22
```

**Tower Note:** Bastion is single point of access to entire infrastructure. Failure here blocks all remote management. NSG must explicitly allow 10.0.3.0/27 as source for SSH/RDP on app subnet.

---

### Check 14: Bastion Connectivity — Path to Windows VM
**Category:** CONNECTIVITY  
**Check:** Verify Azure Bastion can reach vm-win on RDP port 3389 from Bastion subnet

**Command:**
```bash
# Test Bastion→Windows connectivity via CLI
az network bastion rdp \
  --resource-group "rg-ailab-sathish" \
  --name "bastion-ailab" \
  --target-resource-id "$(az vm show -g rg-ailab-sathish -n vm-win --query id -o tsv)" \
  --username "labadmin"

# Or verify NSG rule for RDP
az network nsg rule show \
  --resource-group "rg-ailab-sathish" \
  --nsg-name "nsg-app" \
  --name "AllowRDP" \
  --query "{SourcePrefix:sourceAddressPrefix, DestPort:destinationPortRange}"
```

**Expected (NSG rule):**
```
SourcePrefix    DestPort
--------------  ----------
10.0.3.0/27     3389
```

**Tower Note:** Windows Server access path must work independently of Linux. Both SSH and RDP rules must co-exist on same NSG (app subnet). Validates application subnet NSG handles both protocols.

---

### Check 15: Network Interface Card Forwarding — IP Forwarding Disabled
**Category:** SECURITY  
**Check:** Confirm IP forwarding is disabled on all NICs (prevents VMs acting as routers)

**Command:**
```bash
# Check all NICs for IP forwarding status
for nic in nic-app nic-db nic-win; do
  echo "=== $nic ===" 
  az network nic show \
    --resource-group "rg-ailab-sathish" \
    --name "$nic" \
    --query "{Name:name, EnableIpForwarding:enableIpForwarding}" \
    -o table
done
```

**Expected:**
```
=== nic-app === 
Name        EnableIpForwarding
-----------  ------------------
nic-app     False

=== nic-db === 
Name       EnableIpForwarding
--------  ------------------
nic-db    False

=== nic-win === 
Name        EnableIpForwarding
-----------  ------------------
nic-win     False
```

**Tower Note:** IP forwarding disabled prevents compromised VMs from becoming rogue routers or participating in man-in-the-middle attacks. Not a routing requirement here; default disabled is correct security posture.

---

## 📊 CONNECTIVITY & PERFORMANCE CHECKS

### Check 16: Network Throughput Baseline — No Packet Loss
**Category:** CONNECTIVITY | PERFORMANCE  
**Check:** Validate intra-VNET connectivity with ICMP ping (baseline latency and packet loss)

**Command:**
```bash
# SSH to vm-app and ping vm-db
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10 'ping -c 5 10.0.2.10'
```

**Expected:**
```
PING 10.0.2.10 (10.0.2.10) 56(84) bytes of data.
64 bytes from 10.0.2.10: icmp_seq=1 ttl=64 time=1.23 ms
64 bytes from 10.0.2.10: icmp_seq=2 ttl=64 time=1.15 ms
64 bytes from 10.0.2.10: icmp_seq=3 ttl=64 time=1.28 ms
64 bytes from 10.0.2.10: icmp_seq=4 ttl=64 time=1.20 ms
64 bytes from 10.0.2.10: icmp_seq=5 ttl=64 time=1.19 ms

--- 10.0.2.10 statistics ---
5 packets transmitted, 5 received, 0% packet loss, time 4010ms
rtt min/avg/max/stddev = 1.15/1.21/1.28/0.05 ms
```

**Tower Note:** Zero packet loss confirms stable Layer-3 connectivity. Sub-2ms latency is typical for same Azure region. Validates no network congestion or blackholes. Baseline for future performance monitoring.

---

### Check 17: Network Watcher — NSG Flow Logs Configuration
**Category:** MONITORING | CONNECTIVITY  
**Check:** Verify NSG flow logging is enabled for traffic analysis and troubleshooting

**Command:**
```bash
# Check if Network Watcher is created in region
az network watcher list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, ProvisioningState:provisioningState}" \
  -o table

# List NSG flow log configurations
az network watcher flow-log list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{TargetResourceId:targetResourceId, Enabled:enabled}" \
  -o table
```

**Expected:**
```
(Network Watcher may not exist by default — create if needed)

# Flow logs may be empty initially — this is not a failure
# but indicates logging isn't yet configured
```

**Tower Note:** NSG flow logs capture allow/deny traffic for forensics. Optional but recommended for troubleshooting connectivity issues. Can be enabled post-deployment without service impact. Network operations best practice.

---

### Check 18: Load Balancer / Public Endpoint Review
**Category:** CONNECTIVITY | SECURITY  
**Check:** Verify no unexpected load balancers or public endpoints bypass Bastion

**Command:**
```bash
# List all public IPs
az network public-ip list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, IpAddress:ipAddress, AssociatedResource:ipConfiguration.id}" \
  -o table

# List load balancers
az network lb list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, Sku:sku.name}" \
  -o table
```

**Expected:**
```
# Public IPs (only Bastion public IP expected)
Name          IpAddress         AssociatedResource
-----------  ----------------  /subscriptions/.../bastion...
pip-bastion  52.XX.XXX.XXX     (Bastion config ID)

# Load Balancers
(Empty table — none expected)
```

**Tower Note:** Network architects must verify no unintended public endpoints. Bastion should be ONLY public IP. Load balancers require explicit approval. Validates zero-trust perimeter maintained.

---

## 🔐 COMPLIANCE & AUDIT CHECKS

### Check 19: Network Security Group Tagging & Ownership
**Category:** COMPLIANCE | MONITORING  
**Check:** Verify NSGs are tagged with owner/team for audit and accountability

**Command:**
```bash
# Check NSG tags
for nsg in nsg-app nsg-db; do
  echo "=== $nsg ===" 
  az network nsg show \
    --resource-group "rg-ailab-sathish" \
    --name "$nsg" \
    --query "{Name:name, Tags:tags}" \
    -o json
done
```

**Expected:**
```json
=== nsg-app === 
{
  "Name": "nsg-app",
  "Tags": {
    "owner": "sathish"
  }
}

=== nsg-db === 
{
  "Name": "nsg-db",
  "Tags": {
    "owner": "sathish"
  }
}
```

**Tower Note:** Tags on network resources enable cost allocation and compliance tracking. Missing tags indicate infrastructure deployed outside governance process. Network operations must enforce tagging for audit trail.

---

### Check 20: Azure Firewall / DDoS Protection Review
**Category:** SECURITY | COMPLIANCE  
**Check:** Confirm appropriate DDoS protection level and no unsanctioned firewalls

**Command:**
```bash
# Check VNET for DDoS protection
az network vnet show \
  --resource-group "rg-ailab-sathish" \
  --name "vnet-ailab" \
  --query "{Name:name, DdosProtectionStandard:ddosProtectionPlan}" \
  -o json

# List firewalls in resource group
az network firewall list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, Sku:sku.name}" \
  -o table
```

**Expected:**
```json
{
  "Name": "vnet-ailab",
  "DdosProtectionStandard": null
}
```

**Expected (Firewalls):**
```
(Empty table — none expected for this lab)
```

**Tower Note:** DDoS Protection Standard is optional for lab. Production requires evaluation. Default Basic protection (included) is acceptable. No Azure Firewall needed in this topology since NSGs provide sufficient segmentation. Network architecture review validates cost-appropriate security.

---

## 🔌 ADVANCED NETWORK CHECKS

### Check 21: Service Endpoints — Azure Storage Validation
**Category:** CONNECTIVITY | SECURITY  
**Check:** Verify service endpoints exist for Azure Storage (if using private endpoints)

**Command:**
```bash
# Check service endpoints on app subnet
az network vnet subnet show \
  --resource-group "rg-ailab-sathish" \
  --vnet-name "vnet-ailab" \
  --name "snet-app" \
  --query "{Subnet:name, ServiceEndpoints:serviceEndpoints[].service}" \
  -o json
```

**Expected:**
```json
{
  "Subnet": "snet-app",
  "ServiceEndpoints": []
}
```
(Empty is acceptable; indicates no service endpoint restrictions configured — storage is accessible via public endpoint)

**Tower Note:** Service endpoints restrict access to Azure services (Storage, SQL, etc.) at the VNET level. Optional in this deployment but important for production hardening. Absence means Storage account is publicly accessible but firewall-protected.

---

### Check 22: User-Defined Routes (UDRs) — Route Table Inspection
**Category:** CONNECTIVITY  
**Check:** Confirm no problematic UDRs exist that could interrupt inter-subnet routing

**Command:**
```bash
# List all route tables
az network route-table list \
  --resource-group "rg-ailab-sathish" \
  --query "[].{Name:name, Routes:routes[].{Name:name, AddressPrefix:addressPrefix, NextHopType:nextHopType}}" \
  -o json

# Check if subnets have custom routes
for subnet in snet-app snet-db AzureBastionSubnet; do
  echo "=== $subnet ===" 
  az network vnet subnet show \
    --resource-group "rg-ailab-sathish" \
    --vnet-name "vnet-ailab" \
    --name "$subnet" \
    --query "{Subnet:name, RouteTable:routeTable.id}" \
    -o table
done
```

**Expected:**
```
(Empty route tables — this is correct)

=== snet-app === 
Subnet      RouteTable
--------  --------
snet-app  (null)

=== snet-db === 
Subnet     RouteTable
--------  --------
snet-db   (null)

=== AzureBastionSubnet === 
Subnet                RouteTable
---------------------  --------
AzureBastionSubnet     (null)
```

**Tower Note:** User-defined routes allow custom routing policies (e.g., send all traffic through NVA). Absence (null) means using default system routes—correct for this simple three-subnet topology. Presence would require explicit validation of routing intent.

---

### Check 23: VNET Peering & Connectivity to Other Networks
**Category:** CONNECTIVITY  
**Check:** Verify no unexpected VNET peerings and confirm isolation if none expected

**Command:**
```bash
# List all VNET peerings
az network vnet peering list \
  --resource-group "rg-ailab-sathish" \
  --vnet-name "vnet-ailab" \
  --query "[].{Name:name, PeeringState:peeringState, RemoteVnet:remoteVirtualNetwork.id}" \
  -o table
```

**Expected:**
```
(Empty table — no peerings)
```

**Tower Note:** VNET isolation validates network segregation. No peerings to other VNETs or on-premises networks is correct for this lab deployment. Production would require explicit peering strategy review (hub-and-spoke, mesh, etc.).

---

### Check 24: MTU Path Verification — Maximum Transmission Unit
**Category:** PERFORMANCE  
**Check:** Confirm MTU is set to 1500 bytes (standard Azure setting) with no fragmentation

**Command:**
```bash
# SSH to vm-app and test MTU
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10 'ip link show | grep mtu'

# Test path MTU to vm-db (Linux)
ssh -J labadmin@10.0.3.0 labadmin@10.0.1.10 'tracepath -m 10 10.0.2.10 | tail -3'
```

**Expected (ip link):**
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
```

**Expected (tracepath — should reach without "too big" errors):**
```
     10.0.2.10                              reached
     resume: pmtu 1500 host unreachable
```

**Tower Note:** Standard Azure MTU is 1500 bytes. Fragmentation detection validates end-to-end path supports full-size frames. Important for throughput optimization and troubleshooting performance issues.

---

### Check 25: Subnet Utilization — IP Address Pool Analysis
**Category:** MONITORING | CONNECTIVITY  
**Check:** Verify adequate available IPs in each subnet for future expansion

**Command:**
```bash
# Calculate available IPs per subnet
# snet-app: 10.0.1.0/24 = 256 total, 254 usable (minus network & broadcast)
# snet-db:  10.0.2.0/24 = 256 total, 254 usable
# Bastion:  10.0.3.0/27 = 32 total, 30 usable

# Verify current NIC allocation
for subnet in snet-app snet-db AzureBastionSubnet; do
  echo "=== $subnet ===" 
  az network vnet subnet show \
    --resource-group "rg-ailab-sathish" \
    --vnet-name "vnet-ailab" \
    --name "$subnet" \
    --query "{Subnet:name, IpConfigurations:ipConfigurations | length(@)}" \
    -o table
done
```

**Expected:**
```
=== snet-app === 
Subnet       IpConfigurations
-----------  ---------------
snet-app     2               (vm-app NIC + vm-win NIC)

=== snet-db === 
Subnet      IpConfigurations
--------  ---------------
snet-db   1                (vm-db NIC)

=== AzureBastionSubnet === 
Subnet                IpConfigurations
---------------------  ---------------
AzureBastionSubnet     1               (Bastion)
```

**Tower Note:** Utilization analysis validates capacity planning. App subnet: 2/254 = 0.8% used (excellent headroom). DB subnet: 1/254 = 0.4% used. Bastion: 1/30 = 3.3% used. All well within limits for future growth.

---

## FINAL VALIDATION SUMMARY

| Category | Checks | Status | Issues Found |
|----------|--------|--------|-------------|
| SECURITY | 9 | ☐ PASS / ☐ BLOCK | |
| CONNECTIVITY | 10 | ☐ PASS / ☐ BLOCK | |
| MONITORING | 3 | ☐ PASS / ☐ BLOCK | |
| COMPLIANCE | 2 | ☐ PASS / ☐ BLOCK | |
| PERFORMANCE | 1 | ☐ PASS / ☐ BLOCK | |

### Network Operations Sign-Off
- [ ] All 25 checks executed
- [ ] No SECURITY checks blocked
- [ ] No CONNECTIVITY checks blocked  
- [ ] NSG rules validated for defense-in-depth
- [ ] Network segmentation confirmed (3-tier isolation)
- [ ] Bastion as sole access point verified
- [ ] Issues documented in change request ticket
- [ ] Network diagram reviewed with team

**Network Approved for Production:** ☐ YES | ☐ NO  
**Network Ops Lead:** _________________  
**Date:** _________________

---

## TROUBLESHOOTING REFERENCE

### If NSG Rules Not Applied
1. Verify subnet NSG association: `az network vnet subnet show -g rg-ailab-sathish --vnet-name vnet-ailab -n snet-app --query networkSecurityGroup`
2. Check NSG exists: `az network nsg show -g rg-ailab-sathish -n nsg-app`
3. Verify rule is in NSG: `az network nsg rule list -g rg-ailab-sathish --nsg-name nsg-app`
4. Allow 5-10 minutes for rule propagation

### If Inter-Subnet Connectivity Fails
1. Verify intra-VNET route exists: `az network nic show-effective-route-table -g rg-ailab-sathish -n nic-app`
2. Confirm NSGs allow traffic both directions (inbound on dest, outbound on source)
3. Test with `nc -zv` or `telnet` to isolate layer (ICMP vs TCP)
4. Check VM OS firewall (iptables on Linux, Windows Firewall on Windows)

### If Bastion Cannot Connect
1. Verify Bastion subnet is exactly /27: `az network vnet subnet show -g rg-ailab-sathish --vnet-name vnet-ailab -n AzureBastionSubnet`
2. Check Bastion public IP exists: `az network bastion show -g rg-ailab-sathish -n bastion-ailab`
3. Confirm app subnet NSG allows source 10.0.3.0/27 on ports 22/3389
4. Verify Bastion service is healthy: Check Azure Portal → Bastion blade

### If DNS Resolution Fails
1. Verify Azure default DNS is in use: `az network nic show -g rg-ailab-sathish -n nic-app --query dnsSettings`
2. Test from VM: `nslookup vm-db` (should resolve to 10.0.2.10)
3. Verify DNS suffix set to `internal.cloudapp.net`
4. Check `/etc/resolv.conf` on Linux contains `168.63.129.16`

### If Latency is High (>5ms within same region)
1. Verify VMs are in same region: `az vm show -g rg-ailab-sathish -n vm-app --query location`
2. Check for packet loss: `ping -c 100 10.0.2.10 | grep loss`
3. Verify no route fragmentation: `tracepath 10.0.2.10`
4. Check NSG rule priorities—rules evaluated in order

---

## NETWORK OPERATIONS RUNBOOK REFERENCES
- **NSG Documentation:** https://docs.microsoft.com/azure/virtual-network/network-security-groups-overview
- **Azure Bastion:** https://docs.microsoft.com/azure/bastion/bastion-overview
- **VNET Routing:** https://docs.microsoft.com/azure/virtual-network/virtual-networks-udr-overview
- **Network Watcher:** https://docs.microsoft.com/azure/network-watcher/network-watcher-overview

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-16  
**Next Review:** Post-deployment + 7 days  
**Owner:** Network Operations Team
