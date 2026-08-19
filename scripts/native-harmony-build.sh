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

# BUG-036：校验所有 src/test/*.test.ets 都已注册进 List.test.ets，防止新增测试漏跑。
for test_file in "$HARMONY_DIR"/entry/src/test/*.test.ets; do
  test_base="$(basename "$test_file" .ets)"
  if [[ "$test_base" == "List.test" ]]; then
    continue
  fi
  if ! grep -q "\./${test_base}'" "$HARMONY_DIR/entry/src/test/List.test.ets"; then
    echo "未注册的测试文件：${test_base}（请在 entry/src/test/List.test.ets 中 import 并调用）" >&2
    exit 1
  fi
done

# BUG-047：AppMeta.version 与 AppScope/app.json5 versionName 一致性校验。
APP_META_VERSION="$(grep -oE "static readonly version: string = '[0-9.]+'" \
  "$HARMONY_DIR/entry/src/main/ets/common/AppMeta.ets" | grep -oE '[0-9.]+' | head -1)"
APP_JSON_VERSION="$(grep -oE '"versionName": "[0-9.]+"' "$HARMONY_DIR/AppScope/app.json5" \
  | grep -oE '[0-9.]+' | head -1)"
if [[ -z "$APP_META_VERSION" || "$APP_META_VERSION" != "$APP_JSON_VERSION" ]]; then
  echo "版本不一致：AppMeta.ets=${APP_META_VERSION}, AppScope/app.json5=${APP_JSON_VERSION}" >&2
  exit 1
fi

cd "$HARMONY_DIR"
"$OHPM" install
"$HVIGOR" assembleHap
"$HVIGOR" test --mode module -p module=entry -p buildMode=test

if [[ ! -f "$TEST_RESULT" ]] || ! grep -Eq 'Tests run: [0-9]+, Failure: 0, Error: 0' "$TEST_RESULT"; then
  echo "HarmonyOS unit-test report is missing or contains failures: $TEST_RESULT" >&2
  exit 1
fi

grep 'Tests run:' "$TEST_RESULT"
