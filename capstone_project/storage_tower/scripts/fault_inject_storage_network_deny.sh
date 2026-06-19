#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource-group> <storage-account-name>"
  exit 1
fi

RG="$1"
SA="$2"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "[$TS] Injecting storage fault: set default network action to Deny"
BEFORE="$(az storage account show -g "$RG" -n "$SA" --query "networkRuleSet.defaultAction" -o tsv)"
echo "[$TS] Before defaultAction=$BEFORE"

az storage account update -g "$RG" -n "$SA" --default-action Deny --only-show-errors 1>/dev/null
AFTER="$(az storage account show -g "$RG" -n "$SA" --query "networkRuleSet.defaultAction" -o tsv)"

echo "[$TS] After defaultAction=$AFTER"
if [[ "$AFTER" != "Deny" ]]; then
  echo "Fault injection failed; expected Deny"
  exit 2
fi

echo "[$TS] Fault injected successfully"
