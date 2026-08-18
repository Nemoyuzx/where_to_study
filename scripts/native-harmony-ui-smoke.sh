#!/usr/bin/env bash
# Where To Study 鸿蒙 UI 冒烟测试（hdc + uitest）。
# 对应 iOS 端 native/apple/UITests/PrimaryNavigationSmokeTests 的关键断言：
# 1) 三个一级页面可导航；2) review-demo 示例模式展示本地数据；
# 3) 教学日历日/周/月/年四视图切换。
# 用法：./scripts/native-harmony-ui-smoke.sh [deviceSerial]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
HDC="${SDK_DIR}/default/openharmony/toolchains/hdc"
TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  TARGET="$("${HDC}" list targets | head -1)"
fi
if [[ -z "${TARGET}" ]]; then
  echo "未发现已连接的设备/模拟器。请先在 DevEco Device Manager 中启动模拟器。" >&2
  exit 1
fi
BUNDLE="com.nemoyu.wheretostudy.native.harmony"
HELPER="${ROOT_DIR}/scripts/harmony-ui-helper.py"
LAYOUT_DEV="/data/local/tmp/wts_smoke_layout.json"
LAYOUT_HOST="/tmp/wts_smoke_layout.json"

PASS=0
FAIL=0

dump_layout() {
  "${HDC}" -t "${TARGET}" shell rm -f "${LAYOUT_DEV}" >/dev/null 2>&1 || true
  "${HDC}" -t "${TARGET}" shell uitest dumpLayout -p "${LAYOUT_DEV}" >/dev/null 2>&1
  sleep 1
  "${HDC}" -t "${TARGET}" file recv "${LAYOUT_DEV}" "${LAYOUT_HOST}" >/dev/null 2>&1
}

find_text() {
  # find_text <text> [ymin] [ymax] -> "x1 y1 x2 y2"
  python3 "${HELPER}" "${LAYOUT_HOST}" find "$1" "${2:--1}" "${3:-1000000000}" 2>/dev/null || true
}

assert_text() {
  # assert_text <描述> <text> [ymin] [ymax]
  local bounds attempt
  for attempt in 1 2 3 4; do
    bounds="$(find_text "$2" "${3:--1}" "${4:-1000000000}")"
    if [[ -n "$bounds" ]]; then
      break
    fi
    sleep 1.5
    dump_layout
  done
  if [[ -n "$bounds" ]]; then
    PASS=$((PASS + 1))
    echo "  ✓ $1"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $1（未找到文本：$2）" >&2
  fi
}

swipe_up() {
  # swipe_up：向上滑动一屏（用于查看折叠区域下方的内容）
  "$HDC" -t "$TARGET" shell uitest uiInput swipe 660 2000 660 800 1500 >/dev/null 2>&1
  sleep 1
}

tap_text() {
  # tap_text <text> [ymin] [ymax]
  local bounds x y
  bounds="$(find_text "$1" "${2:--1}" "${3:-1000000000}")"
  if [[ -z "$bounds" ]]; then
    echo "  ✗ 点击失败：未找到文本 $1" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  read -r x1 y1 x2 y2 <<<"$bounds"
  x=$(( (x1 + x2) / 2 ))
  y=$(( (y1 + y2) / 2 ))
  # 底部导航区（ymin >= 2600）的 dump 坐标比可点击区域低约 65px，
  # 点击坐标上移收拢，保证命中标签栏。
  if [[ "${2:--1}" -ge 2600 && "$y" -gt 2740 ]]; then
    y=2740
  fi
  "${HDC}" -t "${TARGET}" shell uitest uiInput click "$x" "$y" >/dev/null 2>&1
  sleep 1
}

launch_app() {
  # launch_app <flag>  flag: uiTesting | reviewDemo
  "${HDC}" -t "${TARGET}" shell aa force-stop "${BUNDLE}" >/dev/null 2>&1 || true
  sleep 1
  "${HDC}" -t "${TARGET}" shell aa start -b "${BUNDLE}" -a EntryAbility "--pb" "$1" true >/dev/null 2>&1
  sleep 4
}

echo "== 鸿蒙 UI 冒烟测试（target: ${TARGET}）=="

echo "[1] 三个一级页面可导航（uiTesting 模式）"
launch_app uiTesting
dump_layout
assert_text "空教室页标题" "联动查询"
tap_text "教学日历" 2600 2800
dump_layout
assert_text "教学日历页" "今天"
tap_text "设置" 2600 2800
dump_layout
assert_text "设置页" "个人账户"
tap_text "空教室" 2600 2800
dump_layout
assert_text "返回空教室页" "联动查询"

echo "[2] review-demo 示例模式展示本地数据"
launch_app reviewDemo
dump_layout
assert_text "示例模式横幅" "示例数据 · 不连接北邮教务服务"
swipe_up
dump_layout
assert_text "示例课表课程" "数据挖掘"
tap_text "设置" 2600 2800
swipe_up
dump_layout
assert_text "示例模式说明" "内置示例模式已开启，不会连接教务服务或读写真实用户数据。"

echo "[3] 教学日历日/周/月/年四视图切换"
launch_app reviewDemo
dump_layout
tap_text "教学日历" 2600 2800
dump_layout
assert_text "周视图标题" "周" 380 620
tap_text "日" 380 620
dump_layout
assert_text "日视图模式按钮" "日" 380 620
tap_text "月" 380 620
dump_layout
assert_text "月视图模式按钮" "月" 380 620
assert_text "月视图星期表头" "一" 480 700
tap_text "年" 380 620
dump_layout
assert_text "年视图说明" "颜色越深表示当天课程越多"
assert_text "年视图一月" "1月"

echo
echo "== 结果：通过 ${PASS}，失败 ${FAIL} =="
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
