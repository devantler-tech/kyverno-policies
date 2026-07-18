# AGENTS.md — shared Kyverno policy library

This is the canonical instruction file for humans and AI agents working in this repository. It defers
to the devantler-tech monorepo [`AGENTS.md`](https://github.com/devantler-tech/monorepo/blob/main/AGENTS.md)
for the shared engineering contract (issue-driven work, draft-PR checkpoint, trust gate, protected
branches, untrusted-input handling, worktree isolation, and validation discipline).

## What this repository is

`devantler-tech/kyverno-policies` is the tested, reusable policy catalog consumed by the Platform and
Platform Template repositories. Generic policy behavior belongs here so consumer copies do not drift.
Consumer wiring and rollout remain separate changes in those repositories.

## Structure

- `policies/<category>/<policy>.yaml` — one policy per file.
- `tests/<policy>/kyverno-test.yaml` — Kyverno CLI behavior contract.
- `tests/<policy>/generated-*.yaml` — exact generated-resource fixtures.
- `kustomization.yaml` — root catalog; every published policy must be listed.
- `scripts/test-policy-catalog.sh` — structural invariants `kyverno test` cannot express.

## Policy rules

- Keep policies generic across consumers. Environment-specific exclusions, patches, and rollout choices
  stay in the consumer repository.
- New behavior is issue-backed and test-first. For generate rules, assert the complete generated resource
  and at least one nonmatching resource before adding or changing the policy.
- A policy added to this catalog is inert until a consumer pins and references it. Consumer adoption is a
  separate draft PR validated in every affected overlay.
- Document prerequisites such as CRDs, controller RBAC, Kyverno resource filters, and interacting
  autoscalers. Do not claim a policy reaches resources filtered out by the Kyverno installation.
- Preserve backward-compatible behavior by default. An API migration or breaking output change needs its
  own issue, exact parity tests, and a reversible consumer rollout.
- Never commit credentials, cluster-specific identities, private topology, or live security evidence.

## Validation

Run every gate before opening or updating a PR:

```sh
yamllint .
kubectl kustomize . > /dev/null
kyverno test . --require-tests --detailed-results --remove-color
bash scripts/test-policy-catalog.sh
shellcheck scripts/test-policy-catalog.sh
actionlint .github/workflows/ci.yaml
zizmor .github/workflows/ci.yaml
git diff --check
```

`kyverno test .` discovers every `tests/*/kyverno-test.yaml` recursively, so a new policy is
behavior-tested as soon as its fixture exists — never add fixture paths to a runner by hand.

CI pins the Kyverno CLI via `KYVERNO_CLI_VERSION` in
[`.github/workflows/ci.yaml`](.github/workflows/ci.yaml), because that CLI decides how the behavior
gate evaluates the catalog. Match it locally (`kyverno version`) so a local pass means the same thing
as a CI pass. Raising a policy's `policies.kyverno.io/minversion` above the pinned CLI fails CI by
design — bump the pin in the same change.

Tests are static and local. Never connect to or mutate a live cluster to validate a policy-library diff.

## Maintenance

GitHub Issues are the roadmap and work queue. Resolve the oldest actionable issue first, ship changes as
draft PRs with Conventional-Commit titles and the Daily AI disclosure, and keep drafts review-ready without
self-promoting them. Keep this file, the README catalog, tests, and CI in sync whenever policy conventions
or validation commands change.
