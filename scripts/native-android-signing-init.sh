#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_PROJECT_DIR="$ROOT_DIR/native/android"
KEYSTORE_DIR="$ANDROID_PROJECT_DIR/keystore"
PROPERTIES_PATH="${ANDROID_SIGNING_PROPERTIES_FILE:-$ANDROID_PROJECT_DIR/keystore.properties}"
KEY_ALIAS="${ANDROID_SIGNING_KEY_ALIAS:-upload}"
DNAME="${ANDROID_SIGNING_DNAME:-CN=Where To Study, OU=Mobile, O=Nemoyu, L=Beijing, ST=Beijing, C=CN}"

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

DEFAULT_STORE_FILE="$KEYSTORE_DIR/where-to-study-upload.jks"
STORE_FILE_INPUT="${ANDROID_SIGNING_STORE_FILE:-$DEFAULT_STORE_FILE}"
mkdir -p "$(dirname "$STORE_FILE_INPUT")"
STORE_FILE="$(cd "$(dirname "$STORE_FILE_INPUT")" && pwd)/$(basename "$STORE_FILE_INPUT")"

STORE_PASSWORD="${ANDROID_SIGNING_STORE_PASSWORD:-$(generate_password)}"
KEY_PASSWORD="${ANDROID_SIGNING_KEY_PASSWORD:-$STORE_PASSWORD}"

if [ -f "$STORE_FILE" ] && [ -f "$PROPERTIES_PATH" ]; then
  echo "Native Android signing assets already exist:"
  echo "  keystore: $STORE_FILE"
  echo "  properties: $PROPERTIES_PATH"
  exit 0
fi

KEYTOOL_BIN=""

if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/keytool" ]; then
  KEYTOOL_BIN="$JAVA_HOME/bin/keytool"
elif [ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" ]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  KEYTOOL_BIN="$JAVA_HOME/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  KEYTOOL_BIN="$(command -v keytool)"
else
  echo "keytool not found. Set JAVA_HOME or install Android Studio / a JDK first." >&2
  exit 1
fi

if [ ! -f "$STORE_FILE" ]; then
  "$KEYTOOL_BIN" -genkeypair \
    -storetype JKS \
    -keystore "$STORE_FILE" \
    -storepass "$STORE_PASSWORD" \
    -alias "$KEY_ALIAS" \
    -keypass "$KEY_PASSWORD" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "$DNAME"
fi

cat > "$PROPERTIES_PATH" <<EOF
storeFile=$STORE_FILE
storePassword=$STORE_PASSWORD
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASSWORD
EOF

chmod 600 "$PROPERTIES_PATH" "$STORE_FILE"

echo "Native Android signing initialized."
echo "  keystore: $STORE_FILE"
echo "  properties: $PROPERTIES_PATH"
echo "Back up both files before moving to another machine or CI."
