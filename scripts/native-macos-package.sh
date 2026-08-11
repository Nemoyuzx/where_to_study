#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/package-validation.sh
source "$ROOT_DIR/scripts/package-validation.sh"
npm --prefix "$ROOT_DIR" run licenses:check
APPLE_DIR="$ROOT_DIR/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData/release-macOS"
OUTPUT_DIR="${NATIVE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
RELEASE_LABEL="${1:-v0.1.1-native-preview}"
ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-macos-universal.zip"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/where-to-study-native-macos.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [[ "$RELEASE_LABEL" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)([-+].*)?$ ]]; then
  EXPECTED_VERSION="${BASH_REMATCH[1]}"
else
  EXPECTED_VERSION=""
fi
CONFIGURED_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "\([^"]*\)"/\1/p' "$APPLE_DIR/project.yml" | head -n 1)"

"$ROOT_DIR/scripts/native-apple-generate.sh"
xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyMac \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  OTHER_SWIFT_FLAGS="-debug-prefix-map $ROOT_DIR=. -file-prefix-map $ROOT_DIR=." \
  build

SOURCE_APP="$DERIVED_DATA/Build/Products/Release/WhereToStudyMac.app"
PACKAGE_APP="$TEMP_DIR/Where To Study.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Native macOS app bundle was not found: $SOURCE_APP" >&2
  exit 1
fi

SOURCE_BINARY="$SOURCE_APP/Contents/MacOS/WhereToStudyMac"
ARCHITECTURES="$(lipo -archs "$SOURCE_BINARY")"
for architecture in arm64 x86_64; do
  if [[ " $ARCHITECTURES " != *" $architecture "* ]]; then
    echo "Native macOS build is missing the $architecture architecture." >&2
    exit 1
  fi
done

ditto "$SOURCE_APP" "$PACKAGE_APP"
PACKAGE_BINARY="$PACKAGE_APP/Contents/MacOS/WhereToStudyMac"
strip -S "$PACKAGE_BINARY"

INFO_PLIST="$PACKAGE_APP/Contents/Info.plist"
ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
ACTUAL_BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
if [[ -n "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "Native macOS package version $ACTUAL_VERSION does not match release label $RELEASE_LABEL." >&2
  exit 1
fi
if [[ -z "$CONFIGURED_BUILD" || "$ACTUAL_BUILD" != "$CONFIGURED_BUILD" ]]; then
  echo "Native macOS package build $ACTUAL_BUILD does not match project build $CONFIGURED_BUILD." >&2
  exit 1
fi

if path_contains_fixed_text "$ROOT_DIR" "$PACKAGE_APP"; then
  echo "Native macOS package contains a local source path." >&2
  exit 1
fi
if path_contains_fixed_text 'http://jwglweixin.bupt.edu.cn' "$PACKAGE_APP"; then
  echo "Native macOS package contains the retired HTTP teaching-system endpoint." >&2
  exit 1
fi
if ! path_contains_fixed_text 'https://jwglweixin.bupt.edu.cn' "$PACKAGE_APP"; then
  echo "Native macOS package is missing the expected HTTPS teaching-system endpoint." >&2
  exit 1
fi
if [[ ! -f "$PACKAGE_APP/Contents/Resources/PrivacyInfo.xcprivacy" ]]; then
  echo "Native macOS package is missing PrivacyInfo.xcprivacy." >&2
  exit 1
fi
if ! cmp -s "$ROOT_DIR/LICENSE" "$PACKAGE_APP/Contents/Resources/LICENSE"; then
  echo "Native macOS package is missing the exact project license." >&2
  exit 1
fi
for notice in THIRD_PARTY_LICENSES.html THIRD_PARTY_NOTICES.md; do
  if ! cmp -s "$ROOT_DIR/$notice" "$PACKAGE_APP/Contents/Resources/$notice"; then
    echo "Native macOS package is missing the exact $notice file." >&2
    exit 1
  fi
done
plutil -lint "$PACKAGE_APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null

codesign --force --deep --sign - --timestamp=none "$PACKAGE_APP"
codesign --verify --deep --strict --verbose=2 "$PACKAGE_APP"

mkdir -p "$OUTPUT_DIR"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_APP" "$ARCHIVE"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo "Native macOS package ready at:"
echo "  $ARCHIVE"
