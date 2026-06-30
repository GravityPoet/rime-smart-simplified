#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${RIME_USER_DIR:-$HOME/Library/Rime}"
DRY_RUN=0
BACKUP=1
DOWNLOAD_GRAM=1
VERIFY_GRAM=1
GRAM_FILE="wanxiang-lts-zh-hans.gram"
GRAM_URL="https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
GRAM_API_URL="https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS"

usage() {
  printf 'Usage: %s [--dry-run] [--no-backup] [--no-download-gram] [--skip-verify-gram]\n' "$0"
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

if [ ! -f "$ROOT/rime_ice.schema.yaml" ] || [ ! -f "$ROOT/rime.lua" ]; then
  printf 'Install source is incomplete: %s\n' "$ROOT" >&2
  exit 1
fi

cd "$ROOT"
MANIFEST="$(mktemp)"
trap 'rm -f "$MANIFEST"' EXIT

{
  find . -maxdepth 1 -type f \
    \( \
      \( -name '*.yaml' ! -name 'user.yaml' ! -name 'installation.yaml' \) \
      -o -name 'rime.lua' \
      -o -name 'custom_phrase.txt' \
    \)
  find ./cn_dicts ./cn_dicts_wanxiang ./en_dicts -type f \
    \( -name '*.dict.yaml' -o -name '*.txt' \)
  find ./lua -type f -name '*.lua'
  find ./opencc -type f \( -name '*.json' -o -name '*.txt' \)
} \
  | sed 's#^\./##' \
  | sort > "$MANIFEST"

printf 'Target: %s\n' "$TARGET"
printf 'Backup decision: overwrite-capable local config install; backup is enabled by default.\n'
printf 'Files to install: %s\n' "$(wc -l < "$MANIFEST" | tr -d ' ')"
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

if [ "$DRY_RUN" -eq 1 ]; then
  sed -n '1,200p' "$MANIFEST"
  exit 0
fi

mkdir -p "$TARGET"

if [ "$BACKUP" -eq 1 ]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="${TARGET}.backup.${TS}"
  BACKED_UP=0
  while IFS= read -r rel; do
    if [ -e "$TARGET/$rel" ]; then
      if [ "$BACKED_UP" -eq 0 ]; then
        mkdir -p "$BACKUP_DIR"
        BACKED_UP=1
      fi
      mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      cp -a "$TARGET/$rel" "$BACKUP_DIR/$rel"
    fi
  done < "$MANIFEST"
  if [ "$BACKED_UP" -eq 1 ]; then
    printf 'Backup: %s\n' "$BACKUP_DIR"
  else
    printf 'Backup: none needed\n'
  fi
else
  printf 'Backup: skipped by --no-backup\n'
fi

while IFS= read -r rel; do
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp -a "$ROOT/$rel" "$TARGET/$rel"
done < "$MANIFEST"

if [ -f "$ROOT/$GRAM_FILE" ]; then
  cp -a "$ROOT/$GRAM_FILE" "$TARGET/$GRAM_FILE"
elif [ ! -f "$TARGET/$GRAM_FILE" ] && [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  tmp_file="$TARGET/$GRAM_FILE.tmp"
  rm -f "$tmp_file"
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
  curl -L --fail --output "$tmp_file" "$GRAM_URL"
  if [ "$VERIFY_GRAM" -eq 1 ]; then
    verify_gram_digest "$tmp_file" "$expected_digest"
  fi
  mv "$tmp_file" "$TARGET/$GRAM_FILE"
fi

test -f "$TARGET/rime_ice.schema.yaml"
test -f "$TARGET/rime_ice.dict.yaml"
test -f "$TARGET/rime.lua"
if [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  test -f "$TARGET/$GRAM_FILE"
fi

printf 'Installed. Redeploy Rime/Squirrel/Weasel from the input-method menu.\n'
