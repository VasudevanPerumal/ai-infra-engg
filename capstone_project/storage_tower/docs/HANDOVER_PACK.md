# Receiving Ops Handover Pack - Storage Tower

## Delivered Artifacts
- Terraform stack: ../terraform
- IaC four-gate one-line proof: IAC_GATE_SUMMARY.md
- Gate check script: ../scripts/gate_checks.ps1
- Fault script: ../scripts/fault_inject_storage_network_deny.sh
- Restore script: ../scripts/restore_storage_network_allow.sh
- Restore-tested-first statement: FAULT_RESTORE_CONFIRMATION.md
- Baseline verifier: ../scripts/verify_storage_baseline.sh
- Evidence templates: ../evidence
- Prompt library: PROMPT_LIBRARY.md
- RCA draft: RCA_DRAFT_STORAGE_INCIDENT.md
- Submission checklist: SUBMISSION_CHECKLIST.md

## Operational Run Sequence
1. Complete variables in terraform/terraform.tfvars.
2. Run pre-apply gates and capture output.
3. Apply infrastructure.
4. Run post-apply idempotency gate.
5. Test restore script before fault.
6. Inject fault and collect evidence.
7. Restore and verify baseline.
8. Complete RCA fields and submit.

## Key Commands
- pwsh ./scripts/gate_checks.ps1 -Mode preapply
- terraform -chdir=./terraform apply tfplan.preapply
- pwsh ./scripts/gate_checks.ps1 -Mode postapply
- bash ./scripts/restore_storage_network_allow.sh <RG> <SA>
- bash ./scripts/fault_inject_storage_network_deny.sh <RG> <SA>
- bash ./scripts/verify_storage_baseline.sh <RG> <SA>

## Acceptance Criteria
- All Day 4 gates pass.
- Restore tested before break.
- Incident timeline includes ordered timestamped evidence.
- Prompt library includes diagnosis and remediation prompts with keep/change/reject notes.
- Root cause and preventive actions documented.
