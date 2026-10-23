#!/usr/bin/env bash
# Fails when a pull request edits, renames or removes a migration that is
# already on its base branch. Migrations are immutable once merged (db/migrate.mjs
# also refuses them at deploy); fix forward with a new one.
#   scripts/check-migrations-unchanged.sh <base-branch>
set -euo pipefail
base="${1:?usage: check-migrations-unchanged.sh <base-branch>}"

git fetch --quiet --depth=1 origin "$base"
changed=$(git diff --name-only --diff-filter=MDR FETCH_HEAD HEAD -- db/migrations)
if [ -n "$changed" ]; then
  echo "::error::Merged migrations must not change. Add a new migration instead of editing:"
  echo "$changed"
  exit 1
fi
echo "Merged migrations are unchanged."
