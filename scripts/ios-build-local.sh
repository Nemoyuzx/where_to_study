#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "iOS builds require macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="$HOME/.cargo/bin:$PATH"
# Tauri validates this field before applying --no-sign. The placeholder is never
# used for signing and can be overridden when a real development team is set.
export APPLE_DEVELOPMENT_TEAM="${APPLE_DEVELOPMENT_TEAM:-AAAAAAAAAA}"

cd "$ROOT_DIR"
npm run tauri -- ios build --target aarch64 --features custom-protocol --no-sign --archive-only --ci "$@"
