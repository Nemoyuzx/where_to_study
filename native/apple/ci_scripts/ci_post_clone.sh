#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  REPOSITORY_ROOT=$CI_PRIMARY_REPOSITORY_PATH
else
  REPOSITORY_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)
fi

APPLE_DIR="$REPOSITORY_ROOT/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Xcode Cloud needs Homebrew to install XcodeGen." >&2
    exit 1
  fi
  echo "Installing XcodeGen for the generated native Apple project..."
  brew install xcodegen
fi

echo "Generating $PROJECT from native/apple/project.yml..."
"$REPOSITORY_ROOT/scripts/native-apple-generate.sh"

if [ ! -f "$PROJECT/project.pbxproj" ]; then
  echo "XcodeGen did not create $PROJECT." >&2
  exit 1
fi

# Fail in the post-clone phase with an actionable log if the shared schemes
# cannot be discovered, instead of letting both platform actions fail later.
xcodebuild -project "$PROJECT" -list >/dev/null
echo "Native Apple project and shared schemes are ready for Xcode Cloud."
