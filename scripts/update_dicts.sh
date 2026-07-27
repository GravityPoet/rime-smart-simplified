#!/bin/bash
set -euo pipefail

# 万象词库热更新：对比上游 amzxyz/rime_wanxiang 的 dicts/ 并按需替换本地
# cn_dicts_wanxiang/ 副本。默认 dry-run 只对比不写入；--apply 才下载替换。
#
# 明确不更新的文件：
#   cn_dicts/41448.dict.yaml       雾凇大字表，含本地定制注释（唔/嗯/呒/呣 等）
#   cn_dicts/smart_terms.dict.yaml 用户专业词库
#   cn_dicts/smart_finance.dict.yaml 用户投资词库

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="$ROOT/cn_dicts_wanxiang"
UPSTREAM_REPO="amzxyz/rime_wanxiang"
UPSTREAM_BRANCH="wanxiang"
UPSTREAM_API="https://api.github.com/repos/$UPSTREAM_REPO/contents/dicts?ref=$UPSTREAM_BRANCH"
UPSTREAM_RAW="https://raw.githubusercontent.com/$UPSTREAM_REPO/$UPSTREAM_BRANCH/dicts"
VERSION_FILE="$LOCAL_DIR/.upstream-commit"
# 与 rime_ice.dict.yaml import_tables 保持一致的万象词典清单
DICTS="zi jichu lianxiang cuoyin duoyin shici diming"
# 新文件行数低于本地行数的该比例（百分数）时拒绝替换，防上游截断或重构
MIN_LINE_RATIO=80

APPLY=0
usage() {
  printf 'Usage: %s [--apply]\n' "$0"
  printf '  默认 dry-run：仅对比上游与本地差异，不做任何写入。\n'
  printf '  --apply     下载有更新的词典，校验后备份并替换。\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || { printf 'git is required for blob-sha comparison.\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'curl is required.\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'python3 is required for GitHub API parsing.\n' >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

printf 'Fetching upstream file list (%s@%s) ...\n' "$UPSTREAM_REPO" "$UPSTREAM_BRANCH"
curl -fsSL "$UPSTREAM_API" > "$TMP_DIR/contents.json"

upstream_sha() {
  python3 - "$TMP_DIR/contents.json" "$1.dict.yaml" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for item in data:
    if item.get("name") == sys.argv[2]:
        print(item.get("sha", ""))
        break
PY
}

HEAD_COMMIT="$(curl -fsSL "https://api.github.com/repos/$UPSTREAM_REPO/commits/$UPSTREAM_BRANCH" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')"
printf 'Upstream HEAD: %s\n' "$HEAD_COMMIT"
if [ -f "$VERSION_FILE" ]; then
  printf 'Local record : %s\n' "$(cat "$VERSION_FILE")"
fi
printf '\n'

OUTDATED=""
for name in $DICTS; do
  local_file="$LOCAL_DIR/$name.dict.yaml"
  if [ ! -f "$local_file" ]; then
    printf '%-10s MISSING locally, will fetch\n' "$name"
    OUTDATED="$OUTDATED $name"
    continue
  fi
  remote_sha="$(upstream_sha "$name")"
  if [ -z "$remote_sha" ]; then
    printf '%-10s not found upstream, skipped\n' "$name"
    continue
  fi
  local_sha="$(git hash-object "$local_file")"
  if [ "$local_sha" = "$remote_sha" ]; then
    printf '%-10s up to date\n' "$name"
  else
    printf '%-10s update available (local %.7s -> upstream %.7s)\n' "$name" "$local_sha" "$remote_sha"
    OUTDATED="$OUTDATED $name"
  fi
done

if [ -z "$OUTDATED" ]; then
  printf '\nAll wanxiang dictionaries are up to date.\n'
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  printf '\nDry run only. Re-run with --apply to download and replace:%s\n' "$OUTDATED"
  printf 'After applying: run ./scripts/install.sh and redeploy the input method.\n'
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$LOCAL_DIR.backup.$TS"
mkdir -p "$BACKUP_DIR"
printf '\nBackup directory: %s\n' "$BACKUP_DIR"

APPLIED=""
FAILED=""
for name in $OUTDATED; do
  local_file="$LOCAL_DIR/$name.dict.yaml"
  tmp_file="$TMP_DIR/$name.dict.yaml"
  printf 'Downloading %s.dict.yaml ...\n' "$name"
  if ! curl -fL --retry 2 --output "$tmp_file" "$UPSTREAM_RAW/$name.dict.yaml"; then
    printf '%s: download failed, skipped\n' "$name" >&2
    FAILED="$FAILED $name"
    continue
  fi
  if ! grep -q "^name: $name$" "$tmp_file"; then
    printf '%s: upstream file has unexpected dictionary name header, skipped\n' "$name" >&2
    FAILED="$FAILED $name"
    continue
  fi
  if [ -f "$local_file" ]; then
    old_lines="$(wc -l < "$local_file" | tr -d ' ')"
    new_lines="$(wc -l < "$tmp_file" | tr -d ' ')"
    if [ "$old_lines" -gt 0 ] && [ $((new_lines * 100)) -lt $((old_lines * MIN_LINE_RATIO)) ]; then
      printf '%s: upstream shrank too much (%s -> %s lines), skipped for safety\n' \
        "$name" "$old_lines" "$new_lines" >&2
      FAILED="$FAILED $name"
      continue
    fi
    cp -a "$local_file" "$BACKUP_DIR/$name.dict.yaml"
  fi
  mv "$tmp_file" "$local_file"
  APPLIED="$APPLIED $name"
done

if [ -n "$FAILED" ]; then
  if [ -n "$APPLIED" ]; then
    printf '\nUpdated before failure:%s\n' "$APPLIED"
    printf 'Rollback: copy files back from %s\n' "$BACKUP_DIR"
  fi
  printf '\nSkipped (kept local copies):%s\n' "$FAILED"
  exit 1
fi
if [ -n "$APPLIED" ]; then
  printf '%s\n' "$HEAD_COMMIT" > "$VERSION_FILE"
  printf '\nUpdated:%s\n' "$APPLIED"
  printf 'Upstream commit recorded in %s\n' "$VERSION_FILE"
  printf 'Rollback: copy files back from %s\n' "$BACKUP_DIR"
  printf 'Next: cd %s && ./scripts/install.sh && redeploy the input method.\n' "$ROOT"
fi
