# RCA Draft - Storage Access Outage After Network Policy Drift

## 1. Executive Summary
On 2026-06-19 between 06:37:02Z and 06:38:10Z, the FinBridge storage workload experienced access failures after a deliberate fault injection changed Azure Storage account network policy from Allow to Deny. The incident was detected through failed storage operations and confirmed via Azure CLI evidence. Service was restored by reverting the policy to Allow after a restore-first test had already proven rollback safety.

## 2. Impact
- Start time (UTC): 2026-06-19T06:37:02.2520783Z
- End time (UTC): 2026-06-19T06:38:10.1939041Z
- Duration: 68 seconds
- User/business impact: Storage data-plane access checks failed during the fault window; test workload operations dependent on blob listing were blocked.
- Services affected: Azure Storage account `finbridgecapst8q47gk` container access (`app-data`) in the capstone environment.

## 3. Timeline (UTC)
Use ../evidence/INCIDENT_TIMELINE.csv as source of truth.

## 4. Detection and Triage
- Initial detection signal: `az storage container list` failed with a network-rule block message and exit code 1.
- Detection source: Azure CLI data-plane command executed from operator workstation.
- Triage actions taken in order:
	1. Confirmed restore-first safety check with `defaultAction=Allow`.
	2. Injected fault by setting storage `defaultAction=Deny`.
	3. Re-ran container listing and confirmed failure signal.
	4. Validated policy drift by checking storage network default action.
	5. Restored `defaultAction=Allow`.
	6. Re-ran container listing and confirmed recovery (exit code 0).

## 5. Root Cause
### Technical Root Cause
Storage account networkRuleSet.defaultAction was set to Deny, causing access paths used by workload tests to fail.

### Contributing Factors
- No preventive guardrail on storage network policy changes.
- Dependency on manual post-change verification.

## 6. Resolution
- Recovery action: Updated storage account network default action from Deny to Allow using Azure CLI restore operation.
- Validation: Post-restore policy state returned to Allow and data-plane container listing succeeded with exit code 0.

## 7. What Went Well
- Rollback script was prepared and tested before fault injection.
- Structured evidence collection accelerated diagnosis.

## 8. What Went Wrong
- Fault impact manifested immediately in dependent checks.
- Limited prebuilt alarms for storage policy drift in this capstone setup.

## 9. Preventive Actions
1. Add Azure Policy to block unauthorized defaultAction=Deny in this resource group.
2. Add alert on storage network policy changes.
3. Add automated canary test for storage read/write after any network change.

## 10. Evidence Index
- Observation log: ../evidence/OBSERVATION_LOG.md
- Timeline: ../evidence/INCIDENT_TIMELINE.csv
- Prompt library: PROMPT_LIBRARY.md
- Gate summary: IAC_GATE_SUMMARY.md
- Fault/restore confirmation: FAULT_RESTORE_CONFIRMATION.md
