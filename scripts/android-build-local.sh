#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_NAME="$(uname -s)"
DEFAULT_ANDROID_HOME="$HOME/Library/Android/sdk"
DEFAULT_NDK_VERSION="27.2.12479018"
DEFAULT_JAVA_HOME="${JAVA_HOME:-}"

case "$OS_NAME" in
  Darwin)
    HOST_TAG="darwin-x86_64"
    if [ -z "$DEFAULT_JAVA_HOME" ] && [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
      DEFAULT_JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    fi
    ;;
  Linux)
    HOST_TAG="linux-x86_64"
    ;;
  *)
    echo "Unsupported host OS: $OS_NAME" >&2
    exit 1
    ;;
esac

export ANDROID_HOME="${ANDROID_HOME:-$DEFAULT_ANDROID_HOME}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/${ANDROID_NDK_VERSION:-$DEFAULT_NDK_VERSION}}"
export NDK_HOME="${NDK_HOME:-$ANDROID_NDK_HOME}"
export JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"

if [ -z "$JAVA_HOME" ] || [ ! -d "$JAVA_HOME" ]; then
  echo "Set JAVA_HOME or install Android Studio so the bundled JBR can be used." >&2
  exit 1
fi

LLVM_PREBUILT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin"

if [ ! -d "$ANDROID_NDK_HOME" ]; then
  echo "Android NDK not found at $ANDROID_NDK_HOME" >&2
  exit 1
fi

if [ ! -d "$LLVM_PREBUILT" ]; then
  echo "Android NDK LLVM toolchain not found at $LLVM_PREBUILT" >&2
  exit 1
fi

export PATH="$JAVA_HOME/bin:$HOME/.cargo/bin:$LLVM_PREBUILT:$PATH"

cd "$ROOT_DIR"
npm run tauri -- android build --target aarch64 --apk --ci "$@"