#!/usr/bin/env bash
set -euo pipefail
umask 077

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

if [ -f "$STORE_FILE" ] && [ -f "$PROPERTIES_PATH" ]; then
  echo "Native Android signing assets already exist:"
  echo "  keystore: $STORE_FILE"
  echo "  properties: $PROPERTIES_PATH"
  exit 0
fi

if [ -f "$STORE_FILE" ] || [ -f "$PROPERTIES_PATH" ]; then
  echo "Native Android signing assets are incomplete." >&2
  echo "  keystore: $([ -f "$STORE_FILE" ] && echo present || echo missing)" >&2
  echo "  properties: $([ -f "$PROPERTIES_PATH" ] && echo present || echo missing)" >&2
  echo "Restore the missing file from backup, or delete the remaining one and re-run." >&2
  exit 1
fi

case "$STORE_FILE:$PROPERTIES_PATH" in
  "$ROOT_DIR"/*|*:"$ROOT_DIR"/*)
    echo "警告：签名文件位于仓库目录内。仓库 .gitignore 只覆盖默认文件名，" >&2
    echo "自定义文件名请自行确认不会被提交。" >&2
    ;;
esac

STORE_PASSWORD="${ANDROID_SIGNING_STORE_PASSWORD:-$(generate_password)}"
KEY_PASSWORD="${ANDROID_SIGNING_KEY_PASSWORD:-$STORE_PASSWORD}"

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
  # Pass passwords through environment variables so they never appear in
  # process listings (keytool -storepass:env / -keypass:env).
  export KEYTOOL_STORE_PASSWORD="$STORE_PASSWORD"
  export KEYTOOL_KEY_PASSWORD="$KEY_PASSWORD"
  "$KEYTOOL_BIN" -genkeypair \
    -storetype JKS \
    -keystore "$STORE_FILE" \
    -storepass:env KEYTOOL_STORE_PASSWORD \
    -alias "$KEY_ALIAS" \
    -keypass:env KEYTOOL_KEY_PASSWORD \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "$DNAME"
  unset KEYTOOL_STORE_PASSWORD KEYTOOL_KEY_PASSWORD
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
