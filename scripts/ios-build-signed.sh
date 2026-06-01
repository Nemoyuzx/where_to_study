#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "iOS signed builds require macOS." >&2
  exit 1
fi

if [ -z "${APPLE_DEVELOPMENT_TEAM:-}" ]; then
  echo "APPLE_DEVELOPMENT_TEAM is required for signed iOS builds." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="$HOME/.cargo/bin:$PATH"
export IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-release-testing}"

cd "$ROOT_DIR"
npm run tauri -- ios build --target aarch64 --export-method "$IOS_EXPORT_METHOD" --ci "$@"