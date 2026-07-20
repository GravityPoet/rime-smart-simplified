#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STATUS=0

printf 'Rime Smart Simplified - macOS installer\n\n'
if "$ROOT/scripts/install.sh"; then
  printf '\nInstallation finished.\n'
  printf 'Next: open the Squirrel menu and choose Deploy, then select 雾凇拼音.\n'
  printf 'Quick test: type nihao and choose 你好; type rq to show today\047s date.\n'
else
  STATUS=$?
  printf '\nInstallation failed with exit code %s.\n' "$STATUS" >&2
fi

if [ -t 0 ]; then
  printf '\nPress Return to close this window...'
  read -r _
fi

exit "$STATUS"
