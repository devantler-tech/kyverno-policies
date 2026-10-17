# Kyverno policies

Shared, tested Kyverno policies for the devantler-tech platform repositories. This repository is the
single source for policy behavior that would otherwise drift between `platform` and `platform-template`.

Policies are catalogued through the root [`kustomization.yaml`](kustomization.yaml). Adding a policy here
does not deploy it anywhere: each consumer adopts a catalog revision explicitly in a separate, validated
change.

## Try a local render

You need Git and [kubectl](https://kubernetes.io/docs/tasks/tools/) with built-in Kustomize.
No Kubernetes context, cloud credentials or running cluster is needed:

```sh
git clone https://github.com/devantler-tech/kyverno-policies.git
cd kyverno-policies
kubectl kustomize .
```

Success is exit 0 and the catalog's policy resources printed as YAML. This checks the Kustomize
build, not behavior fixtures, CRD admission or a live rollout. Do not apply the floating catalog
to a cluster. Consumers pin an immutable revision and choose policies in their own validated change.

To improve the library, start with [CONTRIBUTING.md](CONTRIBUTING.md). The catalog and behavior
reference below explain what each policy does and what a consumer must supply.

This repository currently has no repository-level LICENSE file. Public source access and this
guide do not grant unrestricted reuse or redistribution rights.

## Catalog

| Policy | Behavior | Prerequisites |
|---|---|---|
| [`add-recommended-labels`](policies/best-practices/add-recommended-labels.yaml) | Adds missing Kubernetes identity labels to Deployments, StatefulSets, and DaemonSets without replacing authored values | Kyverno 1.18+ and admission processing that includes the target workload |
| [`auto-vpa`](policies/best-practices/auto-vpa-generating-policy.yaml) | Generates recommendation-bounded VPAs for Deployments, StatefulSets, and DaemonSets | Kyverno 1.19+, VPA 1.5+ with its CRD/controller, a `metrics.k8s.io` provider, and Kyverno background-controller RBAC for VPAs |
| [`disallow-latest-tag`](policies/best-practices/disallow-latest-tag.yaml) | Audits Pod images that are pinned by neither a tag nor a digest, or that use the mutable `:latest` tag | Kyverno 1.18+ and admission/background processing that includes Pods |
| [`enforce-flux-best-practices`](policies/flux/enforce-flux-best-practices.yaml) | Validates reliability settings on Flux Kustomizations and HelmReleases | Kyverno 1.18+ and the Flux Kustomization v1 and HelmRelease v2 CRDs |
| [`helm-release-enable-tests`](policies/flux/helm-release-enable-tests.yaml) | Enables Helm test actions for explicitly labelled Flux HelmReleases | Kyverno 1.18+, the Flux HelmRelease v2 CRD, and admission filters which permit the target resource |
| [`helm-release-install-crds`](policies/flux/helm-release-install-crds.yaml) | Creates and replaces chart CRDs for explicitly labelled Flux HelmReleases | Kyverno 1.18+, the Flux HelmRelease v2 CRD, and admission filters which permit the target resource |
| [`helm-release-remediation-retries`](policies/flux/helm-release-remediation-retries.yaml) | Supplies safe install and upgrade remediation defaults for explicitly labelled Flux HelmReleases | Kyverno 1.18+, the Flux HelmRelease v2 CRD, and admission filters which permit the target resource |

## Image tag behavior

`disallow-latest-tag` audits every image reference in a Pod's normal, init, and ephemeral containers.
Images must be pinned by an explicit tag after the final path segment or by a digest; a registry port
does not count as a tag. A versioned tag, a versioned tag-plus-digest reference, and a digest-only
reference (the pin format the portfolio's `publish-app` workflow produces) all pass. References with
neither a tag nor a digest fail; `:latest` references fail even when paired with a digest.

The shared policy deliberately contains no namespace exclusions. Consumers own any environment-specific
exceptions and the separately validated decision to promote either rule beyond `Audit`. Kyverno's global
resource filters still win, so a filtered Pod remains unreachable by this policy.

## Recommended label behavior

`add-recommended-labels` fills only missing identity labels on Deployments, StatefulSets, and DaemonSets.
It sets `app` and `app.kubernetes.io/name` on workload metadata and
`app.kubernetes.io/name` on the pod template, using the workload name for each added value. Conditional
anchors leave every explicitly authored value unchanged.

The policy excludes `kube-system`, `kube-public`, and `kube-node-lease`. It runs on create and update
admission only, so existing workloads receive missing labels on their next admitted update. Kyverno's
global admission filters still win. A `generateName`-only create is skipped until the API server assigns
the workload name, then a later update can add the labels. Names longer than the 63-character Kubernetes
label-value limit are also skipped rather than turning an otherwise valid workload into an invalid
admission. Consumer-specific exclusions or rollout choices remain in the consumer repository.

## Auto VPA behavior

`auto-vpa` generates and synchronizes a `VerticalPodAutoscaler` for new and existing workloads that
Kyverno processes. The catalog ships it as three `GeneratingPolicy` objects, one per workload kind
(`auto-vpa-deployment`, `auto-vpa-statefulset`, `auto-vpa-daemonset`), because Kyverno 1.19 deprecates
classic `ClusterPolicy` and plans to remove it in 1.20. Consumers moving from a classic auto-vpa policy
follow [Migrating to the GeneratingPolicy form](#migrating-to-the-generatingpolicy-form).

| Workload | Update mode | Controlled resources | Recommendation bounds |
|---|---|---|---|
| Deployment | `InPlaceOrRecreate` | CPU and memory | `50m`/`64Mi` to `3`/`6Gi` |
| StatefulSet | `Initial` | CPU and memory | `50m`/`64Mi` to `3`/`6Gi` |
| DaemonSet | `InPlaceOrRecreate` | CPU only | `50m` to `1` CPU |

Important operating constraints:

- Kyverno's global resource filters still win. A namespace or kind filtered by the Kyverno installation
  will not receive a generated VPA even though the policy itself matches it.
- VPA 1.5+ enables `InPlaceOrRecreate` by default. In-place operation requires Kubernetes 1.33+ with
  `InPlacePodVerticalScaling`; even on a compatible cluster, an infeasible resize can fall back to pod
  recreation. This policy does not override the updater's global minimum-replica guard, and
  PodDisruptionBudgets still govern disruptive updates.
- `RequestsAndLimits` preserves the authored limit-to-request ratio. `minAllowed` and `maxAllowed` bound
  recommendations and requests, not the proportional limits; workloads need sensible starting ratios and
  a `LimitRange` or admission policy when hard limit ceilings are required.
- StatefulSets use `Initial` to avoid policy-driven eviction of single-writer workloads.
- DaemonSet memory stays workload-owned because one usage histogram covers all replicas; sizing every
  node from the busiest node's memory peak can block cluster scale-down.
- Horizontal autoscaling on CPU or memory conflicts when VPA controls that same resource metric. Exclude
  or adapt those workloads in the consuming repository; custom or external HPA metrics are compatible.
- Consumers must inventory existing VPAs and exclude their targets before adoption. Multiple VPAs matching
  one pod have undefined behavior.
- Exclude workloads that define pod-level `resources`; upstream VPA does not yet support them and its
  container-level recommendation can prevent replacement pods from being admitted.
- Generated VPA names are suffixed with the workload kind (`<name>-deployment`, `<name>-statefulset`,
  `<name>-daemonset`) so a Deployment, StatefulSet, and DaemonSet that legally share one name in a
  namespace each get their own VPA instead of contending for one. The suffix adds up to 12 characters,
  so a workload whose name exceeds 241 characters would generate a VPA name past the 253-character
  DNS-subdomain limit and receive none; keep workload names within that bound (any real workload name is
  far shorter). Consumers adopting this from an earlier workload-name-only version must clean up the
  previously generated `<name>` VPAs, which the new rules no longer manage (migration/cleanup tracked in
  [issue #2](https://github.com/devantler-tech/kyverno-policies/issues/2)).
- The auto-vpa form needs **Kyverno 1.19 or later**. On 1.18.x, `generateExisting` is accepted but does
  nothing for workloads that already exist
  ([kyverno/kyverno#15722](https://github.com/kyverno/kyverno/issues/15722); fixed for 1.19 by
  [#16041](https://github.com/kyverno/kyverno/pull/16041) and never backported), so existing workloads
  would get no VPA until their next update.

### Migrating to the GeneratingPolicy form

The catalog registers exactly one auto-vpa form at a time, and that form is now the `GeneratingPolicy`
one. The classic [`auto-vpa.yaml`](policies/best-practices/auto-vpa.yaml) stays in the repository,
unregistered and still tested, as the rollback form until every consumer has migrated. Its removal is a
separate change. The ported policies are tested against the *same* expected-output fixtures as the
classic policy (`tests/auto-vpa/generated-*-vpa.yaml`), so the VPAs they generate are identical.

The two forms cannot take over each other's VPAs, so a consumer moves in two separately reconciled
steps and never runs both at once:

- Kyverno labels each generated VPA with the policy that owns it. A `GeneratingPolicy` leaves alone any
  VPA it does not own, without reporting an error, and only creates the ones that are missing.
- Deleting a classic policy whose rules synchronize also deletes the VPAs it generated, unless the rule
  sets `orphanDownstreamOnPolicyDelete: true`. The catalog's classic form does not set it.
- While both forms exist, the classic policy keeps rewriting the VPAs it owns, and the new form skips
  them.

If both changes land in one reconcile, the new policies skip the old VPAs, the old policy's cleanup then
deletes them, and they come back only when the background controller next re-scans its policies (by
default up to an hour later).

**Rollout, per cluster:**

1. Confirm the cluster runs Kyverno 1.19.0 or later and meets the prerequisites in the catalog table.
   Inventory every VPA you did not generate with auto-vpa and exclude its target, as for the classic form.
2. Remove the classic auto-vpa policy and let it reconcile. Wait until no VPA labelled
   `generate.kyverno.io/policy-name=auto-vpa` remains. Pods keep their current requests while they have
   no VPA.
3. Reference this catalog's `auto-vpa-generating-policy.yaml` and let it reconcile. Kyverno generates a
   VPA for every existing matching workload straight away.
4. Check that every matching workload has exactly one VPA, labelled with the policy for its kind
   (`auto-vpa-deployment`, `auto-vpa-statefulset` or `auto-vpa-daemonset`).

**Rollback** is the same two steps in reverse: remove the three `GeneratingPolicy` objects and wait until
their VPAs are gone, then re-reference the classic `auto-vpa.yaml` (or pin the previous catalog revision).

A consumer whose own classic copy names VPAs differently (for example without the `-<kind>` suffix) still
follows step 2 first, so that no workload ends up with two VPAs. The migration is tracked in
[issue #1](https://github.com/devantler-tech/kyverno-policies/issues/1), and consumer adoption in
[issue #9](https://github.com/devantler-tech/kyverno-policies/issues/9).

One translation note for anyone extending it: CEL infers a map's value type from its first entry, so
resource literals wrap every value in `dyn(...)`, and fields read off `object` need `string(...)` before
being concatenated.

## Validate changes

Follow the [contribution guide](CONTRIBUTING.md#validate-your-change) for prerequisites and the
complete local baseline, including the pinned Kyverno CLI and retired-link validator. The
repository's [validation contract](AGENTS.md#validation) is authoritative if checks change.

`kyverno test .` runs every policy's declarative behavior fixture, discovered recursively;
`test-policy-catalog.sh` asserts the structural invariants those fixtures cannot express.

The generated-resource fixtures assert the exact VPA target, update mode, controlled resources, and
bounds for each workload kind. An unmatched Job assertion verifies the policy does not generate outside
its documented scope.

## Flux best-practices behavior

`enforce-flux-best-practices` applies an opinionated reliability baseline that requires every matching
resource to declare its reconciliation and remediation controls explicitly:

- Kustomizations set non-empty `interval`, `timeout`, and `retryInterval` values, enable `prune` and
  `wait`, and name their source reference.
- HelmReleases set non-empty `interval` and `timeout` values. Install and upgrade each either use at
  least one remediation retry (`-1` for unlimited retries) or explicitly select Flux's
  `RetryOnFailure` strategy; upgrade remediation also enables `remediateLastFailure`.

The shared policy deliberately has no environment-specific exclusions. Each validation rule uses the
current per-rule `failureAction: Audit` field, so consumers own both their exclusions and the separately
validated rollout to `Enforce`; the deprecated policy-level `validationFailureAction` field is not used.
The fixtures prove both valid and invalid resources, including that a `flux-system/flux-system`
Kustomization is not silently exempted by the reusable policy. They also prove that legacy HelmRelease
beta objects and a nonmatching Flux source remain untouched.

## Helm test opt-in behavior

`helm-release-enable-tests` sets `spec.test.enable: true` on a Flux HelmRelease v2 only when the resource
has this label:

```yaml
metadata:
  labels:
    helm.toolkit.fluxcd.io/helm-test: enabled
```

Unlabelled resources, other label values, legacy HelmRelease beta objects, and non-HelmRelease resources
remain unchanged. The strategic-merge patch deliberately overrides an authored `enable: false` for an
opted-in resource while preserving sibling test settings such as `timeout`, `ignoreFailures`, and
`filters`.

This is an admission mutation, not a mutate-existing rule. A HelmRelease that already exists when a
consumer adopts the policy must pass through a subsequent create or update admission request before the
mutation applies. Kyverno's global admission filters still win, so a filtered HelmRelease remains
unreachable by this policy. Enabling Helm tests makes test failures participate in the Helm action's
remediation by default. `spec.test.ignoreFailures` supplies the shared default for whether failures affect
readiness, but install- and upgrade-specific `remediation.ignoreTestFailures` values override it for their
respective actions. The shared policy contains no environment-specific exclusions.

Consumers replacing a local policy with the same name should pin an immutable catalog revision, remove
the local definition without overlapping ownership, validate every affected overlay, and reapply opted-in
HelmReleases when immediate activation is required.

## Helm CRD lifecycle opt-in behavior

`helm-release-install-crds` sets both `spec.install.crds` and `spec.upgrade.crds` to `CreateReplace` on a
Flux HelmRelease v2 only when the resource has this label:

```yaml
metadata:
  labels:
    helm.toolkit.fluxcd.io/crds: enabled
```

Unlabelled resources, other label values, legacy HelmRelease beta objects, and non-HelmRelease resources
remain unchanged. The strategic-merge patch deliberately overrides existing CRD strategies for an
opted-in resource while preserving sibling install and upgrade settings such as remediation retries.

This is an admission mutation, not a mutate-existing rule. A HelmRelease that already exists when a
consumer adopts the policy must pass through a subsequent create or update admission request before the
mutation applies. Kyverno's global admission filters still win, so a filtered HelmRelease remains
unreachable by this policy. Consumers own chart compatibility with replacing existing CRDs and should opt
in only where chart-managed CRD upgrades are intended. The shared policy contains no environment-specific
exclusions.

Flux must also be authorized to carry out the requested CRD lifecycle. When helm-controller impersonation
is enabled through `spec.serviceAccountName` or a controller-wide default, grant that effective service
account least-privilege cluster-scoped access to read, create, and update
`customresourcedefinitions.apiextensions.k8s.io`. Admission can succeed while reconciliation fails if that
permission is missing; this policy does not require or justify granting blanket `cluster-admin` access.

## Helm remediation defaults opt-in behavior

`helm-release-remediation-retries` adds missing `retries: -1` and `remediateLastFailure: true` leaves to
both `spec.install.remediation` and `spec.upgrade.remediation` on a Flux HelmRelease v2 only when the
resource has this label:

```yaml
metadata:
  labels:
    helm.toolkit.fluxcd.io/remediation: enabled
```

The `-1` retries value makes Flux retry the failed install or upgrade action without a finite limit,
performing the configured remediation between attempts. Existing values, including `0`, `false`, finite
retry counts, and authored `-1` values, remain authoritative because the policy adds only absent scalar
leaves. Install and upgrade settings are handled independently, and their other action, strategy, and
remediation fields are preserved.

An action with an explicit `retries: 0` is also left entirely unchanged. This preserves Flux's default
`remediateLastFailure: false` when the author omits that boolean, avoiding an unexpected uninstall or
rollback after the first failed action.

An action whose `strategy.name` is explicitly `RetryOnFailure` is left entirely unchanged because that
strategy has its own retry behavior and does not use the remediation block in the same way.
`RemediateOnFailure`, a missing strategy, and future strategy values continue through the normal
add-if-absent defaults; the policy does not reject or overwrite them.

With unlimited retries, Flux never reaches a final retry, so `remediateLastFailure: true` remains inert
unless an author later supplies a finite retry count. If helm-controller enables its
`DefaultToRetryOnFailure` feature gate, an omitted strategy can behave as `RetryOnFailure` even though
the admission object does not say so; the added remediation fields remain inert in that case. Authors
who want the policy to skip an action entirely should select `RetryOnFailure` explicitly.

This is an admission mutation, not a mutate-existing rule. A HelmRelease that already exists when a
consumer adopts the policy must pass through a subsequent create or update admission request before the
defaults apply. Future updates continue to add any still-missing default leaves without changing values
the workload author has since supplied. Kyverno's global admission resource filters still win, so a
filtered HelmRelease remains unreachable by this policy. Unlabelled resources, other label values,
legacy HelmRelease beta objects, and non-HelmRelease resources remain unchanged. The shared policy
contains no environment-specific exclusions.
