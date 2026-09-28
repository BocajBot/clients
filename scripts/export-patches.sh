#!/usr/bin/env bash
set -Eeuo pipefail

# Rewrite the patch files listed in the series from a refreshed commit stack.
#
# When upstream moves and a patch stops applying, refresh the stack by hand:
#   git worktree add --detach ../refresh upstream/main
#   apply each series entry in order with `git apply --3way --index`, resolve any
#   conflicts, and commit it with the message from the series
# then export the stack back into the patch files:
#   STACK_REPO=../refresh scripts/export-patches.sh upstream/main
#
# BASE..HEAD in STACK_REPO must hold exactly one commit per series entry, in series
# order, each with the series commit message. Patches are written as full-index diffs
# so `git apply --3way` in update-self-hosted.sh can merge against later upstreams.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

PATCH_ROOT="${PATCH_ROOT:-$REPO_ROOT/patches/self-hosted}"
PATCH_SERIES="${PATCH_SERIES:-$PATCH_ROOT/series}"
STACK_REPO="${STACK_REPO:-.}"
BASE="${1:?usage: STACK_REPO=<worktree> $0 <base-ref> [head-ref]}"
HEAD_REF="${2:-HEAD}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ -f "$PATCH_SERIES" ]] || fail "patch series not found: $PATCH_SERIES"

entries=()
messages=()
while IFS='|' read -r patch_path commit_message; do
  [[ -z "${patch_path//[[:space:]]/}" ]] && continue
  [[ "$patch_path" == \#* ]] && continue
  entries+=("$patch_path")
  messages+=("$commit_message")
done < "$PATCH_SERIES"

mapfile -t commits < <(git -C "$STACK_REPO" rev-list --reverse "$BASE..$HEAD_REF")

(( ${#commits[@]} == ${#entries[@]} )) || \
  fail "$BASE..$HEAD_REF has ${#commits[@]} commits; series has ${#entries[@]} entries"

for i in "${!entries[@]}"; do
  subject="$(git -C "$STACK_REPO" log -1 --format=%s "${commits[$i]}")"
  [[ "$subject" == "${messages[$i]}" ]] || \
    fail "commit ${commits[$i]:0:10} is '$subject', series expects '${messages[$i]}'"
done

for i in "${!entries[@]}"; do
  git -C "$STACK_REPO" diff --full-index "${commits[$i]}^" "${commits[$i]}" \
    > "$PATCH_ROOT/${entries[$i]}"
  printf 'exported %s from %s\n' "${entries[$i]}" "${commits[$i]:0:10}"
done
