#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource-group> <storage-account-name>"
  exit 1
fi

RG="$1"
SA="$2"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "[$TS] Checking storage baseline state"
STATE="$(az storage account show -g "$RG" -n "$SA" --query "networkRuleSet.defaultAction" -o tsv)"
echo "[$TS] defaultAction=$STATE"

if [[ "$STATE" != "Allow" ]]; then
  echo "[$TS] Baseline check failed; expected Allow"
  exit 2
fi

echo "[$TS] Baseline healthy"
