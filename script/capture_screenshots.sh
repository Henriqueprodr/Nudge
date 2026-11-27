#!/bin/zsh

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data_path="$repository_root/.build/DerivedData"
output_directory="$repository_root/docs/screenshots"
application_path="$derived_data_path/Build/Products/Debug/Nudge.app"
capture_build_directory="$repository_root/.build/screenshots"
raw_directory="$capture_build_directory/raw"
composed_directory="$capture_build_directory/composed"
module_cache="$capture_build_directory/module-cache"
compositor="$capture_build_directory/compose_screenshot_gallery"
signing_line="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep '"Apple Development:' \
    | /usr/bin/head -n 1 \
    || true)"
signing_identity="$(/usr/bin/sed -E 's/^[[:space:]]*[0-9]+\) ([0-9A-F]+) .*/\1/' <<< "$signing_line")"
development_team="$(/usr/bin/sed -E 's/.*\(([A-Z0-9]{10})\)"$/\1/' <<< "$signing_line")"

if [[ ! "$signing_identity" =~ ^[0-9A-F]{40}$ || ! "$development_team" =~ ^[A-Z0-9]{10}$ ]]; then
    print -u2 "A stable Apple Development signing identity is required for native screenshot capture."
    print -u2 "Create a personal development certificate in Xcode, then rerun this script."
    exit 1
fi

mkdir -p \
    "$capture_build_directory" \
    "$raw_directory" \
    "$composed_directory" \
    "$module_cache" \
    "$output_directory"

xcodebuild \
    -project "$repository_root/Nudge.xcodeproj" \
    -scheme Nudge \
    -configuration Debug \
    -derivedDataPath "$derived_data_path" \
    GOOGLE_OAUTH_CLIENT_ID= \
    GOOGLE_OAUTH_CLIENT_SECRET= \
    GOOGLE_TASKS_CLIENT_ID= \
    GOOGLE_TASKS_CLIENT_SECRET= \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    DEVELOPMENT_TEAM="$development_team" \
    build \
    >"$capture_build_directory/capture-build.log"

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
    mascot
    application
    overlay
    bird-alert
    task-nag
    task-panel
)
filenames=(
    menu-bar.png
    settings-account.png
    settings-reminders.png
    settings-tasks.png
    settings-bird.png
    settings-application.png
    reminder-overlay.png
    bird-alert.png
    task-nag.png
    task-panel.png
)

for index in {1..${#pages[@]}}; do
    page="${pages[$index]}"
    output_path="$raw_directory/${filenames[$index]}"
    error_path="${output_path:r}.error.txt"
    capture_succeeded=false
    for attempt in 1 2 3; do
        /bin/rm -f "$output_path"
        /bin/rm -f "$error_path"
        /usr/bin/open -n -W "$application_path" --args \
            --screenshot-demo \
            --screenshot-page "$page" \
            --screenshot-output "$output_path"
        if [[ -s "$output_path" ]]; then
            capture_succeeded=true
            break
        fi
        if [[ -s "$error_path" ]] && \
            /usr/bin/grep -q 'Screen Recording permission is required' "$error_path"; then
            break
        fi
        if (( attempt < 3 )); then
            print -u2 "Retrying native $page capture after a transient capture-service failure."
        fi
    done
    if [[ "$capture_succeeded" != true ]]; then
        if [[ -s "$error_path" ]]; then
            /bin/cat "$error_path" >&2
        fi
        print -u2 "Native screenshot capture failed for $page."
        print -u2 "If macOS requested access, enable Nudge in System Settings → Privacy & Security → Screen & System Audio Recording, then rerun this script."
        exit 1
    fi
    /usr/bin/xattr -c "$output_path"
done

/usr/bin/pkill -x Nudge >/dev/null 2>&1 || true

CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULECACHE_PATH="$module_cache" \
xcrun --sdk macosx swiftc \
    -O \
    -framework AppKit \
    -o "$compositor" \
    "$repository_root/script/readme_artwork_support.swift" \
    "$repository_root/script/compose_screenshot_gallery.swift"

for filename in "${filenames[@]}"; do
    /bin/rm -f "$composed_directory/$filename"
done
"$compositor" \
    "$raw_directory" \
    "$composed_directory" \
    "$repository_root/Sources/Nudge/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg"

for filename in "${filenames[@]}"; do
    composed_path="$composed_directory/$filename"
    test -s "$composed_path"
    /usr/bin/xattr -c "$composed_path"
done

for filename in "${filenames[@]}"; do
    /bin/cp "$composed_directory/$filename" "$output_directory/$filename"
    /usr/bin/xattr -c "$output_directory/$filename"
done

for output_path in "$output_directory"/*.png; do
    /usr/bin/sips -g format -g pixelWidth -g pixelHeight "$output_path"
done
