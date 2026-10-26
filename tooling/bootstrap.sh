#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.35.7}"
ANDROID_CMDLINE_TOOLS_VERSION="${ANDROID_CMDLINE_TOOLS_VERSION:-15859902}"
ANDROID_CMDLINE_TOOLS_SHA256="${ANDROID_CMDLINE_TOOLS_SHA256:-4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-36}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required host tool: %s\n' "$1" >&2
    exit 1
  }
}

require_tool curl
require_tool tar
require_tool unzip
require_tool sha256sum
mkdir -p "$FALT_TOOLING_ROOT" "$FALT_ANDROID_SDK_ROOT/cmdline-tools"

if [[ ! -x "$FALT_FLUTTER_ROOT/bin/flutter" ]]; then
  FALT_FLUTTER_ARCHIVE="$FALT_TOOLING_ROOT/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl --fail --location --retry 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    --output "$FALT_FLUTTER_ARCHIVE"
  tar -xJf "$FALT_FLUTTER_ARCHIVE" -C "$FALT_TOOLING_ROOT"
fi

if [[ ! -x "$FALT_ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  FALT_ANDROID_ARCHIVE="$FALT_TOOLING_ROOT/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"
  curl --fail --location --retry 3 \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
    --output "$FALT_ANDROID_ARCHIVE"
  printf '%s  %s\n' "$ANDROID_CMDLINE_TOOLS_SHA256" "$FALT_ANDROID_ARCHIVE" | sha256sum --check --strict
  FALT_ANDROID_STAGE="$FALT_TOOLING_ROOT/android-cmdline-stage"
  rm -rf "$FALT_ANDROID_STAGE"
  mkdir -p "$FALT_ANDROID_STAGE"
  unzip -q "$FALT_ANDROID_ARCHIVE" -d "$FALT_ANDROID_STAGE"
  rm -rf "$FALT_ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv "$FALT_ANDROID_STAGE/cmdline-tools" "$FALT_ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -rf "$FALT_ANDROID_STAGE"
fi

yes | sdkmanager --sdk_root="$FALT_ANDROID_SDK_ROOT" \
  "platform-tools" \
  "platforms;android-${ANDROID_API_LEVEL}" \
  "build-tools;${ANDROID_BUILD_TOOLS}"

cat <<EOF
Toolchains installed under:
  Flutter: $FALT_FLUTTER_ROOT
  Android: $FALT_ANDROID_SDK_ROOT

Licenses were not auto-accepted. Review and accept them explicitly with:
  source tooling/env.sh
  flutter doctor --android-licenses
EOF
