#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="${repo_root}/policies/best-practices/auto-vpa.yaml"
flux_policy="${repo_root}/policies/flux/enforce-flux-best-practices.yaml"
helm_crds_policy="${repo_root}/policies/flux/helm-release-install-crds.yaml"

if [[ ! -f "${policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/auto-vpa.yaml" >&2
  exit 1
fi

if [[ ! -f "${flux_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/flux/enforce-flux-best-practices.yaml" >&2
  exit 1
fi

if [[ ! -f "${helm_crds_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/flux/helm-release-install-crds.yaml" >&2
  exit 1
fi

helm_crds_rule_count="$(yq '.spec.rules | length' "${helm_crds_policy}")"
helm_crds_required_rule_count="$(
  yq '[.spec.rules[].name | select(. == "set-helm-release-install-crds")] | length' \
    "${helm_crds_policy}"
)"
helm_crds_background="$(yq '.spec.background' "${helm_crds_policy}")"
helm_crds_rule_key_count="$(yq '.spec.rules[0] | keys | length' "${helm_crds_policy}")"
helm_crds_match_branch_count="$(yq '.spec.rules[0].match.any | length' "${helm_crds_policy}")"
helm_crds_resource_match_key_count="$(
  yq '.spec.rules[0].match.any[0].resources | keys | length' "${helm_crds_policy}"
)"
helm_crds_kind_count="$(
  yq '.spec.rules[0].match.any[0].resources.kinds | length' "${helm_crds_policy}"
)"
helm_crds_kind="$(yq '.spec.rules[0].match.any[0].resources.kinds[0]' "${helm_crds_policy}")"
helm_crds_operation_count="$(
  yq '.spec.rules[0].match.any[0].resources.operations | length' "${helm_crds_policy}"
)"
helm_crds_create_operation_count="$(
  yq '[.spec.rules[0].match.any[0].resources.operations[] | select(. == "CREATE")] | length' \
    "${helm_crds_policy}"
)"
helm_crds_update_operation_count="$(
  yq '[.spec.rules[0].match.any[0].resources.operations[] | select(. == "UPDATE")] | length' \
    "${helm_crds_policy}"
)"
helm_crds_selector_key_count="$(
  yq '.spec.rules[0].match.any[0].resources.selector | keys | length' "${helm_crds_policy}"
)"
helm_crds_selector_label_count="$(
  yq '.spec.rules[0].match.any[0].resources.selector.matchLabels | length' "${helm_crds_policy}"
)"
helm_crds_selector="$(
  yq '.spec.rules[0].match.any[0].resources.selector.matchLabels."helm.toolkit.fluxcd.io/crds"' \
    "${helm_crds_policy}"
)"
helm_crds_selector_expression_count="$(
  yq '.spec.rules[0].match.any[0].resources.selector.matchExpressions // [] | length' \
    "${helm_crds_policy}"
)"
helm_crds_mutate_key_count="$(yq '.spec.rules[0].mutate | keys | length' "${helm_crds_policy}")"
helm_crds_patch_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge | keys | length' "${helm_crds_policy}"
)"
helm_crds_patch_spec_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec | keys | length' "${helm_crds_policy}"
)"
helm_crds_install_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec.install | keys | length' "${helm_crds_policy}"
)"
helm_crds_upgrade_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec.upgrade | keys | length' "${helm_crds_policy}"
)"
helm_crds_install_value="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec.install.crds' "${helm_crds_policy}"
)"
helm_crds_upgrade_value="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec.upgrade.crds' "${helm_crds_policy}"
)"
helm_crds_minversion="$(
  yq '.metadata.annotations."policies.kyverno.io/minversion"' "${helm_crds_policy}"
)"
helm_crds_catalog_entry_count="$(
  yq '[.resources[] | select(. == "policies/flux/helm-release-install-crds.yaml")] | length' \
    "${repo_root}/kustomization.yaml"
)"

if [[ "${helm_crds_rule_count}" -ne 1 || "${helm_crds_required_rule_count}" -ne 1 ]]; then
  echo "FAIL: shared Helm CRD policy must expose only the set-helm-release-install-crds rule" >&2
  exit 1
fi

if [[ "${helm_crds_background}" != "false" || "${helm_crds_rule_key_count}" -ne 3 ]]; then
  echo "FAIL: shared Helm CRD policy must contain only one admission-time rule" >&2
  exit 1
fi

if [[ "${helm_crds_match_branch_count}" -ne 1 || "${helm_crds_resource_match_key_count}" -ne 3 ||
  "${helm_crds_kind_count}" -ne 1 ||
  "${helm_crds_kind}" != "helm.toolkit.fluxcd.io/v2/HelmRelease" ]]; then
  echo "FAIL: shared Helm CRD policy must match only the served HelmRelease v2 API" >&2
  exit 1
fi

if [[ "${helm_crds_operation_count}" -ne 2 || "${helm_crds_create_operation_count}" -ne 1 ||
  "${helm_crds_update_operation_count}" -ne 1 ]]; then
  echo "FAIL: shared Helm CRD policy must mutate only create and update admissions" >&2
  exit 1
fi

if [[ "${helm_crds_selector_key_count}" -ne 1 || "${helm_crds_selector_label_count}" -ne 1 ||
  "${helm_crds_selector_expression_count}" -ne 0 || "${helm_crds_selector}" != "enabled" ]]; then
  echo "FAIL: shared Helm CRD policy must use only the documented opt-in label" >&2
  exit 1
fi

if [[ "${helm_crds_mutate_key_count}" -ne 1 || "${helm_crds_patch_key_count}" -ne 1 ||
  "${helm_crds_patch_spec_key_count}" -ne 2 || "${helm_crds_install_key_count}" -ne 1 ||
  "${helm_crds_upgrade_key_count}" -ne 1 || "${helm_crds_install_value}" != "CreateReplace" ||
  "${helm_crds_upgrade_value}" != "CreateReplace" ]]; then
  echo "FAIL: shared Helm CRD policy must mutate only install and upgrade CRD strategies" >&2
  exit 1
fi

if [[ "${helm_crds_minversion}" != "1.18.0" ]]; then
  echo "FAIL: shared Helm CRD policy must declare the catalog's Kyverno 1.18.0 floor" >&2
  exit 1
fi

if [[ "${helm_crds_catalog_entry_count}" -ne 1 ]]; then
  echo "FAIL: shared Helm CRD policy must be registered exactly once in the root catalog" >&2
  exit 1
fi

flux_rule_count="$(yq '.spec.rules | length' "${flux_policy}")"
flux_audit_rule_count="$(
  yq '[.spec.rules[].validate | select(.failureAction == "Audit")] | length' "${flux_policy}"
)"
flux_required_rule_count="$(
  yq '[.spec.rules[].name | select(
    . == "kustomization-recommended-settings" or
    . == "helmrelease-reconciliation-settings" or
    . == "helmrelease-install-failure-handling" or
    . == "helmrelease-upgrade-failure-handling"
  )] | length' "${flux_policy}"
)"
flux_kustomization_match_count="$(
  yq '[.spec.rules[] |
    select(.name == "kustomization-recommended-settings") |
    .match.any[].resources.kinds[] |
    select(. == "kustomize.toolkit.fluxcd.io/v1/Kustomization")
  ] | length' "${flux_policy}"
)"
flux_helmrelease_match_count="$(
  yq '[.spec.rules[] |
    select(.name == "helmrelease-reconciliation-settings" or
      .name == "helmrelease-install-failure-handling" or
      .name == "helmrelease-upgrade-failure-handling") |
    .match.any[].resources.kinds[] |
    select(. == "helm.toolkit.fluxcd.io/v2/HelmRelease")
  ] | length' "${flux_policy}"
)"
flux_legacy_helmrelease_match_count="$(
  yq '[.spec.rules[].match.any[].resources.kinds[] |
    select(. == "helm.toolkit.fluxcd.io/v2beta1/HelmRelease" or
      . == "helm.toolkit.fluxcd.io/v2beta2/HelmRelease")
  ] | length' "${flux_policy}"
)"
flux_minversion="$(yq '.metadata.annotations."policies.kyverno.io/minversion"' "${flux_policy}")"

if [[ "${flux_rule_count}" -eq 0 || "${flux_audit_rule_count}" -ne "${flux_rule_count}" ]]; then
  echo "FAIL: every shared Flux validation rule must default to Audit" >&2
  exit 1
fi

if [[ "${flux_minversion}" != "1.18.0" ]]; then
  echo "FAIL: shared Flux policy must declare the catalog's Kyverno 1.18.0 floor" >&2
  exit 1
fi

if [[ "${flux_required_rule_count}" -ne 4 ]]; then
  echo "FAIL: shared Flux policy must validate reconciliation plus both failure strategies" >&2
  exit 1
fi

if [[ "${flux_kustomization_match_count}" -ne 1 || "${flux_helmrelease_match_count}" -ne 3 ]]; then
  echo "FAIL: shared Flux rules must match the served Kustomization v1 and HelmRelease v2 APIs" >&2
  exit 1
fi

if [[ "${flux_legacy_helmrelease_match_count}" -ne 0 ]]; then
  echo "FAIL: shared Flux policy must not match unserved HelmRelease beta APIs" >&2
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

kyverno test "${repo_root}/tests/enforce-flux-best-practices" \
  --require-tests \
  --detailed-results \
  --remove-color

kyverno test "${repo_root}/tests/helm-release-install-crds" \
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
