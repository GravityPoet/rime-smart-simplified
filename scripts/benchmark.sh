#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS=20
OUTPUT=""
LUA_ONLY=0
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

timestamp_ns() {
  python3 -c 'import time; print(time.monotonic_ns())'
}

json_quote() {
  # Python is already required below for monotonic timing; use its JSON
  # encoder instead of fragile sed multiline escaping.
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

usage() {
  printf 'Usage: %s [--lua-only] [--iterations N] [--output FILE] [--run-id ID]\n' "$0"
  printf '  默认运行合成 Lua 候选流基准，并测量隔离安装、Rime 构建和真实输入 smoke。\n'
  printf '  --lua-only    只运行不依赖前端/模型的 Lua 候选流基准。\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lua-only) LUA_ONLY=1 ;;
    --iterations)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      ITERATIONS="$2"
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      OUTPUT="$2"
      shift
      ;;
    --run-id)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      RUN_ID="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

case "$ITERATIONS" in
  ''|*[!0-9]*) printf 'iterations must be an integer.\n' >&2; exit 2 ;;
esac
[ "$ITERATIONS" -ge 1 ] && [ "$ITERATIONS" -le 10000 ] || {
  printf 'iterations must be between 1 and 10000.\n' >&2
  exit 2
}

if [ -z "$OUTPUT" ]; then
  OUTPUT="$ROOT/benchmark-results.jsonl"
fi
mkdir -p "$(dirname "$OUTPUT")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rime-smart-simplified-benchmark.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

LUA_BIN="${LUA_BIN:-}"
if [ -z "$LUA_BIN" ]; then
  LUA_BIN="$(command -v lua5.4 2>/dev/null || command -v lua 2>/dev/null || true)"
fi
[ -n "$LUA_BIN" ] || { printf 'lua or lua5.4 is required.\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'python3 is required for monotonic timing.\n' >&2; exit 1; }

LUA_RESULT="$TMP_DIR/lua.jsonl"
"$LUA_BIN" "$ROOT/tests/lua_benchmark.lua" "$ROOT" "$ITERATIONS" "$RUN_ID" > "$LUA_RESULT"

{
  GIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  printf '{"schema":"rime-smart-simplified-benchmark/v1","record":"run","run_id":%s,"git_sha":%s,"platform":%s,"lua_only":%s,"iterations":%s,"proxy":true,"synthetic":false,"real_frontend":false,"accuracy_claim":false,"measurement":"benchmark_harness"' \
    "$(json_quote "$RUN_ID")" "$(json_quote "$GIT_SHA")" "$(json_quote "$(uname -s)-$(uname -m)")" \
    "$([ "$LUA_ONLY" -eq 1 ] && printf true || printf false)" "$ITERATIONS"
  if [ "$LUA_ONLY" -eq 0 ]; then
    if ! command -v rime_deployer >/dev/null 2>&1 || ! command -v c++ >/dev/null 2>&1 \
      || ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists rime; then
      printf '%s\n' >&2 'full benchmark requires rime_deployer, c++, pkg-config, and librime development files.'
      exit 1
    fi

    RIME_DIR="$TMP_DIR/rime"
    INSTALL_START="$TMP_DIR/install.start"
    INSTALL_END="$TMP_DIR/install.end"
    timestamp_ns > "$INSTALL_START"
    RIME_USER_DIR="$RIME_DIR" "$ROOT/scripts/install.sh" --no-download-gram --no-download-predict > "$TMP_DIR/install.out"
    timestamp_ns > "$INSTALL_END"
    rime_deployer --build "$RIME_DIR" "$RIME_DIR" "$RIME_DIR/build" > "$TMP_DIR/build.out" 2>&1
    timestamp_ns > "$TMP_DIR/build.end"
    SMOKE_COMPILE_START="$TMP_DIR/smoke-compile.start"
    SMOKE_COMPILE_END="$TMP_DIR/smoke-compile.end"
    SMOKE_RUN_START="$TMP_DIR/smoke-run.start"
    SMOKE_RUN_END="$TMP_DIR/smoke-run.end"
    timestamp_ns > "$SMOKE_COMPILE_START"
    c++ -std=c++17 "$ROOT/tests/rime_smoke.cpp" \
      $(pkg-config --cflags --libs rime) \
      -o "$RIME_DIR/rime-smoke"
    timestamp_ns > "$SMOKE_COMPILE_END"
    timestamp_ns > "$SMOKE_RUN_START"
    "$RIME_DIR/rime-smoke" "$RIME_DIR" "$RIME_DIR" nihao 你好 > "$TMP_DIR/smoke.out" 2> "$TMP_DIR/smoke.err"
    timestamp_ns > "$SMOKE_RUN_END"

    install_ns="$(( $(cat "$INSTALL_END") - $(cat "$INSTALL_START") ))"
    build_ns="$(( $(cat "$TMP_DIR/build.end") - $(cat "$INSTALL_END") ))"
    smoke_compile_ns="$(( $(cat "$SMOKE_COMPILE_END") - $(cat "$SMOKE_COMPILE_START") ))"
    smoke_run_ns="$(( $(cat "$SMOKE_RUN_END") - $(cat "$SMOKE_RUN_START") ))"
  fi
  printf '}\n'
  if [ "$LUA_ONLY" -eq 0 ]; then
    printf '{"schema":"rime-smart-simplified-benchmark/v1","record":"isolated_install_proxy","run_id":%s,"status":"passed","proxy":true,"synthetic":false,"real_frontend":false,"accuracy_claim":false,"measurement":"real_install_in_temp_dir","elapsed_ms":%.3f,"downloaded_models":false}\n' \
      "$(json_quote "$RUN_ID")" "$(awk -v n="$install_ns" 'BEGIN { print n / 1000000 }')"
    printf '{"schema":"rime-smart-simplified-benchmark/v1","record":"isolated_rime_build_proxy","run_id":%s,"status":"passed","proxy":true,"synthetic":false,"real_frontend":false,"accuracy_claim":false,"measurement":"real_rime_deployer_build","elapsed_ms":%.3f}\n' \
      "$(json_quote "$RUN_ID")" "$(awk -v n="$build_ns" 'BEGIN { print n / 1000000 }')"
    printf '{"schema":"rime-smart-simplified-benchmark/v1","record":"librime_candidate_smoke_proxy","run_id":%s,"status":"passed","proxy":true,"synthetic":false,"real_frontend":false,"accuracy_claim":false,"measurement":"real_librime_api_no_frontend","compile_ms":%.3f,"run_ms":%.3f,"input":"nihao","expected_candidate":"你好"}\n' \
      "$(json_quote "$RUN_ID")" \
      "$(awk -v n="$smoke_compile_ns" 'BEGIN { print n / 1000000 }')" \
      "$(awk -v n="$smoke_run_ns" 'BEGIN { print n / 1000000 }')"
  fi
  cat "$LUA_RESULT"
} > "$OUTPUT"

printf 'Benchmark written: %s\n' "$OUTPUT"
