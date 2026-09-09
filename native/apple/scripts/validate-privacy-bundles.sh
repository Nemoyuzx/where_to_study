#!/usr/bin/env bash
set -euo pipefail

# Check the bundles that will actually run, not only the source manifests.
# App Group defaults must declare 1C8F.1 in both the app and its extension.
platform="${1:-}"
app="${2:-}"
case "$platform" in
  ios)
    app_manifest="$app/PrivacyInfo.xcprivacy"
    widget="$app/PlugIns/WhereToStudyiOSWidget.appex"
    widget_manifest="$widget/PrivacyInfo.xcprivacy"
    ;;
  macos)
    app_manifest="$app/Contents/Resources/PrivacyInfo.xcprivacy"
    widget="$app/Contents/PlugIns/WhereToStudyWidget.appex"
    widget_manifest="$widget/Contents/Resources/PrivacyInfo.xcprivacy"
    ;;
  *)
    echo "Usage: bash validate-privacy-bundles.sh <ios|macos> <application.app>" >&2
    exit 1
    ;;
esac

validate_manifest() {
  local manifest="$1" requires_local_defaults="$2" index=0 reason_index category reason
  local has_group_reason=false has_local_reason=false
  if [[ ! -f "$manifest" ]]; then
    echo "Missing packaged privacy manifest: $manifest" >&2
    return 1
  fi
  plutil -lint "$manifest" >/dev/null
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$manifest")" != "false" ]]; then
    echo "Packaged privacy manifest must disable tracking: $manifest" >&2
    return 1
  fi
  while category="$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPIType" "$manifest" 2>/dev/null)"; do
    if [[ "$category" == "NSPrivacyAccessedAPICategoryUserDefaults" ]]; then
      reason_index=0
      while reason="$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPITypeReasons:$reason_index" "$manifest" 2>/dev/null)"; do
        [[ "$reason" != "1C8F.1" ]] || has_group_reason=true
        [[ "$reason" != "CA92.1" ]] || has_local_reason=true
        reason_index=$((reason_index + 1))
      done
    fi
    index=$((index + 1))
  done
  if [[ "$has_group_reason" != true ]]; then
    echo "Packaged App Group UserDefaults declaration is missing 1C8F.1: $manifest" >&2
    return 1
  fi
  if [[ "$requires_local_defaults" == true && "$has_local_reason" != true ]]; then
    echo "Packaged app UserDefaults declaration is missing CA92.1: $manifest" >&2
    return 1
  fi
}

if [[ ! -d "$app" || ! -d "$widget" ]]; then
  echo "Application and WidgetKit bundles must both exist: $app; $widget" >&2
  exit 1
fi
validate_manifest "$app_manifest" true
validate_manifest "$widget_manifest" false
echo "Validated packaged $platform app and WidgetKit privacy manifests: $app"
