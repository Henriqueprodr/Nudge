#!/bin/zsh

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
build_directory="$repository_root/.build/readme-assets"
module_cache="$build_directory/module-cache"
generator="$build_directory/generate_readme_assets"
hero_path="$repository_root/docs/assets/nudge-hero.png"
social_preview_path="$repository_root/docs/assets/nudge-social-preview.jpg"

mkdir -p "$build_directory" "$module_cache"

CLANG_MODULE_CACHE_PATH="$module_cache" \
SWIFT_MODULECACHE_PATH="$module_cache" \
xcrun --sdk macosx swiftc \
    -O \
    -framework AppKit \
    -o "$generator" \
    "$repository_root/script/readme_artwork_support.swift" \
    "$repository_root/script/generate_readme_assets.swift"

"$generator" "$repository_root"

/usr/bin/xattr -c "$hero_path" "$social_preview_path"

social_preview_size="$(/usr/bin/stat -f '%z' "$social_preview_path")"
if (( social_preview_size >= 1000000 )); then
    print -u2 "The GitHub social-preview image must remain below 1 MB."
    exit 1
fi

/usr/bin/sips -g format -g pixelWidth -g pixelHeight "$hero_path" "$social_preview_path"
print "Generated README hero and social-preview artwork."
