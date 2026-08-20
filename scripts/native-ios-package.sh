#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/package-validation.sh
source "$ROOT_DIR/scripts/package-validation.sh"
"$ROOT_DIR/scripts/sync-app-icons.sh"
npm --prefix "$ROOT_DIR" run licenses:check
APPLE_DIR="$ROOT_DIR/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData/release-iOS"
OUTPUT_DIR="${NATIVE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
RELEASE_LABEL="${1:-v0.1.7}"
ARCHIVE_PATH="$DERIVED_DATA/WhereToStudyiOS.xcarchive"
PACKAGE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-ios-unsigned.xcarchive.zip"
validate_release_label "$RELEASE_LABEL"

if [[ "$RELEASE_LABEL" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)([-+].*)?$ ]]; then
  EXPECTED_VERSION="${BASH_REMATCH[1]}"
else
  EXPECTED_VERSION=""
fi
CONFIGURED_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "\([^"]*\)"/\1/p' "$APPLE_DIR/project.yml" | head -n 1)"
EXPECTED_BUNDLE_IDENTIFIER="com.nemoyu.wheretostudy.native.macos"

"$ROOT_DIR/scripts/native-apple-generate.sh"
rm -rf "$ARCHIVE_PATH"

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyiOS \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  OTHER_SWIFT_FLAGS="-debug-prefix-map $ROOT_DIR=. -file-prefix-map $ROOT_DIR=." \
  archive

APP="$ARCHIVE_PATH/Products/Applications/WhereToStudyiOS.app"
if [[ ! -d "$APP" ]]; then
  echo "Native iOS archive does not contain WhereToStudyiOS.app." >&2
  exit 1
fi
WIDGET="$APP/PlugIns/WhereToStudyiOSWidget.appex"
if [[ ! -d "$WIDGET" ]]; then
  echo "Native iOS archive is missing the WidgetKit extension." >&2
  exit 1
fi
if [[ "$(plutil -extract CFBundleIdentifier raw "$WIDGET/Info.plist")" \
  != "com.nemoyu.wheretostudy.native.macos.widget" ]]; then
  echo "Native iOS WidgetKit extension has the wrong bundle identifier." >&2
  exit 1
fi
if [[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$WIDGET/Info.plist")" \
  != "com.apple.widgetkit-extension" ]]; then
  echo "Native iOS archive does not contain a WidgetKit extension point." >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "$APP/WhereToStudyiOS")"
if [[ " $ARCHITECTURES " != *" arm64 "* ]]; then
  echo "Native iOS archive is missing the arm64 architecture." >&2
  exit 1
fi

if [[ ! -f "$APP/Assets.car" ]]; then
  echo "Native iOS archive is missing the compiled app icon catalog." >&2
  exit 1
fi
if [[ ! -f "$APP/PrivacyInfo.xcprivacy" ]]; then
  echo "Native iOS archive is missing PrivacyInfo.xcprivacy." >&2
  exit 1
fi
if ! cmp -s "$ROOT_DIR/LICENSE" "$APP/LICENSE"; then
  echo "Native iOS archive is missing the exact project license." >&2
  exit 1
fi
for notice in THIRD_PARTY_LICENSES.html THIRD_PARTY_NOTICES.md; do
  if ! cmp -s "$ROOT_DIR/$notice" "$APP/$notice"; then
    echo "Native iOS archive is missing the exact $notice file." >&2
    exit 1
  fi
done
plutil -lint "$APP/Info.plist" "$APP/PrivacyInfo.xcprivacy" >/dev/null
ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")"
ACTUAL_BUILD="$(plutil -extract CFBundleVersion raw "$APP/Info.plist")"
ACTUAL_BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
if [[ "$ACTUAL_BUNDLE_IDENTIFIER" != "$EXPECTED_BUNDLE_IDENTIFIER" ]]; then
  echo "Native iOS archive bundle identifier $ACTUAL_BUNDLE_IDENTIFIER does not match $EXPECTED_BUNDLE_IDENTIFIER." >&2
  exit 1
fi
if [[ -n "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "Native iOS archive version $ACTUAL_VERSION does not match release label $RELEASE_LABEL." >&2
  exit 1
fi
if [[ -z "$CONFIGURED_BUILD" || "$ACTUAL_BUILD" != "$CONFIGURED_BUILD" ]]; then
  echo "Native iOS archive build $ACTUAL_BUILD does not match project build $CONFIGURED_BUILD." >&2
  exit 1
fi
if [[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$APP/Info.plist")" != "false" ]]; then
  echo "Native iOS archive does not declare ITSAppUsesNonExemptEncryption=false." >&2
  exit 1
fi

while IFS= read -r -d '' relocation_file; do
  RELEASE_SOURCE_ROOT="$ROOT_DIR" perl -0pi -e 's/\Q$ENV{RELEASE_SOURCE_ROOT}\E/./g' "$relocation_file"
done < <(find "$ARCHIVE_PATH/dSYMs" -type f -path '*/Relocations/*' -name '*.yml' -print0 2>/dev/null)

if path_contains_fixed_text "$ROOT_DIR" "$ARCHIVE_PATH"; then
  echo "Native iOS archive contains a local source path." >&2
  exit 1
fi
if path_contains_fixed_text 'http://jwglweixin.bupt.edu.cn' "$ARCHIVE_PATH"; then
  echo "Native iOS archive contains the retired HTTP teaching-system endpoint." >&2
  exit 1
fi
if ! path_contains_fixed_text 'https://jwglweixin.bupt.edu.cn' "$ARCHIVE_PATH"; then
  echo "Native iOS archive is missing the expected HTTPS teaching-system endpoint." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
ditto -c -k --sequesterRsrc --keepParent "$ARCHIVE_PATH" "$PACKAGE"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$PACKAGE")" > "$(basename "$PACKAGE").sha256"
)

echo "Unsigned native iOS archive ready at:"
echo "  $PACKAGE"
echo "This archive is for CI and later signing; it is not directly installable on an iPhone."
