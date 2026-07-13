#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"
PATCH_ROOT="${PATCH_ROOT:-$REPO_ROOT/patches/self-hosted}"
PATCH_SERIES="${PATCH_SERIES:-$PATCH_ROOT/series}"

[[ -f "$PATCH_SERIES" ]] || { echo "missing series: $PATCH_SERIES" >&2; exit 1; }

while IFS='|' read -r patch_path _; do
  [[ -z "${patch_path//[[:space:]]/}" ]] && continue
  [[ "$patch_path" == \#* ]] && continue
  patch="$PATCH_ROOT/$patch_path"
  [[ -f "$patch" ]] || { echo "missing patch: $patch" >&2; exit 1; }
  git apply --stat "$patch" >/dev/null
  git apply --numstat "$patch" >/dev/null
  echo "valid: $patch_path"
done < "$PATCH_SERIES"
