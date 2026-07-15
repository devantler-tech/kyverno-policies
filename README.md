# Kyverno policies

Shared, tested Kyverno policies for the devantler-tech platform repositories. This repository is the
single source for policy behavior that would otherwise drift between `platform` and `platform-template`.

Policies are catalogued through the root [`kustomization.yaml`](kustomization.yaml). Adding a policy here
does not deploy it anywhere: each consumer adopts a catalog revision explicitly in a separate, validated
change.

## Catalog

| Policy | Behavior | Prerequisites |
|---|---|---|
| [`auto-vpa`](policies/best-practices/auto-vpa.yaml) | Generates bounded VPAs for Deployments, StatefulSets, and DaemonSets | Kyverno 1.18+, VPA CRD/controller, and Kyverno background-controller RBAC for VPAs |

## Render the catalog

```sh
kubectl kustomize .
```

Consumers should pin an immutable repository revision and select policies deliberately. Do not apply the
catalog to a live cluster directly from a floating branch.

## Auto VPA behavior

`auto-vpa` generates and synchronizes a `VerticalPodAutoscaler` for new and existing workloads that
Kyverno processes.

| Workload | Update mode | Controlled resources | Bounds |
|---|---|---|---|
| Deployment | `InPlaceOrRecreate` | CPU and memory | `50m`/`64Mi` to `3`/`6Gi` |
| StatefulSet | `Initial` | CPU and memory | `50m`/`64Mi` to `3`/`6Gi` |
| DaemonSet | `InPlaceOrRecreate` | CPU only | `50m` to `1` CPU |

Important operating constraints:

- Kyverno's global resource filters still win. A namespace or kind filtered by the Kyverno installation
  will not receive a generated VPA even though the policy itself matches it.
- `RequestsAndLimits` preserves the authored limit-to-request ratio. Workloads need sensible starting
  limits, and operators should review recommendations before adopting the policy broadly.
- StatefulSets use `Initial` to avoid policy-driven eviction of single-writer workloads.
- DaemonSet memory stays workload-owned because one usage histogram covers all replicas; sizing every
  node from the busiest node's memory peak can block cluster scale-down.
- CPU-driven horizontal autoscaling can conflict with CPU VPA control. Exclude or adapt such workloads
  in the consuming repository.
- The parity version retains workload-name-only VPA names. Same-name workloads of different kinds are a
  known collision risk tracked in [issue #2](https://github.com/devantler-tech/kyverno-policies/issues/2).
- The first shared version deliberately retains the consumers' classic `ClusterPolicy` API. Migration to
  `GeneratingPolicy` is tracked in [issue #1](https://github.com/devantler-tech/kyverno-policies/issues/1).

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
