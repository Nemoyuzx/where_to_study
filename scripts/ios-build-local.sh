#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "iOS builds require macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="$HOME/.cargo/bin:$PATH"

cd "$ROOT_DIR"
npm run tauri -- ios build --target aarch64 --features custom-protocol --no-sign --archive-only --ci "$@"
