#!/usr/bin/env bash
set -euo pipefail

MODE=""
SHOULD_LAUNCH=0
INCLUDES_BUILT_IN_CLIENT=1

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
    --no-built-in-client)
      INCLUDES_BUILT_IN_CLIENT=0
      ;;
    *)
      echo "usage: $0 --public [--launch|--no-launch] [--no-built-in-client]" >&2
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
  "GOOGLE_TASKS_CLIENT_ID="
)

# The public release ships Nudge's own Google Desktop OAuth client, so people connect their
# Google account with one click instead of creating a Google Cloud project. Google documents
# that an installed app cannot keep a Desktop client secret confidential, so shipping it is
# expected; it still stays out of Git, logs, and command-line arguments.
EXPECTED_CLIENT_ID=""
EXPECTED_CLIENT_SECRET=""
OAUTH_XCCONFIG=""
cleanup_oauth_xcconfig() {
  if [[ -n "$OAUTH_XCCONFIG" ]]; then
    rm -f "$OAUTH_XCCONFIG"
  fi
}
trap cleanup_oauth_xcconfig EXIT

if [[ "$INCLUDES_BUILT_IN_CLIENT" -eq 1 ]]; then
  OAUTH_CLIENT_JSON="${NUDGE_OAUTH_CLIENT_JSON:-$ROOT_DIR/.private/google-oauth-client.json}"
  EXPECTED_CLIENT_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"
  EXPECTED_CLIENT_SECRET="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
  if [[ -z "$EXPECTED_CLIENT_ID" || -z "$EXPECTED_CLIENT_SECRET" ]]; then
    if [[ ! -f "$OAUTH_CLIENT_JSON" ]]; then
      echo "Nudge's Google Desktop OAuth client is required for the public release." >&2
      echo "Save its JSON as .private/google-oauth-client.json, set NUDGE_OAUTH_CLIENT_JSON," >&2
      echo "or pass --no-built-in-client for a build where people import their own." >&2
      exit 1
    fi
    EXPECTED_CLIENT_ID="$(plutil -extract installed.client_id raw -o - "$OAUTH_CLIENT_JSON" 2>/dev/null || true)"
    EXPECTED_CLIENT_SECRET="$(plutil -extract installed.client_secret raw -o - "$OAUTH_CLIENT_JSON" 2>/dev/null || true)"
  fi
  if [[ ! "$EXPECTED_CLIENT_ID" =~ ^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$ ]]; then
    echo "The Google OAuth configuration does not contain a valid Desktop client ID." >&2
    exit 1
  fi
  if [[ ! "$EXPECTED_CLIENT_SECRET" =~ ^[A-Za-z0-9._~-]+$ ]]; then
    echo "The Google OAuth configuration does not contain a valid Desktop client secret." >&2
    exit 1
  fi
  OAUTH_XCCONFIG="$(umask 077 && mktemp "${TMPDIR:-/tmp}/NudgeReleaseOAuth.xcconfig.XXXXXX")"
  printf 'GOOGLE_OAUTH_CLIENT_ID = %s\nGOOGLE_OAUTH_CLIENT_SECRET = %s\n' \
    "$EXPECTED_CLIENT_ID" "$EXPECTED_CLIENT_SECRET" > "$OAUTH_XCCONFIG"
  BUILD_ARGUMENTS+=("-xcconfig" "$OAUTH_XCCONFIG")
else
  BUILD_ARGUMENTS+=("GOOGLE_OAUTH_CLIENT_ID=" "GOOGLE_OAUTH_CLIENT_SECRET=")
fi

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

if [[ -n "$BUNDLED_LEGACY_CLIENT_ID" ]]; then
  echo "The public app contains the legacy Google Tasks client ID key." >&2
  exit 1
fi
if [[ "$INCLUDES_BUILT_IN_CLIENT" -eq 1 ]]; then
  if [[ "$BUNDLED_OAUTH_CLIENT_ID" != "$EXPECTED_CLIENT_ID" ||
        "$BUNDLED_OAUTH_CLIENT_SECRET" != "$EXPECTED_CLIENT_SECRET" ]]; then
    echo "The public app does not contain Nudge's Google OAuth client." >&2
    exit 1
  fi
  echo "Public app contains Nudge's built-in Google OAuth client (values not printed)."
else
  if [[ -n "$BUNDLED_OAUTH_CLIENT_ID" || -n "$BUNDLED_OAUTH_CLIENT_SECRET" ]]; then
    echo "The credential-free app contains embedded Google OAuth configuration." >&2
    exit 1
  fi
  if grep -RIlE --binary-files=text \
    '[A-Za-z0-9._-]+\.apps\.googleusercontent\.com' \
    "$RELEASE_APP" >/dev/null 2>&1; then
    echo "The credential-free app contains a concrete Google OAuth client identifier." >&2
    exit 1
  fi
  echo "Credential-free app contains no embedded Google OAuth client values."
fi
unset BUNDLED_OAUTH_CLIENT_ID BUNDLED_LEGACY_CLIENT_ID BUNDLED_OAUTH_CLIENT_SECRET
unset EXPECTED_CLIENT_ID EXPECTED_CLIENT_SECRET

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
