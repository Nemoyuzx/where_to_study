#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLE_DIR="$ROOT_DIR/native/apple"
"$ROOT_DIR/scripts/sync-app-icons.sh"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData"
STRICT_SWIFT_SETTINGS=(
  SWIFT_STRICT_CONCURRENCY=complete
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
)

shutdown_test_simulators() {
  xcrun simctl shutdown all >/dev/null 2>&1 || true
}

select_ios_simulator_udid() {
  local devices preferred fallback selected
  devices="$(xcrun simctl list devices available)"
  preferred="$(awk -F '[()]' '/iPhone 16e/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
    print $2
    exit
  }' <<<"$devices")"
  fallback="$(awk -F '[()]' '/iPhone/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
    print $2
    exit
  }' <<<"$devices")"
  selected="${preferred:-$fallback}"

  if [[ ! "$selected" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    echo "No available iPhone simulator was found." >&2
    printf '%s\n' "$devices" >&2
    return 1
  fi
  printf '%s\n' "$selected"
}

trap shutdown_test_simulators EXIT

"$ROOT_DIR/scripts/native-apple-generate.sh"
IOS_SIMULATOR_UDID="$(select_ios_simulator_udid)"

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
  ENABLE_APP_SANDBOX=NO \
  CODE_SIGN_ENTITLEMENTS= \
  "${STRICT_SWIFT_SETTINGS[@]}" \
  test

xcodebuild \
  -project "$PROJECT" \
  -scheme WhereToStudyiOS \
  -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA/iOS" \
  -retry-tests-on-failure \
  -test-iterations 2 \
  CODE_SIGNING_ALLOWED=NO \
  "${STRICT_SWIFT_SETTINGS[@]}" \
  test
