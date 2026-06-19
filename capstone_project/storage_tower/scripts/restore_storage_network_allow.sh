#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource-group> <storage-account-name>"
  exit 1
fi

RG="$1"
SA="$2"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

CURRENT="$(az storage account show -g "$RG" -n "$SA" --query "networkRuleSet.defaultAction" -o tsv)"
echo "[$TS] Current defaultAction=$CURRENT"

if [[ "$CURRENT" == "Allow" ]]; then
  echo "[$TS] Restore already in place (idempotent success)"
  exit 0
fi

az storage account update -g "$RG" -n "$SA" --default-action Allow --only-show-errors 1>/dev/null
UPDATED="$(az storage account show -g "$RG" -n "$SA" --query "networkRuleSet.defaultAction" -o tsv)"

echo "[$TS] Updated defaultAction=$UPDATED"
if [[ "$UPDATED" != "Allow" ]]; then
  echo "Restore failed; expected Allow"
  exit 2
fi

echo "[$TS] Restore successful"
