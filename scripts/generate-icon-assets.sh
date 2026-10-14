#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_root/assets/icons"
manifest="$source_dir/icon-manifest.json"
catalog="$project_root/iOS/MealPlate/MealPlate/Resources/Assets.xcassets"

mkdir -p "$catalog"
printf '%s\n' '{' '  "info" : {' '    "author" : "xcode",' '    "version" : 1' '  }' '}' > "$catalog/Contents.json"

jq -r '.icons | to_entries[] | [.key, .value.file, .value.colorMode] | @tsv' "$manifest" |
while IFS=$'\t' read -r semantic_name file_name color_mode; do
    image_set="$catalog/$semantic_name.imageset"
    mkdir -p "$image_set"
    cp "$source_dir/$file_name" "$image_set/$file_name"

    if [[ "$color_mode" == "currentColor" ]]; then
        rendering_intent="template"
    else
        rendering_intent="original"
    fi

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
        "    \"template-rendering-intent\" : \"$rendering_intent\"" \
        '  }' \
        '}' > "$image_set/Contents.json"
done
