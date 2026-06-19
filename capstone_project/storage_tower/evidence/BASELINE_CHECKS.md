# Baseline Verification Checklist

## Infrastructure Baseline
- [ ] Terraform apply completed successfully.
- [ ] Post-apply idempotency gate passed (terraform plan -detailed-exitcode returns 0).
- [ ] VM reachable by SSH from approved IP.
- [ ] Storage account exists and container app-data exists.

## Storage Baseline
- [ ] networkRuleSet.defaultAction is Allow.
- [ ] Baseline verifier script returns healthy.
- [ ] Storage read/write test succeeds.

## Gate Evidence
- [ ] Lint output captured.
- [ ] Dry-run plan output captured.
- [ ] Bounded scope check captured.
- [ ] Idempotency output captured.
