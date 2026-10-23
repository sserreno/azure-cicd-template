#!/usr/bin/env bash
# Releases to prod: tags origin/main as the given version and moves the
# release branch to it, which starts .github/workflows/prod.yml (docs/adr/0004-deploy-with-oidc-and-a-release-branch.md).
# Passing an existing tag redeploys that version (e.g. to roll back).
#
#   scripts/release.sh v1.2.0
set -euo pipefail

tag="${1:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 vMAJOR.MINOR.PATCH" >&2; exit 1; }

git fetch --quiet --tags origin main

if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag $tag exists: redeploying it to prod."
else
  git tag --annotate "$tag" --message "Release $tag" origin/main
  git push origin "refs/tags/$tag"
  echo "Tagged origin/main as $tag."
fi

commit=$(git rev-parse "$tag^{commit}")
# --force allows moving release backwards when redeploying an older tag.
git push --force origin "$commit:refs/heads/release"
echo "release now points at $tag ($commit). Follow the prod workflow in GitHub Actions."
