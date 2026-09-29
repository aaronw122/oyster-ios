#!/usr/bin/env bash
# Copy the backend's canonical contract fixtures verbatim into OysterKit's test
# resources and record the backend commit they came from in SOURCE.
#
#   BACKEND_REPO  path to an oyster-backend checkout (default: ../backend)
#   BACKEND_REF   ref to copy from, fetched from origin first
#                 (default: origin/feat/oyster-plan-integration)
#
# The backend checkout is only read (fetch + archive); its working tree is untouched.
set -euo pipefail

cd "$(dirname "$0")/.."

BACKEND_REPO="${BACKEND_REPO:-../backend}"
BACKEND_REF="${BACKEND_REF:-origin/feat/oyster-plan-integration}"
DEST="OysterKit/Tests/OysterKitTests/Fixtures/contract"

git -C "$BACKEND_REPO" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "not a git checkout: $BACKEND_REPO (set BACKEND_REPO)" >&2; exit 1; }

git -C "$BACKEND_REPO" fetch -q origin
SHA="$(git -C "$BACKEND_REPO" rev-parse "$BACKEND_REF^{commit}")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$BACKEND_REPO" archive "$SHA" fixtures/contract | tar -x -C "$TMP"

mkdir -p "$DEST"
rsync -a --delete --exclude SOURCE "$TMP/fixtures/contract/" "$DEST/"
cat >"$DEST/SOURCE" <<EOF
repo: github.com/aaronw122/oyster-backend
ref: $BACKEND_REF
commit: $SHA
path: fixtures/contract
EOF

echo "Synced fixtures from $BACKEND_REF ($SHA) into $DEST"
