# GitHub Actions deploys with per-environment identities over OIDC, prod from a release branch

Each environment has a user-assigned managed identity with Contributor rights on that environment's resource group only. GitHub Actions signs in as it through OIDC federated credentials, so no Azure secret is stored in GitHub. Subscription-level setup runs once, from `scripts/setup-azure.sh` with the owner's account. That setup covers the policies, budget, resource group and identities.

The federated credentials trust Git refs, so the setup works on GitHub plans without deployment environments.
- The `dev` identity trusts `main` and pull requests. A merge to `main` deploys dev, and a pull request gets an infrastructure what-if.
- The `prod` identity trusts only the `release` branch. Federated credentials can't match a tag pattern such as `v*`, so `scripts/release.sh` tags `origin/main` and pushes the tagged commit to `release`. `prod.yml` refuses any `release` commit without a `v*` tag.

GitHub's OIDC tokens name the repository with numeric IDs (`repo:owner@123/name@456:…`), so the federated credentials use that form. Renaming or transferring the repository doesn't change them, but recreating it does: re-run the setup wizard then.

## Consequences

- Releasing to prod is a deliberate human step: run `scripts/release.sh vX.Y.Z`. Redeploying an older tag the same way rolls back.
- `release.sh` runs with your own Git credentials, because a workflow's default token can't push commits that change workflow files.
