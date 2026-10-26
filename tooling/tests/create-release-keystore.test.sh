#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/keytool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
keystore=''
storetype=''
while (($#)); do
  case "$1" in
    -keystore) keystore="$2"; shift 2 ;;
    -storetype) storetype="$2"; shift 2 ;;
    *) shift ;;
  esac
done
test -n "$keystore"
test "$storetype" = JKS
printf 'fake-keystore\n' > "$keystore"
EOF
chmod +x "$FAKE_BIN/keytool"

export PATH="$FAKE_BIN:$PATH"
export FALT_ROOT="$TEST_ROOT/project"
export FALT_KEYSTORE_PATH="$FALT_ROOT/mobile/android/falt-release.jks"
export FALT_KEY_PROPERTIES_PATH="$FALT_ROOT/mobile/android/key.properties"
export FALT_STORE_PASSWORD='store-secret'
export FALT_KEY_PASSWORD='key-secret'
export FALT_KEY_ALIAS='falt-release'

mkdir -p "$FALT_ROOT/mobile/android"
"$SCRIPT_ROOT/tooling/create-release-keystore.sh"

test -s "$FALT_KEYSTORE_PATH"
test -s "$FALT_KEY_PROPERTIES_PATH"
grep -Fx 'storeFile=falt-release.jks' "$FALT_KEY_PROPERTIES_PATH"
grep -Fx 'keyAlias=falt-release' "$FALT_KEY_PROPERTIES_PATH"
grep -Fx 'keyPassword=key-secret' "$FALT_KEY_PROPERTIES_PATH"
grep -Fx 'storePassword=store-secret' "$FALT_KEY_PROPERTIES_PATH"

if "$SCRIPT_ROOT/tooling/create-release-keystore.sh" >/dev/null 2>&1; then
  echo 'expected existing keystore to be rejected' >&2
  exit 1
fi

printf 'create-release-keystore test: ok\n'
