#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/native/android"
PROPERTIES_PATH="${ANDROID_SIGNING_PROPERTIES_FILE:-$ROOT_DIR/src-tauri/gen/android/keystore.properties}"
OUTPUT_DIR="${NATIVE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
RELEASE_LABEL="${1:-v0.1.1-native-preview}"
ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-android-universal.apk"

read_property() {
  local key="$1"
  sed -n "s/^${key}=//p" "$PROPERTIES_PATH" | tail -n 1
}

if [[ -z "${ANDROID_SIGNING_STORE_FILE:-}" && -f "$PROPERTIES_PATH" ]]; then
  ANDROID_SIGNING_STORE_FILE="$(read_property storeFile)"
  ANDROID_SIGNING_STORE_PASSWORD="$(read_property storePassword)"
  ANDROID_SIGNING_KEY_ALIAS="$(read_property keyAlias)"
  ANDROID_SIGNING_KEY_PASSWORD="$(read_property keyPassword)"
  if [[ "$ANDROID_SIGNING_STORE_FILE" != /* ]]; then
    ANDROID_SIGNING_STORE_FILE="$(cd "$(dirname "$PROPERTIES_PATH")" && pwd)/$ANDROID_SIGNING_STORE_FILE"
  fi
  export ANDROID_SIGNING_STORE_FILE ANDROID_SIGNING_STORE_PASSWORD
  export ANDROID_SIGNING_KEY_ALIAS ANDROID_SIGNING_KEY_PASSWORD
fi

for variable in \
  ANDROID_SIGNING_STORE_FILE \
  ANDROID_SIGNING_STORE_PASSWORD \
  ANDROID_SIGNING_KEY_ALIAS \
  ANDROID_SIGNING_KEY_PASSWORD; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing Android release signing variable: $variable" >&2
    exit 1
  fi
done

if [[ ! -f "$ANDROID_SIGNING_STORE_FILE" ]]; then
  echo "Android release keystore was not found." >&2
  exit 1
fi

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"

"$ANDROID_DIR/gradlew" \
  --project-dir "$ANDROID_DIR" \
  testReleaseUnitTest lintRelease assembleRelease

SIGNED_APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
if [[ ! -f "$SIGNED_APK" ]]; then
  echo "Native Android build did not produce a signed release APK." >&2
  exit 1
fi

APKSIGNER="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name apksigner | sort -V | tail -n 1)"
if [[ -z "$APKSIGNER" ]]; then
  echo "Android apksigner was not found." >&2
  exit 1
fi
"$APKSIGNER" verify --verbose "$SIGNED_APK" >/dev/null

ZIPALIGN="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name zipalign | sort -V | tail -n 1)"
if [[ -z "$ZIPALIGN" ]]; then
  echo "Android zipalign was not found." >&2
  exit 1
fi
"$ZIPALIGN" -c -P 16 -v 4 "$SIGNED_APK" >/dev/null

mkdir -p "$OUTPUT_DIR"
cp "$SIGNED_APK" "$ARCHIVE"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo "Native Android package ready at:"
echo "  $ARCHIVE"
