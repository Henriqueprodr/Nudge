#!/bin/zsh

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
build_directory="$repository_root/.build/readme-assets"
module_cache="$build_directory/module-cache"
generator="$build_directory/generate_readme_assets"
hero_path="$repository_root/docs/assets/nudge-hero.png"
social_preview_path="$repository_root/docs/assets/nudge-social-preview.jpg"
icon_path="$repository_root/docs/assets/nudge-icon.png"
icon_document="$repository_root/Sources/Nudge/Resources/AppIcon.icon"
icon_export="$build_directory/app-icon-export.png"
icon_composer_tool="$(/usr/bin/xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"

mkdir -p "$build_directory" "$module_cache"

if [[ ! -x "$icon_composer_tool" ]]; then
    print -u2 "Icon Composer's ictool was not found. Install Xcode 26 or later."
    exit 1
fi

# Render the real app icon (the Icon Composer document the app ships) for the README.
/bin/rm -f "$icon_export"
"$icon_composer_tool" "$icon_document" \
    --export-image \
    --output-file "$icon_export" \
    --platform macOS \
    --rendition Default \
    --width 512 \
    --height 512 \
    --scale 2 \
    >/dev/null
test -s "$icon_export"

CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULECACHE_PATH="$module_cache" \
xcrun --sdk macosx swiftc \
    -O \
    -framework AppKit \
    -o "$generator" \
    "$repository_root/script/readme_artwork_support.swift" \
    "$repository_root/script/generate_readme_assets.swift"

"$generator" "$repository_root"

/usr/bin/xattr -c "$icon_path" "$hero_path" "$social_preview_path"

social_preview_size="$(/usr/bin/stat -f '%z' "$social_preview_path")"
if (( social_preview_size >= 1000000 )); then
    print -u2 "The GitHub social-preview image must remain below 1 MB."
    exit 1
fi

/usr/bin/sips -g format -g pixelWidth -g pixelHeight "$icon_path" "$hero_path" "$social_preview_path"
print "Generated the README icon, hero, and social-preview artwork."
