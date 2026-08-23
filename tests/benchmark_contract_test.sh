#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-benchmark-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

RESULT="$TMP_DIR/benchmark.jsonl"

if [ ! -x "$ROOT/scripts/benchmark.sh" ]; then
  printf 'benchmark contract: scripts/benchmark.sh is missing or not executable\n' >&2
  exit 1
fi

"$ROOT/scripts/benchmark.sh" --lua-only --iterations 2 --output "$RESULT"
test -s "$RESULT"

# Keep this contract intentionally small: benchmark details may evolve, but
# the result must remain JSON Lines with a run record and both synthetic seams.
grep '"schema":"rime-smart-simplified-benchmark/v1"' "$RESULT" >/dev/null
grep '"record":"run"' "$RESULT" >/dev/null
grep '"module":"short_code_clean_filter"' "$RESULT" >/dev/null
grep '"module":"cold_word_drop.filter"' "$RESULT" >/dev/null
grep '"synthetic":true' "$RESULT" >/dev/null

line_count="$(wc -l < "$RESULT" | tr -d ' ')"
test "$line_count" -ge 3

printf 'Benchmark contract passed.\n'
