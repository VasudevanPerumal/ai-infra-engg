# Storage Tower Capstone Runbook

## Scope
This pack implements the FinBridge Storage tower scenario:
- Azure infrastructure from fresh Terraform
- Day 4 four gates before apply
- Fault and restore scripts (restore tested before break)
- Structured evidence capture and RCA handover

## Prerequisites
- Terraform 1.6+
- Azure CLI logged in (az login)
- Subscription selected (az account set --subscription <SUB_ID>)
- Bash shell for .sh scripts (Git Bash or WSL on Windows)

## Phase 1: Build (Fresh IaC)
1. Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars and fill values.
2. Run pre-apply gates:
   - pwsh ./scripts/gate_checks.ps1 -Mode preapply
3. Apply infrastructure:
   - terraform -chdir=./terraform apply tfplan.preapply
4. Run post-apply idempotency gate:
   - pwsh ./scripts/gate_checks.ps1 -Mode postapply

## Phase 2: Arm (Fault + Restore)
1. Capture outputs:
   - terraform -chdir=./terraform output -raw resource_group_name
   - terraform -chdir=./terraform output -raw storage_account_name
2. Test restore script before fault (graded gate):
   - bash ./scripts/restore_storage_network_allow.sh <RG> <STORAGE_ACCOUNT>
3. Verify baseline:
   - bash ./scripts/verify_storage_baseline.sh <RG> <STORAGE_ACCOUNT>

## Phase 3: Break & Detect
1. Inject fault:
   - bash ./scripts/fault_inject_storage_network_deny.sh <RG> <STORAGE_ACCOUNT>
2. Detect issue evidence examples:
   - az storage account show -g <RG> -n <STORAGE_ACCOUNT> --query "networkRuleSet.defaultAction" -o tsv
   - Run workload/storage access check and capture failure output.
3. Record timestamped observations in evidence/OBSERVATION_LOG.md and evidence/INCIDENT_TIMELINE.csv.

## Phase 4: Diagnose & Resolve
1. Hypothesis: storage account network policy changed from Allow to Deny, blocking access.
2. Remediate:
   - bash ./scripts/restore_storage_network_allow.sh <RG> <STORAGE_ACCOUNT>
3. Verify recovery:
   - bash ./scripts/verify_storage_baseline.sh <RG> <STORAGE_ACCOUNT>
4. Fill RCA draft in docs/RCA_DRAFT_STORAGE_INCIDENT.md.

## Submission Checklist
Use docs/SUBMISSION_CHECKLIST.md to verify required output completeness.
