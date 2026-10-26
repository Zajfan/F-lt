#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"
FALT_FAILED=0

check_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'OK   %-20s %s\n' "$1" "$(command -v "$1")"
  else
    printf 'MISS %-20s\n' "$1"
    FALT_FAILED=1
  fi
}

check_tool flutter
check_tool dart
check_tool adb
check_tool sdkmanager
check_tool java
check_tool psql

if command -v flutter >/dev/null 2>&1; then
  flutter --version || FALT_FAILED=1
  flutter doctor -v || FALT_FAILED=1
fi

if [[ -f "$FALT_ROOT/mobile/pubspec.yaml" && ! -f "$FALT_ROOT/mobile/pubspec.lock" ]]; then
  printf 'MISS mobile/pubspec.lock — run flutter pub get\n'
  FALT_FAILED=1
fi

if [[ -f "$FALT_ROOT/mobile/pubspec.lock" ]]; then
  for FALT_DEPENDENCY in supabase_flutter workmanager sqflite_sqlcipher flutter_secure_storage; do
    if ! rg -q "^  ${FALT_DEPENDENCY}:" "$FALT_ROOT/mobile/pubspec.lock"; then
      printf 'MISS mobile/pubspec.lock entry: %s — run flutter pub get\n' "$FALT_DEPENDENCY"
      FALT_FAILED=1
    fi
  done
fi

if [[ -z "${FALT_SUPABASE_URL:-}" || -z "${FALT_SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  printf 'INFO Supabase runtime config is not exported; use mobile/config/env.json\n'
fi

if [[ "$FALT_FAILED" -ne 0 ]]; then
  printf 'Fält doctor: incomplete\n'
  exit 1
fi
printf 'Fält doctor: ready\n'
