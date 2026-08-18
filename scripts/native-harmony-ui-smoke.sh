#!/usr/bin/env bash
# Where To Study 鸿蒙 UI 冒烟测试（hdc + uitest）。
# 对应 iOS 端 native/apple/UITests/PrimaryNavigationSmokeTests 的关键断言：
# 1) 三个一级页面可导航；2) review-demo 示例模式展示本地数据；
# 3) 教学日历日/周/月/年四视图切换；4) 宽屏（折叠屏展开/2in1/PC）侧栏导航。
# 用法：./scripts/native-harmony-ui-smoke.sh [deviceSerial] [wide|phone]
#   - 不传布局参数时按设备实际布局自动选择手机段/宽屏段（BUG-034 修复）；
#   - 显式传 "wide" 强制宽屏段、"phone" 强制手机段。
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
  # BUG-035 修复：dump/recv 失败时显式报错并返回非零，避免基于过期布局断言。
  "${HDC}" -t "${TARGET}" shell rm -f "${LAYOUT_DEV}" >/dev/null 2>&1 || true
  local out
  out="$("${HDC}" -t "${TARGET}" shell uitest dumpLayout -p "${LAYOUT_DEV}" 2>&1)" || true
  sleep 1
  "${HDC}" -t "${TARGET}" file recv "${LAYOUT_DEV}" "${LAYOUT_HOST}" >/dev/null 2>&1 || true
  if [[ ! -s "${LAYOUT_HOST}" ]]; then
    echo "  ⚠ dumpLayout 失败：${out}" >&2
    return 1
  fi
}

find_text() {
  # find_text <text> [ymin] [ymax] -> "x1 y1 x2 y2"
  python3 "${HELPER}" "${LAYOUT_HOST}" find "$1" "${2:--1}" "${3:-1000000000}" 2>/dev/null || true
}

assert_text() {
  # assert_text <描述> <text> [ymin] [ymax]
  local bounds attempt
  bounds=""
  for attempt in 1 2 3 4; do
    bounds="$(find_text "$2" "${3:--1}" "${4:-1000000000}")"
    if [[ -n "$bounds" ]]; then
      break
    fi
    sleep 1.5
    dump_layout || true
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
  "${HDC}" -t "${TARGET}" shell uitest uiInput swipe 660 2000 660 800 1500 >/dev/null 2>&1
  sleep 1
}

tap_text() {
  # tap_text <text> [ymin] [ymax]
  local bounds x y x1 y1 x2 y2
  bounds="$(find_text "$1" "${2:--1}" "${3:-1000000000}")"
  if [[ -z "$bounds" ]]; then
    echo "  ✗ 点击失败：未找到文本 $1" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  read -r x1 y1 x2 y2 <<<"$bounds"
  x=$(( (x1 + x2) / 2 ))
  y=$(( (y1 + y2) / 2 ))
  # 底部导航区（ymin >= 2600）的 dump 坐标比可点击区域低约 65px（Pura 90 实测），
  # 统一上移修正；不再依赖单设备绝对坐标（BUG-061 修复）。
  if [[ "${2:--1}" -ge 2600 ]]; then
    y=$(( y - 65 ))
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

detect_layout_mode() {
  # 依据首屏是否出现侧栏（BUPT 标题）判定宽屏/手机布局（BUG-034 修复）。
  launch_app reviewDemo
  dump_layout || true
  if [[ -n "$(find_text "BUPT")" ]]; then
    echo "wide"
  else
    echo "phone"
  fi
}

echo "== 鸿蒙 UI 冒烟测试（target: ${TARGET}）=="
MODE="${2:-auto}"
if [[ "${MODE}" == "auto" ]]; then
  MODE="$(detect_layout_mode)"
  echo "== 检测到布局模式：${MODE} =="
fi

if [[ "${MODE}" == "phone" ]]; then
echo "[1] 三个一级页面可导航（uiTesting 模式）"
launch_app uiTesting
dump_layout || true
assert_text "空教室页标题" "联动查询"
tap_text "教学日历" 2600 2800
dump_layout || true
assert_text "教学日历页" "今天"
tap_text "设置" 2600 2800
dump_layout || true
assert_text "设置页" "个人账户"
tap_text "空教室" 2600 2800
dump_layout || true
assert_text "返回空教室页" "联动查询"

echo "[2] review-demo 示例模式展示本地数据"
launch_app reviewDemo
dump_layout || true
assert_text "示例模式横幅" "示例数据 · 不连接北邮教务服务"
swipe_up
dump_layout || true
assert_text "示例课表课程" "数据挖掘"
tap_text "设置" 2600 2800
swipe_up
dump_layout || true
assert_text "示例模式说明" "内置示例模式已开启，不会连接教务服务或读写真实用户数据。"

echo "[3] 教学日历日/周/月/年四视图切换"
launch_app reviewDemo
dump_layout || true
tap_text "教学日历" 2600 2800
dump_layout || true
assert_text "周视图标题" "周" 380 620
tap_text "日" 380 620
dump_layout || true
assert_text "日视图模式按钮" "日" 380 620
tap_text "月" 380 620
dump_layout || true
assert_text "月视图模式按钮" "月" 380 620
assert_text "月视图星期表头" "一" 480 700
tap_text "年" 380 620
dump_layout || true
assert_text "年视图说明" "颜色越深表示当天课程越多"
assert_text "年视图一月" "1月"
fi

if [[ "${MODE}" == "wide" ]]; then
echo "[4] 宽屏（折叠屏展开/2in1/PC）侧栏导航"
launch_app reviewDemo
dump_layout || true
assert_text "侧栏标题 BUPT" "BUPT"
assert_text "侧栏应用名" "Where To Study"
tap_text "教学日历" 100 1000
dump_layout || true
assert_text "日历页（宽屏详情区）" "今天"
tap_text "设置" 100 1000
dump_layout || true
assert_text "设置页" "个人账户"
tap_text "空教室" 100 1000
dump_layout || true
assert_text "返回空教室页" "联动查询"
fi

echo
echo "== 结果：通过 ${PASS}，失败 ${FAIL} =="
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
