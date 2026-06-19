# Observation Log (Day 7 Style)

## Incident Metadata
- Incident ID: INC-STORAGE-001
- Date: 2026-06-19
- Environment: Capstone / FinBridge
- Tower: Storage
- Primary symptom: Storage access failure after fault injection

## Ordered Observations
| Step | UTC Timestamp | Signal | Source | Interpretation |
|---|---|---|---|---|
| 1 | 2026-06-19T06:36:15.7956716Z | Baseline defaultAction=Allow | az storage account show | Storage access policy healthy |
| 2 | 2026-06-19T06:36:15.7956716Z | Restore tested before break (state remained Allow) | az storage account update/show | Rollback path proven before fault |
| 3 | 2026-06-19T06:37:02.2520783Z | Fault injected: defaultAction=Deny | az storage account update/show | Intentional policy fault applied |
| 4 | 2026-06-19T06:37:45.1886817Z | Storage access test failed (network rule block, exit code 1) | az storage container list | Impact confirmed |
| 5 | 2026-06-19T06:38:00.8157575Z | Restore set defaultAction=Allow | az storage account update/show | Remediation complete |
| 6 | 2026-06-19T06:38:10.1939041Z | Access test succeeded (exit code 0) | az storage container list | Recovery verified |

## Raw Command Outputs
- 2026-06-19T06:36:15.7956716Z: `RESTORE_TEST_DEFAULT_ACTION=Allow`
- 2026-06-19T06:36:30.0285930Z: pre-fault `az storage container list` returned container `app-data` and `PREFAULT_ACCESS=SUCCESS`
- 2026-06-19T06:37:02.2520783Z: `POSTFAULT_DEFAULT_ACTION=Deny`
- 2026-06-19T06:37:45.1886817Z: `DETECTION_EXIT_CODE=1`, CLI message: "The request may be blocked by network rules of storage account"
- 2026-06-19T06:38:00.8157575Z: `POSTRESTORE_DEFAULT_ACTION=Allow`
- 2026-06-19T06:38:10.1939041Z: `VERIFICATION_EXIT_CODE=0`, container listing succeeded, `POSTRESTORE_ACCESS=SUCCESS`

## Baseline vs Incident Delta
- Baseline: `networkRuleSet.defaultAction=Allow`; container listing works.
- Incident: `networkRuleSet.defaultAction=Deny`; container listing fails with network-rule block.
- Delta: Single policy drift on storage network default action changed access behavior from success to failure.
