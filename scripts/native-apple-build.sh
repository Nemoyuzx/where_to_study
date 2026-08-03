#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE_DIR="$ROOT_DIR/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData"
STRICT_SWIFT_SETTINGS=(
  SWIFT_STRICT_CONCURRENCY=complete
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
)

shutdown_test_simulators() {
  xcrun simctl shutdown all >/dev/null 2>&1 || true
}

trap shutdown_test_simulators EXIT

"$ROOT_DIR/scripts/native-apple-generate.sh"

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyMac \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA/macOS" \
  CODE_SIGNING_ALLOWED=NO \
  "${STRICT_SWIFT_SETTINGS[@]}" \
  build

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyMac \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA/tests" \
  CODE_SIGNING_ALLOWED=NO \
  "${STRICT_SWIFT_SETTINGS[@]}" \
  test

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyiOS \
  -destination "platform=iOS Simulator,name=iPhone 16e,OS=latest" \
  -derivedDataPath "$DERIVED_DATA/iOS" \
  CODE_SIGNING_ALLOWED=NO \
  "${STRICT_SWIFT_SETTINGS[@]}" \
  test
