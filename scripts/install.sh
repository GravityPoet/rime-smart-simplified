#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET=""
DRY_RUN=0
BACKUP=1
DOWNLOAD_GRAM=1
VERIFY_GRAM=1
DOWNLOAD_PREDICT=1
GRAM_FILE="wanxiang-lts-zh-hans.gram"
GRAM_URL="https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
GRAM_API_URL="https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS"
# librime-predict 官方数据（繁体，方案内 prediction_simplify 已固定转为简体）。
# 该 Release 较旧，GitHub API 不提供 digest，这里固定校验已知 SHA-256。
PREDICT_FILE="predict.db"
PREDICT_URL="https://github.com/rime/librime-predict/releases/download/data-1.0/predict.db"
PREDICT_SHA256="2a5a2b7c77f8f3d7c0836dfc8fd8b791ac2574d8bd93a3a2baaae1ee4861f5be"
INSTALL_MANIFEST_NAME=".rime-smart-simplified.install-manifest"
WORK_DIR=""
MANIFEST=""
INSTALL_PATHS=""
NEW_FILES=""
EXISTING_FILES=""
BACKUP_DIR=""
WRITE_STARTED=0
TARGET_EXISTED=0

cleanup() {
  if [ -n "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

rollback_on_error() {
  status=$?
  trap - ERR
  set +e

  if [ "$TARGET_EXISTED" -eq 0 ] && [ -e "$TARGET" ]; then
    rm -rf "$TARGET"
    printf 'Installation failed; removed the incomplete new target: %s\n' "$TARGET" >&2
  elif [ "$WRITE_STARTED" -eq 1 ]; then
    if [ "$TARGET_EXISTED" -eq 0 ]; then
      rm -rf "$TARGET"
      printf 'Installation failed; removed the incomplete new target: %s\n' "$TARGET" >&2
    else
      while IFS= read -r rel; do
        [ -n "$rel" ] && rm -f "$TARGET/$rel"
      done < "$NEW_FILES"

      if [ "$BACKUP" -eq 1 ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        while IFS= read -r rel; do
          [ -n "$rel" ] || continue
          if [ -e "$BACKUP_DIR/$rel" ]; then
            mkdir -p "$TARGET/$(dirname "$rel")"
            cp -a "$BACKUP_DIR/$rel" "$TARGET/$rel"
          fi
        done < "$EXISTING_FILES"
        printf 'Installation failed; restored the previous files from: %s\n' "$BACKUP_DIR" >&2
      elif [ -s "$EXISTING_FILES" ]; then
        printf 'Installation failed after --no-backup; overwritten files could not be restored automatically.\n' >&2
      else
        printf 'Installation failed; removed files created by this attempt.\n' >&2
      fi
    fi
  else
    printf 'Installation failed before existing Rime files were changed.\n' >&2
  fi

  exit "$status"
}

resolve_target() {
  if [ -n "${RIME_USER_DIR:-}" ]; then
    TARGET="$RIME_USER_DIR"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      TARGET="$HOME/Library/Rime"
      ;;
    Linux)
      printf '%s\n' \
        'Linux requires an explicit RIME_USER_DIR because Fcitx5 and IBus use different directories.' \
        'Fcitx5: RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh' \
        'IBus:   RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh' >&2
      exit 2
      ;;
    *)
      printf 'Unsupported platform. Set RIME_USER_DIR explicitly: %s\n' "$(uname -s)" >&2
      exit 2
      ;;
  esac
}

next_backup_dir() {
  base="${TARGET}.backup.$(date +%Y%m%d-%H%M%S)"
  candidate="$base"
  suffix=1
  while [ -e "$candidate" ]; do
    candidate="${base}.${suffix}"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

find_symlink_component() {
  rel="$1"
  current="$TARGET"
  remaining="$rel"
  while [ -n "$remaining" ]; do
    case "$remaining" in
      */*) component="${remaining%%/*}"; remaining="${remaining#*/}" ;;
      *) component="$remaining"; remaining="" ;;
    esac
    current="$current/$component"
    if [ -L "$current" ]; then
      printf '%s\n' "$current"
      return 0
    fi
  done
  return 1
}

trap cleanup EXIT

usage() {
  printf 'Usage: %s [--dry-run] [--no-backup] [--no-download-gram] [--skip-verify-gram] [--no-download-predict]\n' "$0"
}

fetch_gram_digest() {
  curl -fsSL "$GRAM_API_URL" | awk -v name="$GRAM_FILE" '
    index($0, "\"name\": \"" name "\"") { found = 1 }
    found && index($0, "\"digest\":") {
      sub(/^.*"digest": "/, "", $0)
      sub(/".*$/, "", $0)
      print
      exit
    }
  '
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'Neither shasum nor sha256sum is available; cannot verify %s\n' "$1" >&2
    exit 1
  fi
}

verify_gram_digest() {
  file="$1"
  digest="$2"
  case "$digest" in
    sha256:*)
      expected="${digest#sha256:}"
      ;;
    *)
      printf 'Unsupported or missing GitHub asset digest for %s: %s\n' "$GRAM_FILE" "$digest" >&2
      exit 1
      ;;
  esac
  actual="$(sha256_file "$file")"
  if [ "$actual" != "$expected" ]; then
    printf 'SHA-256 mismatch for %s\n' "$GRAM_FILE" >&2
    printf 'Expected: %s\n' "$expected" >&2
    printf 'Actual:   %s\n' "$actual" >&2
    exit 1
  fi
  printf 'Verified %s SHA-256: %s\n' "$GRAM_FILE" "$actual"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-backup)
      BACKUP=0
      ;;
    --no-download-gram)
      DOWNLOAD_GRAM=0
      ;;
    --skip-verify-gram)
      VERIFY_GRAM=0
      ;;
    --no-download-predict)
      DOWNLOAD_PREDICT=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

resolve_target

if [ ! -f "$ROOT/rime_ice.schema.yaml" ] || [ ! -f "$ROOT/rime.lua" ]; then
  printf 'Install source is incomplete: %s\n' "$ROOT" >&2
  exit 1
fi

cd "$ROOT"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-smart-simplified.XXXXXX")"
MANIFEST="$WORK_DIR/manifest"
INSTALL_PATHS="$WORK_DIR/install-paths"
OWNED_FILES="$WORK_DIR/owned-files"
NEW_FILES="$WORK_DIR/new-files"
EXISTING_FILES="$WORK_DIR/existing-files"

{
  find . -maxdepth 1 -type f \
    \( \
      \( -name '*.yaml' ! -name 'user.yaml' ! -name 'installation.yaml' \) \
      -o -name 'rime.lua' \
    \)
  if [ ! -e "$TARGET/custom_phrase.txt" ]; then
    printf '%s\n' './custom_phrase.txt'
  fi
  if [ ! -e "$TARGET/smart_chat_phrases.txt" ]; then
    printf '%s\n' './smart_chat_phrases.txt'
  fi
  find ./cn_dicts ./cn_dicts_wanxiang ./en_dicts -type f \
    \( -name '*.dict.yaml' -o -name '*.txt' \)
  find ./lua -type f -name '*.lua' \
    ! -path './lua/cold_word_drop/drop_words.lua' \
    ! -path './lua/cold_word_drop/hide_words.lua' \
    ! -path './lua/cold_word_drop/reduce_freq_words.lua'
  for rel in \
    lua/cold_word_drop/drop_words.lua \
    lua/cold_word_drop/hide_words.lua \
    lua/cold_word_drop/reduce_freq_words.lua
  do
    if [ ! -e "$TARGET/$rel" ]; then
      printf './%s\n' "$rel"
    fi
  done
  find ./opencc -type f \( -name '*.json' -o -name '*.txt' \)
} \
  | sed 's#^\./##' \
  | sort > "$MANIFEST"

cp "$MANIFEST" "$INSTALL_PATHS"
if [ -f "$ROOT/$GRAM_FILE" ] \
  || { [ ! -f "$TARGET/$GRAM_FILE" ] && [ "$DOWNLOAD_GRAM" -eq 1 ]; }
then
  printf '%s\n' "$GRAM_FILE" >> "$INSTALL_PATHS"
fi
if [ -f "$ROOT/$PREDICT_FILE" ] \
  || { [ ! -f "$TARGET/$PREDICT_FILE" ] && [ "$DOWNLOAD_PREDICT" -eq 1 ]; }
then
  printf '%s\n' "$PREDICT_FILE" >> "$INSTALL_PATHS"
fi
sort -u "$INSTALL_PATHS" > "$WORK_DIR/install-paths.sorted"
mv "$WORK_DIR/install-paths.sorted" "$INSTALL_PATHS"

TARGET_SYMLINKS="$WORK_DIR/target-symlinks"
while IFS= read -r rel; do
  if symlink_path="$(find_symlink_component "$rel")"; then
    printf '%s -> %s\n' "$rel" "$symlink_path" >> "$TARGET_SYMLINKS"
  fi
done < "$INSTALL_PATHS"
if [ -s "$TARGET_SYMLINKS" ]; then
  printf 'Refusing to write through symlinks below the Rime target. Merge or replace these links first:\n' >&2
  sed 's/^/  /' "$TARGET_SYMLINKS" >&2
  exit 1
fi

MARKER_PATH="$TARGET/$INSTALL_MANIFEST_NAME"
if [ -L "$MARKER_PATH" ]; then
  printf 'Refusing to overwrite a symlinked install manifest: %s\n' "$MARKER_PATH" >&2
  exit 1
fi
if [ -e "$MARKER_PATH" ] && [ ! -f "$MARKER_PATH" ]; then
  printf 'Refusing to overwrite a non-regular install manifest: %s\n' "$MARKER_PATH" >&2
  exit 1
fi

printf 'Target: %s\n' "$TARGET"
printf 'Backup decision: overwrite-capable local config install; backup is enabled by default.\n'
printf 'Files to install: %s\n' "$(wc -l < "$MANIFEST" | tr -d ' ')"
if [ -e "$TARGET/custom_phrase.txt" ]; then
  printf 'Private phrases: preserving existing custom_phrase.txt\n'
else
  printf 'Private phrases: installing the public custom_phrase.txt template\n'
fi
if [ -e "$TARGET/lua/cold_word_drop/drop_words.lua" ] \
  || [ -e "$TARGET/lua/cold_word_drop/hide_words.lua" ] \
  || [ -e "$TARGET/lua/cold_word_drop/reduce_freq_words.lua" ]
then
  printf 'Cold-word preferences: preserving existing hide/drop/reduce records\n'
else
  printf 'Cold-word preferences: installing empty templates\n'
fi
if [ -f "$ROOT/$GRAM_FILE" ]; then
  printf 'Grammar model: will copy local %s\n' "$GRAM_FILE"
elif [ -f "$TARGET/$GRAM_FILE" ]; then
  printf 'Grammar model: already exists at target\n'
elif [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  if [ "$VERIFY_GRAM" -eq 1 ]; then
    printf 'Grammar model: will download official RIME-LMDG LTS asset and verify GitHub Release SHA-256 digest\n'
  else
    printf 'Grammar model: will download official RIME-LMDG LTS asset without digest verification\n'
  fi
else
  printf 'Grammar model: skipped by --no-download-gram\n'
fi
if [ -f "$ROOT/$PREDICT_FILE" ]; then
  printf 'Predict data: will copy local %s\n' "$PREDICT_FILE"
elif [ -f "$TARGET/$PREDICT_FILE" ]; then
  printf 'Predict data: already exists at target\n'
elif [ "$DOWNLOAD_PREDICT" -eq 1 ]; then
  printf 'Predict data: will download official librime-predict asset and verify pinned SHA-256\n'
else
  printf 'Predict data: skipped by --no-download-predict\n'
fi

if [ "$DRY_RUN" -eq 1 ]; then
  sed -n '1,200p' "$MANIFEST"
  exit 0
fi

GRAM_SOURCE=""
if [ -f "$ROOT/$GRAM_FILE" ]; then
  GRAM_SOURCE="$ROOT/$GRAM_FILE"
elif [ ! -f "$TARGET/$GRAM_FILE" ] && [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  GRAM_SOURCE="$WORK_DIR/$GRAM_FILE"
  printf 'Downloading %s ...\n' "$GRAM_FILE"
  expected_digest=""
  if [ "$VERIFY_GRAM" -eq 1 ]; then
    expected_digest="$(fetch_gram_digest)"
    if [ -z "$expected_digest" ]; then
      printf 'Could not read GitHub Release SHA-256 digest for %s\n' "$GRAM_FILE" >&2
      printf 'Re-run with --skip-verify-gram only if you accept an unverified download.\n' >&2
      exit 1
    fi
  fi
  curl -L --fail --output "$GRAM_SOURCE" "$GRAM_URL"
  if [ "$VERIFY_GRAM" -eq 1 ]; then
    verify_gram_digest "$GRAM_SOURCE" "$expected_digest"
  fi
fi

PREDICT_SOURCE=""
if [ -f "$ROOT/$PREDICT_FILE" ]; then
  PREDICT_SOURCE="$ROOT/$PREDICT_FILE"
elif [ ! -f "$TARGET/$PREDICT_FILE" ] && [ "$DOWNLOAD_PREDICT" -eq 1 ]; then
  PREDICT_SOURCE="$WORK_DIR/$PREDICT_FILE"
  printf 'Downloading %s ...\n' "$PREDICT_FILE"
  if ! curl -L --fail --output "$PREDICT_SOURCE" "$PREDICT_URL"; then
    exit 1
  fi
  actual_predict_sha="$(sha256_file "$PREDICT_SOURCE")"
  if [ "$actual_predict_sha" != "$PREDICT_SHA256" ]; then
    printf 'SHA-256 mismatch for %s\n' "$PREDICT_FILE" >&2
    printf 'Expected: %s\n' "$PREDICT_SHA256" >&2
    printf 'Actual:   %s\n' "$actual_predict_sha" >&2
    exit 1
  fi
  printf 'Verified %s SHA-256: %s\n' "$PREDICT_FILE" "$actual_predict_sha"
fi

: > "$NEW_FILES"
: > "$EXISTING_FILES"
if [ -e "$TARGET" ]; then
  TARGET_EXISTED=1
fi
while IFS= read -r rel; do
  if [ -e "$TARGET/$rel" ]; then
    printf '%s\n' "$rel" >> "$EXISTING_FILES"
  else
    printf '%s\n' "$rel" >> "$NEW_FILES"
  fi
done < "$INSTALL_PATHS"
if [ -e "$MARKER_PATH" ]; then
  printf '%s\n' "$INSTALL_MANIFEST_NAME" >> "$EXISTING_FILES"
else
  printf '%s\n' "$INSTALL_MANIFEST_NAME" >> "$NEW_FILES"
fi

trap rollback_on_error ERR
mkdir -p "$TARGET"

if [ "$BACKUP" -eq 1 ]; then
  BACKUP_DIR="$(next_backup_dir)"
  BACKED_UP=0
  while IFS= read -r rel; do
    if [ "$BACKED_UP" -eq 0 ]; then
      mkdir -p "$BACKUP_DIR"
      BACKED_UP=1
    fi
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$TARGET/$rel" "$BACKUP_DIR/$rel"
  done < "$EXISTING_FILES"
  if [ "$BACKED_UP" -eq 1 ]; then
    printf 'Backup: %s\n' "$BACKUP_DIR"
  else
    printf 'Backup: none needed\n'
  fi
else
  printf 'Backup: skipped by --no-backup\n'
fi

WRITE_STARTED=1
while IFS= read -r rel; do
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp -a "$ROOT/$rel" "$TARGET/$rel"
done < "$MANIFEST"

if [ -n "$GRAM_SOURCE" ]; then
  cp -a "$GRAM_SOURCE" "$TARGET/$GRAM_FILE"
fi

if [ -n "$PREDICT_SOURCE" ]; then
  cp -a "$PREDICT_SOURCE" "$TARGET/$PREDICT_FILE"
fi

test -f "$TARGET/rime_ice.schema.yaml"
test -f "$TARGET/rime_ice.dict.yaml"
test -f "$TARGET/rime.lua"
test -f "$TARGET/custom_phrase.txt"
test -f "$TARGET/smart_chat_phrases.txt"
test -f "$TARGET/lua/cold_word_drop/drop_words.lua"
test -f "$TARGET/lua/cold_word_drop/hide_words.lua"
test -f "$TARGET/lua/cold_word_drop/reduce_freq_words.lua"
if [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  test -f "$TARGET/$GRAM_FILE"
fi
if [ "$DOWNLOAD_PREDICT" -eq 1 ]; then
  test -f "$TARGET/$PREDICT_FILE"
fi

# Keep an ownership manifest beside the installed configuration. It records
# only files this invocation actually wrote; uninstall removes a file only
# while its content still matches this recorded digest. User edits therefore
# remain a hard preservation boundary.
MARKER_TEMP="$WORK_DIR/$INSTALL_MANIFEST_NAME"
: > "$WORK_DIR/source-records"
PACKAGE_VERSION="${RIME_PACKAGE_VERSION:-unknown}"
SOURCE_REVISION="unknown"
if command -v git >/dev/null 2>&1; then
  PACKAGE_VERSION="${RIME_PACKAGE_VERSION:-$(git describe --tags --always 2>/dev/null || printf 'unknown')}"
  SOURCE_REVISION="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
fi
{
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    ownership="managed"
    source_path="$ROOT/$rel"
    if [ "$rel" = "$GRAM_FILE" ] || [ "$rel" = "$PREDICT_FILE" ]; then
      if ! grep -Fx "$rel" "$NEW_FILES" >/dev/null 2>&1; then
        continue
      fi
      ownership="asset-created"
      if [ "$rel" = "$GRAM_FILE" ]; then
        source_path="$GRAM_SOURCE"
      else
        source_path="$PREDICT_SOURCE"
      fi
    fi
    if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
      printf 'Cannot record ownership source for %s\n' "$rel" >&2
      exit 1
    fi
    source_sha="$(sha256_file "$source_path")"
    installed_sha="$(sha256_file "$TARGET/$rel")"
    printf '%s\t%s\t%s\n' "$rel" "$source_sha" "$ownership" >> "$WORK_DIR/source-records"
    printf 'file\t%s\t%s\t%s\t%s\n' "$rel" "$installed_sha" "$source_sha" "$ownership"
  done < "$INSTALL_PATHS"
} > "$MARKER_TEMP.entries"
SOURCE_HASH="$(sha256_file "$WORK_DIR/source-records")"
{
  printf '# rime-smart-simplified install manifest v2\n'
  printf '# Generated by scripts/install.sh; do not edit.\n'
  printf '# package_version=%s\n' "$PACKAGE_VERSION"
  printf '# source_revision=%s\n' "$SOURCE_REVISION"
  printf '# source_hash=sha256:%s\n' "$SOURCE_HASH"
  cat "$MARKER_TEMP.entries"
} > "$MARKER_TEMP"
cp -a "$MARKER_TEMP" "$MARKER_PATH"

WRITE_STARTED=0
trap - ERR
printf 'Installed. Redeploy Rime/Squirrel/Weasel from the input-method menu.\n'
