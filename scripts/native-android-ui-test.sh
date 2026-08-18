#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/native/android"
GRADLEW="$ANDROID_DIR/gradlew"

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
AVD_NAME="${ANDROID_UI_TEST_AVD:-Medium_Phone_API_36.1}"
EMULATOR_PORT="${ANDROID_UI_TEST_PORT:-5580}"
EMULATOR_GPU="${ANDROID_UI_TEST_GPU:-host}"
SERIAL="emulator-$EMULATOR_PORT"
ADB_WAS_RUNNING=false
EMULATOR_PID=""

if pgrep -f "$ANDROID_HOME/platform-tools/adb" >/dev/null 2>&1; then
  ADB_WAS_RUNNING=true
fi

cleanup() {
  "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
  if [[ -n "$EMULATOR_PID" ]]; then
    wait "$EMULATOR_PID" >/dev/null 2>&1 || true
  fi
  "$GRADLEW" --project-dir "$ANDROID_DIR" --stop >/dev/null 2>&1 || true
  if [[ "$ADB_WAS_RUNNING" == false ]]; then
    "$ADB" kill-server >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ ! -x "$GRADLEW" || ! -x "$ADB" || ! -x "$EMULATOR" ]]; then
  echo "Android Gradle wrapper, adb, or emulator is unavailable." >&2
  exit 1
fi

if ! "$EMULATOR" -list-avds | grep -Fxq "$AVD_NAME"; then
  echo "Android UI test AVD '$AVD_NAME' is unavailable." >&2
  exit 1
fi

if "$ADB" devices | grep -Fq "$SERIAL"; then
  echo "Emulator port $EMULATOR_PORT is already in use." >&2
  exit 1
fi

UI_TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/where-to-study-android-ui-test.XXXXXX.log")"
"$EMULATOR" "@$AVD_NAME" \
  -port "$EMULATOR_PORT" \
  -wipe-data \
  -no-snapshot \
  -no-window \
  -no-audio \
  -no-boot-anim \
  -gpu "$EMULATOR_GPU" \
  >"$UI_TEST_LOG" 2>&1 &
EMULATOR_PID=$!

"$ADB" -s "$SERIAL" wait-for-device
for _ in $(seq 1 180); do
  if [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 1
done

if [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
  echo "Android emulator did not finish booting within 180 seconds." >&2
  exit 1
fi

"$ADB" -s "$SERIAL" shell settings put global window_animation_scale 0
"$ADB" -s "$SERIAL" shell settings put global transition_animation_scale 0
"$ADB" -s "$SERIAL" shell settings put global animator_duration_scale 0

ANDROID_SERIAL="$SERIAL" "$GRADLEW" \
  --project-dir "$ANDROID_DIR" \
  connectedDebugAndroidTest
