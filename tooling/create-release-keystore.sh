#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FALT_ROOT="${FALT_ROOT:-$SCRIPT_ROOT}"
KEYSTORE_PATH="${FALT_KEYSTORE_PATH:-$FALT_ROOT/mobile/android/falt-release.jks}"
KEY_PROPERTIES_PATH="${FALT_KEY_PROPERTIES_PATH:-$FALT_ROOT/mobile/android/key.properties}"
KEY_ALIAS="${FALT_KEY_ALIAS:-falt-release}"
STORE_PASSWORD="${FALT_STORE_PASSWORD:-}"
KEY_PASSWORD="${FALT_KEY_PASSWORD:-$STORE_PASSWORD}"
KEY_DNAME="${FALT_KEY_DNAME:-CN=Falt Release, OU=Mobile, O=Falt, L=Stockholm, C=SE}"

if ! command -v keytool >/dev/null 2>&1; then
  printf 'Missing required host tool: keytool\n' >&2
  exit 1
fi

if [[ -z "$STORE_PASSWORD" || -z "$KEY_PASSWORD" ]]; then
  cat >&2 <<'EOF'
Set FALT_STORE_PASSWORD and FALT_KEY_PASSWORD in the shell before running this script.
Do not commit either secret; mobile/android/key.properties and *.jks are ignored.
EOF
  exit 2
fi

if [[ -e "$KEYSTORE_PATH" || -e "$KEY_PROPERTIES_PATH" ]]; then
  printf 'Refusing to overwrite an existing keystore or key.properties.\n' >&2
  printf '  keystore: %s\n  config:   %s\n' "$KEYSTORE_PATH" "$KEY_PROPERTIES_PATH" >&2
  exit 3
fi

mkdir -p "$(dirname "$KEYSTORE_PATH")" "$(dirname "$KEY_PROPERTIES_PATH")"
umask 077

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype JKS \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "$KEY_DNAME"

cat > "$KEY_PROPERTIES_PATH" <<EOF
storeFile=$(basename "$KEYSTORE_PATH")
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASSWORD
storePassword=$STORE_PASSWORD
EOF

printf 'Release keystore created at %s\n' "$KEYSTORE_PATH"
printf 'Gradle signing config created at %s\n' "$KEY_PROPERTIES_PATH"
printf 'Back up both files securely; losing them prevents updates to published APKs.\n'
