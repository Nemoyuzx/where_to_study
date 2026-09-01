#!/usr/bin/env bash
# Where To Study 鸿蒙 UI 冒烟测试（hdc + uitest）。
# 对应 iOS 端 native/apple/UITests/PrimaryNavigationSmokeTests 的关键断言：
# 1) 三个一级页面可导航；2) review-demo 示例模式展示本地数据；
# 3) 设置页账号/密码触摸聚焦与输入；4) 教学日历日/周/月/年四视图切换；
# 5) 宽屏（折叠屏展开/2in1/PC）侧栏导航。
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
BUNDLE="com.nemoyu.wheretostudy"
HELPER="${ROOT_DIR}/scripts/harmony-ui-helper.py"
LAYOUT_DEV="/data/local/tmp/wts_smoke_layout.json"
LAYOUT_HOST="/tmp/wts_smoke_layout.json"

PASS=0
FAIL=0

display_metrics() {
  "${HDC}" -t "${TARGET}" shell hidumper -s DisplayManagerService -a -a 2>/dev/null |
    awk -F ':' '
      $1 ~ /^[[:space:]]*Width$/ { gsub(/[[:space:]]/, "", $2); width=$2 }
      $1 ~ /^[[:space:]]*Height$/ { gsub(/[[:space:]]/, "", $2); height=$2 }
      $1 ~ /^[[:space:]]*DensityInCurResolution$/ { gsub(/[[:space:]]/, "", $2); density=$2 }
      END { if (width != "" && height != "" && density != "") print width, height, density }
    '
}

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

find_id() {
  # find_id <id> -> "x1 y1 x2 y2"
  python3 "${HELPER}" "${LAYOUT_HOST}" find-id "$1" 2>/dev/null || true
}

attr_by_id() {
  # attr_by_id <id> <attribute>
  python3 "${HELPER}" "${LAYOUT_HOST}" attr-id "$1" "$2" 2>/dev/null || true
}

assert_text() {
  # assert_text <描述> <text> [ymin] [ymax]
  local bounds
  bounds=""
  for _ in 1 2 3 4; do
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
  local width height density x start_y end_y
  read -r width height density <<<"$(display_metrics)"
  x=$(( width / 2 ))
  start_y=$(( height * 78 / 100 ))
  end_y=$(( height * 35 / 100 ))
  "${HDC}" -t "${TARGET}" shell uitest uiInput swipe "$x" "$start_y" "$x" "$end_y" 1500 \
    >/dev/null 2>&1
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
  "${HDC}" -t "${TARGET}" shell uitest uiInput click "$x" "$y" >/dev/null 2>&1
  sleep 1
}

tap_id() {
  # tap_id <id>
  local bounds x y x1 y1 x2 y2
  bounds="$(find_id "$1")"
  if [[ -z "$bounds" ]]; then
    echo "  ✗ 点击失败：未找到 ID $1" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  read -r x1 y1 x2 y2 <<<"$bounds"
  x=$(( (x1 + x2) / 2 ))
  y=$(( (y1 + y2) / 2 ))
  "${HDC}" -t "${TARGET}" shell uitest uiInput click "$x" "$y" >/dev/null 2>&1
  sleep 1
}

assert_id_attr() {
  # assert_id_attr <描述> <id> <attribute> <expected>
  local actual
  dump_layout || true
  actual="$(attr_by_id "$2" "$3")"
  if [[ "$actual" == "$4" ]]; then
    PASS=$((PASS + 1))
    echo "  ✓ $1"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $1（$2.$3：期望 $4，实际 ${actual:-<空>}）" >&2
  fi
}

assert_phone_navigation_bottom_clearance() {
  local width height density id bounds x1 y1 x2 y2 clearance failed
  read -r width height density <<<"$(display_metrics)"
  if [[ -z "${height:-}" || -z "${density:-}" ]]; then
    FAIL=$((FAIL + 1))
    echo "  ✗ 无法读取屏幕高度或像素密度" >&2
    return
  fi
  failed=0
  for id in navigation.planner navigation.calendar navigation.query navigation.settings; do
    bounds="$(find_id "$id")"
    if [[ -z "$bounds" ]]; then
      failed=1
      continue
    fi
    read -r x1 y1 x2 y2 <<<"$bounds"
    clearance="$(awk -v screen="$height" -v bottom="$y2" -v scale="$density" \
      'BEGIN { printf "%.2f", (screen - bottom) / scale }')"
    if ! awk -v value="$clearance" 'BEGIN { exit !(value >= 28) }'; then
      echo "  ✗ $id 底部净空仅 ${clearance}vp（要求 >= 28vp）" >&2
      failed=1
    fi
  done
  if [[ "$failed" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "  ✓ 四个手机导航控件底部净空均不小于 28vp"
  else
    FAIL=$((FAIL + 1))
  fi
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
assert_phone_navigation_bottom_clearance
tap_id "navigation.calendar"
dump_layout || true
assert_text "教学日历页" "今天"
tap_id "navigation.settings"
dump_layout || true
assert_text "设置页" "个人账户"
tap_id "navigation.planner"
dump_layout || true
assert_text "返回空教室页" "联动查询"

echo "[2] review-demo 示例模式展示本地数据"
launch_app reviewDemo
dump_layout || true
assert_text "示例模式横幅" "示例数据 · 不连接北邮教务服务"
swipe_up
dump_layout || true
assert_text "示例课表课程" "数据挖掘"
tap_id "navigation.settings"
swipe_up
dump_layout || true
assert_text "本地安全存储说明" "账号和密码仅保存于本机，并由 HarmonyOS ASSET 安全存储保护。"

echo "[3] 设置页账号与密码可触摸聚焦并输入"
launch_app uiTestingLive
dump_layout || true
tap_id "navigation.settings"
dump_layout || true
tap_id "settings_account_input"
assert_id_attr "学号输入框获得焦点" "settings_account_input" "focused" "true"
"${HDC}" -t "${TARGET}" shell uitest uiInput text 2026000000 >/dev/null 2>&1
assert_id_attr "学号输入框可输入" "settings_account_input" "text" "2026000000"
tap_id "settings_password_input"
assert_id_attr "密码输入框获得焦点" "settings_password_input" "focused" "true"

echo "[4] 教学日历日/周/月/年四视图切换"
launch_app reviewDemo
dump_layout || true
tap_id "navigation.calendar"
dump_layout || true
assert_text "周视图标题" "周"
tap_text "日"
dump_layout || true
assert_text "日视图模式按钮" "日"
tap_text "月"
dump_layout || true
assert_text "月视图模式按钮" "月"
assert_text "月视图星期表头" "一"
tap_text "年"
dump_layout || true
assert_text "年视图说明" "颜色越深表示当天日程越多"
assert_text "年视图一月" "1月"
fi

if [[ "${MODE}" == "wide" ]]; then
echo "[5] 宽屏（折叠屏展开/2in1/PC）侧栏导航"
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
