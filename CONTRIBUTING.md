# Contributing to the Kyverno policy library

The repository currently has no repository-level LICENSE file. This contribution guide does not
grant unrestricted reuse or redistribution rights; do not assume a license from public visibility.

Help clarify a policy's behavior, add a focused fixture or improve a reusable policy. Discuss
substantial work in an [issue](https://github.com/devantler-tech/kyverno-policies/issues) first.
Do not include credentials, private topology or sensitive security evidence in public artifacts.
Use this repository's private
[Report a vulnerability](https://github.com/devantler-tech/kyverno-policies/security/advisories/new)
form for sensitive reports.

## Make a first contribution

For a first change, improve a small explanation in `README.md` without changing the catalog or
policy behavior. Install Git first, fork `devantler-tech/kyverno-policies` on GitHub, replace
`YOUR-LOGIN` below, and enter a dedicated worktree from your fork:

```sh
git clone https://github.com/YOUR-LOGIN/kyverno-policies.git
cd kyverno-policies
git worktree add -b docs/first-contribution ../kyverno-policies-first-change HEAD
cd ../kyverno-policies-first-change
```

Read [AGENTS.md](AGENTS.md) before editing any file. Keep changes in this isolated worktree;
the primary clone remains separate. “Repository root” below means the worktree directory.

Before validation, you also need Bash and standard Unix tools, kubectl with built-in Kustomize,
[Mike Farah's yq v4](https://mikefarah.gitbook.io/yq/),
[yamllint](https://yamllint.readthedocs.io/), [ShellCheck](https://www.shellcheck.net/),
[actionlint](https://github.com/rhysd/actionlint) and [zizmor](https://docs.zizmor.sh/).
Install the [Kyverno CLI](https://kyverno.io/docs/kyverno-cli/) version pinned as
`KYVERNO_CLI_VERSION` in [CI](.github/workflows/ci.yaml), currently **1.18.2**, and check
`kyverno version` before testing. A different CLI can evaluate the same fixture differently.
CI's install steps verify the release asset's repository-pinned digest and Sigstore identity.
These tests are local; no cluster context, App credentials or cloud account is required.

The documentation guard also uses a Go validator from the shared automation release. You need
Go at or above that release's `go.mod` floor, currently **1.26.8**. From the repository root,
prepare it in a new temporary directory (public GitHub access and Go module downloads may be needed):

```sh
validation_tools="$(mktemp -d)"
git clone https://github.com/devantler-tech/.github.git "$validation_tools/validator-source"
git -C "$validation_tools/validator-source" checkout --detach bd0035dd8f41fcf1459b878882b8897443f8dc59
GOWORK=off GOFLAGS= GOTOOLCHAIN=local go -C "$validation_tools/validator-source/actions/validate-retired-repo-links" build -mod=readonly -trimpath -o "$validation_tools/retired-repo-links" .
```

This revision matches the immutable validator pin in CI. Keep `validation_tools` set in the
same shell for the next command block. If CI changes that pin, use its new exact revision and
Go floor rather than a floating checkout. Do not weaken a validator to get a passing result.

## Validate your change

After your README edit, run every command from the repository root:

```sh
yamllint .
kubectl kustomize . > /dev/null
kyverno test . --require-tests --detailed-results --remove-color
bash scripts/test-policy-catalog.sh
bash scripts/test-retired-repo-links.sh "$validation_tools/retired-repo-links"
shellcheck scripts/test-policy-catalog.sh scripts/test-retired-repo-links.sh
actionlint .github/workflows/ci.yaml
zizmor .github/workflows/ci.yaml
git diff --check
```

All commands must exit 0. Rendering and most lint checks are quiet on success. Kyverno must
discover and evaluate the behavior fixtures; a missing test or skipped prerequisite is not
success. The structure test checks catalog boundaries and matched/unmatched generation controls.
The retired-link test prints expected defect diagnostics while checking that those defects are
rejected; its final PASS distinguishes successful negative controls from an unchecked scan.

This proves local fixture and structural behavior, not a deployed controller or consumer rollout.
Required native CI and substantive review of the exact current head remain separate merge gates.

## Change policy behavior safely

Read [AGENTS.md](AGENTS.md) before a policy change. Keep shared policies generic and register
published policies in the root catalog. Add tests first, including the complete generated object
and a nonmatching resource for generate rules. Consumer wiring, exclusions, adoption and rollout
belong in separate validated consumer changes; adding a policy here deploys nothing.

Preserve existing behavior by default. An API migration or breaking output change needs its own
issue, parity tests and reversible rollout. Never test this library by connecting to a live cluster.

## Submit your change

Review the diff, configure commit signing and stage explicit paths. For the README-only change:

```sh
git add README.md
git commit -S -m "docs: clarify policy-library onboarding"
git push -u origin docs/first-contribution
```

Open a **draft** PR to `devantler-tech/kyverno-policies:main` using the inherited
[PR template](https://github.com/devantler-tech/.github/blob/main/.github/PULL_REQUEST_TEMPLATE.md).
Use a Conventional Commit title, keep Why/What focused on the reader-facing problem and outcome,
and link the issue for substantial work. Put detailed validation in a comment or check summary.
Disclose AI assistance when used. Address review findings; required CI and an exact-head green
substantive review must pass before merge. Follow the inherited
[code of conduct](https://github.com/devantler-tech/.github/blob/main/.github/CODE_OF_CONDUCT.md).
