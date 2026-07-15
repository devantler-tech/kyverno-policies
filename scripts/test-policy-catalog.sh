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

flux_policy="${repo_root}/policies/best-practices/enforce-flux-best-practices.yaml"

if [[ ! -f "${flux_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/enforce-flux-best-practices.yaml" >&2
  exit 1
fi

# The catalog ships this policy in Audit: it is inert until a consumer references
# it and enforcement rollout is the consumer's decision. Guard the safe default so
# an edit cannot accidentally ship Enforce from the shared library.
flux_failure_action="$(yq '.spec.validationFailureAction' "${flux_policy}")"
if [[ "${flux_failure_action}" != "Audit" ]]; then
  echo "FAIL: enforce-flux-best-practices must ship as Audit; enforcement is a consumer rollout choice" >&2
  exit 1
fi

# Every rule must validate (not generate/mutate); this is an admission-check policy.
flux_rule_count="$(yq '.spec.rules | length' "${flux_policy}")"
flux_validate_rule_count="$(yq '[.spec.rules[] | select(has("validate"))] | length' "${flux_policy}")"
if [[ "${flux_rule_count}" -eq 0 || "${flux_validate_rule_count}" -ne "${flux_rule_count}" ]]; then
  echo "FAIL: every enforce-flux-best-practices rule must be a validate rule" >&2
  exit 1
fi

kyverno test "${repo_root}/tests/enforce-flux-best-practices" \
  --require-tests \
  --detailed-results \
  --remove-color
