#!/usr/bin/env bash
set -euo pipefail

MODE=""
SHOULD_LAUNCH=0

for argument in "$@"; do
  case "$argument" in
    --public)
      MODE="public"
      ;;
    --launch)
      SHOULD_LAUNCH=1
      ;;
    --no-launch)
      SHOULD_LAUNCH=0
      ;;
    *)
      echo "usage: $0 --public [--launch|--no-launch]" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "The public release mode must be selected with --public." >&2
  exit 2
fi

APP_NAME="Nudge"
VERSION="0.1.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData-Release-$MODE"
ARCHIVE_PATH="$ROOT_DIR/.build/Archives/$APP_NAME-$MODE.xcarchive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/.build/releases/$MODE"
RELEASE_APP="$RELEASE_DIR/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-v$VERSION.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"

mkdir -p "$ROOT_DIR/.build/Archives" "$RELEASE_DIR"
rm -rf "$ARCHIVE_PATH" "$RELEASE_APP"
rm -f "$ZIP_PATH" "$CHECKSUM_PATH"

BUILD_ARGUMENTS=(
  "ARCHS=arm64 x86_64"
  "ONLY_ACTIVE_ARCH=NO"
  "CODE_SIGN_STYLE=Manual"
  "CODE_SIGN_IDENTITY=-"
  "DEVELOPMENT_TEAM="
  "GOOGLE_OAUTH_CLIENT_ID="
  "GOOGLE_TASKS_CLIENT_ID="
  "GOOGLE_OAUTH_CLIENT_SECRET="
)

xcodebuild \
  -quiet \
  -project "$ROOT_DIR/Nudge.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  "${BUILD_ARGUMENTS[@]}"

test -d "$ARCHIVED_APP"
ditto "$ARCHIVED_APP" "$RELEASE_APP"
plutil -lint "$RELEASE_APP/Contents/Info.plist"

oauth_value() {
  plutil -extract "$1" raw -o - "$RELEASE_APP/Contents/Info.plist" 2>/dev/null || true
}

BUNDLED_OAUTH_CLIENT_ID="$(oauth_value GoogleOAuthClientID)"
BUNDLED_LEGACY_CLIENT_ID="$(oauth_value GoogleTasksClientID)"
BUNDLED_OAUTH_CLIENT_SECRET="$(oauth_value GoogleOAuthClientSecret)"

if [[ -n "$BUNDLED_OAUTH_CLIENT_ID" ||
      -n "$BUNDLED_LEGACY_CLIENT_ID" ||
      -n "$BUNDLED_OAUTH_CLIENT_SECRET" ]]; then
  echo "The public app contains embedded Google OAuth configuration." >&2
  exit 1
fi
if grep -RIlE --binary-files=text \
  '[A-Za-z0-9._-]+\.apps\.googleusercontent\.com' \
  "$RELEASE_APP" >/dev/null 2>&1; then
  echo "The public app contains a concrete Google OAuth client identifier." >&2
  exit 1
fi
echo "Public app contains no embedded Google OAuth client values."
unset BUNDLED_OAUTH_CLIENT_ID BUNDLED_LEGACY_CLIENT_ID BUNDLED_OAUTH_CLIENT_SECRET

ARCHITECTURES="$(lipo -archs "$RELEASE_APP/Contents/MacOS/$APP_NAME")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
  echo "The packaged executable is not universal." >&2
  exit 1
fi

codesign --verify --deep --strict "$RELEASE_APP"
SIGNING_DETAILS="$(codesign -dvvv "$RELEASE_APP" 2>&1)"
if [[ "$SIGNING_DETAILS" != *"flags="*"runtime"* ]]; then
  echo "The packaged app does not enable hardened runtime." >&2
  exit 1
fi

if [[ "$SIGNING_DETAILS" != *"Signature=adhoc"* ]]; then
  echo "The public app is not ad-hoc signed as expected." >&2
  exit 1
fi
echo "Ad-hoc public signature and hardened runtime validated."
unset SIGNING_DETAILS

if spctl -a --type execute "$RELEASE_APP" >/dev/null 2>&1; then
  echo "Gatekeeper accepted the app on this Mac."
else
  echo "Gatekeeper rejection is expected because this release is not Developer ID signed or notarized."
fi

ditto -c -k --sequesterRsrc --keepParent "$RELEASE_APP" "$ZIP_PATH"
CHECKSUM="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$ZIP_PATH")" > "$CHECKSUM_PATH"
unset CHECKSUM

if [[ "$SHOULD_LAUNCH" -eq 1 ]]; then
  "$RELEASE_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
  SMOKE_PID=$!
  sleep 1
  kill -0 "$SMOKE_PID"
  kill "$SMOKE_PID"
  wait "$SMOKE_PID" 2>/dev/null || true
fi

echo "Release app: $RELEASE_APP"
echo "Release ZIP: $ZIP_PATH"
echo "Checksum: $CHECKSUM_PATH"
echo "Archive: $ARCHIVE_PATH"
