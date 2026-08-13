#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/scripts/sync-app-icons.sh"
ANDROID_DIR="$ROOT_DIR/native/android"
GRADLEW="$ANDROID_DIR/gradlew"

cleanup() {
  "$GRADLEW" --project-dir "$ANDROID_DIR" --stop >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if [[ ! -x "$GRADLEW" ]]; then
  echo "Missing native Android Gradle wrapper. Run the repository bootstrap first." >&2
  exit 1
fi

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

"$GRADLEW" --project-dir "$ANDROID_DIR" \
  testDebugUnitTest \
  lintDebug \
  assembleDebug \
  assembleDebugAndroidTest
