#!/bin/bash

INCLUDE_FORMULAE=false
EXPORT_CSV=false
EXPORT_MD=false

# === Parse Args ===
for arg in "$@"; do
  case $arg in
    --with-formulae)
      INCLUDE_FORMULAE=true
      ;;
    --export-csv)
      EXPORT_CSV=true
      ;;
    --export-md)
      EXPORT_MD=true
      ;;
  esac
done

# Ensure required tools
if ! command -v mas &> /dev/null; then
    echo "Installing 'mas' via Homebrew..."
    brew install mas
fi

if ! command -v jq &> /dev/null; then
    echo "Installing 'jq' via Homebrew..."
    brew install jq
fi

# Temp file for export
output=$(mktemp)

# === Homebrew Formulae (optional) ===
if $INCLUDE_FORMULAE; then
    echo "=== Homebrew (Formula) Packages ===" | tee -a "$output"
    brew list --formula --versions | while read line; do
        name=$(echo "$line" | awk '{print $1}')
        version=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        printf "%-30s v%s\n" "$name" "$version" | tee -a "$output"
    done
    echo "" | tee -a "$output"
fi

# === Homebrew Casks ===
echo "=== Homebrew (Cask) Apps ===" | tee -a "$output"
brew list --cask --versions | while read line; do
    name=$(echo "$line" | awk '{print $1}')
    version=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
    printf "%-30s v%s\n" "$name" "$version" | tee -a "$output"
done
echo "" | tee -a "$output"

# === Mac App Store Apps ===
echo "=== Mac App Store Apps ===" | tee -a "$output"
mas list | while read line; do
    appname=$(echo "$line" | cut -f2)
    version=$(echo "$line" | grep -oE '\([^\)]+\)' | tr -d '()')
    printf "%-30s v%s\n" "$appname" "$version" | tee -a "$output"
done
echo "" | tee -a "$output"

# === Manually Installed Apps ===
echo "=== Manually Installed Apps ===" | tee -a "$output"
known_apps=$( (brew list --cask --versions | awk '{print $1}'; mas list | awk '{print $2}') | tr '[:upper:]' '[:lower:]' )

manual_apps=$(find /Applications ~/Applications -maxdepth 1 -name "*.app" -exec basename {} .app \; 2>/dev/null | sort -f | uniq)
echo "$manual_apps" | while read app; do
    app_lc=$(echo "$app" | tr '[:upper:]' '[:lower:]')
    if ! echo "$known_apps" | grep -qx "$app_lc"; then
        echo "$app" | tee -a "$output"
    fi
done

# === Export to CSV ===
if $EXPORT_CSV; then
    csv_file="installed_apps.csv"
    echo "Type,App,Version" > "$csv_file"
    current_section=""
    while IFS= read -r line; do
        if [[ "$line" == ===* ]]; then
            current_section=$(echo "$line" | sed 's/=== //; s/ ===//')
        elif [[ -n "$line" ]]; then
            app=$(echo "$line" | sed 's/  */ /g' | cut -d ' ' -f1-1)
            version=$(echo "$line" | grep -oE 'v[0-9].*$' || echo "")
            echo "\"$current_section\",\"$app\",\"$version\"" >> "$csv_file"
        fi
    done < "$output"
    echo "✅ Exported CSV to $csv_file"
fi

# === Export to Markdown ===
if $EXPORT_MD; then
    md_file="installed_apps.md"
    echo "# Installed Applications" > "$md_file"
    current_section=""
    while IFS= read -r line; do
        if [[ "$line" == ===* ]]; then
            current_section=$(echo "$line" | sed 's/=== //; s/ ===//')
            echo -e "\n## $current_section" >> "$md_file"
            echo "| App | Version |" >> "$md_file"
            echo "|------|---------|" >> "$md_file"
        elif [[ -n "$line" ]]; then
            app=$(echo "$line" | sed 's/  */ /g' | cut -d ' ' -f1-1)
            version=$(echo "$line" | grep -oE 'v[0-9].*$' || echo "")
            echo "| $app | $version |" >> "$md_file"
        fi
    done < "$output"
    echo "✅ Exported Markdown to $md_file"
fi

# Cleanup
rm "$output"