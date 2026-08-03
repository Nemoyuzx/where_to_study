#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE_DIR="$ROOT_DIR/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData/release-iOS"
OUTPUT_DIR="${NATIVE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
RELEASE_LABEL="${1:-v0.1.1-native-preview}"
ARCHIVE_PATH="$DERIVED_DATA/WhereToStudyiOS.xcarchive"
PACKAGE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-native-ios-unsigned.xcarchive.zip"

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
plutil -lint "$APP/Info.plist" "$APP/PrivacyInfo.xcprivacy" >/dev/null
if [[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$APP/Info.plist")" != "false" ]]; then
  echo "Native iOS archive does not declare ITSAppUsesNonExemptEncryption=false." >&2
  exit 1
fi

while IFS= read -r -d '' relocation_file; do
  RELEASE_SOURCE_ROOT="$ROOT_DIR" perl -0pi -e 's/\Q$ENV{RELEASE_SOURCE_ROOT}\E/./g' "$relocation_file"
done < <(find "$ARCHIVE_PATH/dSYMs" -type f -path '*/Relocations/*' -name '*.yml' -print0 2>/dev/null)

if rg --text --fixed-strings --quiet --no-ignore --hidden "$ROOT_DIR" "$ARCHIVE_PATH"; then
  echo "Native iOS archive contains a local source path." >&2
  exit 1
fi
if rg --text --fixed-strings --quiet 'http://jwglweixin\.bupt\.edu\.cn' "$ARCHIVE_PATH"; then
  echo "Native iOS archive contains the retired HTTP teaching-system endpoint." >&2
  exit 1
fi
if ! rg --text --fixed-strings --quiet 'https://jwglweixin.bupt.edu.cn' "$ARCHIVE_PATH"; then
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
