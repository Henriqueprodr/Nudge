#!/bin/zsh

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data_path="$repository_root/.build/DerivedData"
output_directory="$repository_root/docs/screenshots"
application_path="$derived_data_path/Build/Products/Debug/Nudge.app"

mkdir -p "$repository_root/.build/screenshots" "$output_directory"

xcodebuild \
    -project "$repository_root/Nudge.xcodeproj" \
    -scheme Nudge \
    -configuration Debug \
    -derivedDataPath "$derived_data_path" \
    GOOGLE_OAUTH_CLIENT_ID= \
    GOOGLE_OAUTH_CLIENT_SECRET= \
    GOOGLE_TASKS_CLIENT_ID= \
    GOOGLE_TASKS_CLIENT_SECRET= \
    build \
    >"$repository_root/.build/screenshots/capture-build.log"

test -d "$application_path"

oauth_client_id="$(/usr/libexec/PlistBuddy -c 'Print :GoogleOAuthClientID' "$application_path/Contents/Info.plist" 2>/dev/null || true)"
oauth_client_secret="$(/usr/libexec/PlistBuddy -c 'Print :GoogleOAuthClientSecret' "$application_path/Contents/Info.plist" 2>/dev/null || true)"
if [[ -n "$oauth_client_id" || -n "$oauth_client_secret" ]]; then
    print -u2 "Screenshot build unexpectedly contains Google OAuth configuration."
    exit 1
fi

/usr/bin/pkill -x Nudge >/dev/null 2>&1 || true

pages=(
    menu
    account
    reminders
    tasks
    application
    overlay
    task-panel
)
filenames=(
    menu-bar.png
    settings-account.png
    settings-reminders.png
    settings-tasks.png
    settings-application.png
    reminder-overlay.png
    task-panel.png
)

for index in {1..${#pages[@]}}; do
    page="${pages[$index]}"
    output_path="$output_directory/${filenames[$index]}"
    /bin/rm -f "$output_path"
    /usr/bin/open -n -W "$application_path" --args \
        --screenshot-demo \
        --screenshot-page "$page" \
        --screenshot-output "$output_path"
    test -s "$output_path"
    /usr/bin/xattr -c "$output_path"
done

/usr/bin/pkill -x Nudge >/dev/null 2>&1 || true

for output_path in "$output_directory"/*.png; do
    /usr/bin/sips -g format -g pixelWidth -g pixelHeight "$output_path"
done
