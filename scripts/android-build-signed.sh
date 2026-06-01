#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_PROJECT_DIR="$ROOT_DIR/src-tauri/gen/android"
PROPERTIES_PATH="${ANDROID_SIGNING_PROPERTIES_FILE:-$ANDROID_PROJECT_DIR/keystore.properties}"
OUTPUT_DIR="$ANDROID_PROJECT_DIR/app/build/outputs/apk/universal/release"

has_env_signing() {
  [ -n "${ANDROID_SIGNING_STORE_FILE:-}" ] \
    && [ -n "${ANDROID_SIGNING_STORE_PASSWORD:-}" ] \
    && [ -n "${ANDROID_SIGNING_KEY_ALIAS:-}" ] \
    && [ -n "${ANDROID_SIGNING_KEY_PASSWORD:-}" ]
}

if ! has_env_signing && [ ! -f "$PROPERTIES_PATH" ]; then
  echo "No Android release signing config found." >&2
  echo "Run ./scripts/android-signing-init.sh or set ANDROID_SIGNING_* environment variables first." >&2
  exit 1
fi

"$ROOT_DIR/scripts/android-build-local.sh" "$@"

SIGNED_APK="$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.apk' ! -name '*-unsigned.apk' | head -n 1)"

if [ -z "$SIGNED_APK" ]; then
  echo "Android build completed but no signed APK was produced in $OUTPUT_DIR" >&2
  exit 1
fi

echo "Signed Android APK ready at:"
echo "  $SIGNED_APK"