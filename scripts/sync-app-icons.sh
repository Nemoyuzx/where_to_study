#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/src-tauri/icons/icon.png"
TAURI_ICONS_DIR="$ROOT_DIR/src-tauri/icons"
APPLE_ICONSET_DIR="$ROOT_DIR/native/apple/Resources/Assets.xcassets/AppIcon.appiconset"
TAURI_APPLE_ICONSET_DIR="$ROOT_DIR/src-tauri/gen/apple/Assets.xcassets/AppIcon.appiconset"
ALPHA_STRIPPER="$ROOT_DIR/scripts/strip-png-alpha.swift"
ANDROID_RES_DIR="$ROOT_DIR/native/android/app/src/main/res"
ANDROID_ADAPTIVE_ICON_DIR="$ROOT_DIR/scripts/icon-resources/android"

[[ -s "$SOURCE_ICON" ]] || {
  printf 'Missing canonical app icon: %s\n' "$SOURCE_ICON" >&2
  exit 1
}

for command in node npx; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 1
  }
done

read -r width height < <(node -e '
  const fs = require("node:fs");
  const data = fs.readFileSync(process.argv[1]);
  const pngSignature = "89504e470d0a1a0a";
  if (data.length < 24 || data.subarray(0, 8).toString("hex") !== pngSignature) {
    process.exit(65);
  }
  process.stdout.write(data.readUInt32BE(16) + " " + data.readUInt32BE(20) + "\n");
' "$SOURCE_ICON")
[[ "$width" == "$height" && "$width" -ge 512 ]] || {
  printf 'Canonical app icon must be a square PNG of at least 512 px.\n' >&2
  exit 1
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/where-to-study-icons.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

npx tauri icon "$SOURCE_ICON" --output "$tmp_dir/generated"

sync_file() {
  local source="$1"
  local destination="$2"

  if [[ ! -f "$destination" ]] || ! cmp -s "$source" "$destination"; then
    cp "$source" "$destination"
  fi
}

sync_icns() {
  local source="$1"
  local destination="$2"
  local generated_preview="$tmp_dir/generated-icns-preview.png"
  local current_preview="$tmp_dir/current-icns-preview.png"

  if [[ -f "$destination" ]] \
    && sips -s format png "$source" --out "$generated_preview" >/dev/null \
    && sips -s format png "$destination" --out "$current_preview" >/dev/null \
    && cmp -s "$generated_preview" "$current_preview"; then
    return
  fi
  cp "$source" "$destination"
}

for filename in 32x32.png 128x128.png 128x128@2x.png icon.ico; do
  sync_file "$tmp_dir/generated/$filename" "$TAURI_ICONS_DIR/$filename"
done

if [[ "$(uname -s)" == "Darwin" ]]; then
  for command in sips xcrun; do
    command -v "$command" >/dev/null 2>&1 || {
      printf 'Required Apple icon command is unavailable: %s\n' "$command" >&2
      exit 1
    }
  done

  sync_icns "$tmp_dir/generated/icon.icns" "$TAURI_ICONS_DIR/icon.icns"

  mkdir -p "$APPLE_ICONSET_DIR" "$TAURI_APPLE_ICONSET_DIR"
  generated_apple_icons=("$tmp_dir/generated/ios/"*.png)
  xcrun swift "$ALPHA_STRIPPER" "${generated_apple_icons[@]}"
  for source in "${generated_apple_icons[@]}"; do
    filename="$(basename "$source")"
    sync_file "$source" "$APPLE_ICONSET_DIR/$filename"
    sync_file "$source" "$TAURI_APPLE_ICONSET_DIR/$filename"
  done
else
  printf 'Apple ICNS and opaque AppIcon synchronization requires macOS; preserving committed Apple resources.\n'
fi

for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  destination="$ANDROID_RES_DIR/mipmap-$density"
  mkdir -p "$destination"
  for source in "$tmp_dir/generated/android/mipmap-$density/"*.png; do
    sync_file "$source" "$destination/$(basename "$source")"
  done
done
mkdir -p "$ANDROID_RES_DIR/drawable" "$ANDROID_RES_DIR/mipmap-anydpi-v26" "$ANDROID_RES_DIR/values"
sync_file "$ANDROID_ADAPTIVE_ICON_DIR/ic_launcher_foreground_safe.xml" \
  "$ANDROID_RES_DIR/drawable/ic_launcher_foreground_safe.xml"
for filename in ic_launcher.xml ic_launcher_round.xml; do
  sync_file "$ANDROID_ADAPTIVE_ICON_DIR/$filename" \
    "$ANDROID_RES_DIR/mipmap-anydpi-v26/$filename"
done
sync_file "$tmp_dir/generated/android/values/ic_launcher_background.xml" \
  "$ANDROID_RES_DIR/values/ic_launcher_background.xml"

printf 'Synchronized app icons from %s (%sx%s).\n' \
  "$SOURCE_ICON" "$width" "$height"
