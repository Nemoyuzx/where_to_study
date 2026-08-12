#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/package-validation.sh
source "$ROOT_DIR/scripts/package-validation.sh"
npm --prefix "$ROOT_DIR" run licenses:check
ANDROID_DIR="$ROOT_DIR/native/android"
PROPERTIES_PATH="${ANDROID_SIGNING_PROPERTIES_FILE:-$ROOT_DIR/src-tauri/gen/android/keystore.properties}"
OUTPUT_DIR="${NATIVE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
RELEASE_LABEL="${1:-v0.1.3}"
APK_ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-android-universal.apk"
AAB_ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-android.aab"
EXPECTED_CERTIFICATE_FILE="$ANDROID_DIR/release-certificate.sha256"
validate_release_label "$RELEASE_LABEL"

if [[ "$RELEASE_LABEL" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)([-+].*)?$ ]]; then
  EXPECTED_VERSION="${BASH_REMATCH[1]}"
else
  EXPECTED_VERSION=""
fi
CONFIGURED_VERSION="$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' "$ANDROID_DIR/app/build.gradle.kts" | head -n 1)"
CONFIGURED_BUILD="$(sed -n 's/.*versionCode = \([0-9][0-9]*\).*/\1/p' "$ANDROID_DIR/app/build.gradle.kts" | head -n 1)"

cleanup() {
  "$ANDROID_DIR/gradlew" --project-dir "$ANDROID_DIR" --stop >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

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

if [[ ! -f "$EXPECTED_CERTIFICATE_FILE" ]]; then
  echo "Expected Android release certificate fingerprint was not found." >&2
  exit 1
fi
EXPECTED_CERTIFICATE="$(tr -d '[:space:]:' < "$EXPECTED_CERTIFICATE_FILE" | tr '[:upper:]' '[:lower:]')"
if [[ ! "$EXPECTED_CERTIFICATE" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Expected Android release certificate fingerprint is invalid." >&2
  exit 1
fi

KEYTOOL="$JAVA_HOME/bin/keytool"
if [[ ! -x "$KEYTOOL" ]]; then
  echo "Android release keystore inspector was not found: $KEYTOOL" >&2
  exit 1
fi
if ! KEYSTORE_CERTIFICATE_OUTPUT="$(
  LC_ALL=C "$KEYTOOL" \
    -list \
    -v \
    -keystore "$ANDROID_SIGNING_STORE_FILE" \
    -storepass:env ANDROID_SIGNING_STORE_PASSWORD \
    -alias "$ANDROID_SIGNING_KEY_ALIAS" \
    2>/dev/null
)"; then
  echo "Android release keystore could not be opened with the configured credentials." >&2
  exit 1
fi
KEYSTORE_CERTIFICATE="$(
  sed -n 's/^[[:space:]]*SHA256: //p' <<<"$KEYSTORE_CERTIFICATE_OUTPUT" \
    | tr -d '[:space:]:' \
    | tr '[:upper:]' '[:lower:]'
)"
if [[ ! "$KEYSTORE_CERTIFICATE" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Android release keystore certificate could not be inspected." >&2
  exit 1
fi
if [[ "$KEYSTORE_CERTIFICATE" != "$EXPECTED_CERTIFICATE" ]]; then
  echo "Android release keystore does not match the pinned release certificate." >&2
  exit 1
fi

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

AAPT="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name aapt | sort -V | tail -n 1)"
if [[ -z "$AAPT" ]]; then
  echo "Android aapt was not found." >&2
  exit 1
fi
PACKAGE_BADGING="$("$AAPT" dump badging "$SIGNED_APK" | head -n 1)"
ACTUAL_BUILD="$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$PACKAGE_BADGING")"
ACTUAL_VERSION="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$PACKAGE_BADGING")"
if [[ -n "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "Native Android package version $ACTUAL_VERSION does not match release label $RELEASE_LABEL." >&2
  exit 1
fi
if [[ -z "$CONFIGURED_VERSION" || "$ACTUAL_VERSION" != "$CONFIGURED_VERSION" ]]; then
  echo "Native Android package version $ACTUAL_VERSION does not match Gradle version $CONFIGURED_VERSION." >&2
  exit 1
fi
if [[ -z "$CONFIGURED_BUILD" || "$ACTUAL_BUILD" != "$CONFIGURED_BUILD" ]]; then
  echo "Native Android package build $ACTUAL_BUILD does not match Gradle build $CONFIGURED_BUILD." >&2
  exit 1
fi

if ! APK_CERTIFICATE_OUTPUT="$("$APKSIGNER" verify --print-certs "$SIGNED_APK" 2>&1)"; then
  echo "Native Android APK signer certificate could not be inspected." >&2
  exit 1
fi
ACTUAL_APK_CERTIFICATE="$(
  sed -n 's/^.*certificate SHA-256 digest:[[:space:]]*//p' <<<"$APK_CERTIFICATE_OUTPUT" \
    | tr -d '[:space:]:' \
    | tr '[:upper:]' '[:lower:]'
)"
if [[ ! "$ACTUAL_APK_CERTIFICATE" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Native Android APK signer certificate could not be inspected." >&2
  exit 1
fi
if [[ "$ACTUAL_APK_CERTIFICATE" != "$EXPECTED_CERTIFICATE" ]]; then
  echo "Native Android APK signer does not match the pinned release certificate." >&2
  exit 1
fi

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
ACTUAL_AAB_CERTIFICATE="$(LC_ALL=C "$KEYTOOL" -printcert -jarfile "$SIGNED_AAB" | sed -n 's/^[[:space:]]*SHA256: //p' | tr -d '[:space:]:' | tr '[:upper:]' '[:lower:]')"
if [[ ! "$ACTUAL_AAB_CERTIFICATE" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Native Android AAB signer certificate could not be inspected." >&2
  exit 1
fi
if [[ "$ACTUAL_AAB_CERTIFICATE" != "$EXPECTED_CERTIFICATE" ]]; then
  echo "Native Android AAB signer does not match the pinned release certificate." >&2
  exit 1
fi
unzip -t "$SIGNED_AAB" >/dev/null

if unzip -p "$SIGNED_APK" 'classes*.dex' | stream_contains_fixed_text 'http://jwglweixin.bupt.edu.cn'; then
  echo "Native Android package contains the retired HTTP teaching-system endpoint." >&2
  exit 1
fi
if ! unzip -p "$SIGNED_APK" 'classes*.dex' | stream_contains_fixed_text 'https://jwglweixin.bupt.edu.cn'; then
  echo "Native Android package is missing the expected HTTPS teaching-system endpoint." >&2
  exit 1
fi
if unzip -p "$SIGNED_APK" AndroidManifest.xml | stream_contains_fixed_text 'networkSecurityConfig'; then
  echo "Native Android package still declares a custom network security configuration." >&2
  exit 1
fi
if ! unzip -p "$SIGNED_APK" assets/LICENSE | cmp -s - "$ROOT_DIR/LICENSE"; then
  echo "Native Android APK is missing the exact project license." >&2
  exit 1
fi
if ! unzip -p "$SIGNED_AAB" base/assets/LICENSE | cmp -s - "$ROOT_DIR/LICENSE"; then
  echo "Native Android AAB is missing the exact project license." >&2
  exit 1
fi
for notice in THIRD_PARTY_LICENSES.html THIRD_PARTY_NOTICES.md; do
  if ! unzip -p "$SIGNED_APK" "assets/$notice" | cmp -s - "$ROOT_DIR/$notice"; then
    echo "Native Android APK is missing the exact $notice file." >&2
    exit 1
  fi
  if ! unzip -p "$SIGNED_AAB" "base/assets/$notice" | cmp -s - "$ROOT_DIR/$notice"; then
    echo "Native Android AAB is missing the exact $notice file." >&2
    exit 1
  fi
done

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
