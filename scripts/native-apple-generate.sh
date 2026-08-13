#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE_DIR="$ROOT_DIR/native/apple"
DERIVED_DATA="$APPLE_DIR/DerivedData"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

mkdir -p "$DERIVED_DATA"
touch "$DERIVED_DATA/.metadata_never_index"
xcodegen generate --spec "$APPLE_DIR/project.yml" --project "$APPLE_DIR"
