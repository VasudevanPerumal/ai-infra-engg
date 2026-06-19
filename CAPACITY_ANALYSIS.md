# FinBridge Quarterly Capacity Planning Report
**Forecast run:** 2026-06-18 06:23 UTC

## 1. EXECUTIVE SUMMARY
Overall infrastructure capacity is healthy for CPU and disk, but database connection growth has become an immediate availability risk. The most urgent item is DB Connections, projected to hit its threshold in 8 days (2026-06-26), requiring an immediate no-cost mitigation (PgBouncer and pool tuning) and short-horizon validation.

## 2. FORECAST SUMMARY TABLE
| Metric | Current | Trend | Forecast date to threshold | Severity |
|---|---:|---|---|---|
| CPU % | 4.00% | +0.050/day (very slow growth) | 2031-03-04 | Low |
| Memory % | 36.20% | +0.916/day (rapid growth) | 2026-08-16 | High |
| Disk % | 35.60% | +0.126/day (moderate growth) | 2027-07-15 | Low-Medium |
| DB Connections | 13 | +0.364/day (fast growth) | 2026-06-26 | Critical |

## 3. RECOMMENDED ACTIONS
| Action | Cost impact | Timeline | Justification |
|---|---|---|---|
| Enable PgBouncer on vm-db and tune app/DB pool limits | $0/month | Start now, complete in 48 hours | Fastest path to reduce connection pressure before projected threshold breach in 8 days; software-only change on existing vm-db. |
| Increase DB connection alerting sensitivity and add daily connection leak review in ops runbook | $0/month | 1 week | Process/config control that catches regression early and prevents silent re-growth after pooling is enabled. |
| Upsize vm-db from Standard_B2ms to Standard_D2s_v5 | +$70.90/month (from $67.80 to $138.70) | Decision in 2 weeks; implement in 2-4 weeks if post-PgBouncer trend remains steep | Provides additional CPU/memory headroom against the 59-day memory threshold and absorbs burst behavior while root-cause fixes stabilize. |
| Add one 64GB managed data disk to vm-db (deferred-ready change) | +$5.12/month | Prepare now, execute only if disk forecast materially accelerates | Low-cost expansion option, but currently not required given 392-day runway; keep as pre-approved contingency. |

## 4. WHAT WE ARE NOT DOING AND WHY
- We are not upsizing vm-app this quarter. CPU is at 4.00% with threshold date in 2031-03-04, so spending +$70.90/month now would be over-provisioning.
- We are not immediately adding disk capacity to address the current forecast. Disk threshold is projected for 2027-07-15, giving substantial runway; adding capacity now is premature unless growth rate changes.
- We are not taking a dual-VM upsize (vm-app and vm-db together) at this time. Current risk is concentrated in DB connections and near-term memory growth, so targeted DB-side action is more cost-efficient.

## 5. NEXT REVIEW DATE
Re-run the forecast on **2026-07-02** (two weeks after this run), immediately after PgBouncer/pool tuning has been in steady state long enough to measure trend change.

Change recommendation if any of the following occurs before then:
- DB Connections growth remains above +0.20/day for 3 consecutive days after pooling changes.
- Memory forecast-to-threshold drops below 45 days.
- A new release materially changes transaction volume or connection behavior.