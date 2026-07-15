# Kyverno policies

Shared, tested Kyverno policies for the devantler-tech platform repositories. This repository is the
single source for policy behavior that would otherwise drift between `platform` and `platform-template`.

Policies are catalogued through the root [`kustomization.yaml`](kustomization.yaml). Adding a policy here
does not deploy it anywhere: each consumer adopts a catalog revision explicitly in a separate, validated
change.

## Catalog

| Policy | Behavior | Prerequisites |
|---|---|---|
| [`auto-vpa`](policies/best-practices/auto-vpa.yaml) | Generates recommendation-bounded VPAs for Deployments, StatefulSets, and DaemonSets | Kyverno 1.18+, VPA 1.5+ with its CRD/controller, a `metrics.k8s.io` provider, and Kyverno background-controller RBAC for VPAs |
| [`enforce-flux-best-practices`](policies/best-practices/enforce-flux-best-practices.yaml) | Validates that Flux `Kustomization` and `HelmRelease` resources declare the reliability fields recommended by the Flux docs | Kyverno 1.6+ and the Flux `kustomize`/`helm` controller CRDs installed in the cluster |

## Render the catalog

```sh
kubectl kustomize .
```

Consumers should pin an immutable repository revision and select policies deliberately. Do not apply the
catalog to a live cluster directly from a floating branch.

## Auto VPA behavior

`auto-vpa` generates and synchronizes a `VerticalPodAutoscaler` for new and existing workloads that
Kyverno processes.

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
- The parity version retains workload-name-only VPA names. Same-name workloads of different kinds are a
  known collision risk tracked in [issue #2](https://github.com/devantler-tech/kyverno-policies/issues/2).
- The first shared version deliberately retains the consumers' classic `ClusterPolicy` API. Migration to
  `GeneratingPolicy` is tracked in [issue #1](https://github.com/devantler-tech/kyverno-policies/issues/1).

## Enforce Flux best practices behavior

`enforce-flux-best-practices` is an admission-check (validate) policy. It asserts that Flux resources
declare the reliability-critical fields recommended by the Flux documentation, catching a misconfigured
resource at admission instead of at the next runtime failure.

| Resource | Required fields |
|---|---|
| `Kustomization` | `spec.interval`, `spec.timeout`, `spec.retryInterval`, `spec.prune: true`, `spec.wait: true`, `spec.sourceRef` |
| `HelmRelease` | `spec.interval`, `spec.timeout`, install + upgrade `remediation.retries` (`>=1` or `-1`), and `spec.upgrade.remediation.remediateLastFailure: true` |

Important operating constraints:

- The policy ships in `Audit` (report-only). It is inert until a consumer references it, and flipping it
  to `Enforce` is the consumer's rollout decision, taken once a clean cluster scan confirms nothing trips
  it. Enforcing directly from the shared library would block admissions in every consumer at once.
- The bootstrap `flux-system` Kustomization (namespace and name `flux-system`) is excluded because it is
  created and managed by `flux bootstrap` / ksail rather than by GitOps, so the recommended fields cannot
  be set on it. This exclusion is generic to every Flux installation.
- The `HelmRelease` rule matches the `v2`, `v2beta2`, and `v2beta1` API versions. The Flux controller CRDs
  must be installed for the policy to match; Kyverno's global resource filters still apply.

## Validate changes

```sh
yamllint .
kubectl kustomize . > /dev/null
bash scripts/test-policy-catalog.sh
shellcheck scripts/test-policy-catalog.sh
actionlint .github/workflows/ci.yaml
zizmor .github/workflows/ci.yaml
git diff --check
```

The generated-resource fixtures assert the exact VPA target, update mode, controlled resources, and
bounds for each workload kind. An unmatched Job assertion verifies the policy does not generate outside
its documented scope.
