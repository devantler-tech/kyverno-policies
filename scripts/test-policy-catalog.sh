#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="${repo_root}/policies/best-practices/auto-vpa.yaml"
image_tag_policy="${repo_root}/policies/best-practices/disallow-latest-tag.yaml"
recommended_labels_policy="${repo_root}/policies/best-practices/add-recommended-labels.yaml"
recommended_labels_test="${repo_root}/tests/add-recommended-labels/kyverno-test.yaml"
flux_policy="${repo_root}/policies/flux/enforce-flux-best-practices.yaml"
helm_crds_policy="${repo_root}/policies/flux/helm-release-install-crds.yaml"
helm_test_policy="${repo_root}/policies/flux/helm-release-enable-tests.yaml"
helm_remediation_policy="${repo_root}/policies/flux/helm-release-remediation-retries.yaml"

assert_equal() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${message} (expected ${expected}, got ${actual})" >&2
    exit 1
  fi
}

if [[ ! -f "${policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/auto-vpa.yaml" >&2
  exit 1
fi

if [[ ! -f "${image_tag_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/disallow-latest-tag.yaml" >&2
  exit 1
fi

assert_equal "$(yq '.apiVersion' "${image_tag_policy}")" "kyverno.io/v1" \
  "shared image-tag policy must use kyverno.io/v1"
assert_equal "$(yq '.kind' "${image_tag_policy}")" "ClusterPolicy" \
  "shared image-tag policy must use ClusterPolicy"
assert_equal "$(yq '.metadata.name' "${image_tag_policy}")" "disallow-latest-tag" \
  "shared image-tag policy must use its catalog identity"
assert_equal "$(yq '.metadata.annotations."policies.kyverno.io/minversion"' \
  "${image_tag_policy}")" "1.18.0" \
  "shared image-tag policy must declare the catalog Kyverno floor"
assert_equal "$(yq '.spec.background' "${image_tag_policy}")" "true" \
  "shared image-tag policy must evaluate existing Pods"
assert_equal "$(yq '.spec.rules | length' "${image_tag_policy}")" "2" \
  "shared image-tag policy must expose tag-presence and latest-tag rules"
assert_equal "$(yq '[.spec.rules[].name | select(
  . == "require-image-tag" or . == "disallow-latest-tag"
)] | length' "${image_tag_policy}")" "2" \
  "shared image-tag policy must expose both documented rules"
assert_equal "$(yq '[.spec.rules[].validate | select(.failureAction == "Audit")] | length' \
  "${image_tag_policy}")" "2" \
  "shared image-tag policy must default every rule to Audit"
assert_equal "$(yq '[.spec.rules[].match.any[].resources.kinds[]] | sort | join(",")' \
  "${image_tag_policy}")" "Pod,Pod" \
  "shared image-tag policy must match only Pods"
assert_equal "$(yq '[.. | select(tag == "!!map") | select(has("exclude"))] | length' \
  "${image_tag_policy}")" "0" \
  "shared image-tag policy must leave environment exclusions to consumers"
assert_equal "$(yq '[.spec.rules[] | select(has("mutate") or has("generate"))] | length' \
  "${image_tag_policy}")" "0" \
  "shared image-tag policy must validate without mutating or generating resources"
assert_equal "$(yq '[.resources[] |
  select(. == "policies/best-practices/disallow-latest-tag.yaml")
] | length' "${repo_root}/kustomization.yaml")" "1" \
  "shared image-tag policy must be registered exactly once"

if ! grep -Fq \
  'policies/best-practices/disallow-latest-tag.yaml' \
  "${repo_root}/README.md"; then
  echo "FAIL: README catalog is missing disallow-latest-tag" >&2
  exit 1
fi

if [[ ! -f "${recommended_labels_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/add-recommended-labels.yaml" >&2
  exit 1
fi

if [[ ! -f "${recommended_labels_test}" ]]; then
  echo "FAIL: shared recommended-label policy is missing its behavior contract" >&2
  exit 1
fi

assert_equal "$(yq '.apiVersion' "${recommended_labels_policy}")" "kyverno.io/v1" \
  "shared recommended-label policy must use kyverno.io/v1"
assert_equal "$(yq '.kind' "${recommended_labels_policy}")" "ClusterPolicy" \
  "shared recommended-label policy must use ClusterPolicy"
assert_equal "$(yq '.metadata.name' "${recommended_labels_policy}")" \
  "add-recommended-labels" \
  "shared recommended-label policy must use its catalog identity"
assert_equal "$(yq '.metadata.annotations."policies.kyverno.io/minversion"' \
  "${recommended_labels_policy}")" "1.18.0" \
  "shared recommended-label policy must declare the catalog Kyverno floor"
assert_equal "$(yq '.spec.background' "${recommended_labels_policy}")" "false" \
  "shared recommended-label policy must be admission-only"
assert_equal "$(yq '.spec.rules | length' "${recommended_labels_policy}")" "1" \
  "shared recommended-label policy must expose one mutation rule"
assert_equal "$(yq '.spec.rules[0].name' "${recommended_labels_policy}")" \
  "add-workload-labels" \
  "shared recommended-label policy must use the documented rule identity"
assert_equal "$(yq '.spec.rules[0] | keys | sort | join(",")' \
  "${recommended_labels_policy}")" "exclude,match,mutate,name" \
  "shared recommended-label policy must contain only its match, boundary, and mutation"
assert_equal "$(yq '.spec.rules[0].match.any | length' "${recommended_labels_policy}")" "1" \
  "shared recommended-label policy must expose one match branch"
assert_equal "$(yq '.spec.rules[0].match.any[0].resources | keys | join(",")' \
  "${recommended_labels_policy}")" "kinds" \
  "shared recommended-label policy must match only by kind"
assert_equal "$(yq '.spec.rules[0].match.any[0].resources.kinds | sort | join(",")' \
  "${recommended_labels_policy}")" "DaemonSet,Deployment,StatefulSet" \
  "shared recommended-label policy must match exactly the three workload kinds"
assert_equal "$(yq '.spec.rules[0].exclude.any | length' "${recommended_labels_policy}")" "1" \
  "shared recommended-label policy must expose one system-namespace boundary"
assert_equal "$(yq '.spec.rules[0].exclude.any[0].resources | keys | join(",")' \
  "${recommended_labels_policy}")" "namespaces" \
  "shared recommended-label policy must exclude only by namespace"
assert_equal "$(yq '.spec.rules[0].exclude.any[0].resources.namespaces | sort | join(",")' \
  "${recommended_labels_policy}")" "kube-node-lease,kube-public,kube-system" \
  "shared recommended-label policy must preserve the three Kubernetes system namespaces"
assert_equal "$(yq '.spec.rules[0].mutate | keys | join(",")' \
  "${recommended_labels_policy}")" "patchStrategicMerge" \
  "shared recommended-label policy must use only a strategic-merge patch"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge | keys | sort | join(",")' \
  "${recommended_labels_policy}")" "metadata,spec" \
  "shared recommended-label policy must mutate only workload and pod-template metadata"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.metadata.labels | keys | sort | join(",")' \
  "${recommended_labels_policy}")" "+(app),+(app.kubernetes.io/name)" \
  "shared recommended-label policy must add both missing workload labels conditionally"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.spec.template.metadata.labels | keys | join(",")' \
  "${recommended_labels_policy}")" "+(app.kubernetes.io/name)" \
  "shared recommended-label policy must add the missing pod-template name conditionally"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.metadata.labels."+(app)"' \
  "${recommended_labels_policy}")" '{{ request.object.metadata.name }}' \
  "shared recommended-label policy must derive app from the workload name"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.metadata.labels."+(app.kubernetes.io/name)"' \
  "${recommended_labels_policy}")" '{{ request.object.metadata.name }}' \
  "shared recommended-label policy must derive the workload name label from the workload name"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.spec.template.metadata.labels."+(app.kubernetes.io/name)"' \
  "${recommended_labels_policy}")" '{{ request.object.metadata.name }}' \
  "shared recommended-label policy must derive the pod-template name label from the workload name"
assert_equal "$(yq '[.resources[] |
  select(. == "policies/best-practices/add-recommended-labels.yaml")
] | length' "${repo_root}/kustomization.yaml")" "1" \
  "shared recommended-label policy must be registered exactly once"

if ! grep -Fq \
  'policies/best-practices/add-recommended-labels.yaml' \
  "${repo_root}/README.md"; then
  echo "FAIL: README catalog is missing add-recommended-labels" >&2
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

if [[ ! -f "${helm_test_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/flux/helm-release-enable-tests.yaml" >&2
  exit 1
fi

helm_test_rule_count="$(yq '.spec.rules | length' "${helm_test_policy}")"
helm_test_required_rule_count="$(
  yq '[.spec.rules[].name | select(. == "enable-helm-tests")] | length' "${helm_test_policy}"
)"
helm_test_background="$(yq '.spec.background' "${helm_test_policy}")"
helm_test_rule_key_count="$(yq '.spec.rules[0] | keys | length' "${helm_test_policy}")"
helm_test_match_branch_count="$(yq '.spec.rules[0].match.any | length' "${helm_test_policy}")"
helm_test_resource_match_key_count="$(
  yq '.spec.rules[0].match.any[0].resources | keys | length' "${helm_test_policy}"
)"
helm_test_kind_count="$(yq '.spec.rules[0].match.any[0].resources.kinds | length' "${helm_test_policy}")"
helm_test_kind="$(yq '.spec.rules[0].match.any[0].resources.kinds[0]' "${helm_test_policy}")"
helm_test_operation_count="$(
  yq '.spec.rules[0].match.any[0].resources.operations | length' "${helm_test_policy}"
)"
helm_test_create_operation_count="$(
  yq '[.spec.rules[0].match.any[0].resources.operations[] | select(. == "CREATE")] | length' \
    "${helm_test_policy}"
)"
helm_test_update_operation_count="$(
  yq '[.spec.rules[0].match.any[0].resources.operations[] | select(. == "UPDATE")] | length' \
    "${helm_test_policy}"
)"
helm_test_selector_key_count="$(
  yq '.spec.rules[0].match.any[0].resources.selector | keys | length' "${helm_test_policy}"
)"
helm_test_selector_label_count="$(
  yq '.spec.rules[0].match.any[0].resources.selector.matchLabels | length' "${helm_test_policy}"
)"
helm_test_selector="$(
  yq '.spec.rules[0].match.any[0].resources.selector.matchLabels."helm.toolkit.fluxcd.io/helm-test"' \
    "${helm_test_policy}"
)"
helm_test_selector_expression_count="$(
  yq '.spec.rules[0].match.any[0].resources.selector.matchExpressions // [] | length' \
    "${helm_test_policy}"
)"
helm_test_mutate_key_count="$(yq '.spec.rules[0].mutate | keys | length' "${helm_test_policy}")"
helm_test_patch_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge | keys | length' "${helm_test_policy}"
)"
helm_test_patch_spec_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec | keys | length' "${helm_test_policy}"
)"
helm_test_patch_test_key_count="$(
  yq '.spec.rules[0].mutate.patchStrategicMerge.spec.test | keys | length' "${helm_test_policy}"
)"
helm_test_enabled="$(yq '.spec.rules[0].mutate.patchStrategicMerge.spec.test.enable' "${helm_test_policy}")"
helm_test_minversion="$(yq '.metadata.annotations."policies.kyverno.io/minversion"' "${helm_test_policy}")"
helm_test_catalog_entry_count="$(
  yq '[.resources[] | select(. == "policies/flux/helm-release-enable-tests.yaml")] | length' \
    "${repo_root}/kustomization.yaml"
)"

if [[ "${helm_test_rule_count}" -ne 1 || "${helm_test_required_rule_count}" -ne 1 ]]; then
  echo "FAIL: shared Helm test policy must expose only the enable-helm-tests rule" >&2
  exit 1
fi

if [[ "${helm_test_background}" != "false" || "${helm_test_rule_key_count}" -ne 3 ]]; then
  echo "FAIL: shared Helm test policy must contain only one admission-time rule" >&2
  exit 1
fi

if [[ "${helm_test_match_branch_count}" -ne 1 || "${helm_test_resource_match_key_count}" -ne 3 ||
  "${helm_test_kind_count}" -ne 1 || "${helm_test_kind}" != "helm.toolkit.fluxcd.io/v2/HelmRelease" ]]; then
  echo "FAIL: shared Helm test policy must match only the served HelmRelease v2 API" >&2
  exit 1
fi

if [[ "${helm_test_operation_count}" -ne 2 || "${helm_test_create_operation_count}" -ne 1 ||
  "${helm_test_update_operation_count}" -ne 1 ]]; then
  echo "FAIL: shared Helm test policy must mutate only create and update admissions" >&2
  exit 1
fi

if [[ "${helm_test_selector_key_count}" -ne 1 || "${helm_test_selector_label_count}" -ne 1 ||
  "${helm_test_selector_expression_count}" -ne 0 || "${helm_test_selector}" != "enabled" ]]; then
  echo "FAIL: shared Helm test policy must use only the documented opt-in label" >&2
  exit 1
fi

if [[ "${helm_test_mutate_key_count}" -ne 1 || "${helm_test_patch_key_count}" -ne 1 ||
  "${helm_test_patch_spec_key_count}" -ne 1 || "${helm_test_patch_test_key_count}" -ne 1 ||
  "${helm_test_enabled}" != "true" ]]; then
  echo "FAIL: shared Helm test policy must mutate only spec.test.enable" >&2
  exit 1
fi

if [[ "${helm_test_minversion}" != "1.18.0" ]]; then
  echo "FAIL: shared Helm test policy must declare the catalog's Kyverno 1.18.0 floor" >&2
  exit 1
fi

if [[ "${helm_test_catalog_entry_count}" -ne 1 ]]; then
  echo "FAIL: shared Helm test policy must be registered exactly once in the root catalog" >&2
  exit 1
fi

if [[ ! -f "${helm_remediation_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/flux/helm-release-remediation-retries.yaml" >&2
  exit 1
fi

assert_equal "$(yq '.apiVersion' "${helm_remediation_policy}")" "kyverno.io/v1" \
  "shared Helm remediation policy must use kyverno.io/v1"
assert_equal "$(yq '.kind' "${helm_remediation_policy}")" "ClusterPolicy" \
  "shared Helm remediation policy must use ClusterPolicy"
assert_equal "$(yq '.metadata.name' "${helm_remediation_policy}")" \
  "helm-release-remediation-retries" \
  "shared Helm remediation policy must use its catalog identity"
assert_equal "$(yq '.metadata.annotations."policies.kyverno.io/minversion"' \
  "${helm_remediation_policy}")" "1.18.0" \
  "shared Helm remediation policy must declare the catalog Kyverno floor"
assert_equal "$(yq '.spec.background' "${helm_remediation_policy}")" "false" \
  "shared Helm remediation policy must be admission-only"
assert_equal "$(yq '.spec.rules | length' "${helm_remediation_policy}")" "2" \
  "shared Helm remediation policy must expose two independent rules"
assert_equal "$(yq '[.. | select(tag == "!!map") |
  select(has("targets") or has("mutateExisting") or has("mutateExistingOnPolicyUpdate"))
] | length' "${helm_remediation_policy}")" "0" \
  "shared Helm remediation policy must not mutate existing or targeted resources"
assert_equal "$(yq '[.resources[] |
  select(. == "policies/flux/helm-release-remediation-retries.yaml")
] | length' "${repo_root}/kustomization.yaml")" "1" \
  "shared Helm remediation policy must be registered exactly once"

for side in install upgrade; do
  rule_name="default-${side}-remediation"
  expected_strategy_precondition="{{ request.object.spec.${side}.strategy.name || '' }}"
  expected_retries_precondition="{{ request.object.spec.${side}.remediation.retries || '' }}"

  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules | map(select(.name == env(RULE_NAME))) | length' \
    "${helm_remediation_policy}")" "1" \
    "shared Helm remediation policy must define the ${side} rule exactly once"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | keys | sort | join(",")' \
    "${helm_remediation_policy}")" "match,mutate,name,preconditions" \
    "shared Helm ${side} remediation rule must contain only its rule contract"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .match.any | length' \
    "${helm_remediation_policy}")" "1" \
    "shared Helm ${side} remediation must have one match branch"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .match.any[0].resources | keys | sort | join(",")' \
    "${helm_remediation_policy}")" "kinds,operations,selector" \
    "shared Helm ${side} remediation must contain only the admission match contract"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .match.any[0].resources.kinds | join(",")' \
    "${helm_remediation_policy}")" "helm.toolkit.fluxcd.io/v2/HelmRelease" \
    "shared Helm ${side} remediation must match only HelmRelease v2"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .match.any[0].resources.operations | sort | join(",")' \
    "${helm_remediation_policy}")" "CREATE,UPDATE" \
    "shared Helm ${side} remediation must match create and update admissions"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .match.any[0].resources.selector | keys | join(",")' \
    "${helm_remediation_policy}")" "matchLabels" \
    "shared Helm ${side} remediation must use only a label selector"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .match.any[0].resources.selector.matchLabels | keys | join(",")' \
    "${helm_remediation_policy}")" "helm.toolkit.fluxcd.io/remediation" \
    "shared Helm ${side} remediation must use only the documented opt-in label"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .match.any[0].resources.selector.matchLabels."helm.toolkit.fluxcd.io/remediation"' \
    "${helm_remediation_policy}")" "enabled" \
    "shared Helm ${side} remediation must require explicit opt-in"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .preconditions | keys | join(",")' \
    "${helm_remediation_policy}")" "all" \
    "shared Helm ${side} remediation must use one precondition group"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .preconditions.all | length' \
    "${helm_remediation_policy}")" "2" \
    "shared Helm ${side} remediation must use two missing-safe conditions"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .preconditions.all[0] | keys | sort | join(",")' \
    "${helm_remediation_policy}")" "key,operator,value" \
    "shared Helm ${side} remediation condition must contain only key, operator, and value"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .preconditions.all[0].key' \
    "${helm_remediation_policy}")" "${expected_strategy_precondition}" \
    "shared Helm ${side} remediation must safely read a missing strategy"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .preconditions.all[0].operator' \
    "${helm_remediation_policy}")" "NotEquals" \
    "shared Helm ${side} remediation strategy guard must use NotEquals"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .preconditions.all[0].value' \
    "${helm_remediation_policy}")" "RetryOnFailure" \
    "shared Helm ${side} remediation strategy guard must skip RetryOnFailure"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .preconditions.all[1] | keys | sort | join(",")' \
    "${helm_remediation_policy}")" "key,operator,value" \
    "shared Helm ${side} zero-retry condition must contain only key, operator, and value"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .preconditions.all[1].key' \
    "${helm_remediation_policy}")" "${expected_retries_precondition}" \
    "shared Helm ${side} remediation must safely read a missing retry count"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .preconditions.all[1].operator' \
    "${helm_remediation_policy}")" "NotEquals" \
    "shared Helm ${side} remediation must preserve an explicit zero-retry default"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .preconditions.all[1].value' \
    "${helm_remediation_policy}")" "0" \
    "shared Helm ${side} remediation must preserve an explicit zero-retry default"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) | .mutate | keys | join(",")' \
    "${helm_remediation_policy}")" "patchStrategicMerge" \
    "shared Helm ${side} remediation must use only strategic merge"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .mutate.patchStrategicMerge | keys | join(",")' \
    "${helm_remediation_policy}")" "spec" \
    "shared Helm ${side} remediation patch must touch only spec"
  assert_equal "$(RULE_NAME="${rule_name}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .mutate.patchStrategicMerge.spec | keys | join(",")' \
    "${helm_remediation_policy}")" "${side}" \
    "shared Helm ${side} remediation patch must touch only its action"
  assert_equal "$(RULE_NAME="${rule_name}" SIDE="${side}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .mutate.patchStrategicMerge.spec[env(SIDE)] | keys | join(",")' \
    "${helm_remediation_policy}")" "remediation" \
    "shared Helm ${side} remediation patch must preserve action siblings"
  assert_equal "$(RULE_NAME="${rule_name}" SIDE="${side}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .mutate.patchStrategicMerge.spec[env(SIDE)].remediation | keys | sort | join(",")' \
    "${helm_remediation_policy}")" "+(remediateLastFailure),+(retries)" \
    "shared Helm ${side} remediation must add only missing scalar leaves"
  assert_equal "$(RULE_NAME="${rule_name}" SIDE="${side}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .mutate.patchStrategicMerge.spec[env(SIDE)].remediation."+(retries)"' \
    "${helm_remediation_policy}")" "-1" \
    "shared Helm ${side} remediation must default to unlimited retries"
  assert_equal "$(RULE_NAME="${rule_name}" SIDE="${side}" yq \
    '.spec.rules[] | select(.name == env(RULE_NAME)) |
      .mutate.patchStrategicMerge.spec[env(SIDE)].remediation."+(remediateLastFailure)"' \
    "${helm_remediation_policy}")" "true" \
    "shared Helm ${side} remediation must default last-failure remediation"
done

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

# The GeneratingPolicy port of auto-vpa and the classic form generate a VerticalPodAutoscaler
# under the SAME name for the SAME workload. Registering both in the catalog would have two
# policies contend for one object on every consumer cluster, so the catalog may carry at most
# one of them -- and must never carry neither, which would silently drop auto-vpa entirely.
# This is what keeps the port default-off while it is unadopted, and it stays correct after
# adoption flips which of the two is registered.
ported_vpa_policy="${repo_root}/policies/best-practices/auto-vpa-generating-policy.yaml"

if [[ ! -f "${ported_vpa_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/auto-vpa-generating-policy.yaml" >&2
  exit 1
fi

classic_vpa_registered="$(
  yq '[.resources[] | select(. == "policies/best-practices/auto-vpa.yaml")] | length' \
    "${repo_root}/kustomization.yaml"
)"
ported_vpa_registered="$(
  yq '[.resources[] | select(. == "policies/best-practices/auto-vpa-generating-policy.yaml")] | length' \
    "${repo_root}/kustomization.yaml"
)"

if [[ "${classic_vpa_registered}" -gt 0 && "${ported_vpa_registered}" -gt 0 ]]; then
  echo "FAIL: classic and GeneratingPolicy auto-vpa must not both be registered" >&2
  exit 1
fi

if [[ "${classic_vpa_registered}" -eq 0 && "${ported_vpa_registered}" -eq 0 ]]; then
  echo "FAIL: the catalog must register exactly one auto-vpa form" >&2
  exit 1
fi

ported_vpa_policy_count="$(yq --no-doc '.metadata.name' "${ported_vpa_policy}" | wc -l | tr -d ' ')"

if [[ "${ported_vpa_policy_count}" -ne 3 ]]; then
  echo "FAIL: ported auto-vpa must define one GeneratingPolicy per workload kind" >&2
  exit 1
fi

# The ported policies must use the graduated API: v1alpha1 is marked deprecated on the
# GeneratingPolicy CRD at the catalog's 1.18 floor (still served there, but scheduled to
# disappear), so only policies.kyverno.io/v1 keeps the catalog forward-compatible.
ported_vpa_v1_count="$(
  yq --no-doc '[select(.apiVersion == "policies.kyverno.io/v1")] | length' \
    "${ported_vpa_policy}" | awk '{s+=$1} END {print s}'
)"

if [[ "${ported_vpa_v1_count}" -ne 3 ]]; then
  echo "FAIL: ported auto-vpa must use the graduated policies.kyverno.io/v1 API" >&2
  exit 1
fi

# Parity with the classic rules' synchronize/generateExisting: on GeneratingPolicy both
# live under spec.evaluation and DEFAULT TO FALSE, so a port that omits them silently
# drops behavior the classic policy guarantees.
ported_vpa_synchronized_count="$(
  yq --no-doc '[select(.spec.evaluation.synchronize.enabled == true and .spec.evaluation.generateExisting.enabled == true)] | length' \
    "${ported_vpa_policy}" | awk '{s+=$1} END {print s}'
)"

if [[ "${ported_vpa_synchronized_count}" -ne 3 ]]; then
  echo "FAIL: every ported auto-vpa policy must enable evaluation.synchronize and evaluation.generateExisting" >&2
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

# Declarative behavior specs (tests/*/kyverno-test.yaml) are NOT run here: CI runs
# `kyverno test .` from the repo root, which discovers every fixture recursively.
# Listing fixture paths here instead meant a new policy's fixture was silently never
# executed until someone remembered to add it below. This script now asserts only the
# structural invariants that `kyverno test` cannot express.

output_dir="$(mktemp -d)"
ported_positive_dir="$(mktemp -d)"
ported_negative_dir="$(mktemp -d)"
trap 'rm -rf "${output_dir}" "${ported_positive_dir}" "${ported_negative_dir}"' EXIT

kyverno apply "${policy}" \
  --resource "${repo_root}/tests/auto-vpa/unmatched-job.yaml" \
  --output "${output_dir}" \
  --remove-color >/dev/null

if find "${output_dir}" -type f -print -quit | grep -q .; then
  echo "FAIL: auto-vpa generated a resource for an unmatched Job" >&2
  exit 1
fi

# The same matched/unmatched control pair for the PORTED form, registered or not — the
# port ships in this repo, so its behavior is held here rather than only after adoption.
# The positive control comes FIRST because it is what gives the negative control teeth:
# `kyverno apply` silently drops a policy it cannot parse ("Applying 0 policy rule(s)",
# exit 0), which would make "no files generated for a Job" pass vacuously.
kyverno apply "${ported_vpa_policy}" \
  --resource "${repo_root}/tests/auto-vpa/resources.yaml" \
  --output "${ported_positive_dir}" \
  --remove-color >/dev/null

ported_generated_count="$(find "${ported_positive_dir}" -type f | wc -l | tr -d ' ')"

if [[ "${ported_generated_count}" -ne 3 ]]; then
  echo "FAIL: ported auto-vpa must generate one VPA per matched workload kind (got ${ported_generated_count})" >&2
  exit 1
fi

kyverno apply "${ported_vpa_policy}" \
  --resource "${repo_root}/tests/auto-vpa/unmatched-job.yaml" \
  --output "${ported_negative_dir}" \
  --remove-color >/dev/null

if find "${ported_negative_dir}" -type f -print -quit | grep -q .; then
  echo "FAIL: ported auto-vpa generated a resource for an unmatched Job" >&2
  exit 1
fi
