#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE_DIR="$ROOT_DIR/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData"

"$ROOT_DIR/scripts/native-apple-generate.sh"

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyMac \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA/macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyMac \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA/tests" \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyiOS \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA/iOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
