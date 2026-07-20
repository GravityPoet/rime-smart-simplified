#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUAC_BIN="${LUAC_BIN:-}"
LUA_BIN="${LUA_BIN:-}"
TMP_MANIFEST_DIR=""
TMP_RIME_DIR=""
TMP_BEHAVIOR_DIR=""
TMP_WINDOWS_DIR=""

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
  if [ -n "$TMP_BEHAVIOR_DIR" ]; then
    rm -rf "$TMP_BEHAVIOR_DIR"
  fi
  if [ -n "$TMP_WINDOWS_DIR" ]; then
    rm -rf "$TMP_WINDOWS_DIR"
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

find_lua() {
  if [ -n "$LUA_BIN" ]; then
    command -v "$LUA_BIN" >/dev/null 2>&1 || {
      printf 'Configured LUA_BIN is not available: %s\n' "$LUA_BIN" >&2
      exit 1
    }
    printf '%s\n' "$LUA_BIN"
    return
  fi

  for candidate in lua lua5.4 lua5.3 lua5.2 lua5.1; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf 'No lua binary found. Install Lua or set LUA_BIN.\n' >&2
  exit 1
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'Neither shasum nor sha256sum is available; cannot hash %s\n' "$1" >&2
    exit 1
  fi
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
bash -n "$ROOT/Install-on-macOS.command"
grep 'scripts\\install.ps1' "$ROOT/Install-on-Windows.cmd" >/dev/null

if command -v pwsh >/dev/null 2>&1; then
  printf 'Checking Windows installer dry run...\n'
  TMP_WINDOWS_DIR="$(mktemp -d)"
  WINDOWS_DRY_RUN="$(pwsh -NoLogo -NoProfile -File "$ROOT/scripts/install.ps1" \
    -RimeUserDir "$TMP_WINDOWS_DIR" -DryRun -NoDownloadGram)"
  printf '%s\n' "$WINDOWS_DRY_RUN" | grep 'Files to install:' >/dev/null
  printf '%s\n' "$WINDOWS_DRY_RUN" | grep '^rime_ice\.schema\.yaml$' >/dev/null
  printf '%s\n' "$WINDOWS_DRY_RUN" | grep '^custom_phrase\.txt$' >/dev/null
else
  printf 'Skipping Windows installer execution because pwsh is unavailable.\n'
fi

printf 'Checking Lua syntax...\n'
LUAC_RESOLVED="$(find_luac)"
find "$ROOT/lua" -name '*.lua' -print0 | xargs -0 "$LUAC_RESOLVED" -p
"$LUAC_RESOLVED" -p "$ROOT/rime.lua"

printf 'Checking Lua behavior...\n'
LUA_RESOLVED="$(find_lua)"
TMP_BEHAVIOR_DIR="$(mktemp -d)"
TZ=Asia/Tokyo "$LUA_RESOLVED" "$ROOT/tests/lua_behavior_test.lua" "$ROOT" "$TMP_BEHAVIOR_DIR"

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
assert_in_manifest "$MANIFEST_OUTPUT" '^custom_phrase\.txt$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/.+\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/cold_word_drop/drop_words\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/cold_word_drop/hide_words\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/cold_word_drop/reduce_freq_words\.lua$'
assert_not_in_manifest "$MANIFEST_OUTPUT" '(^user\.yaml$|^installation\.yaml$|runLog\.txt|^\.codegraph/|^docs/)'

printf 'Checking private phrase and cold-word preference preservation...\n'
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/custom_phrase.txt"
mkdir -p "$TMP_MANIFEST_DIR/lua/cold_word_drop"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/lua/cold_word_drop/drop_words.lua"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/lua/cold_word_drop/hide_words.lua"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/lua/cold_word_drop/reduce_freq_words.lua"
PRIVATE_PHRASE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/custom_phrase.txt")"
COLD_DROP_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/drop_words.lua")"
COLD_HIDE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/hide_words.lua")"
COLD_REDUCE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/reduce_freq_words.lua")"
PRESERVE_DRY_RUN="$(RIME_USER_DIR="$TMP_MANIFEST_DIR" "$ROOT/scripts/install.sh" --dry-run --no-download-gram)"
assert_not_in_manifest "$PRESERVE_DRY_RUN" '^custom_phrase\.txt$'
assert_not_in_manifest "$PRESERVE_DRY_RUN" '^lua/cold_word_drop/(drop|hide|reduce_freq)_words\.lua$'
printf '%s\n' "$PRESERVE_DRY_RUN" | grep 'Private phrases: preserving existing custom_phrase.txt' >/dev/null
printf '%s\n' "$PRESERVE_DRY_RUN" | grep 'Cold-word preferences: preserving existing hide/drop/reduce records' >/dev/null
PRESERVE_OUTPUT="$(RIME_USER_DIR="$TMP_MANIFEST_DIR" "$ROOT/scripts/install.sh" --no-download-gram)"
printf '%s\n' "$PRESERVE_OUTPUT" | grep 'Private phrases: preserving existing custom_phrase.txt' >/dev/null
printf '%s\n' "$PRESERVE_OUTPUT" | grep 'Cold-word preferences: preserving existing hide/drop/reduce records' >/dev/null
PRIVATE_PHRASE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/custom_phrase.txt")"
COLD_DROP_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/drop_words.lua")"
COLD_HIDE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/hide_words.lua")"
COLD_REDUCE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/reduce_freq_words.lua")"
test "$PRIVATE_PHRASE_BEFORE" = "$PRIVATE_PHRASE_AFTER"
test "$COLD_DROP_BEFORE" = "$COLD_DROP_AFTER"
test "$COLD_HIDE_BEFORE" = "$COLD_HIDE_AFTER"
test "$COLD_REDUCE_BEFORE" = "$COLD_REDUCE_AFTER"

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
grep -E '^[[:space:]]*name: prediction$' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" >/dev/null
grep -A1 -E '^[[:space:]]*name: prediction$' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" | grep 'reset: 0' >/dev/null
grep 'max_candidates: 9' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" >/dev/null
grep 'max_iterations: 2' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" >/dev/null
grep 'simplifier@prediction_simplify' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" >/dev/null
grep 'opencc_config: t2s.json' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" >/dev/null
grep -- '- uniquifier' "$TMP_RIME_DIR/build/rime_ice.schema.yaml" >/dev/null
if sed -n '/^switcher:/,$p' "$TMP_RIME_DIR/build/default.yaml" | grep -E '^[[:space:]]*- prediction$' >/dev/null 2>&1; then
  printf 'Prediction must not persist across sessions because its active composition interferes with system shortcuts.\n' >&2
  exit 1
fi

printf 'Verification passed.\n'
