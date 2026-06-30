#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUAC_BIN="${LUAC_BIN:-}"
TMP_MANIFEST_DIR=""
TMP_RIME_DIR=""

cleanup() {
  rm -f \
    "$ROOT/user.yaml" \
    "$ROOT/installation.yaml" \
    "$ROOT/lua/cold_word_drop/runLog.txt" \
    "$ROOT/.codegraph/ci-local.txt" \
    "$ROOT/docs/ci-local.txt"
  if [ -n "$TMP_RIME_DIR" ]; then
    rm -rf "$TMP_RIME_DIR"
  fi
  if [ -n "$TMP_MANIFEST_DIR" ]; then
    rm -rf "$TMP_MANIFEST_DIR"
  fi
}
trap cleanup EXIT

find_luac() {
  if [ -n "$LUAC_BIN" ]; then
    command -v "$LUAC_BIN" >/dev/null 2>&1 || {
      printf 'Configured LUAC_BIN is not available: %s\n' "$LUAC_BIN" >&2
      exit 1
    }
    printf '%s\n' "$LUAC_BIN"
    return
  fi

  for candidate in luac luac5.4 luac5.3 luac5.2 luac5.1; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf 'No luac binary found. Install Lua or set LUAC_BIN.\n' >&2
  exit 1
}

assert_not_in_manifest() {
  output="$1"
  pattern="$2"
  if printf '%s\n' "$output" | grep -E "$pattern" >/dev/null 2>&1; then
    printf 'Unexpected file in install manifest matching: %s\n' "$pattern" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

assert_in_manifest() {
  output="$1"
  pattern="$2"
  if ! printf '%s\n' "$output" | grep -E "$pattern" >/dev/null 2>&1; then
    printf 'Expected file missing from install manifest matching: %s\n' "$pattern" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

cd "$ROOT"

printf 'Checking shell syntax...\n'
bash -n "$ROOT/scripts/install.sh"
bash -n "$ROOT/scripts/verify.sh"

printf 'Checking Lua syntax...\n'
LUAC_RESOLVED="$(find_luac)"
find "$ROOT/lua" -name '*.lua' -print0 | xargs -0 "$LUAC_RESOLVED" -p
"$LUAC_RESOLVED" -p "$ROOT/rime.lua"

printf 'Checking install manifest allow-list...\n'
mkdir -p "$ROOT/.codegraph" "$ROOT/docs"
touch \
  "$ROOT/user.yaml" \
  "$ROOT/installation.yaml" \
  "$ROOT/lua/cold_word_drop/runLog.txt" \
  "$ROOT/.codegraph/ci-local.txt" \
  "$ROOT/docs/ci-local.txt"

TMP_MANIFEST_DIR="$(mktemp -d)"
MANIFEST_OUTPUT="$(RIME_USER_DIR="$TMP_MANIFEST_DIR" "$ROOT/scripts/install.sh" --dry-run --no-download-gram)"
assert_in_manifest "$MANIFEST_OUTPUT" '^rime_ice\.schema\.yaml$'
assert_in_manifest "$MANIFEST_OUTPUT" '^rime_ice\.dict\.yaml$'
assert_in_manifest "$MANIFEST_OUTPUT" '^rime\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/.+\.lua$'
assert_not_in_manifest "$MANIFEST_OUTPUT" '(^user\.yaml$|^installation\.yaml$|runLog\.txt|^\.codegraph/|^docs/)'

if [ "${SKIP_NETWORK_CHECK:-0}" != "1" ]; then
  printf 'Checking GitHub Release digest parser...\n'
  GRAM_DIGEST="$(
    curl -fsSL https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS |
      awk -v name="wanxiang-lts-zh-hans.gram" '
        index($0, "\"name\": \"" name "\"") { found = 1 }
        found && index($0, "\"digest\":") {
          sub(/^.*"digest": "/, "", $0)
          sub(/".*$/, "", $0)
          print
          exit
        }
      '
  )"
  if ! printf '%s\n' "$GRAM_DIGEST" | grep -E '^sha256:[0-9a-f]{64}$' >/dev/null 2>&1; then
    printf 'Could not parse GitHub Release SHA-256 digest for wanxiang-lts-zh-hans.gram\n' >&2
    printf 'Parsed value: %s\n' "$GRAM_DIGEST" >&2
    exit 1
  fi
else
  printf 'Skipping network digest check because SKIP_NETWORK_CHECK=1.\n'
fi

if [ "${SKIP_RIME_BUILD:-0}" = "1" ]; then
  printf 'Skipping Rime build because SKIP_RIME_BUILD=1.\n'
  exit 0
fi

if ! command -v rime_deployer >/dev/null 2>&1; then
  printf 'rime_deployer is not available. Install librime-bin or set SKIP_RIME_BUILD=1.\n' >&2
  exit 1
fi

printf 'Checking temporary install and Rime build...\n'
TMP_RIME_DIR="$(mktemp -d)"
INSTALL_OUTPUT="$(RIME_USER_DIR="$TMP_RIME_DIR" "$ROOT/scripts/install.sh" --no-download-gram)"
printf '%s\n' "$INSTALL_OUTPUT" | grep 'Backup: none needed' >/dev/null

rime_deployer --build "$TMP_RIME_DIR" "$TMP_RIME_DIR" "$TMP_RIME_DIR/build"
test -f "$TMP_RIME_DIR/build/rime_ice.schema.yaml"
test -f "$TMP_RIME_DIR/build/rime_ice.table.bin"
test -f "$TMP_RIME_DIR/build/melt_eng.table.bin"
test -f "$TMP_RIME_DIR/build/radical_pinyin.table.bin"

printf 'Verification passed.\n'
