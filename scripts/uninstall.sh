#!/bin/bash
set -euo pipefail

# Precise removal for files owned by this package. Dry-run is the default;
# --apply is required for deletion. Edited/private files are preserved.
TARGET=""
APPLY=0
BACKUP=1
MANIFEST_NAME=".rime-smart-simplified.install-manifest"
WORK_DIR=""
CANDIDATES=""
CANDIDATE_DIGESTS=""
PRESERVED=""
MISSING=""
DELETED_FILES=""
BACKUP_DIR=""

cleanup() {
  [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"
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

resolve_target() {
  if [ -n "${RIME_USER_DIR:-}" ]; then
    TARGET="$RIME_USER_DIR"
    return
  fi
  case "$(uname -s)" in
    Darwin) TARGET="$HOME/Library/Rime" ;;
    Linux)
      printf '%s\n' \
        'Linux requires an explicit RIME_USER_DIR because Fcitx5 and IBus use different directories.' \
        'Fcitx5: RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/uninstall.sh --dry-run' \
        'IBus:   RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/uninstall.sh --dry-run' >&2
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

valid_relative_path() {
  rel="$1"
  tab="$(printf '\t')"
  case "$rel" in
    ""|/*|*"$tab"*) return 1 ;;
  esac
  case "/$rel/" in
    */./*|*/../*) return 1 ;;
  esac
  return 0
}

print_plan() {
  printf 'Target: %s\n' "$TARGET"
  printf 'Ownership manifest: %s\n' "$TARGET/$MANIFEST_NAME"
  printf '%s\n' 'Deletion candidates (content unchanged since install):'
  if [ -s "$CANDIDATES" ]; then sed 's/^/  REMOVE /' "$CANDIDATES"; else printf '  (none)\n'; fi
  if [ -s "$PRESERVED" ]; then
    printf '%s\n' 'Preserved files (edited, private, or non-removable):'
    sed 's/^/  KEEP    /' "$PRESERVED"
  fi
  if [ -s "$MISSING" ]; then
    printf '%s\n' 'Already absent:'
    sed 's/^/  ABSENT  /' "$MISSING"
  fi
}

rollback_on_error() {
  status=$?
  trap - ERR
  set +e
  if [ "$BACKUP" -eq 1 ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      if [ -f "$BACKUP_DIR/$rel" ]; then
        mkdir -p "$TARGET/$(dirname "$rel")"
        cp -a "$BACKUP_DIR/$rel" "$TARGET/$rel"
      fi
    done < "$DELETED_FILES"
    printf 'Uninstall failed; restored deleted files from: %s\n' "$BACKUP_DIR" >&2
  elif [ -s "$DELETED_FILES" ]; then
    printf 'Uninstall failed after --no-backup; deleted files could not be restored automatically.\n' >&2
  else
    printf 'Uninstall failed before any files were removed.\n' >&2
  fi
  exit "$status"
}

usage() {
  printf 'Usage: %s [--dry-run] [--apply] [--no-backup]\n' "$0"
  printf '%s\n' 'Default mode is a dry-run. --apply is required to remove files.'
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) APPLY=0 ;;
    --apply|--yes) APPLY=1 ;;
    --no-backup) BACKUP=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

resolve_target
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-smart-simplified-uninstall.XXXXXX")"
CANDIDATES="$WORK_DIR/candidates"
CANDIDATE_DIGESTS="$WORK_DIR/candidate-digests"
PRESERVED="$WORK_DIR/preserved"
MISSING="$WORK_DIR/missing"
DELETED_FILES="$WORK_DIR/deleted"
: > "$CANDIDATES"
: > "$CANDIDATE_DIGESTS"
: > "$PRESERVED"
: > "$MISSING"
: > "$DELETED_FILES"

MARKER_PATH="$TARGET/$MANIFEST_NAME"
if [ -L "$MARKER_PATH" ]; then
  printf 'Refusing to read a symlinked install manifest: %s\n' "$MARKER_PATH" >&2
  exit 1
fi
if [ ! -f "$MARKER_PATH" ]; then
  printf 'No ownership manifest found at %s.\n' "$MARKER_PATH" >&2
  printf '%s\n' 'Run the current installer once (it preserves private files) before using precise uninstall.' >&2
  exit 2
fi

first_line="$(sed -n '1p' "$MARKER_PATH")"
if [ "$first_line" != '# rime-smart-simplified install manifest v2' ]; then
  printf 'Unsupported or legacy ownership manifest; refusing deletion: %s\n' "$MARKER_PATH" >&2
  exit 1
fi

while IFS="$(printf '\t')" read -r kind rel installed_sha source_sha ownership extra; do
  case "$kind" in
    ""|\#*) continue ;;
    file)
      if [ -n "$extra" ] || ! valid_relative_path "$rel"; then
        printf 'Invalid ownership manifest entry; refusing to continue: %s\n' "$rel" >&2
        exit 1
      fi
      if ! printf '%s\n' "$installed_sha" | grep -E '^[0-9A-Fa-f]{64}$' >/dev/null 2>&1 || \
        ! printf '%s\n' "$source_sha" | grep -E '^[0-9A-Fa-f]{64}$' >/dev/null 2>&1; then
        printf 'Invalid digest for ownership manifest entry: %s\n' "$rel" >&2
        exit 1
      fi
      case "$ownership" in
        managed|asset-created) ;;
        *) printf 'Unsupported ownership class for %s: %s\n' "$rel" "$ownership" >&2; exit 1 ;;
      esac
      if symlink_path="$(find_symlink_component "$rel")"; then
        printf 'Refusing to inspect through a symlink below the Rime target: %s\n' "$symlink_path" >&2
        exit 1
      fi
      path="$TARGET/$rel"
      if [ -e "$path" ]; then
        if [ ! -f "$path" ]; then
          printf 'Refusing to remove a non-regular owned path: %s\n' "$path" >&2
          exit 1
        fi
        actual="$(sha256_file "$path")"
        if [ "$actual" = "$installed_sha" ]; then
          printf '%s\n' "$rel" >> "$CANDIDATES"
          printf '%s\t%s\n' "$rel" "$installed_sha" >> "$CANDIDATE_DIGESTS"
        else
          printf '%s (edited; digest differs)\n' "$rel" >> "$PRESERVED"
        fi
      else
        printf '%s\n' "$rel" >> "$MISSING"
      fi
      ;;
    *) printf 'Unknown ownership manifest record: %s\n' "$kind" >&2; exit 1 ;;
  esac
done < "$MARKER_PATH"

# The marker itself is tool-owned metadata, but keep it when any owned file
# was edited so a later run can still identify and remove the remaining files.
if [ -s "$PRESERVED" ]; then
  printf '%s (retained because edited files remain)\n' "$MANIFEST_NAME" >> "$PRESERVED"
else
  printf '%s\n' "$MANIFEST_NAME" >> "$CANDIDATES"
  printf '%s\t%s\n' "$MANIFEST_NAME" "$(sha256_file "$MARKER_PATH")" >> "$CANDIDATE_DIGESTS"
fi
print_plan
if [ "$APPLY" -eq 0 ]; then
  printf '%s\n' 'Dry run only; re-run with --apply to remove unchanged package files.'
  exit 0
fi

if [ "$BACKUP" -eq 1 ]; then
  BACKUP_DIR="$(next_backup_dir)"
  mkdir -p "$BACKUP_DIR"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -f "$TARGET/$rel" ]; then
      mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      cp -a "$TARGET/$rel" "$BACKUP_DIR/$rel"
    fi
  done < "$CANDIDATES"
  printf 'Backup: %s\n' "$BACKUP_DIR"
else
  printf '%s\n' 'Backup: skipped by --no-backup (failure cannot be restored automatically).' >&2
fi

trap rollback_on_error ERR
while IFS="$(printf '\t')" read -r rel expected; do
  [ -n "$rel" ] || continue
  if [ "$rel" = "$MANIFEST_NAME" ] && [ -s "$PRESERVED" ]; then
    continue
  fi
  if [ ! -f "$TARGET/$rel" ] || [ "$(sha256_file "$TARGET/$rel")" != "$expected" ]; then
    printf '%s (changed during uninstall; preserved)\n' "$rel" >> "$PRESERVED"
    continue
  fi
  rm -f "$TARGET/$rel"
  printf '%s\n' "$rel" >> "$DELETED_FILES"
done < "$CANDIDATE_DIGESTS"
trap - ERR

removed_count="$(wc -l < "$DELETED_FILES" | tr -d ' ')"
printf 'Uninstalled %s owned file(s).\n' "$removed_count"
printf '%s\n' 'User-edited/private files were preserved. Empty directories are left in place.'
if [ -s "$PRESERVED" ]; then
  printf '%s\n' 'Skipped during apply:'
  sed 's/^/  KEEP    /' "$PRESERVED"
  printf '%s\n' "Ownership manifest retained for a later cleanup run: $MARKER_PATH"
fi
if [ "$BACKUP" -eq 1 ]; then
  printf 'Recovery: copy files back from %s, then redeploy Rime.\n' "$BACKUP_DIR"
fi
