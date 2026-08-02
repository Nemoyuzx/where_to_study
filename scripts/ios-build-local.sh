#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "iOS builds require macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/src-tauri/gen/apple/where_to_study.xcodeproj/project.pbxproj"
PROJECT_BACKUP=""

restore_generated_project() {
  if [ -n "$PROJECT_BACKUP" ]; then
    cp "$PROJECT_BACKUP" "$PROJECT_FILE"
    rm -f "$PROJECT_BACKUP"
  fi
}

if [ -f "$PROJECT_FILE" ]; then
  PROJECT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/where-to-study-ios-project.XXXXXX")"
  cp "$PROJECT_FILE" "$PROJECT_BACKUP"
  trap restore_generated_project EXIT
fi

export PATH="$HOME/.cargo/bin:$PATH"
# Tauri validates this field before applying --no-sign. The placeholder is never
# used for signing and can be overridden when a real development team is set.
export APPLE_DEVELOPMENT_TEAM="${APPLE_DEVELOPMENT_TEAM:-AAAAAAAAAA}"

cd "$ROOT_DIR"
npm run tauri -- ios build --target aarch64 --features custom-protocol --no-sign --archive-only --ci "$@"
