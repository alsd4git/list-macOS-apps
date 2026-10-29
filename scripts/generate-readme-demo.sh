#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_ROOT="$(mktemp -d)"
trap 'rm -rf "$DEMO_ROOT"' EXIT

MOCK_BIN="$DEMO_ROOT/bin"
APPLICATIONS_DIR="$DEMO_ROOT/Applications"
HOME_DIR="$DEMO_ROOT/home"
EXPORT_DIR="$DEMO_ROOT/exports"
OUTPUT_FILE="$DEMO_ROOT/output.txt"

mkdir -p "$MOCK_BIN" "$APPLICATIONS_DIR" "$HOME_DIR/Applications" "$EXPORT_DIR"

cat >"$MOCK_BIN/brew" <<'MOCK_BREW'
#!/bin/bash
set -euo pipefail

if [[ "$1" == "list" && "$2" == "--formula" && "$3" == "--versions" ]]; then
  printf '%s\n' 'jq 1.8.0' 'ripgrep 14.1.0'
elif [[ "$1" == "list" && "$2" == "--cask" && "${3-}" == "--versions" ]]; then
  printf '%s\n' 'firefox 135.0' 'iterm2 3.5.11'
elif [[ "$1" == "list" && "$2" == "--cask" ]]; then
  printf '%s\n' firefox iterm2
elif [[ "$1" == "info" && "$2" == "--json=v2" && "$3" == "--cask" ]]; then
  printf '%s\n' '{"casks":[{"artifacts":[]}]}'
else
  echo "unexpected brew arguments: $*" >&2
  exit 1
fi
MOCK_BREW

cat >"$MOCK_BIN/mas" <<'MOCK_MAS'
#!/bin/bash
set -euo pipefail

if [[ "$1" == "list" ]]; then
  printf '%s\n' '123456789 Pages (14.4)' '987654321 Keynote (14.4)'
else
  echo "unexpected mas arguments: $*" >&2
  exit 1
fi
MOCK_MAS

# Casks in this fixture have no .app artifacts, so this jq stub returns no names.
cat >"$MOCK_BIN/jq" <<'MOCK_JQ'
#!/bin/bash
set -euo pipefail
cat >/dev/null
MOCK_JQ

chmod +x "$MOCK_BIN/brew" "$MOCK_BIN/mas" "$MOCK_BIN/jq"

mkdir -p \
  "$REPO_ROOT/docs" \
  "$APPLICATIONS_DIR/Firefox.app" \
  "$APPLICATIONS_DIR/Pages.app" \
  "$APPLICATIONS_DIR/Acme Sketch.app" \
  "$HOME_DIR/Applications/Local Utility.app"

env \
  PATH="$MOCK_BIN:/usr/bin:/bin" \
  HOME="$HOME_DIR" \
  APPLICATIONS_DIRS="$APPLICATIONS_DIR:$HOME_DIR/Applications" \
  "$REPO_ROOT/list-installed-apps.sh" \
    --with-formulae --export-csv --export-md --export-json \
    --output-dir "$EXPORT_DIR" >"$OUTPUT_FILE"

cp "$EXPORT_DIR/installed_apps.json" "$REPO_ROOT/docs/demo-inventory.json"

python3 - "$OUTPUT_FILE" "$REPO_ROOT/docs/readme-demo.svg" <<'PY'
from html import escape
from pathlib import Path
import sys

output_path, svg_path = map(Path, sys.argv[1:])
lines = output_path.read_text().replace(str(output_path.parent / "exports"), "./inventory").splitlines()
font_size = 15
line_height = 23
padding = 24
width = 760
height = padding * 2 + line_height * len(lines)

text = "\n".join(
    f'<text x="{padding}" y="{padding + (index + 1) * line_height - 4}" '
    f'fill="{"#a8e6a3" if line.startswith("===") else "#e7e7e7"}" '
    f'font-size="{font_size}">{escape(line)}</text>'
    for index, line in enumerate(lines)
)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
  <title id="title">Synthetic macOS application inventory</title>
  <desc id="desc">Output from list-installed-apps.sh using fake package manager commands and temporary app bundles.</desc>
  <rect width="100%" height="100%" rx="12" fill="#17191c"/>
  <circle cx="24" cy="22" r="6" fill="#ff5f57"/><circle cx="44" cy="22" r="6" fill="#febc2e"/><circle cx="64" cy="22" r="6" fill="#28c840"/>
  <g font-family="SFMono-Regular, Consolas, monospace">{text}</g>
</svg>
'''
svg_path.write_text(svg)
PY

printf 'Generated docs/readme-demo.svg and docs/demo-inventory.json from synthetic fixtures.\n'
