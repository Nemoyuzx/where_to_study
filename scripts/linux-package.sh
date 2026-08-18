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
validate_release_label "$RELEASE_LABEL"

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
  local extracted_root="$1"

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
  require_exact_legal_files "$extracted_root"
}

DEB_PATH="${LINUX_DEB_PATH:-$(require_single_artifact "$BUNDLE_DIR/deb" '*.deb' 'Debian package')}"
APPIMAGE_PATH="${LINUX_APPIMAGE_PATH:-$(require_single_artifact "$BUNDLE_DIR/appimage" '*.AppImage' 'AppImage')}"

DEB_VERSION="$(dpkg-deb -f "$DEB_PATH" Version)"
DEB_ARCHITECTURE="$(dpkg-deb -f "$DEB_PATH" Architecture)"
if [[ "$DEB_VERSION" != "$APP_VERSION" ]]; then
  echo "Debian package version $DEB_VERSION does not match package version $APP_VERSION." >&2
  exit 1
fi
if [[ "$DEB_ARCHITECTURE" != "amd64" ]]; then
  echo "Debian package architecture must be amd64, got $DEB_ARCHITECTURE." >&2
  exit 1
fi
if ! file "$APPIMAGE_PATH" | grep -Eq 'ELF 64-bit.*x86-64'; then
  echo "AppImage is not an x86-64 ELF executable: $APPIMAGE_PATH" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/where-to-study-linux.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR/deb" "$TEMP_DIR/appimage"
dpkg-deb -x "$DEB_PATH" "$TEMP_DIR/deb"
validate_extracted_bundle "$TEMP_DIR/deb"

chmod +x "$APPIMAGE_PATH"
(
  cd "$TEMP_DIR/appimage"
  "$APPIMAGE_PATH" --appimage-extract >/dev/null
)
validate_extracted_bundle "$TEMP_DIR/appimage/squashfs-root"

mkdir -p "$OUTPUT_DIR"
DEB_OUTPUT="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-linux-x86_64.deb"
APPIMAGE_OUTPUT="$OUTPUT_DIR/Where-To-Study-$RELEASE_LABEL-linux-x86_64.AppImage"
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
