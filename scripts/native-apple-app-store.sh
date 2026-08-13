#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/package-validation.sh
source "$ROOT_DIR/scripts/package-validation.sh"
"$ROOT_DIR/scripts/sync-app-icons.sh"

APPLE_DIR="$ROOT_DIR/native/apple"
PROJECT="$APPLE_DIR/WhereToStudyNative.xcodeproj"
DERIVED_DATA="$APPLE_DIR/DerivedData/app-store"
OUTPUT_ROOT="${APPLE_APP_STORE_OUTPUT_DIR:-$ROOT_DIR/release-artifacts/app-store}"
ACTION="${1:-preflight}"
PLATFORM="${2:-all}"
TEAM_ID="${APPLE_DEVELOPMENT_TEAM:-}"
AUTH_KEY_PATH="${APPLE_AUTH_KEY_PATH:-}"
AUTH_KEY_ID="${APPLE_AUTH_KEY_ID:-}"
AUTH_KEY_ISSUER_ID="${APPLE_AUTH_KEY_ISSUER_ID:-}"
IOS_PROFILE_SPECIFIER="${APPLE_IOS_PROFILE_SPECIFIER:-Where To Study iOS App Store}"
MACOS_PROFILE_SPECIFIER="${APPLE_MACOS_PROFILE_SPECIFIER:-Where To Study macOS App Store}"
WIDGET_PROFILE_SPECIFIER="${APPLE_WIDGET_PROFILE_SPECIFIER:-Where To Study Widget App Store}"
INSTALLER_SIGNING_CERTIFICATE="${APPLE_INSTALLER_SIGNING_CERTIFICATE:-}"
MAIN_BUNDLE_IDENTIFIER="com.nemoyu.wheretostudy.native.macos"
WIDGET_BUNDLE_IDENTIFIER="com.nemoyu.wheretostudy.native.macos.widget"
APP_GROUP_IDENTIFIER="group.com.nemoyu.wheretostudy.native"

configured_value() {
  local key="$1"
  sed -n "s/^[[:space:]]*$key: \"\([^\"]*\)\"/\1/p" "$APPLE_DIR/project.yml" | head -n 1
}

VERSION="${APPLE_MARKETING_VERSION:-$(configured_value MARKETING_VERSION)}"
BUILD_NUMBER="${APPLE_BUILD_NUMBER:-$(configured_value CURRENT_PROJECT_VERSION)}"

usage() {
  cat <<'EOF'
Usage: ./scripts/native-apple-app-store.sh <preflight|archive|export|upload> [ios|macos|all]

Required for archive/export/upload:
  APPLE_DEVELOPMENT_TEAM    10-character Apple Developer Team ID

Optional App Store Connect authentication (all three values are required together):
  APPLE_AUTH_KEY_PATH       Path to AuthKey_<KEY_ID>.p8
  APPLE_AUTH_KEY_ID         App Store Connect API key ID
  APPLE_AUTH_KEY_ISSUER_ID  App Store Connect issuer ID

Optional version overrides:
  APPLE_MARKETING_VERSION   Defaults to MARKETING_VERSION in project.yml
  APPLE_BUILD_NUMBER        Defaults to CURRENT_PROJECT_VERSION in project.yml

Optional provisioning profile overrides:
  APPLE_IOS_PROFILE_SPECIFIER     Defaults to Where To Study iOS App Store
  APPLE_MACOS_PROFILE_SPECIFIER   Defaults to Where To Study macOS App Store
  APPLE_WIDGET_PROFILE_SPECIFIER  Defaults to Where To Study Widget App Store

Optional macOS installer signing override:
  APPLE_INSTALLER_SIGNING_CERTIFICATE
    Certificate name or SHA-1 hash. Defaults to the current team's installed
    Mac Installer Distribution identity.
EOF
}

case "$ACTION" in
  preflight|archive|export|upload) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

case "$PLATFORM" in
  ios|macos|all) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APPLE_MARKETING_VERSION must use X.Y.Z format: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "APPLE_BUILD_NUMBER must be a positive integer: $BUILD_NUMBER" >&2
  exit 1
fi

AUTH_ARGUMENTS=()
auth_value_count=0
for value in "$AUTH_KEY_PATH" "$AUTH_KEY_ID" "$AUTH_KEY_ISSUER_ID"; do
  [[ -n "$value" ]] && auth_value_count=$((auth_value_count + 1))
done
if (( auth_value_count != 0 && auth_value_count != 3 )); then
  echo "APPLE_AUTH_KEY_PATH, APPLE_AUTH_KEY_ID and APPLE_AUTH_KEY_ISSUER_ID must be set together." >&2
  exit 1
fi
if (( auth_value_count == 3 )); then
  if [[ ! -f "$AUTH_KEY_PATH" ]]; then
    echo "App Store Connect authentication key was not found: $AUTH_KEY_PATH" >&2
    exit 1
  fi
  AUTH_ARGUMENTS=(
    -authenticationKeyPath "$AUTH_KEY_PATH"
    -authenticationKeyID "$AUTH_KEY_ID"
    -authenticationKeyIssuerID "$AUTH_KEY_ISSUER_ID"
  )
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required." >&2
    exit 1
  fi
}

plist_bool_is_true() {
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true)" == "true" ]]
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

static_preflight() {
  require_command xcodebuild
  require_command xcrun
  require_command xcodegen
  require_command codesign
  require_command plutil

  npm --prefix "$ROOT_DIR" run licenses:check
  plutil -lint \
    "$APPLE_DIR/Resources/PrivacyInfo.xcprivacy" \
    "$APPLE_DIR/Resources/WhereToStudyMac.entitlements" \
    "$APPLE_DIR/Resources/WhereToStudyWidget.entitlements" >/dev/null

  if ! plist_bool_is_true "$APPLE_DIR/Resources/WhereToStudyMac.entitlements" \
    com.apple.security.app-sandbox; then
    echo "The macOS app is missing the App Sandbox entitlement." >&2
    exit 1
  fi
  if ! plist_bool_is_true "$APPLE_DIR/Resources/WhereToStudyMac.entitlements" \
    com.apple.security.network.client; then
    echo "The macOS app is missing outgoing network access." >&2
    exit 1
  fi
  if ! plist_bool_is_true "$APPLE_DIR/Resources/WhereToStudyMac.entitlements" \
    com.apple.security.personal-information.calendars; then
    echo "The macOS app is missing calendar access." >&2
    exit 1
  fi
  if [[ "$(plutil -extract NSPrivacyTracking raw "$APPLE_DIR/Resources/PrivacyInfo.xcprivacy")" != "false" ]]; then
    echo "PrivacyInfo.xcprivacy must explicitly disable tracking." >&2
    exit 1
  fi
  if grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*""' "$APPLE_DIR/project.yml"; then
    echo "project.yml must not override DEVELOPMENT_TEAM with an empty value." >&2
    exit 1
  fi
  for identifier in \
    "$MAIN_BUNDLE_IDENTIFIER" \
    "$WIDGET_BUNDLE_IDENTIFIER" \
    "$APP_GROUP_IDENTIFIER"; do
    if ! grep -Fq "$identifier" "$APPLE_DIR/project.yml" \
      && ! grep -Fq "$identifier" "$APPLE_DIR/Resources/WhereToStudyMac.entitlements" \
      && ! grep -Fq "$identifier" "$APPLE_DIR/Resources/WhereToStudyWidget.entitlements"; then
      echo "Missing required Apple identifier: $identifier" >&2
      exit 1
    fi
  done

  "$ROOT_DIR/scripts/native-apple-generate.sh"
  echo "Apple App Store source preflight passed for version $VERSION ($BUILD_NUMBER)."
}

require_signing_configuration() {
  if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "APPLE_DEVELOPMENT_TEAM must be set to the 10-character team ID." >&2
    exit 1
  fi
  if [[ -z "$AUTH_KEY_PATH" ]] \
    && ! security find-identity -v -p codesigning 2>/dev/null | grep -Eq '[1-9][0-9]* valid identities found'; then
    echo "No local code-signing identity is installed. Xcode automatic signing may create one from the signed-in account; an App Store Connect API key is recommended for CI." >&2
  fi
}

installer_signing_certificate() {
  if [[ -n "$INSTALLER_SIGNING_CERTIFICATE" ]]; then
    printf '%s\n' "$INSTALLER_SIGNING_CERTIFICATE"
    return
  fi
  security find-identity -v -p basic 2>/dev/null | awk -v team="$TEAM_ID" '
    (index($0, "3rd Party Mac Developer Installer:") \
      || index($0, "Mac Installer Distribution:")) \
      && index($0, "(" team ")") { print $2; exit }
  '
}

archive_path() {
  case "$1" in
    ios) printf '%s/ios/WhereToStudyiOS.xcarchive\n' "$DERIVED_DATA" ;;
    macos) printf '%s/macos/WhereToStudyMac.xcarchive\n' "$DERIVED_DATA" ;;
  esac
}

app_path() {
  case "$1" in
    ios) printf '%s/Products/Applications/WhereToStudyiOS.app\n' "$(archive_path ios)" ;;
    macos) printf '%s/Products/Applications/WhereToStudyMac.app\n' "$(archive_path macos)" ;;
  esac
}

validate_archive() {
  local platform="$1" archive app info resources entitlements signature_details actual_identifier actual_version actual_build
  archive="$(archive_path "$platform")"
  app="$(app_path "$platform")"
  if [[ "$platform" == "macos" ]]; then
    info="$app/Contents/Info.plist"
    resources="$app/Contents/Resources"
  else
    info="$app/Info.plist"
    resources="$app"
  fi

  if [[ ! -d "$app" ]]; then
    echo "Archive does not contain its application bundle: $app" >&2
    exit 1
  fi
  codesign --verify --deep --strict --verbose=2 "$app"
  signature_details="$(codesign -dvv "$app" 2>&1)"
  if [[ "$signature_details" == *"Signature=adhoc"* ]]; then
    echo "App Store archive is ad-hoc signed: $app" >&2
    exit 1
  fi
  actual_version="$(plutil -extract CFBundleShortVersionString raw "$info")"
  actual_build="$(plutil -extract CFBundleVersion raw "$info")"
  actual_identifier="$(plutil -extract CFBundleIdentifier raw "$info")"
  if [[ "$actual_identifier" != "$MAIN_BUNDLE_IDENTIFIER" ]]; then
    echo "Archive bundle identifier $actual_identifier does not match $MAIN_BUNDLE_IDENTIFIER." >&2
    exit 1
  fi
  if [[ "$actual_version" != "$VERSION" || "$actual_build" != "$BUILD_NUMBER" ]]; then
    echo "Archive version $actual_version ($actual_build) does not match $VERSION ($BUILD_NUMBER)." >&2
    exit 1
  fi
  if [[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$info")" != "false" ]]; then
    echo "Archive does not declare ITSAppUsesNonExemptEncryption=false." >&2
    exit 1
  fi
  if [[ ! -f "$resources/PrivacyInfo.xcprivacy" ]]; then
    echo "Archive is missing PrivacyInfo.xcprivacy." >&2
    exit 1
  fi
  plutil -lint "$info" "$resources/PrivacyInfo.xcprivacy" >/dev/null
  if ! cmp -s "$ROOT_DIR/LICENSE" "$resources/LICENSE"; then
    echo "Archive is missing the exact GPL-3.0-only license." >&2
    exit 1
  fi
  for notice in THIRD_PARTY_LICENSES.html THIRD_PARTY_NOTICES.md; do
    if ! cmp -s "$ROOT_DIR/$notice" "$resources/$notice"; then
      echo "Archive is missing the exact $notice file." >&2
      exit 1
    fi
  done

  entitlements="$(mktemp "${TMPDIR:-/tmp}/where-to-study-entitlements.plist.XXXXXX")"
  codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
  if [[ "$(plutil -extract get-task-allow raw "$entitlements" 2>/dev/null || true)" == "true" ]]; then
    echo "Archive unexpectedly includes get-task-allow." >&2
    rm -f "$entitlements"
    exit 1
  fi
  if [[ "$platform" == "macos" ]]; then
    local widget widget_entitlements
    if ! plist_bool_is_true "$entitlements" com.apple.security.app-sandbox \
      || ! plist_bool_is_true "$entitlements" com.apple.security.network.client \
      || ! plist_bool_is_true "$entitlements" com.apple.security.personal-information.calendars; then
      echo "Signed macOS archive is missing required sandbox entitlements." >&2
      rm -f "$entitlements"
      exit 1
    fi
    if [[ "$(plutil -extract LSApplicationCategoryType raw "$info")" != "public.app-category.education" ]]; then
      echo "Signed macOS archive has the wrong App Store category." >&2
      rm -f "$entitlements"
      exit 1
    fi
    widget="$app/Contents/PlugIns/WhereToStudyWidget.appex"
    codesign --verify --strict --verbose=2 "$widget"
    if [[ "$(plutil -extract CFBundleIdentifier raw "$widget/Contents/Info.plist")" \
      != "$WIDGET_BUNDLE_IDENTIFIER" ]]; then
      echo "Signed macOS widget has the wrong bundle identifier." >&2
      rm -f "$entitlements"
      exit 1
    fi
    widget_entitlements="$(mktemp "${TMPDIR:-/tmp}/where-to-study-widget-entitlements.plist.XXXXXX")"
    codesign -d --entitlements :- "$widget" > "$widget_entitlements" 2>/dev/null
    for signed_entitlements in "$entitlements" "$widget_entitlements"; do
      if [[ "$(plist_value "$signed_entitlements" 'com.apple.security.application-groups:0')" \
        != "$APP_GROUP_IDENTIFIER" ]]; then
        echo "Signed macOS app and widget must share the registered App Group." >&2
        rm -f "$entitlements" "$widget_entitlements"
        exit 1
      fi
    done
    rm -f "$widget_entitlements"
  fi
  rm -f "$entitlements"
  echo "Validated signed $platform archive: $archive"
}

archive_platform() {
  local platform="$1" scheme destination archive platform_derived
  archive="$(archive_path "$platform")"
  platform_derived="$DERIVED_DATA/$platform/Build"
  case "$platform" in
    ios)
      scheme="WhereToStudyiOS"
      destination="generic/platform=iOS"
      ;;
    macos)
      scheme="WhereToStudyMac"
      destination="generic/platform=macOS"
      ;;
  esac
  rm -rf "$archive" "$platform_derived"
  mkdir -p "$(dirname "$archive")"

  command=(xcodebuild)
  if (( auth_value_count == 3 )); then
    command+=("${AUTH_ARGUMENTS[@]}")
  fi
  command+=(
    -allowProvisioningUpdates
    -project "$PROJECT"
    -scheme "$scheme"
    -configuration Release
    -destination "$destination"
    -archivePath "$archive"
    -derivedDataPath "$platform_derived"
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="Apple Distribution"
    APPLE_IOS_PROFILE_SPECIFIER="$IOS_PROFILE_SPECIFIER"
    APPLE_MACOS_PROFILE_SPECIFIER="$MACOS_PROFILE_SPECIFIER"
    APPLE_WIDGET_PROFILE_SPECIFIER="$WIDGET_PROFILE_SPECIFIER"
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
    SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE_BUILD
    SWIFT_STRICT_CONCURRENCY=complete
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO
    "OTHER_SWIFT_FLAGS=-debug-prefix-map $ROOT_DIR=. -file-prefix-map $ROOT_DIR=."
  )
  if [[ "$platform" == "macos" ]]; then
    command+=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
  fi
  command+=(archive)
  "${command[@]}"
  validate_archive "$platform"
}

write_export_options() {
  local destination="$1" file="$2" platform="$3" main_profile installer_certificate
  if [[ "$platform" == "ios" ]]; then
    main_profile="$IOS_PROFILE_SPECIFIER"
  else
    main_profile="$MACOS_PROFILE_SPECIFIER"
  fi
  plutil -create xml1 "$file"
  plutil -insert method -string app-store-connect "$file"
  plutil -insert destination -string "$destination" "$file"
  plutil -insert signingStyle -string manual "$file"
  plutil -insert signingCertificate -string "Apple Distribution" "$file"
  plutil -insert teamID -string "$TEAM_ID" "$file"
  plutil -insert provisioningProfiles -xml '<dict/>' "$file"
  /usr/libexec/PlistBuddy -c \
    "Add :provisioningProfiles:$MAIN_BUNDLE_IDENTIFIER string $main_profile" "$file"
  if [[ "$platform" == "macos" ]]; then
    installer_certificate="$(installer_signing_certificate)"
    if [[ -z "$installer_certificate" ]]; then
      echo "No Mac Installer Distribution identity was found for team $TEAM_ID." >&2
      echo "Install one or set APPLE_INSTALLER_SIGNING_CERTIFICATE explicitly." >&2
      return 1
    fi
    plutil -insert installerSigningCertificate -string "$installer_certificate" "$file"
    /usr/libexec/PlistBuddy -c \
      "Add :provisioningProfiles:$WIDGET_BUNDLE_IDENTIFIER string $WIDGET_PROFILE_SPECIFIER" "$file"
  fi
  plutil -insert manageAppVersionAndBuildNumber -bool NO "$file"
  plutil -insert uploadSymbols -bool YES "$file"
  plutil -insert stripSwiftSymbols -bool YES "$file"
}

export_or_upload_platform() {
  local platform="$1" destination="$2" archive export_options export_dir extension package_name package_path
  archive="$(archive_path "$platform")"
  export_options="$(mktemp "${TMPDIR:-/tmp}/where-to-study-export.plist.XXXXXX")"
  export_dir="$OUTPUT_ROOT/$VERSION-$BUILD_NUMBER/$platform"
  rm -rf "$export_dir"
  mkdir -p "$export_dir"
  write_export_options "$destination" "$export_options" "$platform"

  command=(xcodebuild)
  if (( auth_value_count == 3 )); then
    command+=("${AUTH_ARGUMENTS[@]}")
  fi
  command+=(
    -allowProvisioningUpdates
    -exportArchive
    -archivePath "$archive"
    -exportPath "$export_dir"
    -exportOptionsPlist "$export_options"
  )
  "${command[@]}"
  rm -f "$export_options"

  if [[ "$destination" == "upload" ]]; then
    echo "Uploaded $platform build $VERSION ($BUILD_NUMBER) to App Store Connect."
    return
  fi

  if [[ "$platform" == "ios" ]]; then
    extension="ipa"
    package_name="Where-To-Study-v$VERSION-build$BUILD_NUMBER-app-store-ios.ipa"
  else
    extension="pkg"
    package_name="Where-To-Study-v$VERSION-build$BUILD_NUMBER-app-store-macos.pkg"
  fi
  package_path="$(find "$export_dir" -maxdepth 2 -type f -name "*.$extension" -print -quit)"
  if [[ -z "$package_path" ]]; then
    echo "Xcode export did not produce a .$extension package." >&2
    exit 1
  fi
  if [[ "$(basename "$package_path")" != "$package_name" ]]; then
    mv "$package_path" "$export_dir/$package_name"
    package_path="$export_dir/$package_name"
  fi
  (
    cd "$export_dir"
    shasum -a 256 "$package_name" > "$package_name.sha256"
  )
  echo "Exported $platform App Store package: $package_path"
}

static_preflight
if [[ "$ACTION" == "preflight" ]]; then
  if [[ -z "$TEAM_ID" ]]; then
    echo "Signing status: APPLE_DEVELOPMENT_TEAM is not configured; signed archive and upload were not attempted."
  else
    echo "Signing status: team $TEAM_ID is configured."
  fi
  exit 0
fi

require_signing_configuration
if [[ "$PLATFORM" == "all" ]]; then
  PLATFORMS=(ios macos)
else
  PLATFORMS=("$PLATFORM")
fi
for current_platform in "${PLATFORMS[@]}"; do
  archive_platform "$current_platform"
  case "$ACTION" in
    export) export_or_upload_platform "$current_platform" export ;;
    upload) export_or_upload_platform "$current_platform" upload ;;
  esac
done
