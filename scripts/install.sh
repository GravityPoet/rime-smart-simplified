#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${RIME_USER_DIR:-$HOME/Library/Rime}"
DRY_RUN=0
BACKUP=1
DOWNLOAD_GRAM=1
GRAM_FILE="wanxiang-lts-zh-hans.gram"
GRAM_URL="https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"

usage() {
  printf 'Usage: %s [--dry-run] [--no-backup] [--no-download-gram]\n' "$0"
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

find . -type f \
  ! -path './.git/*' \
  ! -path './scripts/*' \
  ! -path './third_party/*' \
  ! -name '.gitignore' \
  ! -name '.gitattributes' \
  ! -name 'README.md' \
  ! -name 'INSTALL.md' \
  ! -name 'PRIVACY.md' \
  ! -name 'THIRD_PARTY.md' \
  ! -name 'RELEASE_CHECKLIST.md' \
  ! -name 'LICENSE' \
  ! -name "$GRAM_FILE" \
  | sed 's#^\./##' | sort > "$MANIFEST"

printf 'Target: %s\n' "$TARGET"
printf 'Backup decision: overwrite-capable local config install; backup is enabled by default.\n'
printf 'Files to install: %s\n' "$(wc -l < "$MANIFEST" | tr -d ' ')"
if [ -f "$ROOT/$GRAM_FILE" ]; then
  printf 'Grammar model: will copy local %s\n' "$GRAM_FILE"
elif [ -f "$TARGET/$GRAM_FILE" ]; then
  printf 'Grammar model: already exists at target\n'
elif [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  printf 'Grammar model: will download official RIME-LMDG LTS asset\n'
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
  mkdir -p "$BACKUP_DIR"
  while IFS= read -r rel; do
    if [ -e "$TARGET/$rel" ]; then
      mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      cp -a "$TARGET/$rel" "$BACKUP_DIR/$rel"
    fi
  done < "$MANIFEST"
  printf 'Backup: %s\n' "$BACKUP_DIR"
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
  curl -L --fail --output "$tmp_file" "$GRAM_URL"
  mv "$tmp_file" "$TARGET/$GRAM_FILE"
fi

test -f "$TARGET/rime_ice.schema.yaml"
test -f "$TARGET/rime_ice.dict.yaml"
test -f "$TARGET/rime.lua"
if [ "$DOWNLOAD_GRAM" -eq 1 ]; then
  test -f "$TARGET/$GRAM_FILE"
fi

printf 'Installed. Redeploy Rime/Squirrel/Weasel from the input-method menu.\n'
