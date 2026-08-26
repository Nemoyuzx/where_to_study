#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/package-validation.sh
source "$ROOT_DIR/scripts/package-validation.sh"

npm --prefix "$ROOT_DIR" run licenses:check

OUTPUT_DIR="${LINUX_RELEASE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts}"
BUNDLE_DIR="${LINUX_BUNDLE_DIR:-$ROOT_DIR/src-tauri/target/release/bundle}"
APP_VERSION="$(node -p "require('$ROOT_DIR/package.json').version")"
RELEASE_LABEL="${1:-v$APP_VERSION}"
printf -v LEGACY_CONTEST_HOST '%s.%s.%s.%s' 101 201 29 29
CONTEST_EVENTS_URL="https://where-to-study.cn/api/contest-events"
CONTEST_NOTICES_URL="https://where-to-study.cn/api/contest-notices"
validate_release_label "$RELEASE_LABEL"

MACHINE_ARCHITECTURE="${LINUX_ARCHITECTURE:-$(uname -m)}"
case "$MACHINE_ARCHITECTURE" in
  x86_64)
    DEB_EXPECTED_ARCHITECTURE="amd64"
    RELEASE_ARCHITECTURE="x86_64"
    APPIMAGE_FILE_PATTERN='ELF 64-bit.*x86-64'
    ;;
  aarch64|arm64)
    DEB_EXPECTED_ARCHITECTURE="arm64"
    RELEASE_ARCHITECTURE="aarch64"
    APPIMAGE_FILE_PATTERN='ELF 64-bit.*(ARM aarch64|ARM64)'
    ;;
  *)
    echo "Unsupported Linux release architecture: $MACHINE_ARCHITECTURE" >&2
    exit 1
    ;;
esac

if [[ "$RELEASE_LABEL" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)([-+].*)?$ ]] &&
  [[ "${BASH_REMATCH[1]}" != "$APP_VERSION" ]]; then
  echo "Release label $RELEASE_LABEL does not match app version $APP_VERSION." >&2
  exit 1
fi

require_single_artifact() {
  local directory="$1"
  local pattern="$2"
  local description="$3"
  local -a matches=()

  if [[ -d "$directory" ]]; then
    while IFS= read -r -d '' artifact; do
      matches+=("$artifact")
    done < <(find "$directory" -maxdepth 1 -type f -name "$pattern" -print0)
  fi

  if (( ${#matches[@]} != 1 )); then
    echo "Expected exactly one $description in $directory, found ${#matches[@]}." >&2
    exit 1
  fi
  printf '%s\n' "${matches[0]}"
}

require_exact_legal_files() {
  local extracted_root="$1"
  local legal_file candidate expected_hash actual_hash

  for legal_file in LICENSE THIRD_PARTY_LICENSES.html THIRD_PARTY_NOTICES.md; do
    expected_hash="$(sha256sum "$ROOT_DIR/$legal_file" | cut -d ' ' -f 1)"
    candidate=""
    while IFS= read -r -d '' possible; do
      actual_hash="$(sha256sum "$possible" | cut -d ' ' -f 1)"
      if [[ "$actual_hash" == "$expected_hash" ]]; then
        candidate="$possible"
        break
      fi
    done < <(find "$extracted_root" -type f -name "$legal_file" -print0)

    if [[ -z "$candidate" ]]; then
      echo "Linux bundle is missing the exact $legal_file file." >&2
      exit 1
    fi
  done
}

validate_extracted_bundle() {
  local extracted_root="$1" executable endpoint

  if path_contains_fixed_text "$ROOT_DIR" "$extracted_root"; then
    echo "Linux bundle contains a local source path." >&2
    exit 1
  fi
  if path_contains_fixed_text 'http://jwglweixin.bupt.edu.cn' "$extracted_root"; then
    echo "Linux bundle contains the retired HTTP teaching-system endpoint." >&2
    exit 1
  fi
  if ! path_contains_fixed_text 'https://jwglweixin.bupt.edu.cn' "$extracted_root"; then
    echo "Linux bundle is missing the expected HTTPS teaching-system endpoint." >&2
    exit 1
  fi
  if path_contains_fixed_text "$LEGACY_CONTEST_HOST" "$extracted_root"; then
    echo "Linux bundle contains the retired contest API host." >&2
    exit 1
  fi
  executable="$(find "$extracted_root" -type f \
    \( -name 'where_to_study' -o -name 'where-to-study' \) -print -quit)"
  if [[ -z "$executable" ]]; then
    echo "Linux bundle is missing the Where To Study executable." >&2
    exit 1
  fi
  for endpoint in "$CONTEST_EVENTS_URL" "$CONTEST_NOTICES_URL"; do
    if ! path_contains_fixed_text "$endpoint" "$executable"; then
      echo "Linux executable is missing the HTTPS contest endpoint: $endpoint" >&2
      exit 1
    fi
  done
  require_exact_legal_files "$extracted_root"
}

DEB_PATH="${LINUX_DEB_PATH:-$(require_single_artifact "$BUNDLE_DIR/deb" '*.deb' 'Debian package')}"
APPIMAGE_PATH="${LINUX_APPIMAGE_PATH:-$(require_single_artifact "$BUNDLE_DIR/appimage" '*.AppImage' 'AppImage')}"

case "$RELEASE_ARCHITECTURE" in
  x86_64)
    APPIMAGE_TOOL_ARCH="x86_64"
    APPIMAGE_TOOL_SHA256="a45d3e227bc7f397e9cf6bfa4c9507494efa2293357b6e86690a3de2ca992e79"
    ;;
  aarch64)
    APPIMAGE_TOOL_ARCH="aarch64"
    APPIMAGE_TOOL_SHA256="6fdecf5bf8af4e0db03c6b2a80976acc3c96b6a4d19622fa6c6adfd308378bbc"
    ;;
esac

DEB_VERSION="$(dpkg-deb -f "$DEB_PATH" Version)"
DEB_ARCHITECTURE="$(dpkg-deb -f "$DEB_PATH" Architecture)"
DEB_DEPENDENCIES="$(dpkg-deb -f "$DEB_PATH" Depends)"
if [[ "$DEB_VERSION" != "$APP_VERSION" ]]; then
  echo "Debian package version $DEB_VERSION does not match package version $APP_VERSION." >&2
  exit 1
fi
if [[ "$DEB_ARCHITECTURE" != "$DEB_EXPECTED_ARCHITECTURE" ]]; then
  echo "Debian package architecture must be $DEB_EXPECTED_ARCHITECTURE, got $DEB_ARCHITECTURE." >&2
  exit 1
fi
if ! grep -q 'libwebkit2gtk-4.1-0' <<<"$DEB_DEPENDENCIES"; then
  echo "Debian package is missing the WebKitGTK runtime dependency." >&2
  exit 1
fi
if ! grep -q 'libgtk-3-0' <<<"$DEB_DEPENDENCIES"; then
  echo "Debian package is missing the GTK runtime dependency." >&2
  exit 1
fi
if ! grep -Eq 'lib(ayatana-)?appindicator3-1' <<<"$DEB_DEPENDENCIES"; then
  echo "Debian package is missing the detected app-indicator runtime dependency." >&2
  exit 1
fi
if ! file "$APPIMAGE_PATH" | grep -Eq "$APPIMAGE_FILE_PATTERN"; then
  echo "AppImage does not match $RELEASE_ARCHITECTURE: $APPIMAGE_PATH" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/where-to-study-linux.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR/deb" "$TEMP_DIR/appimage" "$TEMP_DIR/repacked" "$TEMP_DIR/tools"
dpkg-deb -x "$DEB_PATH" "$TEMP_DIR/deb"
validate_extracted_bundle "$TEMP_DIR/deb"

chmod +x "$APPIMAGE_PATH"
(
  cd "$TEMP_DIR/appimage"
  "$APPIMAGE_PATH" --appimage-extract >/dev/null
)
APPDIR="$TEMP_DIR/appimage/squashfs-root"
"$ROOT_DIR/scripts/harden-linux-appimage.sh" "$APPDIR"

APPIMAGE_TOOL="${APPIMAGETOOL_PATH:-}"
if [[ -z "$APPIMAGE_TOOL" ]]; then
  TAURI_TOOL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tauri"
  for candidate in \
    "$TAURI_TOOL_CACHE/linuxdeploy-plugin-appimage.AppImage" \
    "$TAURI_TOOL_CACHE/linuxdeploy-plugin-appimage-$APPIMAGE_TOOL_ARCH.AppImage"; do
    if [[ -f "$candidate" ]] &&
      [[ "$(sha256sum "$candidate" | cut -d ' ' -f 1)" == "$APPIMAGE_TOOL_SHA256" ]]; then
      APPIMAGE_TOOL="$candidate"
      break
    fi
  done
fi
if [[ -z "$APPIMAGE_TOOL" ]]; then
  APPIMAGE_TOOL="$TEMP_DIR/tools/linuxdeploy-plugin-appimage-$APPIMAGE_TOOL_ARCH.AppImage"
  curl --fail --location --retry 3 --output "$APPIMAGE_TOOL" \
    "https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-$APPIMAGE_TOOL_ARCH.AppImage"
fi
if [[ "$(sha256sum "$APPIMAGE_TOOL" | cut -d ' ' -f 1)" != "$APPIMAGE_TOOL_SHA256" ]]; then
  echo "AppImage repack tool checksum does not match the pinned digest." >&2
  exit 1
fi
chmod +x "$APPIMAGE_TOOL"

REPACKED_APPIMAGE="$TEMP_DIR/repacked/Where-To-Study.AppImage"
ARCH="$APPIMAGE_TOOL_ARCH" \
  APPIMAGE_EXTRACT_AND_RUN=1 \
  LDAI_OUTPUT="$REPACKED_APPIMAGE" \
  "$APPIMAGE_TOOL" --appdir "$APPDIR"
if [[ ! -f "$REPACKED_APPIMAGE" ]]; then
  echo "AppImage repack tool did not create $REPACKED_APPIMAGE." >&2
  exit 1
fi
if ! file "$REPACKED_APPIMAGE" | grep -Eq "$APPIMAGE_FILE_PATTERN"; then
  echo "Repacked AppImage does not match $RELEASE_ARCHITECTURE." >&2
  exit 1
fi
chmod +x "$REPACKED_APPIMAGE"

mkdir -p "$TEMP_DIR/repacked-validation"
(
  cd "$TEMP_DIR/repacked-validation"
  "$REPACKED_APPIMAGE" --appimage-extract >/dev/null
)
REPACKED_ROOT="$TEMP_DIR/repacked-validation/squashfs-root"
validate_extracted_bundle "$REPACKED_ROOT"
if find "$REPACKED_ROOT/usr/lib" -maxdepth 1 \( -type f -o -type l \) \
  -name 'libwayland-*.so*' -print -quit | grep -q .; then
  echo "Repacked AppImage still contains host Wayland ABI libraries." >&2
  exit 1
fi
if ! grep -Fq '# Where To Study AppImage host ABI isolation' \
  "$REPACKED_ROOT/apprun-hooks/linuxdeploy-plugin-gtk.sh"; then
  echo "Repacked AppImage is missing the GLib/GIO isolation hook." >&2
  exit 1
fi
APPIMAGE_PATH="$REPACKED_APPIMAGE"

mkdir -p "$OUTPUT_DIR"
DEB_OUTPUT="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-linux-$RELEASE_ARCHITECTURE.deb"
APPIMAGE_OUTPUT="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-linux-$RELEASE_ARCHITECTURE.AppImage"
install -m 0644 "$DEB_PATH" "$DEB_OUTPUT"
install -m 0755 "$APPIMAGE_PATH" "$APPIMAGE_OUTPUT"

for artifact in "$DEB_OUTPUT" "$APPIMAGE_OUTPUT"; do
  (
    cd "$OUTPUT_DIR"
    sha256sum "$(basename "$artifact")" > "$(basename "$artifact").sha256"
  )
done

echo "Linux packages ready at:"
echo "  $DEB_OUTPUT"
echo "  $APPIMAGE_OUTPUT"
