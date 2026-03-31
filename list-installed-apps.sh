#!/bin/bash

set -euo pipefail

INCLUDE_FORMULAE=false
EXPORT_CSV=false
EXPORT_MD=false
EXPORT_JSON=false
OUTPUT_DIR="."

data_file=""
known_apps_file=""
cleanup_paths=""

usage() {
  cat <<'EOF'
Usage: ./list-installed-apps.sh [options]

Options:
  --with-formulae   Include Homebrew formulae in the output.
  --export-csv      Export the collected inventory to installed_apps.csv.
  --export-md       Export the collected inventory to installed_apps.md.
  --export-json     Export the collected inventory to installed_apps.json.
  --output-dir DIR  Write export files into DIR.
  --help            Show this help message.
EOF
}

cleanup() {
  if [[ -n "${cleanup_paths}" ]]; then
    # shellcheck disable=SC2086
    rm -f ${cleanup_paths}
  fi
}

trap cleanup EXIT

append_cleanup_path() {
  if [[ -z "${cleanup_paths}" ]]; then
    cleanup_paths="$1"
  else
    cleanup_paths="${cleanup_paths} $1"
  fi
}

normalize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

section_title() {
  case "$1" in
    formulae) printf '%s' "Homebrew (Formulae) Packages" ;;
    casks) printf '%s' "Homebrew (Cask) Apps" ;;
    mas) printf '%s' "Mac App Store Apps" ;;
    manual) printf '%s' "Manually Installed Apps" ;;
    *) printf '%s' "$1" ;;
  esac
}

csv_escape() {
  printf '%s' "$1" | sed 's/"/""/g'
}

md_escape() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

add_record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$data_file"
}

add_known_app() {
  local normalized_name
  normalized_name=$(normalize_name "$1")
  if [[ -n "$normalized_name" ]]; then
    printf '%s\n' "$normalized_name" >> "$known_apps_file"
  fi
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

collect_formulae() {
  local line name version

  if ! have_command brew; then
    echo "Warning: skipping Homebrew formulae because 'brew' is not installed." >&2
    return
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    name=$(printf '%s\n' "$line" | awk '{print $1}')
    version=$(printf '%s\n' "$line" | awk '{$1=""; sub(/^ /, ""); print}')
    add_record "formulae" "$name" "$version"
  done < <(brew list --formula --versions)
}

collect_casks() {
  local line name version

  if ! have_command brew; then
    echo "Warning: skipping Homebrew casks because 'brew' is not installed." >&2
    return
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    name=$(printf '%s\n' "$line" | awk '{print $1}')
    version=$(printf '%s\n' "$line" | awk '{$1=""; sub(/^ /, ""); print}')
    add_record "casks" "$name" "$version"
    add_known_app "$name"
  done < <(brew list --cask --versions)
}

collect_cask_apps() {
  local cask_token cask_info app_name

  if ! have_command brew; then
    echo "Warning: skipping Homebrew cask app artifacts because 'brew' is not installed." >&2
    return
  fi

  if ! have_command jq; then
    echo "Warning: skipping Homebrew cask app artifacts because 'jq' is not installed." >&2
    return
  fi

  while IFS= read -r cask_token; do
    [[ -z "$cask_token" ]] && continue

    if ! cask_info=$(brew info --json=v2 --cask "$cask_token" 2>/dev/null); then
      continue
    fi

    while IFS= read -r app_name; do
      [[ -z "$app_name" ]] && continue
      app_name=${app_name%.app}
      add_known_app "$app_name"
    done < <(printf '%s\n' "$cask_info" | jq -r '.casks[]?.artifacts[]? | select(has("app")) | .app[]?')
  done < <(brew list --cask)
}

collect_mas_apps() {
  local line app_name version

  if ! have_command mas; then
    echo "Warning: skipping Mac App Store apps because 'mas' is not installed." >&2
    return
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+(.+)[[:space:]]+\(([^()]*)\)[[:space:]]*$ ]]; then
      app_name=${BASH_REMATCH[1]}
      version=${BASH_REMATCH[2]}
    else
      app_name="$line"
      version=""
    fi

    add_record "mas" "$app_name" "$version"
    add_known_app "$app_name"
  done < <(mas list)
}

collect_manual_apps() {
  local app_path app_name normalized_name
  local -a search_paths

  search_paths=()
  [[ -d "/Applications" ]] && search_paths+=("/Applications")
  [[ -d "${HOME}/Applications" ]] && search_paths+=("${HOME}/Applications")

  if [[ ${#search_paths[@]} -eq 0 ]]; then
    echo "Warning: skipping manual applications because no Applications directories were found." >&2
    return
  fi

  while IFS= read -r app_path; do
    [[ -z "$app_path" ]] && continue
    app_name=$(basename "$app_path" .app)
    normalized_name=$(normalize_name "$app_name")

    if ! grep -Fqx "$normalized_name" "$known_apps_file"; then
      add_record "manual" "$app_name" ""
    fi
  done < <(find "${search_paths[@]}" -maxdepth 1 -type d -name "*.app" -print 2>/dev/null | sort -f | uniq)
}

print_section() {
  local section="$1"
  local title

  title=$(section_title "$section")
  echo "=== ${title} ==="

  awk -F '\t' -v current="$section" '
    $1 == current {
      if (length($3) > 0) {
        printf "%-30s v%s\n", $2, $3
      } else {
        print $2
      }
    }
  ' "$data_file"

  echo
}

export_csv() {
  local csv_file="$OUTPUT_DIR/installed_apps.csv"
  local section_title_value escaped_section escaped_app escaped_version

  printf 'Type,App,Version\n' > "$csv_file"

  while IFS=$'\t' read -r section app version; do
    section_title_value=$(section_title "$section")
    escaped_section=$(csv_escape "$section_title_value")
    escaped_app=$(csv_escape "$app")
    escaped_version=$(csv_escape "$version")
    printf '"%s","%s","%s"\n' "$escaped_section" "$escaped_app" "$escaped_version" >> "$csv_file"
  done < "$data_file"

  echo "Exported CSV to $csv_file"
}

export_markdown() {
  local md_file="$OUTPUT_DIR/installed_apps.md"
  local previous_section="" title escaped_app escaped_version

  printf '# Installed Applications\n' > "$md_file"

  while IFS=$'\t' read -r section app version; do
    if [[ "$section" != "$previous_section" ]]; then
      title=$(section_title "$section")
      printf '\n## %s\n| App | Version |\n|------|---------|\n' "$title" >> "$md_file"
      previous_section="$section"
    fi

    escaped_app=$(md_escape "$app")
    escaped_version=$(md_escape "$version")
    printf '| %s | %s |\n' "$escaped_app" "$escaped_version" >> "$md_file"
  done < "$data_file"

  echo "Exported Markdown to $md_file"
}

export_json() {
  local json_file="$OUTPUT_DIR/installed_apps.json"
  local first=true escaped_section escaped_app escaped_version

  printf '[\n' > "$json_file"

  while IFS=$'\t' read -r section app version; do
    escaped_section=$(json_escape "$(section_title "$section")")
    escaped_app=$(json_escape "$app")
    escaped_version=$(json_escape "$version")

    if [[ "$first" == true ]]; then
      first=false
    else
      printf ',\n' >> "$json_file"
    fi

    printf '  {"type":"%s","app":"%s","version":"%s"}' \
      "$escaped_section" "$escaped_app" "$escaped_version" >> "$json_file"
  done < "$data_file"

  printf '\n]\n' >> "$json_file"
  echo "Exported JSON to $json_file"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-formulae)
        INCLUDE_FORMULAE=true
        ;;
      --export-csv)
        EXPORT_CSV=true
        ;;
      --export-md)
        EXPORT_MD=true
        ;;
      --export-json)
        EXPORT_JSON=true
        ;;
      --output-dir)
        shift
        if [[ $# -eq 0 ]]; then
          echo "Error: --output-dir requires a directory path." >&2
          exit 1
        fi
        OUTPUT_DIR="$1"
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        echo "Error: unknown option '$1'." >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

parse_args "$@"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "Error: output directory '$OUTPUT_DIR' does not exist." >&2
  exit 1
fi

data_file=$(mktemp)
known_apps_file=$(mktemp)
append_cleanup_path "$data_file"
append_cleanup_path "$known_apps_file"

if $INCLUDE_FORMULAE; then
  collect_formulae
fi
collect_casks
collect_cask_apps
collect_mas_apps
collect_manual_apps

sort -t $'\t' -k1,1 -k2,2f "$data_file" -o "$data_file"
sort -fu "$known_apps_file" -o "$known_apps_file"

if $INCLUDE_FORMULAE; then
  print_section "formulae"
fi
print_section "casks"
print_section "mas"
print_section "manual"

if $EXPORT_CSV; then
  export_csv
fi

if $EXPORT_MD; then
  export_markdown
fi

if $EXPORT_JSON; then
  export_json
fi
