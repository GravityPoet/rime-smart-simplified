#!/bin/bash
set -euo pipefail

# Build the exact tracked tree that git archive would publish, then assert that
# customer runtime data and installer state cannot cross the release boundary.
# This deliberately checks HEAD (rather than the working tree): CI runs against
# the commit that a release tag would point at.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${RELEASE_ARCHIVE_REF:-HEAD}"
PREFIX="rime-smart-simplified-archive-audit/"
WORK_DIR=""

cleanup() {
  if [ -n "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

command -v git >/dev/null 2>&1 || { printf 'git is required for archive checks.\n' >&2; exit 2; }
command -v unzip >/dev/null 2>&1 || { printf 'unzip is required for archive checks.\n' >&2; exit 2; }

git -C "$ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || {
  printf 'Archive ref is not a commit: %s\n' "$REF" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-release-archive.XXXXXX")"
ARCHIVE="$WORK_DIR/package.zip"
EXTRACT_DIR="$WORK_DIR/extract"
mkdir -p "$EXTRACT_DIR"

git -C "$ROOT" archive --format=zip --prefix="$PREFIX" --output="$ARCHIVE" "$REF"
unzip -q -t "$ARCHIVE"
unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"
ARCHIVE_ROOT="$EXTRACT_DIR/${PREFIX%/}"

required_entries=(
  "Install-on-macOS.command"
  "Install-on-Windows.cmd"
  "scripts/install.sh"
  "scripts/install.ps1"
  "UPSTREAM_ASSETS.lock.json"
  "scripts/check_upstream_freshness.sh"
  "scripts/uninstall.sh"
  "scripts/uninstall.ps1"
)
for relative_path in "${required_entries[@]}"; do
  required_path="$ARCHIVE_ROOT/$relative_path"
  if [ ! -f "$required_path" ]; then
    printf 'Release archive is missing required entry: %s\n' "$relative_path" >&2
    exit 1
  fi
done
if [ ! -x "$ARCHIVE_ROOT/Install-on-macOS.command" ]; then
  printf 'Release archive lost the executable bit: Install-on-macOS.command\n' >&2
  exit 1
fi

# These are user state, rollback copies, generated build output, or local
# benchmark results. A package that contains any one of them is not releasable.
FORBIDDEN_PATTERN='(^|/)(user\.yaml|installation\.yaml|predict\.db|.*\.gram|.*\.userdb($|/)|.*\.backup\.|.*\.bak($|\.)|.*\.tmp($|\.)|.*\.log($|\.)|\.rime-smart-simplified\.install-manifest|benchmark-results\.jsonl|custom_phrase\.local\.txt|context_boost\.tsv|context_boost\.journal\.tsv|pin_by_select\.tsv|pin_by_select_v2\.tsv|runLog\.txt)$|(^|/)(build|sync|\.codegraph|.*\.backup\.[^/]+)(/|$)'
RUNTIME_HITS="$WORK_DIR/runtime-hits"
find "$ARCHIVE_ROOT" \( -type f -o -type d \) | sed "s#^$ARCHIVE_ROOT/##" | grep -E "$FORBIDDEN_PATTERN" >"$RUNTIME_HITS" || true
if [ -s "$RUNTIME_HITS" ]; then
  printf 'Release archive contains runtime, backup, or local state:\n' >&2
  sed 's/^/  /' "$RUNTIME_HITS" >&2
  exit 1
fi

printf 'Release archive check passed: ref=%s files=%s\n' \
  "$REF" "$(find "$ARCHIVE_ROOT" -type f | wc -l | tr -d ' ')"
