#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${MACOS_APP_PATH:-$ROOT_DIR/src-tauri/target/release/bundle/macos/Where To Study.app}"
OUTPUT_DIR="${MACOS_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
APP_VERSION="$(node -p "require('$ROOT_DIR/package.json').version")"
RELEASE_LABEL="${1:-v$APP_VERSION}"
ARCHIVE="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-macos-arm64.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "macOS app bundle not found: $APP_PATH" >&2
  echo "Run npm run tauri:build first." >&2
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
