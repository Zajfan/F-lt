#!/usr/bin/env bash
set -euo pipefail

FALT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FALT_TOOLING_ROOT="${FALT_TOOLING_ROOT:-$FALT_ROOT/.tooling}"
FALT_ANDROID_SDK_ROOT="${FALT_ANDROID_SDK_ROOT:-$FALT_TOOLING_ROOT/android-sdk}"
FALT_FLUTTER_ROOT="${FALT_FLUTTER_ROOT:-$FALT_TOOLING_ROOT/flutter}"

export FALT_ROOT FALT_TOOLING_ROOT FALT_ANDROID_SDK_ROOT FALT_FLUTTER_ROOT
export ANDROID_HOME="$FALT_ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$FALT_ANDROID_SDK_ROOT"
export PATH="$FALT_FLUTTER_ROOT/bin:$FALT_FLUTTER_ROOT/bin/cache/dart-sdk/bin:$FALT_ANDROID_SDK_ROOT/platform-tools:$FALT_ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

if [[ -z "${JAVA_HOME:-}" ]]; then
  for FALT_JAVA_CANDIDATE in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk /usr/lib/jvm/java-21 /usr/lib/jvm/java-17; do
    if [[ -x "$FALT_JAVA_CANDIDATE/bin/java" ]]; then
      export JAVA_HOME="$FALT_JAVA_CANDIDATE"
      break
    fi
  done
fi
