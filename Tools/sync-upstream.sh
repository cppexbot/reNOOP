#!/usr/bin/env bash
# reNOOP: pull fixes from the original NOOP repo (ryanbr/noop) into this fork's main.
#
# The fork keeps its own iOS interface, so a sync is a MERGE (never a rebase): upstream fixes to logic,
# BLE, analytics, storage and Android come in; screens this fork deleted or rewrote stay ours.
#
#   Tools/sync-upstream.sh          fetch + merge, auto-resolve what is safe, list what needs a human
#
# What it resolves by itself:
#   - a file the fork DELETED that upstream changed (old Today/Sleep/Liquid screens, ...) stays deleted;
#     the upstream commits that touched it are printed so a real fix can be ported to the new screen.
# What it leaves for you (conflict markers): files both sides edited. Keep our UI, take their logic.
# After resolving: rename new user-facing "NOOP" strings to "reNOOP" (Swift literals + xcstrings keys),
# build iOS + macOS, run the tests, then `git commit`.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/ryanbr/noop.git
# Remember conflict resolutions, so a hunk resolved once resolves itself on the next sync.
git config rerere.enabled true
git config rerere.autoupdate true

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Working tree has uncommitted changes. Commit them first." >&2
  exit 1
fi

git fetch upstream
base=$(git merge-base HEAD upstream/main)
ahead=$(git rev-list --count HEAD..upstream/main)
if [ "$ahead" -eq 0 ]; then
  echo "Already up to date with upstream/main."
  exit 0
fi
echo "Merging $ahead upstream commit(s)..."

if git merge --no-ff --no-commit upstream/main; then
  echo "Merged without conflicts. Build, test, then: git commit"
  exit 0
fi

echo
echo "== Deleted here, changed upstream -> kept deleted. Port a fix to the new screen if it matters:"
git status --porcelain | awk '$1=="DU"{print $2}' | while read -r f; do
  git rm -q -- "$f"
  echo "  $f"
  git log --format='      %h %s' "$base..upstream/main" -- "$f"
done

echo
echo "== Deleted upstream, changed here -> review (git rm to accept, git add to keep):"
git status --porcelain | awk '$1=="UD"{print "  "$2}'

echo
echo "== Both edited -> resolve by hand (keep our UI, take their logic):"
git diff --name-only --diff-filter=U | sed 's/^/  /'
