#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/native/android"
PROPERTIES_PATH="${ANDROID_SIGNING_PROPERTIES_FILE:-$ROOT_DIR/src-tauri/gen/android/keystore.properties}"
OUTPUT_DIR="${NATIVE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
RELEASE_LABEL="${1:-v0.1.1-native-preview}"
APK_ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-android-universal.apk"
AAB_ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-android.aab"

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
  testReleaseUnitTest lintRelease assembleRelease bundleRelease

SIGNED_APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
if [[ ! -f "$SIGNED_APK" ]]; then
  echo "Native Android build did not produce a signed release APK." >&2
  exit 1
fi

SIGNED_AAB="$ANDROID_DIR/app/build/outputs/bundle/release/app-release.aab"
if [[ ! -f "$SIGNED_AAB" ]]; then
  echo "Native Android build did not produce a signed release AAB." >&2
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

JARSIGNER="$JAVA_HOME/bin/jarsigner"
if [[ ! -x "$JARSIGNER" ]]; then
  echo "Android AAB verifier was not found: $JARSIGNER" >&2
  exit 1
fi
"$JARSIGNER" -verify "$SIGNED_AAB" >/dev/null
unzip -t "$SIGNED_AAB" >/dev/null

if unzip -p "$SIGNED_APK" 'classes*.dex' | rg --text --fixed-strings --quiet 'http://jwglweixin.bupt.edu.cn'; then
  echo "Native Android package contains the retired HTTP teaching-system endpoint." >&2
  exit 1
fi
if ! unzip -p "$SIGNED_APK" 'classes*.dex' | rg --text --fixed-strings --quiet 'https://jwglweixin.bupt.edu.cn'; then
  echo "Native Android package is missing the expected HTTPS teaching-system endpoint." >&2
  exit 1
fi
if unzip -p "$SIGNED_APK" AndroidManifest.xml | rg --text --fixed-strings --quiet 'networkSecurityConfig'; then
  echo "Native Android package still declares a custom network security configuration." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
cp "$SIGNED_APK" "$APK_ARCHIVE"
cp "$SIGNED_AAB" "$AAB_ARCHIVE"
(
  cd "$OUTPUT_DIR"
  for artifact in "$APK_ARCHIVE" "$AAB_ARCHIVE"; do
    shasum -a 256 "$(basename "$artifact")" > "$(basename "$artifact").sha256"
  done
)

echo "Native Android packages ready at:"
echo "  $APK_ARCHIVE"
echo "  $AAB_ARCHIVE"
