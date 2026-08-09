#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${MACOS_APP_PATH:-$ROOT_DIR/src-tauri/target/release/bundle/macos/Where To Study.app}"
OUTPUT_DIR="${MACOS_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
APP_VERSION="$(node -p "require('$ROOT_DIR/package.json').version")"
RELEASE_LABEL="${1:-v$APP_VERSION}"
ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-macos-arm64.zip"

if [[ "$RELEASE_LABEL" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)([-+].*)?$ ]] &&
  [[ "${BASH_REMATCH[1]}" != "$APP_VERSION" ]]; then
  echo "Release label $RELEASE_LABEL does not match app version $APP_VERSION." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "macOS app bundle not found: $APP_PATH" >&2
  echo "Run npm run tauri:build first." >&2
  exit 1
fi

if rg --text --fixed-strings --quiet --no-ignore --hidden "$ROOT_DIR" "$APP_PATH"; then
  echo "macOS app bundle contains a local source path." >&2
  exit 1
fi
if rg --text --fixed-strings --quiet 'http://jwglweixin\.bupt\.edu\.cn' "$APP_PATH"; then
  echo "macOS app bundle contains the retired HTTP teaching-system endpoint." >&2
  exit 1
fi
if ! rg --text --fixed-strings --quiet 'https://jwglweixin.bupt.edu.cn' "$APP_PATH"; then
  echo "macOS app bundle is missing the expected HTTPS teaching-system endpoint." >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
if [[ "$ACTUAL_VERSION" != "$APP_VERSION" ]]; then
  echo "macOS app bundle version $ACTUAL_VERSION does not match package version $APP_VERSION." >&2
  exit 1
fi
EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")"
APP_BINARY="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -f "$APP_BINARY" ]] || [[ " $(lipo -archs "$APP_BINARY") " != *" arm64 "* ]]; then
  echo "macOS app bundle is missing its arm64 executable." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
codesign --force --deep --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
TEMP_DIR="$(mktemp -d "$OUTPUT_DIR/.macos-package.XXXXXX")"
TEMP_ARCHIVE="$TEMP_DIR/$(basename "$ARCHIVE")"
(
  cd "$(dirname "$APP_PATH")"
  COPYFILE_DISABLE=1 zip -qry -X "$TEMP_ARCHIVE" "$(basename "$APP_PATH")"
)
mv "$TEMP_ARCHIVE" "$ARCHIVE"
rmdir "$TEMP_DIR"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo "macOS archive ready at:"
echo "  $ARCHIVE"
