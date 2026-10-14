#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_root/贴纸库"
manifest="$project_root/app-contract/sticker-catalog.v1.json"
catalog="$project_root/iOS/MealPlate/MealPlate/Resources/Assets.xcassets"

jq -r '.stickers[] | [.asset_name, .source] | @tsv' "$manifest" |
while IFS=$'\t' read -r asset_name relative_source; do
    image_set="$catalog/$asset_name.imageset"
    file_name="${relative_source:t}"
    mkdir -p "$image_set"
    cp "$source_dir/$relative_source" "$image_set/$file_name"

    printf '%s\n' \
        '{' \
        '  "images" : [' \
        '    {' \
        "      \"filename\" : \"$file_name\"," \
        '      "idiom" : "universal"' \
        '    }' \
        '  ],' \
        '  "info" : {' \
        '    "author" : "xcode",' \
        '    "version" : 1' \
        '  },' \
        '  "properties" : {' \
        '    "preserves-vector-representation" : true,' \
        '    "template-rendering-intent" : "original"' \
        '  }' \
        '}' > "$image_set/Contents.json"
done
