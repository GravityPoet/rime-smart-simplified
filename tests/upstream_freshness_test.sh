#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check_upstream_freshness.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-upstream-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

printf 'Checking the committed upstream lock locally...\n'
"$CHECK" --local-only --strict >/dev/null

printf 'Checking that a tampered lock is rejected...\n'
cp "$ROOT/UPSTREAM_ASSETS.lock.json" "$TMP_DIR/tampered.json"
python3 - "$TMP_DIR/tampered.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
data["dictionaries"]["commit"] = "0" * 40
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
set +e
UPSTREAM_LOCK_FILE="$TMP_DIR/tampered.json" "$CHECK" --local-only --strict >/dev/null 2>&1
STATUS=$?
set -e
test "$STATUS" -eq 1

printf 'Checking explicit offline status handling...\n'
set +e
UPSTREAM_API_ROOT="http://127.0.0.1:1" "$CHECK" --strict >/dev/null 2>&1
STRICT_STATUS=$?
UPSTREAM_API_ROOT="http://127.0.0.1:1" "$CHECK" --offline-ok >/dev/null 2>&1
OFFLINE_STATUS=$?
set -e
test "$STRICT_STATUS" -eq 2
test "$OFFLINE_STATUS" -eq 0

printf 'Upstream freshness contract passed.\n'
