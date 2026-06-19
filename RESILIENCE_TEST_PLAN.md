# Azure Resilience Test Plan

Environment analysed from Terraform and state in `tflabs/`:

- Resource group: `rg-ailab-sathish`
- Region: `eastus`
- App VM: `vm-app` (`10.0.1.10`, Ubuntu 22.04, Standard_B2ms)
- DB VM: `vm-db` (`10.0.2.10`, Ubuntu 22.04, PostgreSQL 14, `max_connections=20`)
- Windows VM: `vm-win` (`10.0.1.20`, Windows Server 2022, IIS)
- Bastion: `bastion-ailab`, Basic SKU, only interactive access path
- Storage account: `stailabsathish`, Standard LRS, blob soft-delete 7 days

Important environment note: the supplied brief says auto-shutdown is `20:00 UTC`, but the Terraform code currently sets `daily_recurrence_time = "0800"` for all three VMs. Validate the live schedule before running any stop/start scenario.

## Command Conventions

Run these once in Azure Cloud Shell before any scenario that uses `az`:

```bash
export RG="rg-ailab-sathish"
export APP_VM="vm-app"
export DB_VM="vm-db"
export WIN_VM="vm-win"
export APP_IP="10.0.1.10"
export DB_IP="10.0.2.10"
export WIN_IP="10.0.1.20"
export STG="stailabsathish"
```

Linux commands below can be run either:

```bash
# through Bastion SSH
ssh labadmin@10.0.1.10

# or from Cloud Shell without direct SSH
az vm run-command invoke -g "$RG" -n "$APP_VM" --command-id RunShellScript --scripts "<command>"
az vm run-command invoke -g "$RG" -n "$DB_VM" --command-id RunShellScript --scripts "<command>"
```

Windows commands below can be run either in a Bastion RDP PowerShell session or with:

```bash
az vm run-command invoke -g "$RG" -n "$WIN_VM" --command-id RunPowerShellScript --scripts "<PowerShell command>"
```

## Global Pre-Test Gate

All of the following must pass before any scenario is triggered:

```bash
az vm list -g "$RG" --show-details \
  --query "[].{Name:name,Power:powerState,PrivateIP:privateIps}" -o table

az network bastion show -g "$RG" -n bastion-ailab \
  --query "{Name:name,Sku:sku.name,State:provisioningState}" -o table

az resource list -g "$RG" --resource-type Microsoft.DevTestLab/schedules \
  --query "[].{Name:name,Time:properties.dailyRecurrence.time,Status:properties.status}" -o table

az storage account blob-service-properties show --account-name "$STG" --auth-mode login \
  --query "{Enabled:deleteRetentionPolicy.enabled,Days:deleteRetentionPolicy.days}" -o table
```

No-Go conditions:

- Any VM is not `VM running`
- Bastion is not `Succeeded`
- Blob soft-delete is not enabled for 7 days
- Current time is within 30 minutes of the live auto-shutdown schedule

## Scenario A: Payment JVM Hang

Description: Simulates the payment process becoming stuck in an uninterruptible application wait without crashing. This is realistic for JVM deadlock, blocked I/O, or a bad thread pool condition and is the fastest way to prove that operators can identify and unstick the payment runtime.

Failure type: APPLICATION

Blast radius: `vm-app` payment processing stops immediately. `vm-db` remains healthy but receives no new useful work. `vm-win` is unaffected.

Go/No-Go check:

```bash
APP_PID="$(pgrep -f 'java.*-Xmx4g' | head -n1)"; \
[ -n "$APP_PID" ] && ps -o pid=,stat=,etime=,cmd= -p "$APP_PID" && \
ps -o stat= -p "$APP_PID" | grep -vq T && echo "GO: payment JVM responsive candidate pid $APP_PID" || \
echo "NO-GO: payment JVM not found or already stopped"
```

Trigger:

```bash
APP_PID="$(pgrep -f 'java.*-Xmx4g' | head -n1)"; \
echo "$APP_PID" | sudo tee /tmp/resilience-app.pid >/dev/null; \
sudo kill -STOP "$APP_PID"
```

Expected impact:

- `vm-app`: payment JVM remains present but stops scheduling work; open sessions stall and new requests queue or time out
- `vm-db`: connection count drops toward idle baseline
- `vm-win`: no impact
- Bastion and storage: no impact

Recovery:

```bash
APP_PID="$(cat /tmp/resilience-app.pid)"; \
sudo kill -CONT "$APP_PID"
```

Validation:

```bash
APP_PID="$(cat /tmp/resilience-app.pid)"; \
ps -o pid=,stat=,etime=,cmd= -p "$APP_PID"; \
sudo ss -ltnp | grep "pid=$APP_PID,"
```

RTO target: `< 2 minutes`

## Scenario B: vm-app CPU Saturation

Description: Simulates a payment surge or runaway computation on a B-series app VM. This is realistic because `vm-app` is a `Standard_B2ms`; sustained CPU pressure both degrades the service and burns burst credits.

Failure type: COMPUTE

Blast radius: `vm-app` latency rises sharply. `vm-db` remains healthy but request rate falls. `vm-win` is unaffected.

Go/No-Go check:

```bash
awk '{if ($1 < 1.00) print "GO: load average=" $1; else print "NO-GO: load average=" $1}' /proc/loadavg; \
pgrep -f 'java.*-Xmx4g' >/dev/null && echo "GO: payment JVM present" || echo "NO-GO: payment JVM missing"
```

Trigger:

```bash
sudo rm -f /tmp/resilience-cpu.pids; \
for i in 1 2; do yes > /dev/null & echo $! | sudo tee -a /tmp/resilience-cpu.pids >/dev/null; done; \
cat /tmp/resilience-cpu.pids
```

Expected impact:

- `vm-app`: CPU usage approaches 100 percent on both vCPUs; payment requests slow down or time out
- `vm-db`: no direct failure; lower transaction arrival rate
- `vm-win`: no impact
- Bastion: remains usable

Recovery:

```bash
sudo xargs -r kill < /tmp/resilience-cpu.pids; \
sudo rm -f /tmp/resilience-cpu.pids
```

Validation:

```bash
awk '{print "Load average=" $1}' /proc/loadavg; \
pgrep -f '^yes$' >/dev/null && echo "NO-GO: CPU burners still running" || echo "GO: CPU burners cleared"; \
pgrep -af 'java.*-Xmx4g'
```

RTO target: `< 3 minutes`

## Scenario C: PostgreSQL Connection Pool Exhaustion

Description: Simulates an application-side connection leak against a database limited to `max_connections=20`. This is one of the highest-risk faults in this environment because there is very little connection headroom.

Failure type: DATABASE

Blast radius: Payment writes fail first. `vm-app` keeps running but cannot complete DB-backed transactions. `vm-db` stays up while refusing new client work.

Go/No-Go check:

```bash
sudo -u postgres psql -c "SHOW max_connections; SHOW superuser_reserved_connections; SELECT count(*) AS current_sessions FROM pg_stat_activity;"

PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT 1 AS db_ok;"
```

Trigger:

```bash
rm -f /tmp/resilience-dbconn.pids; \
for i in $(seq 1 17); do \
  PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT pg_sleep(240);" >/dev/null 2>&1 & \
  echo $! >> /tmp/resilience-dbconn.pids; \
done; \
PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT 1;"
```

Expected impact:

- `vm-app`: new DB sessions fail with `too many clients already`; payment requests that need PostgreSQL return errors
- `vm-db`: PostgreSQL stays online but rejects new non-superuser sessions
- `vm-win`: no impact
- Bastion and storage: no impact

Recovery:

```bash
xargs -r kill < /tmp/resilience-dbconn.pids; \
rm -f /tmp/resilience-dbconn.pids; \
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename='labuser' AND query LIKE 'SELECT pg_sleep(240);%';"
```

Validation:

```bash
sudo -u postgres psql -c "SELECT count(*) AS sessions_after_recovery FROM pg_stat_activity;"; \
PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT now() AS recovered_at;"
```

RTO target: `< 4 minutes`

## Scenario D: PostgreSQL Service Outage

Description: Simulates the database service stopping cleanly because of package restart, operator mistake, or service crash. This is a direct payment-path failure and should be one of the first tests run.

Failure type: DATABASE

Blast radius: All payment operations that need state fail immediately. `vm-app` remains reachable but cannot commit transactions.

Go/No-Go check:

```bash
systemctl is-active postgresql; \
sudo -u postgres psql -c "SELECT now() AS db_time;"; \
PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT 1 AS app_to_db_ok;"
```

Trigger:

```bash
sudo systemctl stop postgresql
```

Expected impact:

- `vm-db`: TCP 5432 stops accepting connections
- `vm-app`: payment operations fail fast or time out on DB connection attempts
- `vm-win`: no impact
- Bastion and storage: no impact

Recovery:

```bash
sudo systemctl start postgresql
```

Validation:

```bash
systemctl is-active postgresql; \
sudo -u postgres psql -c "SELECT now() AS db_time;"; \
PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT 1 AS app_to_db_ok;"
```

RTO target: `< 3 minutes`

## Scenario E: NSG Blocks App-to-DB Traffic

Description: Simulates an Azure control-plane misconfiguration where a higher-priority deny rule is introduced ahead of `AllowPostgres`. This is realistic in manual change windows and Terraform drift situations.

Failure type: NETWORK

Blast radius: Payment traffic from `vm-app` to `vm-db` on TCP 5432 is severed at the subnet boundary. The app keeps running but cannot reach state.

Go/No-Go check:

```bash
nc -zvw3 10.0.2.10 5432; \
az network nsg rule list -g "$RG" --nsg-name nsg-db \
  --query "[].{Name:name,Priority:priority,Access:access,Port:destinationPortRange}" -o table
```

Trigger:

```bash
az network nsg rule create -g "$RG" --nsg-name nsg-db --name DenyPostgres-ResilienceTest \
  --priority 90 --direction Inbound --access Deny --protocol Tcp \
  --source-address-prefixes 10.0.1.0/24 --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 5432
```

Expected impact:

- `vm-app`: TCP connect to `10.0.2.10:5432` fails; payment service errors on every DB-backed request
- `vm-db`: PostgreSQL remains healthy but sees no app traffic
- `vm-win`: no impact
- Bastion: still usable for both Linux VMs

Recovery:

```bash
az network nsg rule delete -g "$RG" --nsg-name nsg-db --name DenyPostgres-ResilienceTest
```

Validation:

```bash
nc -zvw3 10.0.2.10 5432; \
PGPASSWORD='Lab@2024!' psql -h 10.0.2.10 -U labuser -d labdb -c "SELECT 1 AS network_restored;"
```

RTO target: `< 5 minutes`

## Scenario F: vm-app Disk Nearly Full

Description: Simulates uncontrolled log growth or temporary-file accumulation on the app VM. This is realistic on a small 30 GB OS disk and often causes partial application failure before the VM itself looks down.

Failure type: STORAGE

Blast radius: `vm-app` can no longer write logs and temporary files reliably. Payment processing may degrade or restart. Other VMs are unaffected.

Go/No-Go check:

```bash
df -h /; \
df --output=avail / | tail -1 | awk '{if ($1 > 2097152) print "GO: more than 2 GiB free"; else print "NO-GO: insufficient free space"}'; \
pgrep -af 'java.*-Xmx4g'
```

Trigger:

```bash
FREE_KB="$(df --output=avail / | tail -1 | tr -d ' ')"; \
TARGET_KB="$((FREE_KB - 262144))"; \
sudo fallocate -l "${TARGET_KB}K" /tmp/resilience-fill.img; \
dd if=/dev/zero of=/tmp/resilience-write-probe bs=1M count=300 status=none
```

Expected impact:

- `vm-app`: disk free space drops to roughly 256 MiB; application writes become unreliable and may return `No space left on device`
- `vm-db`: no direct impact
- `vm-win`: no impact
- Bastion: SSH remains available unless other failures exist

Recovery:

```bash
sudo rm -f /tmp/resilience-fill.img /tmp/resilience-write-probe; \
sync; \
sudo systemctl restart payment.service 2>/dev/null || true
```

Validation:

```bash
df -h /; \
dd if=/dev/zero of=/tmp/resilience-write-recovery bs=1M count=10 status=none && rm -f /tmp/resilience-write-recovery; \
pgrep -af 'java.*-Xmx4g'
```

RTO target: `< 5 minutes`

## Scenario G: Unexpected vm-app Stop and Restart

Description: Simulates the operational effect of the configured daily auto-shutdown, accidental power-off, or host-level stop/start on the payment tier. This matters because `vm-app` is a single instance and there is no load balancer or secondary node.

Failure type: COMPUTE

Blast radius: Entire payment tier is unavailable until the VM is back up and the JVM is accepting work again. `vm-db` and `vm-win` stay online.

Go/No-Go check:

```bash
az vm get-instance-view -g "$RG" -n "$APP_VM" \
  --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv; \
az resource list -g "$RG" --resource-type Microsoft.DevTestLab/schedules \
  --query "[].{Name:name,Time:properties.dailyRecurrence.time,Status:properties.status}" -o table
```

Trigger:

```bash
az vm stop -g "$RG" -n "$APP_VM"
```

Expected impact:

- `vm-app`: full outage; Bastion SSH sessions to the VM drop
- `vm-db`: database stays healthy but idle
- `vm-win`: no impact
- Payment service: complete service interruption until boot completes

Recovery:

```bash
az vm start -g "$RG" -n "$APP_VM"
```

Validation:

```bash
until [ "$(az vm get-instance-view -g "$RG" -n "$APP_VM" --query \"instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]\" -o tsv)" = "PowerState/running" ]; do sleep 10; done

az vm run-command invoke -g "$RG" -n "$APP_VM" --command-id RunShellScript \
  --scripts "pgrep -af 'java.*-Xmx4g'; sudo ss -ltnp | grep java"
```

RTO target: `< 5 minutes`

## Scenario H: IIS Reporting Service App Pool Outage

Description: Simulates the reporting tier becoming unavailable due to an IIS app pool stop. This does not directly block payments, but it does affect operational reporting and can hide downstream issues during an incident.

Failure type: APPLICATION

Blast radius: `vm-win` reporting endpoints fail. Payment service remains available. Monitoring dashboards or internal reports may go dark.

Go/No-Go check:

```powershell
Import-Module WebAdministration
Get-ChildItem IIS:\AppPools | Select-Object Name,@{Name='State';Expression={(Get-WebAppPoolState -Name $_.Name).Value}}
Invoke-WebRequest http://localhost/ -UseBasicParsing | Select-Object StatusCode
```

Trigger:

```powershell
New-Item -ItemType Directory -Force -Path C:\Temp | Out-Null
Import-Module WebAdministration
Get-ChildItem IIS:\AppPools |
  Where-Object { (Get-WebAppPoolState -Name $_.Name).Value -eq 'Started' } |
  Select-Object -ExpandProperty Name |
  Set-Content C:\Temp\resilience-started-pools.txt
Get-Content C:\Temp\resilience-started-pools.txt | ForEach-Object { Stop-WebAppPool -Name $_ }
```

Expected impact:

- `vm-win`: reporting HTTP endpoints fail
- `vm-app` and `vm-db`: no direct impact
- Incident responders lose visibility if they depend on IIS-hosted reports

Recovery:

```powershell
Import-Module WebAdministration
Get-Content C:\Temp\resilience-started-pools.txt | ForEach-Object { Start-WebAppPool -Name $_ }
```

Validation:

```powershell
Import-Module WebAdministration
Get-Content C:\Temp\resilience-started-pools.txt | ForEach-Object { Get-WebAppPoolState -Name $_ }
Invoke-WebRequest http://localhost/ -UseBasicParsing | Select-Object StatusCode
```

RTO target: `< 3 minutes`

## Scenario I: Storage Soft-Delete Recovery Drill

Description: Simulates an operator accidentally deleting a diagnostic artifact from the LRS storage account and verifies that soft-delete can restore it. This does not affect payment runtime directly, but it confirms that supporting forensic data is recoverable.

Failure type: STORAGE

Blast radius: Only the test blob in `stailabsathish` is affected. Payment, DB, and IIS services continue normally.

Go/No-Go check:

```bash
az storage account blob-service-properties show --account-name "$STG" --auth-mode login \
  --query "{Enabled:deleteRetentionPolicy.enabled,Days:deleteRetentionPolicy.days}" -o table; \
az storage container create --account-name "$STG" --name resilience-test --auth-mode login >/dev/null; \
date -u > /tmp/resilience-storage.txt; \
az storage blob upload --account-name "$STG" --container-name resilience-test --name scenario-i.txt \
  --file /tmp/resilience-storage.txt --auth-mode login --overwrite
```

Trigger:

```bash
az storage blob delete --account-name "$STG" --container-name resilience-test --name scenario-i.txt \
  --auth-mode login --delete-snapshots include
```

Expected impact:

- No runtime service outage
- The test blob disappears from normal listing until restored
- Diagnostic-data recovery path is exercised without risking production data

Recovery:

```bash
az storage blob undelete --account-name "$STG" --container-name resilience-test --name scenario-i.txt --auth-mode login
```

Validation:

```bash
az storage blob exists --account-name "$STG" --container-name resilience-test --name scenario-i.txt --auth-mode login -o table; \
az storage blob download --account-name "$STG" --container-name resilience-test --name scenario-i.txt \
  --file /tmp/resilience-storage-restored.txt --auth-mode login --overwrite; \
cat /tmp/resilience-storage-restored.txt
```

RTO target: `< 2 minutes`

## Priority Order

Ranked by direct risk to the payment service:

1. Scenario E: NSG Blocks App-to-DB Traffic
2. Scenario D: PostgreSQL Service Outage
3. Scenario C: PostgreSQL Connection Pool Exhaustion
4. Scenario G: Unexpected vm-app Stop and Restart
5. Scenario A: Payment JVM Hang
6. Scenario B: vm-app CPU Saturation
7. Scenario F: vm-app Disk Nearly Full
8. Scenario H: IIS Reporting Service App Pool Outage
9. Scenario I: Storage Soft-Delete Recovery Drill

## Dependency Map

Run order matters because several scenarios can mask one another:

- Run Scenario A before Scenarios B, F, and G so the payment JVM state is known-good before heavier compute tests.
- Run Scenario C before Scenarios D and E because it requires a functioning DB path to prove exhaustion rather than outage.
- Run Scenario D before Scenario E so service-level DB failure is distinguished from Azure network policy failure.
- Run Scenario F after Scenarios A through E because low disk can distort logs and post-test evidence collection.
- Run Scenario G after all Linux in-guest tests because stop/start clears temp files, process IDs, and in-memory evidence.
- Run Scenario H independently; it does not affect the payment path.
- Run Scenario I last; it is low risk and does not inform payment-path triage.

Recommended execution sequence:

1. Scenario A
2. Scenario C
3. Scenario D
4. Scenario E
5. Scenario B
6. Scenario F
7. Scenario G
8. Scenario H
9. Scenario I

## Known Gaps

- Bastion outage is a real resilience risk, but it is not safe to induce in this lab because Bastion is the only interactive access path and a failure can strand recovery work.
- Azure regional failure cannot be tested safely or meaningfully here because all resources are single-region and there is no paired-region deployment, replication, or failover design.
- Storage account physical failure cannot be simulated by customers. Standard LRS has no zone or region redundancy, so true media or datacenter loss is a design gap rather than a lab test case.
- PostgreSQL corruption and point-in-time restore are not safely testable because this environment has a single standalone VM database, no replica, and no backup workflow defined in Terraform.
- Memory exhaustion on `vm-app` is plausible because the JVM is configured with `-Xmx4g` on an 8 GB VM, but forcing an OOM in a single-node Bastion-only lab risks destabilizing SSH recovery and is not a safe under-five-minute drill.
- Auto-shutdown timing is inconsistent between the brief (`20:00 UTC`) and Terraform (`08:00 UTC`). Resolve that discrepancy before using the schedule operationally.
