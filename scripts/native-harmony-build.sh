#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARMONY_DIR="$ROOT_DIR/native/harmony"
DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app}"
DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/Contents/sdk}"
HVIGOR="${HVIGORW:-$DEVECO_HOME/Contents/tools/hvigor/bin/hvigorw}"
OHPM="${OHPM:-$DEVECO_HOME/Contents/tools/ohpm/bin/ohpm}"
TEST_RESULT="$HARMONY_DIR/entry/.test/default/intermediates/test/coverage_data/test_result.txt"

for executable in "$HVIGOR" "$OHPM"; do
  if [[ ! -x "$executable" ]]; then
    echo "Required DevEco tool is unavailable: $executable" >&2
    exit 1
  fi
done

if [[ ! -f "$DEVECO_SDK_HOME/default/sdk-pkg.json" ]]; then
  echo "HarmonyOS SDK is unavailable under: $DEVECO_SDK_HOME" >&2
  exit 1
fi

export DEVECO_SDK_HOME

cd "$HARMONY_DIR"
"$OHPM" install
"$HVIGOR" assembleHap
"$HVIGOR" test --mode module -p module=entry -p buildMode=test

if [[ ! -f "$TEST_RESULT" ]] || ! grep -Eq 'Tests run: [0-9]+, Failure: 0, Error: 0' "$TEST_RESULT"; then
  echo "HarmonyOS unit-test report is missing or contains failures: $TEST_RESULT" >&2
  exit 1
fi

grep 'Tests run:' "$TEST_RESULT"
