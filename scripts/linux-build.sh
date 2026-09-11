#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Cargo's encoded form also handles checkout paths containing spaces. Respect
# its precedence over RUSTFLAGS and retain all caller-supplied flag tokens.
if [[ -n "${CARGO_ENCODED_RUSTFLAGS+x}" ]]; then
  BUILD_RUST_FLAGS="$CARGO_ENCODED_RUSTFLAGS"
else
  BUILD_RUST_FLAGS="$(node -e 'process.stdout.write((process.env.RUSTFLAGS || "").trim().split(/\s+/).filter(Boolean).join("\x1f"))')"
fi
if [[ -n "$BUILD_RUST_FLAGS" ]]; then
  BUILD_RUST_FLAGS+=$'\x1f'
fi
export CARGO_ENCODED_RUSTFLAGS="${BUILD_RUST_FLAGS}--remap-path-prefix=${ROOT_DIR}=."

# Local path dependencies otherwise embed the private checkout directory in
# panic/source-location strings, even in stripped release executables.
exec npm run tauri -- build --features custom-protocol --bundles deb,appimage --ci "$@"
