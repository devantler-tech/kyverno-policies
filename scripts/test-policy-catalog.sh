#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="${repo_root}/policies/best-practices/auto-vpa.yaml"

if [[ ! -f "${policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/auto-vpa.yaml" >&2
  exit 1
fi

rule_count="$(yq '.spec.rules | length' "${policy}")"
synchronized_rule_count="$(
  yq '[.spec.rules[].generate | select(.synchronize == true and .generateExisting == true)] | length' \
    "${policy}"
)"

if [[ "${rule_count}" -eq 0 || "${synchronized_rule_count}" -ne "${rule_count}" ]]; then
  echo "FAIL: every auto-vpa rule must synchronize and generate for existing workloads" >&2
  exit 1
fi

kyverno test "${repo_root}/tests/auto-vpa" \
  --require-tests \
  --detailed-results \
  --remove-color

output_dir="$(mktemp -d)"
trap 'rm -rf "${output_dir}"' EXIT

kyverno apply "${policy}" \
  --resource "${repo_root}/tests/auto-vpa/unmatched-job.yaml" \
  --output "${output_dir}" \
  --remove-color >/dev/null

if find "${output_dir}" -type f -print -quit | grep -q .; then
  echo "FAIL: auto-vpa generated a resource for an unmatched Job" >&2
  exit 1
fi
