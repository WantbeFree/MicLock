#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/MicLock.xcodeproj"
SCHEME="MicLock"
INFO_PLIST="$ROOT_DIR/MicLock/Info.plist"
DERIVED_DATA="$ROOT_DIR/build/ReleaseDerivedData"
PACKAGE_DIR="$ROOT_DIR/build/ReleasePackage"
NO_BUMP=0
UNSIGNED=0
SKIP_NOTARIZATION=0

usage() {
  echo "Usage: scripts/build_release.sh [--no-bump] [--unsigned] [--skip-notarization]" >&2
  echo "" >&2
  echo "Signed releases require DEVELOPER_ID_APPLICATION plus either NOTARYTOOL_PROFILE" >&2
  echo "or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-bump)
      NO_BUMP=1
      ;;
    --unsigned)
      UNSIGNED=1
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
  shift
done

if [[ "$UNSIGNED" -eq 1 ]]; then
  SKIP_NOTARIZATION=1
fi

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
version_was_bumped=0

restore_version_on_failure() {
  local status=$?

  if [[ "$status" -ne 0 && "$version_was_bumped" -eq 1 ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $current_version" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $current_build" "$INFO_PLIST" || true
    echo "Release failed; restored Info.plist to $current_version ($current_build)." >&2
  fi

  exit "$status"
}

trap restore_version_on_failure EXIT

require_signing_configuration() {
  if [[ "$UNSIGNED" -eq 1 ]]; then
    return
  fi

  if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "Missing DEVELOPER_ID_APPLICATION. Use --unsigned only for local test builds." >&2
    exit 65
  fi

  if [[ "$SKIP_NOTARIZATION" -eq 1 ]]; then
    return
  fi

  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    return
  fi

  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "Missing notarization credentials. Set NOTARYTOOL_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
    exit 65
  fi
}

create_zip() {
  rm -f "$PACKAGE_ZIP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_APP" "$PACKAGE_ZIP"
}

notarytool_submit() {
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    /usr/bin/xcrun notarytool submit "$PACKAGE_ZIP" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  else
    /usr/bin/xcrun notarytool submit "$PACKAGE_ZIP" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
  fi
}

require_signing_configuration

"$ROOT_DIR/scripts/generate_app_icon.sh"

if [[ "$NO_BUMP" -eq 1 ]]; then
  next_version="$current_version"
  next_build="$current_build"
else
  IFS='.' read -r major minor patch <<< "$current_version"
  if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
    echo "Unsupported version format: $current_version" >&2
    exit 1
  fi

  if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
    echo "Unsupported version format: $current_version" >&2
    exit 1
  fi

  if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
    echo "Unsupported build number: $current_build" >&2
    exit 1
  fi

  next_version="$major.$minor.$((patch + 1))"
  next_build="$((current_build + 1))"

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $next_version" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_build" "$INFO_PLIST"
  version_was_bumped=1
fi

/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  clean build

APP_PATH="$DERIVED_DATA/Build/Products/Release/MicLock.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/MicLock"
BUNDLE_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce $APP_PATH" >&2
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE_PLIST")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE_PLIST")"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUNDLE_PLIST")"
binary_arch="$(/usr/bin/file "$BINARY_PATH")"

if [[ "$bundle_id" != "com.wantbefree.miclock" ]]; then
  echo "Unexpected bundle identifier: $bundle_id" >&2
  exit 1
fi

if [[ "$bundle_version" != "$next_version" || "$bundle_build" != "$next_build" ]]; then
  echo "Unexpected version/build: $bundle_version ($bundle_build)" >&2
  exit 1
fi

if [[ "$binary_arch" != *"arm64"* || "$binary_arch" == *"x86_64"* ]]; then
  echo "Unexpected binary architecture: $binary_arch" >&2
  exit 1
fi

mkdir -p "$PACKAGE_DIR"
PACKAGE_APP="$PACKAGE_DIR/MicLock $next_version.app"
if [[ "$UNSIGNED" -eq 1 ]]; then
  PACKAGE_ZIP="$PACKAGE_DIR/MicLock $next_version-macOS-arm64-unsigned.zip"
else
  PACKAGE_ZIP="$PACKAGE_DIR/MicLock $next_version-macOS-arm64.zip"
fi

rm -rf "$PACKAGE_APP" "$PACKAGE_ZIP"
cp -R "$APP_PATH" "$PACKAGE_APP"

if [[ "$UNSIGNED" -eq 0 ]]; then
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$PACKAGE_APP"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$PACKAGE_APP"
fi

create_zip

if [[ "$UNSIGNED" -eq 0 && "$SKIP_NOTARIZATION" -eq 0 ]]; then
  notarytool_submit
  /usr/bin/xcrun stapler staple "$PACKAGE_APP"
  /usr/bin/xcrun stapler validate "$PACKAGE_APP"
  create_zip
fi

echo "Release built successfully:"
echo "  Version: $next_version (build $next_build)"
echo "  App: $PACKAGE_APP"
echo "  Zip: $PACKAGE_ZIP"
if [[ "$UNSIGNED" -eq 1 ]]; then
  echo "  Signing: unsigned local test package"
elif [[ "$SKIP_NOTARIZATION" -eq 1 ]]; then
  echo "  Signing: Developer ID signed, notarization skipped"
else
  echo "  Signing: Developer ID signed and notarized"
fi

trap - EXIT
