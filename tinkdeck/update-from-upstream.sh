#!/usr/bin/env bash
# tinkdeck/update-from-upstream.sh
#
# Updates this fork to the latest upstream NewsBlur, then re-applies all
# tinkdeck-specific customizations. See TINKDECK.md for full details.
#
# Usage: bash tinkdeck/update-from-upstream.sh
#
# Run from the repo root.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLU}[info]${NC}  $*"; }
ok()    { echo -e "${GRN}[ok]${NC}    $*"; }
warn()  { echo -e "${YEL}[warn]${NC}  $*"; }
die()   { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# Files that exist only in this fork — preserved across the reset verbatim.
EXCLUSIVE_FILES=(
    deploy-vps.sh
    docker-compose.vps.yml
    media/js/newsblur/local/story_alt_links.js
    TINKDECK.md
)
# The tinkdeck/ directory itself is also exclusive and is handled separately.

# Shared files touched by tinkdeck patches — used for the conflict check.
TINKDECK_SHARED=(
    apps/profile/views.py
    newsblur_web/docker_local_settings.py
    docker/haproxy/haproxy.docker-compose.cfg
    templates/base.html
    media/js/newsblur/reader/reader_preferences.js
    media/js/newsblur/views/story_title_view.js
)

# ---------------------------------------------------------------------------
# 0. Preflight checks
# ---------------------------------------------------------------------------

[[ "$(git remote get-url upstream 2>/dev/null)" == *samuelclay* ]] \
    || die "upstream remote not found. Run: git remote add upstream https://github.com/samuelclay/NewsBlur.git"

[[ -z "$(git status --porcelain)" ]] \
    || die "Working tree is dirty. Commit or stash changes first."

# ---------------------------------------------------------------------------
# 1. Fetch upstream and show what's changed
# ---------------------------------------------------------------------------

info "Fetching upstream..."
git fetch upstream --quiet

DIFF_COUNT=$(git diff upstream/main HEAD --name-only | wc -l | tr -d ' ')
UPSTREAM_SHA=$(git rev-parse --short upstream/main)
info "upstream/main is at $UPSTREAM_SHA — $DIFF_COUNT files differ from our main"

echo
info "Checking for upstream changes to tinkdeck-patched files..."
CONFLICTS=()
for f in "${TINKDECK_SHARED[@]}"; do
    if git diff upstream/main HEAD --name-only | grep -qx "$f"; then
        CONFLICTS+=("$f")
    fi
done

if [[ ${#CONFLICTS[@]} -eq 0 ]]; then
    ok "No tinkdeck-patched files were changed upstream — patches should apply cleanly."
else
    warn "The following tinkdeck-patched files were also changed upstream."
    warn "Patches may need manual adjustment after this script finishes:"
    for f in "${CONFLICTS[@]}"; do
        echo "      $f"
    done
fi

# ---------------------------------------------------------------------------
# 2. Confirm before destructive steps
# ---------------------------------------------------------------------------

echo
echo -e "${YEL}This will hard-reset main to upstream/main ($UPSTREAM_SHA).${NC}"
echo -e "${YEL}A backup tag will be created first.${NC}"
read -rp "Continue? [y/N] " CONFIRM
[[ "${CONFIRM,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# 3. Tag current state as backup
# ---------------------------------------------------------------------------

TAG="tinkdeck-before-$(date +%Y%m%d)"
git tag "$TAG"
ok "Tagged current state as $TAG"

# ---------------------------------------------------------------------------
# 4. Save exclusive tinkdeck files to a temp directory
# ---------------------------------------------------------------------------

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for f in "${EXCLUSIVE_FILES[@]}"; do
    if [[ -e "$f" ]]; then
        mkdir -p "$TMPDIR/$(dirname "$f")"
        cp "$f" "$TMPDIR/$f"
    fi
done

# Copy the entire tinkdeck/ directory
cp -r tinkdeck/ "$TMPDIR/tinkdeck/"

ok "Saved tinkdeck files to $TMPDIR"

# ---------------------------------------------------------------------------
# 5. Hard-reset to upstream/main
# ---------------------------------------------------------------------------

git reset --hard upstream/main
ok "Reset to upstream/main ($UPSTREAM_SHA)"

# ---------------------------------------------------------------------------
# 6. Restore exclusive tinkdeck files
# ---------------------------------------------------------------------------

for f in "${EXCLUSIVE_FILES[@]}"; do
    if [[ -e "$TMPDIR/$f" ]]; then
        mkdir -p "$(dirname "$f")"
        cp "$TMPDIR/$f" "$f"
    fi
done

cp -r "$TMPDIR/tinkdeck/" tinkdeck/
ok "Restored tinkdeck exclusive files"

# ---------------------------------------------------------------------------
# 7. Apply patches
# ---------------------------------------------------------------------------

echo
info "Applying tinkdeck patches..."

PATCH_OK=()
PATCH_FAIL=()

for patch in tinkdeck/patches/*.patch; do
    # Skip annotated-instruction patches (they're not valid unified diffs)
    if grep -q "^NOTE:\|^CHANGE [0-9]\|^Find this\|^Insert\|^Add " "$patch" 2>/dev/null; then
        warn "$(basename "$patch") is an instruction patch — apply manually (see TINKDECK.md)"
        PATCH_FAIL+=("$patch")
        continue
    fi

    if git apply --check "$patch" 2>/dev/null; then
        git apply "$patch"
        PATCH_OK+=("$(basename "$patch")")
        ok "  $(basename "$patch")"
    else
        PATCH_FAIL+=("$(basename "$patch")")
        warn "  $(basename "$patch") FAILED"
    fi
done

# ---------------------------------------------------------------------------
# 8. Summary and next steps
# ---------------------------------------------------------------------------

echo
if [[ ${#PATCH_FAIL[@]} -eq 0 ]]; then
    ok "All patches applied. Staging and committing..."
    git add -A
    git commit -m "tinkdeck: rebase onto upstream $UPSTREAM_SHA

Applied tinkdeck customizations on top of upstream/main.
See TINKDECK.md for the full list of patches.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
    ok "Committed. Run: git push origin main --force-with-lease"
else
    warn "${#PATCH_FAIL[@]} patch(es) need manual attention:"
    for p in "${PATCH_FAIL[@]}"; do
        echo "      $p"
    done
    echo
    info "For each failed patch, open TINKDECK.md and apply the change manually,"
    info "then regenerate the patch file so it stays accurate for next time."
    info ""
    info "When done:"
    info "  git add -A"
    info "  git commit -m 'tinkdeck: rebase onto upstream $UPSTREAM_SHA'"
    info "  git push origin main --force-with-lease"
    echo
    if [[ ${#PATCH_OK[@]} -gt 0 ]]; then
        info "Patches that applied cleanly (already staged by git apply):"
        for p in "${PATCH_OK[@]}"; do
            echo "      $p"
        done
    fi
    exit 1
fi
