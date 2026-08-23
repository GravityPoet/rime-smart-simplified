#!/bin/bash
set -euo pipefail

# Validate the exact upstream assets used by this repository.  The default
# mode is useful for local development: a changed rolling upstream source is a
# warning, while a transport/API failure is returned as status 2 so callers can
# decide whether to tolerate an offline machine.  Release/CI callers use
# --strict and must have live GitHub metadata.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${UPSTREAM_LOCK_FILE:-$ROOT/UPSTREAM_ASSETS.lock.json}"
LOCAL_DIR="$ROOT/cn_dicts_wanxiang"
API_ROOT="${UPSTREAM_API_ROOT:-https://api.github.com}"
API_ROOT="${API_ROOT%/}"
STRICT=0
LOCAL_ONLY=0
OFFLINE_OK=0

usage() {
  printf 'Usage: %s [--strict] [--local-only] [--offline-ok]\n' "$0"
  printf '  默认：校验本地 pin，并在线检查滚动上游；远端变更只告警。\n'
  printf '  --strict       远端变更、API/网络失败均返回非零（发布/CI 使用）。\n'
  printf '  --local-only   不访问网络，只校验 lock 与当前仓库内容。\n'
  printf '  --offline-ok   API/网络失败按成功返回（仅适合本地离线开发）。\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --local-only) LOCAL_ONLY=1 ;;
    --offline-ok) OFFLINE_OK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 3 ;;
  esac
  shift
done

if [ "$STRICT" -eq 1 ] && [ "$OFFLINE_OK" -eq 1 ]; then
  printf '%s\n' '--strict and --offline-ok are mutually exclusive.' >&2
  exit 3
fi

command -v python3 >/dev/null 2>&1 || {
  printf 'python3 is required for upstream lock validation.\n' >&2
  exit 3
}

if [ ! -f "$LOCK_FILE" ] || [ -L "$LOCK_FILE" ]; then
  printf 'Upstream lock file is missing or symlinked: %s\n' "$LOCK_FILE" >&2
  exit 3
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-upstream-freshness.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

LOCAL_REPORT="$TMP_DIR/local.txt"
set +e
python3 - "$LOCK_FILE" "$LOCAL_DIR" "$ROOT/scripts/install.sh" >"$LOCAL_REPORT" <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

lock_path, local_dir, install_path = sys.argv[1:]

def fail(message):
    print("LOCAL_UPSTREAM_INVALID: " + message, file=sys.stderr)
    raise SystemExit(1)

try:
    with open(lock_path, encoding="utf-8") as fh:
        lock = json.load(fh)
except (OSError, ValueError) as exc:
    fail("cannot parse lock file: %s" % exc)

if lock.get("schema_version") != 1:
    fail("unsupported schema_version")
policy = lock.get("freshness_policy") or {}
max_age = policy.get("rolling_max_age_days")
if not isinstance(max_age, int) or max_age <= 0:
    fail("freshness_policy.rolling_max_age_days must be a positive integer")

dicts = lock.get("dictionaries") or {}
if dicts.get("repo") != "amzxyz/rime-wanxiang" or dicts.get("ref") != "wanxiang":
    fail("dictionary source is not the canonical amzxyz/rime-wanxiang@wanxiang")
if dicts.get("path") != "dicts":
    fail("dictionary path must be dicts")
commit = dicts.get("commit")
if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
    fail("dictionary commit is not a 40-character SHA-1")
try:
    commit_date = datetime.fromisoformat(dicts["commit_date"].replace("Z", "+00:00"))
except (KeyError, TypeError, ValueError):
    fail("dictionary commit_date is not an ISO-8601 timestamp")
if commit_date.tzinfo is None:
    fail("dictionary commit_date must include a timezone")

files = dicts.get("files")
blobs = dicts.get("blob_sha")
if not isinstance(files, list) or not files or len(files) != len(set(files)):
    fail("dictionary files must be a non-empty unique list")
if not isinstance(blobs, dict) or set(blobs) != set(files):
    fail("dictionary blob_sha keys must exactly match dictionary files")

record_path = os.path.join(local_dir, ".upstream-commit")
try:
    with open(record_path, encoding="utf-8") as fh:
        record = fh.read().strip()
except OSError as exc:
    fail("cannot read .upstream-commit: %s" % exc)
if record != commit:
    fail(".upstream-commit does not match lock commit")

def git_blob_sha(path):
    with open(path, "rb") as fh:
        payload = fh.read()
    header = ("blob %d\0" % len(payload)).encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()

for name in files:
    if not isinstance(name, str) or "/" in name or "\\" in name or name.startswith("."):
        fail("dictionary file name is not a safe basename: %r" % (name,))
    expected = blobs.get(name)
    if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{40}", expected):
        fail("invalid blob SHA for %s" % name)
    path = os.path.join(local_dir, name)
    if not os.path.isfile(path) or os.path.islink(path):
        fail("missing or symlinked dictionary: %s" % name)
    actual = git_blob_sha(path)
    if actual != expected:
        fail("local blob mismatch for %s (expected %s, got %s)" % (name, expected, actual))

grammar = lock.get("grammar") or {}
if grammar.get("repo") != "amzxyz/RIME-LMDG" or grammar.get("tag") != "LTS":
    fail("grammar source is not the canonical RIME-LMDG LTS release")
if not isinstance(grammar.get("asset"), str) or not grammar["asset"].endswith(".gram"):
    fail("grammar asset is invalid")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(grammar.get("digest", ""))):
    fail("grammar digest must be sha256:<64 hex>")
if not isinstance(grammar.get("size"), int) or grammar["size"] <= 0:
    fail("grammar size is invalid")
try:
    datetime.fromisoformat(grammar["updated_at"].replace("Z", "+00:00"))
except (KeyError, TypeError, ValueError):
    fail("grammar updated_at is not an ISO-8601 timestamp")

predict = lock.get("predict") or {}
if predict.get("repo") != "rime/librime-predict" or predict.get("tag") != "data-1.0":
    fail("prediction source is not the canonical librime-predict data-1.0 release")
if predict.get("asset") != "predict.db" or not re.fullmatch(r"[0-9a-f]{64}", str(predict.get("sha256", ""))):
    fail("prediction asset or SHA-256 is invalid")
if not isinstance(predict.get("size"), int) or predict["size"] <= 0:
    fail("prediction size is invalid")

try:
    installer = open(install_path, encoding="utf-8").read()
except OSError as exc:
    fail("cannot read installer: %s" % exc)
predict_match = re.search(r'^PREDICT_SHA256="([0-9a-f]{64})"$', installer, re.MULTILINE)
if not predict_match or predict_match.group(1) != predict["sha256"]:
    fail("installer PREDICT_SHA256 does not match lock")
gram_match = re.search(r'^GRAM_FILE="([^"]+)"$', installer, re.MULTILINE)
if not gram_match or gram_match.group(1) != grammar["asset"]:
    fail("installer GRAM_FILE does not match lock")

print("LOCAL_UPSTREAM_OK commit=%s files=%d" % (commit, len(files)))
print("LOCK_MAX_AGE_DAYS=%d" % max_age)
PY
LOCAL_STATUS=$?
set -e
cat "$LOCAL_REPORT"
if [ "$LOCAL_STATUS" -ne 0 ]; then
  exit 1
fi

if [ "$LOCAL_ONLY" -eq 1 ]; then
  printf '%s\n' 'Upstream local pin check passed (network not consulted).'
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  printf 'curl is required for live upstream freshness checks.\n' >&2
  if [ "$OFFLINE_OK" -eq 1 ]; then exit 0; else exit 2; fi
}

api_get() {
  path="$1"
  output="$2"
  url="$API_ROOT$path"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 45 \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      "$url" -o "$output"
  else
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 45 \
      -H 'Accept: application/vnd.github+json' \
      "$url" -o "$output"
  fi
}

DICT_REPO_PATH="/repos/amzxyz/rime-wanxiang"
GRAM_REPO_PATH="/repos/amzxyz/RIME-LMDG"
PREDICT_REPO_PATH="/repos/rime/librime-predict"
if ! api_get "$DICT_REPO_PATH/commits/wanxiang" "$TMP_DIR/dict-commit.json" || \
   ! api_get "$DICT_REPO_PATH/contents/dicts?ref=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha"])' "$TMP_DIR/dict-commit.json")" "$TMP_DIR/dict-contents.json" || \
   ! api_get "$GRAM_REPO_PATH/releases/tags/LTS" "$TMP_DIR/grammar.json" || \
   ! api_get "$PREDICT_REPO_PATH/releases/tags/data-1.0" "$TMP_DIR/predict.json"; then
  printf 'UPSTREAM_FRESHNESS=unknown (GitHub API/network unavailable; status 2)\n' >&2
  if [ "$OFFLINE_OK" -eq 1 ]; then
    exit 0
  fi
  exit 2
fi

REMOTE_REPORT="$TMP_DIR/remote.txt"
set +e
python3 - "$LOCK_FILE" "$TMP_DIR/dict-commit.json" "$TMP_DIR/dict-contents.json" "$TMP_DIR/grammar.json" "$TMP_DIR/predict.json" >"$REMOTE_REPORT" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone

lock_path, commit_path, contents_path, grammar_path, predict_path = sys.argv[1:]

def api_fail(message):
    print("UPSTREAM_API_INVALID: " + message, file=sys.stderr)
    raise SystemExit(2)

try:
    with open(lock_path, encoding="utf-8") as fh:
        lock = json.load(fh)
    with open(commit_path, encoding="utf-8") as fh:
        commit_data = json.load(fh)
    with open(contents_path, encoding="utf-8") as fh:
        contents = json.load(fh)
    with open(grammar_path, encoding="utf-8") as fh:
        grammar_data = json.load(fh)
    with open(predict_path, encoding="utf-8") as fh:
        predict_data = json.load(fh)
except (OSError, ValueError) as exc:
    api_fail("cannot parse GitHub response: %s" % exc)

dicts = lock["dictionaries"]
lock_commit = dicts["commit"]
remote_commit = commit_data.get("sha")
if not isinstance(remote_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", remote_commit):
    api_fail("dictionary commit response has no valid sha")
reasons = []
if remote_commit != lock_commit:
    reasons.append("dictionary ref moved from %s to %s" % (lock_commit[:12], remote_commit[:12]))

remote_date = ((commit_data.get("commit") or {}).get("committer") or {}).get("date")
if not isinstance(remote_date, str):
    api_fail("dictionary commit response has no committer date")
try:
    remote_dt = datetime.fromisoformat(remote_date.replace("Z", "+00:00"))
    lock_dt = datetime.fromisoformat(dicts["commit_date"].replace("Z", "+00:00"))
except ValueError as exc:
    api_fail("invalid dictionary commit date: %s" % exc)
if remote_dt != lock_dt:
    reasons.append("dictionary commit date differs from lock")

if not isinstance(contents, list):
    api_fail("dictionary contents response is not a list")
remote_files = {item.get("name"): item for item in contents if isinstance(item, dict)}
for name in dicts["files"]:
    item = remote_files.get(name)
    if not item:
        reasons.append("dictionary missing upstream: %s" % name)
        continue
    if item.get("type") != "file":
        reasons.append("dictionary is not a regular file upstream: %s" % name)
    if item.get("sha") != dicts["blob_sha"].get(name):
        reasons.append("dictionary blob changed: %s" % name)

grammar = lock["grammar"]
assets = grammar_data.get("assets")
if not isinstance(assets, list):
    api_fail("grammar release has no assets list")
gram_asset = next((a for a in assets if isinstance(a, dict) and a.get("name") == grammar["asset"]), None)
if not gram_asset:
    reasons.append("grammar asset missing upstream")
else:
    if gram_asset.get("digest") != grammar["digest"]:
        reasons.append("grammar digest changed")
    if gram_asset.get("size") != grammar["size"]:
        reasons.append("grammar size changed")
    if gram_asset.get("updated_at") != grammar["updated_at"]:
        reasons.append("grammar asset timestamp changed")

predict = lock["predict"]
predict_assets = predict_data.get("assets")
if not isinstance(predict_assets, list):
    api_fail("prediction release has no assets list")
predict_asset = next((a for a in predict_assets if isinstance(a, dict) and a.get("name") == predict["asset"]), None)
if not predict_asset:
    reasons.append("prediction asset missing upstream")
else:
    # GitHub does not publish a digest for this old release.  Size and update
    # time still detect tag replacement; the content SHA remains pinned in the
    # installer and lock and is checked when the installer downloads it.
    if predict_asset.get("size") != predict["size"]:
        reasons.append("prediction asset size changed")
    if predict_asset.get("updated_at") != predict["updated_at"]:
        reasons.append("prediction asset timestamp changed")

now = datetime.now(timezone.utc)
max_age = lock["freshness_policy"]["rolling_max_age_days"]
for label, dt in (("dictionary commit", remote_dt), ("grammar asset", datetime.fromisoformat(grammar["updated_at"].replace("Z", "+00:00")))):
    age = (now - dt).total_seconds()
    if age < -86400:
        reasons.append("%s timestamp is more than one day in the future" % label)
    elif age > max_age * 86400:
        reasons.append("%s is older than freshness policy (%d days)" % (label, max_age))

if reasons:
    print("UPSTREAM_FRESHNESS=stale")
    for reason in reasons:
        print("STALE_REASON: " + reason)
    raise SystemExit(1)

print("UPSTREAM_FRESHNESS=fresh commit=%s grammar_digest=%s" % (remote_commit, grammar["digest"]))
PY
REMOTE_STATUS=$?
set -e
cat "$REMOTE_REPORT"
case "$REMOTE_STATUS" in
  0)
    exit 0
    ;;
  1)
    if [ "$STRICT" -eq 1 ]; then
      exit 1
    fi
    printf '%s\n' 'Rolling upstream changed or exceeded freshness policy; continuing in non-strict mode.' >&2
    exit 0
    ;;
  2)
    if [ "$OFFLINE_OK" -eq 1 ]; then exit 0; fi
    exit 2
    ;;
  *)
    exit 3
    ;;
esac
