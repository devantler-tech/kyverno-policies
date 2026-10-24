#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# ---------------------------------------------------------------------------------------------
# WHY THIS SCRIPT IS NOT REDUNDANT WITH tests/*/kyverno-test.yaml  (see #31, #32)
#
# The shape assertions below look like duplicates of the declarative fixtures. They are not. Three
# successive attempts to delete them were each refuted by measurement, and the reason is structural:
# the unit of coverage is the MUTATION, not the assertion. One assertion typically constrains
# several mutations at once — some the fixtures also catch, some nothing else catches — so no
# assertion owns a single behaviour change, and "how many of these are redundant?" has no answer at
# the per-assertion level. The tables below are a map of MUTATIONS to coverage; read them that way
# and see the per-mutation section at the end. Do not repeat this refactor without re-running the
# measurement — inspection gives the wrong answer with high confidence.
#
# SCOPE OF THE MEASUREMENT. 17 mutations were measured, all against the `add-recommended-labels`
# section. This file has
# 78 assertions in total; the image-tag, Flux/Helm and auto-VPA checks were NOT mutation-tested, so
# they are neither proven load-bearing nor proven redundant. Measure before touching them.
# All figures below were measured with the repo-pinned Kyverno CLI **1.18.2** and re-measured
# unchanged on **1.19.1** (`KYVERNO_CLI_VERSION`): baseline 127/0, rule rename 127/0, sole-rule
# deletion 116/11, dropped `spec` branch 123/4, `+(workload)` on workload metadata 122/5 and on the pod
# template 127/0, `monitoring` exclusion 127/0, `LessThanOrEquals 63` -> `NotEquals 64` 127/0. They
# depend on CLI evaluator behaviour — notably how `Excluded` rows are scored — so re-measure after any
# CLI bump rather than trusting these numbers.
#
# The fixtures are weaker than they look, in three ways:
#
#   1. RULE IDENTITY IS UNENFORCED FOR A RENAME (#32). Renaming the rule leaves the fixture suite
#      fully GREEN (127/0). Mechanism, as actually observed: when no rule matches the fixture's
#      `rule:` key, EVERY row reports `Excluded`, and `Excluded` satisfies both expectation types
#      this fixture uses — `result: pass` (4 rows) and `result: skip` (7 rows). Critically, the
#      `pass` rows carry `patchedResources`, and that comparison is simply never performed once the
#      row is Excluded, so the mutation's whole point goes unchecked. (This fixture has no
#      `result: fail` rows at all — an earlier draft of this comment wrongly explained the blindness
#      that way.) The rule-NAME assertion is the only guard against a silent rename.
#      Deletion is a different story, and the earlier draft of this comment got it wrong: deleting
#      this policy's SOLE rule does turn the fixtures red (116/11). #32's fail-open applies where a
#      policy keeps other rules — the surviving rules keep it loadable while the deleted rule's
#      fixture rows silently downgrade to `Excluded`. The rule-count assertion also fires here, so
#      it is a second guard against disappearance, not the only one.
#
#   2. FIXTURES CANNOT SEE SOME ADDITIONS — but which ones depends on the patch location, so measure
#      rather than assume. Both of these leave the suite fully green (127 pass / 0 fail):
#        - adding `monitoring` to the namespace exclusions — undetected specifically because no
#          fixture resource lives in `monitoring`. (Fixtures DO live outside the excluded
#          namespaces — most are in `apps` — so "nothing outside the list" is not the reason.)
#        - adding `+(workload)` to the POD-TEMPLATE patch — every fixture's pod template already
#          carries a `workload` label, so the add-anchor is a no-op on every one of them
#      The same addition on the WORKLOAD-METADATA patch IS caught (5 failures): no fixture carries
#      `metadata.labels.workload` at workload level, so the anchor really adds a label there. The
#      `keys | sort | join(",")` closure assertions exist for the blind direction.
#
#   3. FIXTURES CANNOT SEE COMPENSATING PAIRS — changes that preserve every fixture result while
#      moving behaviour outside the range the fixtures pin. Three measured, all undetected:
#        - `LessThanOrEquals 63` -> `NotEquals 64`  (identical at 63 and 64; lets 65+ be mutated
#          into invalid label values)
#        - `NotEquals ""` -> `NotIn ["", "blocked"]` (silently excludes a valid workload)
#        - a label value of `generateName || name || ''` (named fixtures omit `generateName`, the
#          generateName-only fixture is skipped, so an UPDATE carrying both writes the prefix)
#      Note the shape: mutating a precondition's VALUE alone (`NotEquals "zzz"`) IS caught; these
#      change OPERATOR AND VALUE TOGETHER. A mutation is only as good as the joint space it explores.
#
# So: mutate in THREE directions — subtractive, additive, and compensating — and delete an assertion
# only when the fixtures ALONE go red for EVERY direction that assertion constrains.
#
# COVERAGE IS PER-MUTATION, NOT PER-ASSERTION — this is the trap that made the first two attempts at
# this refactor wrong. An assertion is not "redundant" because one subtractive mutation was caught;
# the same assertion is usually the only guard in another direction. Worked example, the closest
# thing here to a redundant check:
#
#   "shared recommended-label policy must mutate only workload and pod-template metadata"
#   (`.spec.rules[0].mutate.patchStrategicMerge | keys | sort | join(",")` == "metadata,spec")
#     - SUBTRACTIVE (drop the `spec` branch):     fixtures go red on their own, 123/4  -> covered
#     - ADDITIVE    (add a top-level branch):     fixtures stay green                  -> UNCOVERED
#   So it is kept. One direction covered is not redundancy.
#
# The same per-mutation split applies in the other direction: several of the remaining assertions
# guard mutations the fixtures DO catch (deleting the sole rule, 116/11; `+(workload)` on workload
# metadata, 122/5) while also guarding mutations nothing else catches. Read the tables above as a
# map of MUTATIONS to coverage, and never summarise them as a count of redundant assertions.
# Strengthening the fixtures (#32) is the way to shrink this script, not deleting from it.
# ---------------------------------------------------------------------------------------------

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
# The classic file is the unregistered rollback for the ValidatingPolicy form (issue #43),
# whose checks follow the Flux ones below.
assert_equal "$(yq '[.resources[] |
  select(. == "policies/best-practices/disallow-latest-tag.yaml")
] | length' "${repo_root}/kustomization.yaml")" "0" \
  "the classic image-tag ClusterPolicy must not be registered beside its ValidatingPolicy form"

if ! grep -Fq \
  'policies/best-practices/disallow-latest-tag.yaml' \
  "${repo_root}/README.md"; then
  echo "FAIL: README is missing the classic disallow-latest-tag rollback" >&2
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
  "${recommended_labels_policy}")" "exclude,match,mutate,name,preconditions" \
  "shared recommended-label policy must contain only its match, boundary, preconditions, and mutation"
assert_equal "$(yq '.spec.rules[0].match.any | length' "${recommended_labels_policy}")" "1" \
  "shared recommended-label policy must expose one match branch"
assert_equal "$(yq '.spec.rules[0].match.any[0].resources | keys | join(",")' \
  "${recommended_labels_policy}")" "kinds" \
  "shared recommended-label policy must match only by kind"
assert_equal "$(yq '.spec.rules[0].match.any[0].resources.kinds | sort | join(",")' \
  "${recommended_labels_policy}")" \
  "apps/v1/DaemonSet,apps/v1/Deployment,apps/v1/StatefulSet" \
  "shared recommended-label policy must match exactly the three built-in workload APIs"
assert_equal "$(yq '.spec.rules[0].exclude.any | length' "${recommended_labels_policy}")" "1" \
  "shared recommended-label policy must expose one system-namespace boundary"
assert_equal "$(yq '.spec.rules[0].exclude.any[0].resources | keys | join(",")' \
  "${recommended_labels_policy}")" "namespaces" \
  "shared recommended-label policy must exclude only by namespace"
assert_equal "$(yq '.spec.rules[0].exclude.any[0].resources.namespaces | sort | join(",")' \
  "${recommended_labels_policy}")" "kube-node-lease,kube-public,kube-system" \
  "shared recommended-label policy must preserve the three Kubernetes system namespaces"
assert_equal "$(yq '.spec.rules[0].preconditions | keys | join(",")' \
  "${recommended_labels_policy}")" "all" \
  "shared recommended-label policy must require every label-safety precondition"
assert_equal "$(yq '.spec.rules[0].preconditions.all | length' \
  "${recommended_labels_policy}")" "2" \
  "shared recommended-label policy must require a materialized label-safe name"
assert_equal "$(yq '.spec.rules[0].preconditions.all[0] | keys | sort | join(",")' \
  "${recommended_labels_policy}")" "key,operator,value" \
  "shared recommended-label policy must keep the name-presence precondition exact"
assert_equal "$(yq '.spec.rules[0].preconditions.all[0].key' \
  "${recommended_labels_policy}")" "{{ request.object.metadata.name || '' }}" \
  "shared recommended-label policy must inspect the materialized workload name"
assert_equal "$(yq '.spec.rules[0].preconditions.all[0].operator' \
  "${recommended_labels_policy}")" "NotEquals" \
  "shared recommended-label policy must skip generateName-only admission requests"
assert_equal "$(yq '.spec.rules[0].preconditions.all[0].value' \
  "${recommended_labels_policy}")" "" \
  "shared recommended-label policy must require a non-empty workload name"
assert_equal "$(yq '.spec.rules[0].preconditions.all[1] | keys | sort | join(",")' \
  "${recommended_labels_policy}")" "key,operator,value" \
  "shared recommended-label policy must keep the label-length precondition exact"
assert_equal "$(yq '.spec.rules[0].preconditions.all[1].key' \
  "${recommended_labels_policy}")" "{{ length(request.object.metadata.name || '') }}" \
  "shared recommended-label policy must measure the workload name used as a label"
assert_equal "$(yq '.spec.rules[0].preconditions.all[1].operator' \
  "${recommended_labels_policy}")" "LessThanOrEquals" \
  "shared recommended-label policy must reject names above the label-value limit"
assert_equal "$(yq '.spec.rules[0].preconditions.all[1].value' \
  "${recommended_labels_policy}")" "63" \
  "shared recommended-label policy must enforce the Kubernetes label-value limit"
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
  "${recommended_labels_policy}")" "{{ request.object.metadata.name || '' }}" \
  "shared recommended-label policy must derive app from the workload name"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.metadata.labels."+(app.kubernetes.io/name)"' \
  "${recommended_labels_policy}")" "{{ request.object.metadata.name || '' }}" \
  "shared recommended-label policy must derive the workload name label from the workload name"
assert_equal "$(yq '.spec.rules[0].mutate.patchStrategicMerge.spec.template.metadata.labels."+(app.kubernetes.io/name)"' \
  "${recommended_labels_policy}")" "{{ request.object.metadata.name || '' }}" \
  "shared recommended-label policy must derive the pod-template name label from the workload name"
assert_equal "$(yq '[.resources[] |
  select(. == "policies/best-practices/add-recommended-labels.yaml")
] | length' "${repo_root}/kustomization.yaml")" "0" \
  "the classic recommended-label ClusterPolicy must not be registered beside its MutatingPolicy form"

if ! grep -Fq \
  'policies/best-practices/add-recommended-labels.yaml' \
  "${repo_root}/README.md"; then
  echo "FAIL: README is missing the classic add-recommended-labels rollback" >&2
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

if [[ "${helm_crds_catalog_entry_count}" -ne 0 ]]; then
  echo "FAIL: the classic Helm CRD ClusterPolicy must not be registered beside its MutatingPolicy form" >&2
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

if [[ "${helm_test_catalog_entry_count}" -ne 0 ]]; then
  echo "FAIL: the classic Helm test ClusterPolicy must not be registered beside its MutatingPolicy form" >&2
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
] | length' "${repo_root}/kustomization.yaml")" "0" \
  "the classic Helm remediation ClusterPolicy must not be registered beside its MutatingPolicy form"

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

assert_equal "$(yq '[.resources[] |
  select(. == "policies/flux/enforce-flux-best-practices.yaml")
] | length' "${repo_root}/kustomization.yaml")" "0" \
  "the classic Flux ClusterPolicy must not be registered beside its ValidatingPolicy form"

# ValidatingPolicy forms of the two classic validate policies (issue #43). Each classic rule
# becomes one ValidatingPolicy named after the rule, so a consumer can set Audit or Deny per
# rule, as it can per classic rule. The classic files stay in the repository, unregistered, as
# the rollback form, and keep their own behavior tests.
#
# `kyverno apply` prints one result per policy, rule and matched resource. The parity check
# below compares the classic form's results with the ValidatingPolicy form's on the classic
# fixtures, so every fixture resource, including the ones neither form matches, gets the same
# result from each ValidatingPolicy as from the classic rule of the same name. It is also the
# positive control: a policy file the CLI cannot load yields no results rather than an error.
cel_image_tag_policy="${repo_root}/policies/best-practices/disallow-latest-tag-validating-policy.yaml"
cel_flux_policy="${repo_root}/policies/flux/enforce-flux-best-practices-validating-policy.yaml"

# Prints "<identity> <namespace>/<name> <result>" for every result, sorted, where identity
# is the result's rule (classic) or policy (ValidatingPolicy) name.
report_results() {
  local policy_file="$1"
  local resource_file="$2"
  local identity="$3"
  local report
  local status=0

  # Exit 1 means a fixture failed a rule, which the fixtures do on purpose. Any other
  # non-zero status is a CLI failure.
  report="$(kyverno apply "${policy_file}" --resource "${resource_file}" \
    --policy-report --remove-color)" || status=$?
  if [[ "${status}" -gt 1 ]]; then
    echo "FAIL: kyverno apply ${policy_file} exited ${status}" >&2
    exit 1
  fi

  # The CLI prints a deprecation warning for a classic policy before the report.
  printf '%s\n' "${report}" | sed -n '/^apiVersion:/,$p' |
    IDENTITY="${identity}" yq '.results[] |
      .[env(IDENTITY)] + " " + (.resources[0].namespace // "") + "/" + .resources[0].name + " " + .result' |
    sort
}

assert_cel_port() {
  local label="$1"
  local classic_file="$2"
  local cel_file="$3"
  local resource_file="$4"
  local catalog_path="${cel_file#"${repo_root}/"}"
  local classic_results
  local cel_results

  if [[ ! -f "${cel_file}" ]]; then
    echo "FAIL: shared catalog is missing ${catalog_path}" >&2
    exit 1
  fi

  assert_equal "$(yq --no-doc '.apiVersion + " " + .kind' "${cel_file}" | sort -u)" \
    "policies.kyverno.io/v1 ValidatingPolicy" \
    "every ${label} policy must be a policies.kyverno.io/v1 ValidatingPolicy"
  assert_equal "$(yq --no-doc '.metadata.name' "${cel_file}" | sort | paste -sd, -)" \
    "$(yq '.spec.rules[].name' "${classic_file}" | sort | paste -sd, -)" \
    "the ${label} ValidatingPolicies must be named after the classic rules, one per rule"
  assert_equal "$(yq --no-doc '.metadata.annotations."policies.kyverno.io/minversion"' \
    "${cel_file}" | sort -u)" "1.19.0" \
    "every ${label} ValidatingPolicy must declare the Kyverno 1.19.0 floor"
  assert_equal "$(yq --no-doc '.spec.validationActions | join(",")' "${cel_file}" | sort -u)" \
    "Audit" \
    "every ${label} ValidatingPolicy must default to Audit only"
  assert_equal "$(yq --no-doc '.spec.evaluation.background.enabled' "${cel_file}" | sort -u)" \
    "true" \
    "every ${label} ValidatingPolicy must evaluate existing resources"
  assert_equal "$(yq --no-doc '.spec.validations | length' "${cel_file}" | sort -u)" "1" \
    "every ${label} ValidatingPolicy must carry exactly one validation"
  assert_equal "$(yq --no-doc '.spec.matchConstraints.resourceRules[].operations | join(",")' \
    "${cel_file}" | sort -u)" "CREATE,UPDATE" \
    "every ${label} ValidatingPolicy must match create and update requests"
  assert_equal "$(yq --no-doc '[.. | select(tag == "!!map") | select(
    has("matchConditions") or has("excludeResourceRules") or
    has("namespaceSelector") or has("objectSelector")
  )] | length' "${cel_file}" | sort -u)" "0" \
    "the ${label} ValidatingPolicies must leave environment exclusions to consumers"
  assert_equal "$(yq --no-doc '.metadata.name + ": " + .spec.validations[0].message' \
    "${cel_file}" | sort)" \
    "$(yq '.spec.rules[] | .name + ": " + .validate.message' "${classic_file}" | sort)" \
    "every ${label} ValidatingPolicy must keep its classic rule's message"
  assert_equal "$(CATALOG_PATH="${catalog_path}" yq '[.resources[] |
    select(. == env(CATALOG_PATH))] | length' "${repo_root}/kustomization.yaml")" "1" \
    "the ${label} ValidatingPolicies must be registered exactly once"

  if ! grep -Fq "${catalog_path}" "${repo_root}/README.md"; then
    echo "FAIL: README catalog is missing ${catalog_path}" >&2
    exit 1
  fi

  classic_results="$(report_results "${classic_file}" "${resource_file}" rule)"
  cel_results="$(report_results "${cel_file}" "${resource_file}" policy)"

  if [[ -z "${classic_results}" ]]; then
    echo "FAIL: the classic ${label} policy produced no results to compare against" >&2
    exit 1
  fi

  if [[ "${cel_results}" != "${classic_results}" ]]; then
    echo "FAIL: the ${label} ValidatingPolicies differ from the classic rules on the classic fixtures:" >&2
    diff <(printf '%s\n' "${classic_results}") <(printf '%s\n' "${cel_results}") >&2 || true
    exit 1
  fi
}

assert_cel_port "image-tag" "${image_tag_policy}" "${cel_image_tag_policy}" \
  "${repo_root}/tests/disallow-latest-tag/resources.yaml"
assert_cel_port "Flux best-practices" "${flux_policy}" "${cel_flux_policy}" \
  "${repo_root}/tests/enforce-flux-best-practices/resources.yaml"

# The classic image-tag policy turns autogen off, so Kyverno evaluates Pods only and not the
# Deployments and other controllers that create them. A ValidatingPolicy autogenerates for
# Pod controllers unless its controller list is set and empty.
assert_equal "$(yq --no-doc '.spec.autogen.podControllers.controllers | (tag) + " " + (length | tostring)' \
  "${cel_image_tag_policy}" | sort -u)" "!!seq 0" \
  "every image-tag ValidatingPolicy must disable Pod-controller autogen"

# MutatingPolicy forms of the four classic mutate policies (issue #44), one per classic policy
# and under its name, so a consumer's reference and patch targets keep their names. The
# classic files stay in the repository, unregistered, as the rollback form, and keep their own
# behavior tests.
#
# The parity check runs every fixture resource through the classic and the MutatingPolicy
# form and compares the results. It covers what the fixtures' `skip` rows cannot: a resource
# a MutatingPolicy does not select reports `Excluded`, which satisfies any `skip` row, so a
# widened match would otherwise pass. Its positive control is that the classic form changes
# at least one fixture resource.

# Prints every resource in a fixture file as it leaves admission through a policy file: one
# key-sorted YAML stream, ordered by kind, namespace and name. `kyverno apply --output` writes
# each resource a policy in the file evaluated and leaves out one it did not match at all, so a
# resource missing from that directory is read from the fixture file unchanged.
admitted_resources() {
  local policy_file="$1"
  local resource_file="$2"
  local output_dir
  local status=0

  output_dir="$(mktemp -d)"
  kyverno apply "${policy_file}" --resource "${resource_file}" --output "${output_dir}" \
    --remove-color >/dev/null 2>&1 || status=$?
  if [[ "${status}" -ne 0 ]]; then
    rm -rf "${output_dir}"
    echo "FAIL: kyverno apply ${policy_file} exited ${status}" >&2
    exit 1
  fi

  yq ea -P '[.] | map(select(. != null)) |
    group_by(.kind + "/" + (.metadata.namespace // "") + "/" +
      (.metadata.name // .metadata.generateName // "")) |
    map(.[-1]) | .[] | sort_keys(..) | split_doc' \
    "${resource_file}" "${output_dir}"/* || status=$?
  rm -rf "${output_dir}"
  if [[ "${status}" -ne 0 ]]; then
    echo "FAIL: could not read the resources ${policy_file} admitted" >&2
    exit 1
  fi
}

assert_mutating_port() {
  local label="$1"
  local classic_file="$2"
  local mp_file="$3"
  local resource_file="$4"
  local catalog_path="${mp_file#"${repo_root}/"}"
  local unchanged
  local classic_admitted
  local mp_admitted

  if [[ ! -f "${mp_file}" ]]; then
    echo "FAIL: shared catalog is missing ${catalog_path}" >&2
    exit 1
  fi

  assert_equal "$(yq --no-doc '.apiVersion + " " + .kind' "${mp_file}" | sort -u)" \
    "policies.kyverno.io/v1 MutatingPolicy" \
    "the ${label} policy must be a policies.kyverno.io/v1 MutatingPolicy"
  assert_equal "$(yq --no-doc '.metadata.name' "${mp_file}")" \
    "$(yq '.metadata.name' "${classic_file}")" \
    "the ${label} MutatingPolicy must keep the classic policy's name"
  assert_equal "$(yq --no-doc '.metadata.annotations."policies.kyverno.io/minversion"' \
    "${mp_file}")" "1.19.0" \
    "the ${label} MutatingPolicy must declare the Kyverno 1.19.0 floor"
  assert_equal "$(yq --no-doc '.spec.evaluation.background.enabled' "${mp_file}")" "false" \
    "the ${label} MutatingPolicy must be admission-only, like the classic policy"
  assert_equal "$(yq --no-doc '.spec.evaluation.mutateExisting.enabled // false' "${mp_file}")" \
    "false" \
    "the ${label} MutatingPolicy must not mutate existing resources"
  assert_equal "$(yq --no-doc '[.spec.matchConstraints.resourceRules[].operations | join(",")] |
    unique | join(" ")' "${mp_file}")" "CREATE,UPDATE" \
    "the ${label} MutatingPolicy must match create and update requests"
  assert_equal "$(CATALOG_PATH="${catalog_path}" yq '[.resources[] |
    select(. == env(CATALOG_PATH))] | length' "${repo_root}/kustomization.yaml")" "1" \
    "the ${label} MutatingPolicy must be registered exactly once"

  if ! grep -Fq "${catalog_path}" "${repo_root}/README.md"; then
    echo "FAIL: README catalog is missing ${catalog_path}" >&2
    exit 1
  fi

  unchanged="$(yq -P 'sort_keys(..)' "${resource_file}" | yq ea -P '[.] |
    group_by(.kind + "/" + (.metadata.namespace // "") + "/" +
      (.metadata.name // .metadata.generateName // "")) |
    map(.[-1]) | .[] | split_doc')"
  classic_admitted="$(admitted_resources "${classic_file}" "${resource_file}")"
  mp_admitted="$(admitted_resources "${mp_file}" "${resource_file}")"

  if [[ "${classic_admitted}" == "${unchanged}" ]]; then
    echo "FAIL: the classic ${label} policy changed no fixture resource, so there is nothing to compare" >&2
    exit 1
  fi

  if [[ "${mp_admitted}" != "${classic_admitted}" ]]; then
    echo "FAIL: the ${label} MutatingPolicy admits the classic fixtures differently from the classic policy:" >&2
    diff <(printf '%s\n' "${classic_admitted}") <(printf '%s\n' "${mp_admitted}") >&2 || true
    exit 1
  fi
}

assert_mutating_port "recommended-label" "${recommended_labels_policy}" \
  "${repo_root}/policies/best-practices/add-recommended-labels-mutating-policy.yaml" \
  "${repo_root}/tests/add-recommended-labels/resources.yaml"
assert_mutating_port "Helm test" "${helm_test_policy}" \
  "${repo_root}/policies/flux/helm-release-enable-tests-mutating-policy.yaml" \
  "${repo_root}/tests/helm-release-enable-tests/resources.yaml"
assert_mutating_port "Helm CRD" "${helm_crds_policy}" \
  "${repo_root}/policies/flux/helm-release-install-crds-mutating-policy.yaml" \
  "${repo_root}/tests/helm-release-install-crds/resources.yaml"
assert_mutating_port "Helm remediation" "${helm_remediation_policy}" \
  "${repo_root}/policies/flux/helm-release-remediation-retries-mutating-policy.yaml" \
  "${repo_root}/tests/helm-release-remediation-retries/resources.yaml"

# The GeneratingPolicy auto-vpa and a classic auto-vpa ClusterPolicy generate a
# VerticalPodAutoscaler under the SAME name for the SAME workload, so two registered forms
# would contend for one object on every consumer cluster, and no registered form would
# silently drop auto-vpa entirely. The catalog ships exactly one form: the GeneratingPolicy.
# Consumers that still need the deprecated classic form keep their own copy or pin catalog
# revision 44ed118 (README, "Migrating to the GeneratingPolicy form").
ported_vpa_policy="${repo_root}/policies/best-practices/auto-vpa-generating-policy.yaml"

if [[ ! -f "${ported_vpa_policy}" ]]; then
  echo "FAIL: shared catalog is missing policies/best-practices/auto-vpa-generating-policy.yaml" >&2
  exit 1
fi

if [[ -e "${repo_root}/policies/best-practices/auto-vpa.yaml" ]]; then
  echo "FAIL: the classic auto-vpa ClusterPolicy must not be shipped beside the GeneratingPolicy form" >&2
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

# Issue #1 made the GeneratingPolicy form the catalog's auto-vpa. Pin that decision so an
# accidental re-registration of the deprecated ClusterPolicy form fails here instead of
# reaching consumers.
if [[ "${ported_vpa_registered}" -ne 1 ]]; then
  echo "FAIL: the GeneratingPolicy auto-vpa must be the registered form, exactly once" >&2
  exit 1
fi

# generateExisting only covers pre-existing workloads from Kyverno 1.19.0 (kyverno/kyverno#15722),
# so every ported policy must declare that floor; CI then holds the pinned CLI at or above it.
ported_vpa_floor_count="$(
  yq --no-doc '[select(.metadata.annotations."policies.kyverno.io/minversion" == "1.19.0")] | length' \
    "${ported_vpa_policy}" | awk '{s+=$1} END {print s}'
)"

if [[ "${ported_vpa_floor_count}" -ne 3 ]]; then
  echo "FAIL: every ported auto-vpa policy must declare policies.kyverno.io/minversion 1.19.0" >&2
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

# Declarative behavior specs (tests/*/kyverno-test.yaml) are NOT run here: CI runs
# `kyverno test .` from the repo root, which discovers every fixture recursively.
# Listing fixture paths here instead meant a new policy's fixture was silently never
# executed until someone remembered to add it below. This script now asserts only the
# structural invariants that `kyverno test` cannot express.

ported_positive_dir="$(mktemp -d)"
ported_negative_dir="$(mktemp -d)"
ported_collision_dir="$(mktemp -d)"
trap 'rm -rf "${ported_positive_dir}" "${ported_negative_dir}" "${ported_collision_dir}"' EXIT

# A matched/unmatched control pair for the auto-vpa policies.
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

# A shortened VPA name must never equal the unshortened name another workload of the same kind
# can legally get, or the two contend for one VPA and one stays unsized (issue #49). For each
# kind the fixture holds a 253-character workload and a workload named like a shortened VPA
# name without its kind suffix: six workloads that must get six valid, different VPA names.
kyverno apply "${ported_vpa_policy}" \
  --resource "${repo_root}/tests/auto-vpa/long-name-collision.yaml" \
  --output "${ported_collision_dir}" \
  --remove-color >/dev/null

collision_vpa_names="$(
  find "${ported_collision_dir}" -type f -exec \
    yq --no-doc 'select(.kind == "VerticalPodAutoscaler") | .metadata.name' {} +
)"
collision_vpa_count="$(printf '%s\n' "${collision_vpa_names}" | awk 'NF {n++} END {print n + 0}')"
collision_unique_count="$(printf '%s\n' "${collision_vpa_names}" | awk 'NF' | sort -u | awk 'END {print NR}')"
collision_overlong_count="$(printf '%s\n' "${collision_vpa_names}" | awk 'length > 253 {n++} END {print n + 0}')"

if [[ "${collision_vpa_count}" -ne 6 || "${collision_unique_count}" -ne 6 || "${collision_overlong_count}" -ne 0 ]]; then
  echo "FAIL: ported auto-vpa must give six long-name workloads six valid, different VPA names (got ${collision_unique_count} different of ${collision_vpa_count}, ${collision_overlong_count} too long)" >&2
  exit 1
fi
