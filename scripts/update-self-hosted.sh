#!/usr/bin/env bash
set -Eeuo pipefail

# Rebuild a self-hosted branch from a fresh upstream/main plus the maintained patch series.
# The target branch is updated only after every patch and requested verification step succeeds.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-origin}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
TARGET_BRANCH="${TARGET_BRANCH:-self-hosted}"
PUSH_REMOTE="${PUSH_REMOTE:-origin}"
PATCH_ROOT="${PATCH_ROOT:-$REPO_ROOT/patches/self-hosted}"
PATCH_SERIES="${PATCH_SERIES:-$PATCH_ROOT/series}"
RUN_TESTS="${RUN_TESTS:-1}"
BUILD_CHROME="${BUILD_CHROME:-1}"
PACKAGE_CHROME="${PACKAGE_CHROME:-0}"
ARTIFACT_DIR="${ARTIFACT_DIR:-}"
INSTALL_DEPS="${INSTALL_DEPS:-0}"
PUSH="${PUSH:-0}"
KEEP_WORKTREE="${KEEP_WORKTREE:-0}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git is required"
[[ -f "$PATCH_SERIES" ]] || fail "patch series not found: $PATCH_SERIES"
git -C "$REPO_ROOT" remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 || \
  fail "remote '$UPSTREAM_REMOTE' is not configured"

# Updating a branch that is checked out elsewhere would leave that worktree inconsistent.
if git -C "$REPO_ROOT" worktree list --porcelain | \
  grep -Fxq "branch refs/heads/$TARGET_BRANCH"; then
  fail "target branch '$TARGET_BRANCH' is checked out in a worktree; switch that worktree first"
fi

printf 'Fetching %s/%s...\n' "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
git -C "$REPO_ROOT" fetch --prune "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
if [[ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository)" == "true" ]]; then
  printf 'Fetching full history required for three-way patch application...\n'
  git -C "$REPO_ROOT" fetch --unshallow "$UPSTREAM_REMOTE"
fi
BASE_REF="$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
git -C "$REPO_ROOT" rev-parse --verify "$BASE_REF^{commit}" >/dev/null

WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/clients-self-hosted.XXXXXXXX")"
cleanup() {
  if [[ "$KEEP_WORKTREE" == "1" ]]; then
    printf 'Keeping worktree for inspection: %s\n' "$WORKTREE" >&2
    return
  fi
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$WORKTREE"
}
trap cleanup EXIT

git -C "$REPO_ROOT" worktree add --detach "$WORKTREE" "$BASE_REF"
git -C "$WORKTREE" config user.name "Self-hosted extension updater"
git -C "$WORKTREE" config user.email "self-hosted-updater@localhost"

apply_patch() {
  local patch_path="$1"
  local commit_message="$2"
  local absolute_patch="$PATCH_ROOT/$patch_path"

  [[ -f "$absolute_patch" ]] || fail "missing patch: $absolute_patch"
  printf 'Applying %s...\n' "$patch_path"

  if git -C "$WORKTREE" apply --reverse --check "$absolute_patch" >/dev/null 2>&1; then
    printf 'Already present upstream; skipping %s\n' "$patch_path"
    return
  fi

  # --3way uses the blob IDs embedded in these patches when main has moved.
  if ! git -C "$WORKTREE" apply --3way --index "$absolute_patch"; then
    printf '\nPatch failed: %s\n' "$patch_path" >&2
    printf 'Inspect conflict state with KEEP_WORKTREE=1 and rerun.\n' >&2
    exit 1
  fi

  if git -C "$WORKTREE" diff --cached --quiet; then
    printf 'Patch produced no staged changes; skipping commit for %s\n' "$patch_path"
    return
  fi

  git -C "$WORKTREE" commit -m "$commit_message"
}

while IFS='|' read -r patch_path commit_message; do
  [[ -z "${patch_path//[[:space:]]/}" ]] && continue
  [[ "$patch_path" == \#* ]] && continue
  [[ -n "$commit_message" ]] || fail "series entry lacks a commit message: $patch_path"
  apply_patch "$patch_path" "$commit_message"
done < "$PATCH_SERIES"

cd "$WORKTREE"
if [[ "$INSTALL_DEPS" == "1" ]]; then
  npm ci
fi

if [[ "$RUN_TESTS" == "1" ]]; then
  npm test -- --runInBand \
    apps/browser/src/autofill/services/autofill.service.spec.ts \
    apps/browser/src/vault/popup/services/vault-popup-items.service.spec.ts
fi

if [[ "$PACKAGE_CHROME" == "1" ]]; then
  npm run dist:chrome --workspace @bitwarden/browser
  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    BUILD_SHA="$(git rev-parse --short=12 HEAD)"
    cp apps/browser/dist/dist-chrome.zip "$ARTIFACT_DIR/self-hosted-chrome-$BUILD_SHA.zip"
  fi
elif [[ "$BUILD_CHROME" == "1" ]]; then
  npm run build:prod:chrome --workspace @bitwarden/browser
fi

NEW_SHA="$(git rev-parse HEAD)"
OLD_SHA="$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/heads/$TARGET_BRANCH" || true)"

if [[ -n "$OLD_SHA" ]]; then
  git -C "$REPO_ROOT" update-ref "refs/heads/$TARGET_BRANCH" "$NEW_SHA" "$OLD_SHA"
else
  git -C "$REPO_ROOT" update-ref "refs/heads/$TARGET_BRANCH" "$NEW_SHA"
fi
printf 'Updated local branch %s to %s\n' "$TARGET_BRANCH" "$NEW_SHA"

if [[ "$PUSH" == "1" ]]; then
  git -C "$REPO_ROOT" remote get-url "$PUSH_REMOTE" >/dev/null 2>&1 || \
    fail "push remote '$PUSH_REMOTE' is not configured"

  REMOTE_SHA="$(git -C "$REPO_ROOT" ls-remote --heads "$PUSH_REMOTE" "refs/heads/$TARGET_BRANCH" | awk '{print $1}')"
  if [[ -n "$REMOTE_SHA" ]]; then
    git -C "$REPO_ROOT" push "$PUSH_REMOTE" \
      "$NEW_SHA:refs/heads/$TARGET_BRANCH" \
      "--force-with-lease=refs/heads/$TARGET_BRANCH:$REMOTE_SHA"
  else
    git -C "$REPO_ROOT" push "$PUSH_REMOTE" "$NEW_SHA:refs/heads/$TARGET_BRANCH"
  fi
  printf 'Pushed %s to %s\n' "$TARGET_BRANCH" "$PUSH_REMOTE"
fi
