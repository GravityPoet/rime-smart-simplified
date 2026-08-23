#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUAC_BIN="${LUAC_BIN:-}"
LUA_BIN="${LUA_BIN:-}"
TMP_MANIFEST_DIR=""
TMP_MANIFEST_ROOT=""
TMP_MANIFEST_SOURCE=""
TMP_RIME_DIR=""
TMP_BEHAVIOR_DIR=""
TMP_WINDOWS_DIR=""
TMP_TRANSACTION_ROOT=""
TMP_UNINSTALL_DIR=""
TMP_TAMPER_DIR=""
TMP_INJECTION_DIR=""
TMP_FORGE_DIR=""

cleanup() {
  if [ -n "$TMP_RIME_DIR" ]; then
    rm -rf "$TMP_RIME_DIR"
  fi
  if [ -n "$TMP_MANIFEST_ROOT" ]; then
    rm -rf "$TMP_MANIFEST_ROOT"
  fi
  if [ -n "$TMP_MANIFEST_SOURCE" ]; then
    rm -rf "$TMP_MANIFEST_SOURCE"
  fi
  if [ -n "$TMP_BEHAVIOR_DIR" ]; then
    rm -rf "$TMP_BEHAVIOR_DIR"
  fi
  if [ -n "$TMP_WINDOWS_DIR" ]; then
    rm -rf "$TMP_WINDOWS_DIR"
  fi
  if [ -n "$TMP_TRANSACTION_ROOT" ]; then
    rm -rf "$TMP_TRANSACTION_ROOT"
  fi
  if [ -n "$TMP_UNINSTALL_DIR" ]; then
    rm -rf "$TMP_UNINSTALL_DIR"
  fi
  if [ -n "$TMP_TAMPER_DIR" ]; then
    rm -rf "$TMP_TAMPER_DIR"
  fi
  if [ -n "$TMP_INJECTION_DIR" ]; then
    rm -rf "$TMP_INJECTION_DIR"
  fi
  if [ -n "$TMP_FORGE_DIR" ]; then
    rm -rf "$TMP_FORGE_DIR"
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

github_api_get() {
  url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 45 \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer $GITHUB_TOKEN" "$url"
  else
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 45 \
      -H 'Accept: application/vnd.github+json' "$url"
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
bash -n "$ROOT/scripts/update_dicts.sh"
bash -n "$ROOT/scripts/check_upstream_freshness.sh"
bash -n "$ROOT/scripts/check_release_archive.sh"
bash -n "$ROOT/scripts/uninstall.sh"
bash -n "$ROOT/scripts/benchmark.sh"
bash -n "$ROOT/scripts/verify.sh"
bash -n "$ROOT/Install-on-macOS.command"
grep 'scripts\\install.ps1' "$ROOT/Install-on-Windows.cmd" >/dev/null

printf 'Checking pinned upstream asset lock...\n'
bash "$ROOT/tests/upstream_freshness_test.sh"

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

printf 'Checking reproducible benchmark contract...\n'
"$ROOT/tests/benchmark_contract_test.sh"

printf 'Checking install manifest allow-list...\n'
TMP_MANIFEST_SOURCE="$(mktemp -d)"
mkdir -p \
  "$TMP_MANIFEST_SOURCE/scripts" \
  "$TMP_MANIFEST_SOURCE/cn_dicts" \
  "$TMP_MANIFEST_SOURCE/cn_dicts_wanxiang" \
  "$TMP_MANIFEST_SOURCE/en_dicts" \
  "$TMP_MANIFEST_SOURCE/lua/cold_word_drop" \
  "$TMP_MANIFEST_SOURCE/opencc" \
  "$TMP_MANIFEST_SOURCE/.codegraph" \
  "$TMP_MANIFEST_SOURCE/docs"
cp "$ROOT/scripts/install.sh" "$TMP_MANIFEST_SOURCE/scripts/install.sh"
cp \
  "$ROOT/rime_ice.schema.yaml" \
  "$ROOT/rime_ice.dict.yaml" \
  "$ROOT/rime_ice.custom.yaml" \
  "$ROOT/rime.lua" \
  "$ROOT/custom_phrase.txt" \
  "$ROOT/smart_chat_phrases.txt" \
  "$TMP_MANIFEST_SOURCE/"
cp "$ROOT/lua/force_gc.lua" "$TMP_MANIFEST_SOURCE/lua/force_gc.lua"
cp \
  "$ROOT/lua/cold_word_drop/drop_words.lua" \
  "$ROOT/lua/cold_word_drop/hide_words.lua" \
  "$ROOT/lua/cold_word_drop/reduce_freq_words.lua" \
  "$TMP_MANIFEST_SOURCE/lua/cold_word_drop/"
touch \
  "$TMP_MANIFEST_SOURCE/user.yaml" \
  "$TMP_MANIFEST_SOURCE/installation.yaml" \
  "$TMP_MANIFEST_SOURCE/lua/cold_word_drop/runLog.txt" \
  "$TMP_MANIFEST_SOURCE/.codegraph/ci-local.txt" \
  "$TMP_MANIFEST_SOURCE/docs/ci-local.txt"

TMP_MANIFEST_ROOT="$(mktemp -d)"
TMP_MANIFEST_DIR="$TMP_MANIFEST_ROOT/target"
mkdir -p "$TMP_MANIFEST_DIR"
MANIFEST_OUTPUT="$(RIME_USER_DIR="$TMP_MANIFEST_DIR" "$TMP_MANIFEST_SOURCE/scripts/install.sh" --dry-run --no-download-gram --no-download-predict)"
assert_in_manifest "$MANIFEST_OUTPUT" '^rime_ice\.schema\.yaml$'
assert_in_manifest "$MANIFEST_OUTPUT" '^rime_ice\.dict\.yaml$'
assert_in_manifest "$MANIFEST_OUTPUT" '^rime\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^custom_phrase\.txt$'
assert_in_manifest "$MANIFEST_OUTPUT" '^smart_chat_phrases\.txt$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/.+\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/cold_word_drop/drop_words\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/cold_word_drop/hide_words\.lua$'
assert_in_manifest "$MANIFEST_OUTPUT" '^lua/cold_word_drop/reduce_freq_words\.lua$'
assert_not_in_manifest "$MANIFEST_OUTPUT" '(^user\.yaml$|^installation\.yaml$|runLog\.txt|^\.codegraph/|^docs/)'

printf 'Checking private phrase and cold-word preference preservation...\n'
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/custom_phrase.txt"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/smart_chat_phrases.txt"
mkdir -p "$TMP_MANIFEST_DIR/lua/cold_word_drop"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/lua/cold_word_drop/drop_words.lua"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/lua/cold_word_drop/hide_words.lua"
cp "$ROOT/PRIVACY.md" "$TMP_MANIFEST_DIR/lua/cold_word_drop/reduce_freq_words.lua"
PRIVATE_PHRASE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/custom_phrase.txt")"
CHAT_PHRASE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/smart_chat_phrases.txt")"
COLD_DROP_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/drop_words.lua")"
COLD_HIDE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/hide_words.lua")"
COLD_REDUCE_BEFORE="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/reduce_freq_words.lua")"
PRESERVE_DRY_RUN="$(RIME_USER_DIR="$TMP_MANIFEST_DIR" "$ROOT/scripts/install.sh" --dry-run --no-download-gram)"
assert_not_in_manifest "$PRESERVE_DRY_RUN" '^custom_phrase\.txt$'
assert_not_in_manifest "$PRESERVE_DRY_RUN" '^smart_chat_phrases\.txt$'
assert_not_in_manifest "$PRESERVE_DRY_RUN" '^lua/cold_word_drop/(drop|hide|reduce_freq)_words\.lua$'
printf '%s\n' "$PRESERVE_DRY_RUN" | grep 'Private phrases: preserving existing custom_phrase.txt' >/dev/null
printf '%s\n' "$PRESERVE_DRY_RUN" | grep 'Cold-word preferences: preserving existing hide/drop/reduce records' >/dev/null
PRESERVE_OUTPUT="$(RIME_USER_DIR="$TMP_MANIFEST_DIR" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict)"
printf '%s\n' "$PRESERVE_OUTPUT" | grep 'Private phrases: preserving existing custom_phrase.txt' >/dev/null
printf '%s\n' "$PRESERVE_OUTPUT" | grep 'Cold-word preferences: preserving existing hide/drop/reduce records' >/dev/null
PRIVATE_PHRASE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/custom_phrase.txt")"
CHAT_PHRASE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/smart_chat_phrases.txt")"
COLD_DROP_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/drop_words.lua")"
COLD_HIDE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/hide_words.lua")"
COLD_REDUCE_AFTER="$(sha256_file "$TMP_MANIFEST_DIR/lua/cold_word_drop/reduce_freq_words.lua")"
test "$PRIVATE_PHRASE_BEFORE" = "$PRIVATE_PHRASE_AFTER"
test "$CHAT_PHRASE_BEFORE" = "$CHAT_PHRASE_AFTER"
test "$COLD_DROP_BEFORE" = "$COLD_DROP_AFTER"
test "$COLD_HIDE_BEFORE" = "$COLD_HIDE_AFTER"
test "$COLD_REDUCE_BEFORE" = "$COLD_REDUCE_AFTER"

printf 'Checking installer fail-closed and rollback boundaries...\n'
TMP_TRANSACTION_ROOT="$(mktemp -d)"

SYMLINK_TARGET="$TMP_TRANSACTION_ROOT/symlink-target"
EXTERNAL_FILE="$TMP_TRANSACTION_ROOT/external-default.yaml"
mkdir -p "$SYMLINK_TARGET"
cp "$ROOT/PRIVACY.md" "$EXTERNAL_FILE"
ln -s "$EXTERNAL_FILE" "$SYMLINK_TARGET/default.yaml"
EXTERNAL_BEFORE="$(sha256_file "$EXTERNAL_FILE")"
set +e
SYMLINK_OUTPUT="$(RIME_USER_DIR="$SYMLINK_TARGET" "$ROOT/scripts/install.sh" --dry-run --no-download-gram --no-download-predict 2>&1)"
SYMLINK_STATUS=$?
set -e
test "$SYMLINK_STATUS" -ne 0
printf '%s\n' "$SYMLINK_OUTPUT" | grep 'Refusing to write through symlinks below the Rime target' >/dev/null
test -L "$SYMLINK_TARGET/default.yaml"
test "$EXTERNAL_BEFORE" = "$(sha256_file "$EXTERNAL_FILE")"

SYMLINK_PARENT_TARGET="$TMP_TRANSACTION_ROOT/symlink-parent-target"
SYMLINK_PARENT_EXTERNAL="$TMP_TRANSACTION_ROOT/symlink-parent-external"
mkdir -p "$SYMLINK_PARENT_TARGET" "$SYMLINK_PARENT_EXTERNAL"
ln -s "$SYMLINK_PARENT_EXTERNAL" "$SYMLINK_PARENT_TARGET/lua"
set +e
SYMLINK_PARENT_OUTPUT="$(RIME_USER_DIR="$SYMLINK_PARENT_TARGET" "$ROOT/scripts/install.sh" --dry-run --no-download-gram --no-download-predict 2>&1)"
SYMLINK_PARENT_STATUS=$?
set -e
test "$SYMLINK_PARENT_STATUS" -ne 0
printf '%s\n' "$SYMLINK_PARENT_OUTPUT" | grep 'Refusing to write through symlinks below the Rime target' >/dev/null
test -z "$(find "$SYMLINK_PARENT_EXTERNAL" -mindepth 1 -print -quit)"

HARDLINK_TARGET="$TMP_TRANSACTION_ROOT/hardlink-target"
HARDLINK_EXTERNAL="$TMP_TRANSACTION_ROOT/hardlink-external.yaml"
mkdir -p "$HARDLINK_TARGET"
printf 'PRIVATE-HARDLINK-SENTINEL\n' > "$HARDLINK_EXTERNAL"
ln "$HARDLINK_EXTERNAL" "$HARDLINK_TARGET/default.yaml"
HARDLINK_BEFORE="$(sha256_file "$HARDLINK_EXTERNAL")"
set +e
HARDLINK_OUTPUT="$(RIME_USER_DIR="$HARDLINK_TARGET" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict 2>&1)"
HARDLINK_STATUS=$?
set -e
test "$HARDLINK_STATUS" -ne 0
printf '%s\n' "$HARDLINK_OUTPUT" | grep 'Refusing to overwrite hard-linked files below the Rime target' >/dev/null
test "$HARDLINK_BEFORE" = "$(sha256_file "$HARDLINK_EXTERNAL")"
HARDLINK_COUNT="$(stat -c '%h' "$HARDLINK_EXTERNAL" 2>/dev/null || stat -f '%l' "$HARDLINK_EXTERNAL")"
test "$HARDLINK_COUNT" -gt 1

NETWORK_TARGET="$TMP_TRANSACTION_ROOT/network-target"
FAKE_CURL_BIN="$TMP_TRANSACTION_ROOT/fake-curl-bin"
mkdir -p "$NETWORK_TARGET" "$FAKE_CURL_BIN"
cp "$ROOT/PRIVACY.md" "$NETWORK_TARGET/rime_ice.custom.yaml"
ln -s /usr/bin/false "$FAKE_CURL_BIN/curl"
NETWORK_BEFORE="$(sha256_file "$NETWORK_TARGET/rime_ice.custom.yaml")"
set +e
NETWORK_OUTPUT="$(PATH="$FAKE_CURL_BIN:$PATH" RIME_USER_DIR="$NETWORK_TARGET" \
  "$ROOT/scripts/install.sh" --skip-verify-gram --no-download-predict 2>&1)"
NETWORK_STATUS=$?
set -e
test "$NETWORK_STATUS" -ne 0
printf '%s\n' "$NETWORK_OUTPUT" | grep 'Downloading wanxiang-lts-zh-hans.gram' >/dev/null
test "$NETWORK_BEFORE" = "$(sha256_file "$NETWORK_TARGET/rime_ice.custom.yaml")"
test -z "$(find "$TMP_TRANSACTION_ROOT" -maxdepth 1 -type d -name 'network-target.backup.*' -print -quit)"

ROLLBACK_TARGET="$TMP_TRANSACTION_ROOT/rollback-target"
FAKE_CP_BIN="$TMP_TRANSACTION_ROOT/fake-cp-bin"
mkdir -p "$ROLLBACK_TARGET" "$FAKE_CP_BIN"
cp "$ROOT/PRIVACY.md" "$ROLLBACK_TARGET/default.yaml"
cp "$ROOT/CONTRIBUTING.md" "$ROLLBACK_TARGET/rime.lua"
DEFAULT_BEFORE="$(sha256_file "$ROLLBACK_TARGET/default.yaml")"
RIME_LUA_BEFORE="$(sha256_file "$ROLLBACK_TARGET/rime.lua")"
cat > "$FAKE_CP_BIN/cp" <<'SH'
#!/bin/sh
last=""
for arg in "$@"; do
  last="$arg"
done
case "$last" in
  */rollback-target/rime.lua) exit 73 ;;
esac
exec /bin/cp "$@"
SH
chmod +x "$FAKE_CP_BIN/cp"
set +e
ROLLBACK_OUTPUT="$(PATH="$FAKE_CP_BIN:$PATH" RIME_USER_DIR="$ROLLBACK_TARGET" \
  "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict 2>&1)"
ROLLBACK_STATUS=$?
set -e
test "$ROLLBACK_STATUS" -eq 73
printf '%s\n' "$ROLLBACK_OUTPUT" | grep 'restored the previous files from' >/dev/null
test "$DEFAULT_BEFORE" = "$(sha256_file "$ROLLBACK_TARGET/default.yaml")"
test "$RIME_LUA_BEFORE" = "$(sha256_file "$ROLLBACK_TARGET/rime.lua")"
test ! -e "$ROLLBACK_TARGET/grammar.yaml"

COLLISION_TARGET="$TMP_TRANSACTION_ROOT/collision-target"
FIXED_DATE_BIN="$TMP_TRANSACTION_ROOT/fixed-date-bin"
mkdir -p "$COLLISION_TARGET" "$FIXED_DATE_BIN"
cat > "$FIXED_DATE_BIN/date" <<'SH'
#!/bin/sh
printf '20000101-000000\n'
SH
chmod +x "$FIXED_DATE_BIN/date"
RIME_USER_DIR="$COLLISION_TARGET" "$TMP_MANIFEST_SOURCE/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null
cp "$ROOT/PRIVACY.md" "$COLLISION_TARGET/rime_ice.custom.yaml"
FIRST_EXPECTED="$(sha256_file "$COLLISION_TARGET/rime_ice.custom.yaml")"
PATH="$FIXED_DATE_BIN:$PATH" RIME_USER_DIR="$COLLISION_TARGET" \
  "$TMP_MANIFEST_SOURCE/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null
cp "$ROOT/CONTRIBUTING.md" "$COLLISION_TARGET/rime_ice.custom.yaml"
SECOND_EXPECTED="$(sha256_file "$COLLISION_TARGET/rime_ice.custom.yaml")"
PATH="$FIXED_DATE_BIN:$PATH" RIME_USER_DIR="$COLLISION_TARGET" \
  "$TMP_MANIFEST_SOURCE/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null
FIRST_BACKUP="$TMP_TRANSACTION_ROOT/collision-target.backup.20000101-000000/rime_ice.custom.yaml"
SECOND_BACKUP="$TMP_TRANSACTION_ROOT/collision-target.backup.20000101-000000.1/rime_ice.custom.yaml"
test "$FIRST_EXPECTED" = "$(sha256_file "$FIRST_BACKUP")"
test "$SECOND_EXPECTED" = "$(sha256_file "$SECOND_BACKUP")"

if [ "$(uname -s)" = Linux ]; then
  LINUX_HOME="$TMP_TRANSACTION_ROOT/linux-home"
  mkdir -p "$LINUX_HOME"
  set +e
  LINUX_OUTPUT="$(env -u RIME_USER_DIR HOME="$LINUX_HOME" \
    "$ROOT/scripts/install.sh" --dry-run --no-download-gram --no-download-predict 2>&1)"
  LINUX_STATUS=$?
  set -e
  test "$LINUX_STATUS" -eq 2
  printf '%s\n' "$LINUX_OUTPUT" | grep 'Linux requires an explicit RIME_USER_DIR' >/dev/null
  test ! -e "$LINUX_HOME/Library/Rime"
fi

if [ "${SKIP_NETWORK_CHECK:-0}" != "1" ]; then
  printf 'Checking GitHub Release digest parser...\n'
  GRAM_DIGEST="$(
    github_api_get https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS |
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
INSTALL_OUTPUT="$(RIME_USER_DIR="$TMP_RIME_DIR" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict)"
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

printf 'Checking real librime input boundary...\n'
if ! command -v c++ >/dev/null 2>&1 || ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists rime; then
  printf 'c++, pkg-config, and the librime development package are required for the input smoke gate.\n' >&2
  exit 1
fi
c++ -std=c++17 "$ROOT/tests/rime_smoke.cpp" \
  $(pkg-config --cflags --libs rime) \
  -o "$TMP_RIME_DIR/rime-smoke"
if ! "$TMP_RIME_DIR/rime-smoke" "$TMP_RIME_DIR" "$TMP_RIME_DIR" nihao 你好 \
  2>"$TMP_RIME_DIR/rime-smoke.log"; then
  cat "$TMP_RIME_DIR/rime-smoke.log" >&2
  exit 1
fi

printf 'Checking precise uninstall ownership boundary...\n'
TMP_UNINSTALL_DIR="$(mktemp -d)"
RIME_USER_DIR="$TMP_UNINSTALL_DIR" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null
printf '# private CI edit\n' >> "$TMP_UNINSTALL_DIR/custom_phrase.txt"
UNINSTALL_DRY_RUN="$(RIME_USER_DIR="$TMP_UNINSTALL_DIR" "$ROOT/scripts/uninstall.sh" --dry-run)"
printf '%s\n' "$UNINSTALL_DRY_RUN" | grep 'custom_phrase.txt (edited; digest differs)' >/dev/null
printf '%s\n' "$UNINSTALL_DRY_RUN" | grep 'rime_ice.schema.yaml' >/dev/null
RIME_USER_DIR="$TMP_UNINSTALL_DIR" "$ROOT/scripts/uninstall.sh" --apply >/dev/null
test -f "$TMP_UNINSTALL_DIR/custom_phrase.txt"
test ! -f "$TMP_UNINSTALL_DIR/rime_ice.schema.yaml"
test -f "$TMP_UNINSTALL_DIR/.rime-smart-simplified.install-manifest"

printf 'Checking ownership manifest tamper boundary...\n'
TMP_TAMPER_DIR="$(mktemp -d)"
RIME_USER_DIR="$TMP_TAMPER_DIR" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null
printf 'PRIVATE-TAMPER-SENTINEL\n' > "$TMP_TAMPER_DIR/private_user_file.txt"
TAMPER_SHA="$(sha256_file "$TMP_TAMPER_DIR/private_user_file.txt")"
printf 'file\tprivate_user_file.txt\t%s\t%s\tmanaged\n' "$TAMPER_SHA" "$TAMPER_SHA" >> \
  "$TMP_TAMPER_DIR/.rime-smart-simplified.install-manifest"
set +e
TAMPER_OUTPUT="$(RIME_USER_DIR="$TMP_TAMPER_DIR" "$ROOT/scripts/uninstall.sh" --apply 2>&1)"
TAMPER_STATUS=$?
set -e
test "$TAMPER_STATUS" -ne 0
printf '%s\n' "$TAMPER_OUTPUT" | grep 'source hash mismatch\|not installable by this package' >/dev/null
test -f "$TMP_TAMPER_DIR/private_user_file.txt"

printf 'Checking forged digest protection for allowed paths...\n'
TMP_FORGE_DIR="$(mktemp -d)"
RIME_USER_DIR="$TMP_FORGE_DIR" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null
printf 'PRIVATE-FORGED-SENTINEL\n' > "$TMP_FORGE_DIR/custom_phrase.txt"
FORGED_SHA="$(sha256_file "$TMP_FORGE_DIR/custom_phrase.txt")"
awk -F '\t' -v forged="$FORGED_SHA" 'BEGIN { OFS = "\t" } $1 == "file" && $2 == "custom_phrase.txt" { $3 = forged; $4 = forged } { print }' \
  "$TMP_FORGE_DIR/.rime-smart-simplified.install-manifest" > "$TMP_FORGE_DIR/manifest.forged"
awk -F '\t' '$1 == "file" { printf "%s\t%s\t%s\n", $2, $4, $5 }' \
  "$TMP_FORGE_DIR/manifest.forged" > "$TMP_FORGE_DIR/manifest-records"
FORGED_SOURCE_HASH="$(sha256_file "$TMP_FORGE_DIR/manifest-records")"
awk -v replacement="$FORGED_SOURCE_HASH" '/^# source_hash=sha256:/ { $0 = "# source_hash=sha256:" replacement } { print }' \
  "$TMP_FORGE_DIR/manifest.forged" > "$TMP_FORGE_DIR/.rime-smart-simplified.install-manifest"
set +e
FORGE_OUTPUT="$(RIME_USER_DIR="$TMP_FORGE_DIR" "$ROOT/scripts/uninstall.sh" --apply 2>&1)"
FORGE_STATUS=$?
set -e
test "$FORGE_STATUS" -ne 0
printf '%s\n' "$FORGE_OUTPUT" | grep 'source digest does not match the package lock' >/dev/null
test -f "$TMP_FORGE_DIR/custom_phrase.txt"

printf 'Checking manifest metadata injection boundary...\n'
TMP_INJECTION_DIR="$(mktemp -d)"
set +e
RIME_USER_DIR="$TMP_INJECTION_DIR" \
  RIME_PACKAGE_VERSION=$'safe\nfile\tprivate_user_file.txt' \
  "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict >/dev/null 2>&1
INJECTION_STATUS=$?
set -e
test "$INJECTION_STATUS" -ne 0
test ! -e "$TMP_INJECTION_DIR/.rime-smart-simplified.install-manifest"

printf 'Verification passed.\n'
