# Prompt Library (Diagnosis, Automation, Documentation)

## 1) Build / IaC Prompt
Prompt:
"Create fresh Terraform for Azure Storage tower with RG, VNet/subnet, NSG, public-IP Linux VM with SSH key auth, and a storage account + private container. Add variables, outputs, and safe defaults for a capstone lab."

Kept:
- Resource decomposition into providers, variables, main, outputs.
- SSH key-only VM access.

Changed:
- Tightened NSG source to operator CIDR input.
- Added bounded-scope checks in PowerShell gate script.

Rejected:
- Any suggestion to hardcode open SSH from 0.0.0.0/0.

## 2) Gate Validation Prompt
Prompt:
"Design Day 4 gate checks for Terraform: lint, dry-run, idempotency, and bounded scope with explicit fail conditions."

Kept:
- Preapply and postapply modes.
- Plan JSON parsing for scope control.

Changed:
- Enforced no delete/delete_before_replace actions.
- Whitelisted expected resource types for this module.

Rejected:
- Soft warnings for destructive changes; converted to hard failures.

## 3) Fault/Restore Prompt
Prompt:
"For Storage tower, propose a reversible fault and paired restore scripts where rollback can be tested safely before break."

Kept:
- Fault by changing storage network default action to Deny.
- Restore by setting default action back to Allow.

Changed:
- Added idempotent checks and timestamped outputs.
- Added explicit usage arguments and non-zero exits on failure.

Rejected:
- Fault ideas that risk permanent data loss or destructive mutations.

## 4) Detection and Hypothesis Prompt
Prompt:
"Given these observations and timestamps, generate an incident hypothesis and the fastest safe validation steps to confirm root cause."

Kept:
- Drift hypothesis around storage network policy.
- Validate via direct Azure CLI state inspection.

Changed:
- Required baseline-vs-incident delta section in evidence log.

Rejected:
- Guess-based diagnosis without direct state comparison.

## 5) RCA Drafting Prompt
Prompt:
"Draft an RCA with summary, timeline, technical root cause, contributing factors, remediation, recovery validation, and prevention actions suitable for receiving Ops."

Kept:
- Standard RCA structure and prevention section.

Changed:
- Added explicit evidence index and operational handover references.

Rejected:
- Vague corrective actions without owner-ready implementation direction.
