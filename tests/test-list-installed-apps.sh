#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/list-installed-apps.sh"
TEST_ROOT="$(mktemp -d)"
MOCK_BIN="$TEST_ROOT/bin"
HOME_DIR="$TEST_ROOT/home"
APPLICATIONS_DIR="$TEST_ROOT/Applications"
EXPORT_DIR="$TEST_ROOT/exports"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$HOME_DIR/Applications" "$APPLICATIONS_DIR" "$EXPORT_DIR"

cat > "$MOCK_BIN/brew" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "$1" == "list" && "$2" == "--cask" && "$3" == "--versions" ]]; then
  cat <<'OUT'
visual-studio-code 1.101.0
google-chrome 134.0.6998.89
OUT
  exit 0
fi

if [[ "$1" == "list" && "$2" == "--formula" && "$3" == "--versions" ]]; then
  cat <<'OUT'
python@3.13 3.13.2
node 24.0.0
OUT
  exit 0
fi

echo "unexpected brew args: $*" >&2
exit 1
EOF

cat > "$MOCK_BIN/mas" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "$1" == "list" ]]; then
  cat <<'OUT'
497799835 Xcode (26.3)
6753110395 Folder Quick Look (1.6)
OUT
  exit 0
fi

echo "unexpected mas args: $*" >&2
exit 1
EOF

chmod +x "$MOCK_BIN/brew" "$MOCK_BIN/mas"

touch "$APPLICATIONS_DIR/Visual Studio Code.app"
touch "$APPLICATIONS_DIR/Xcode.app"
touch "$APPLICATIONS_DIR/OrbStack.app"
touch "$HOME_DIR/Applications/Folder Quick Look.app"
touch "$HOME_DIR/Applications/T3 Code (Alpha).app"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq "$expected" "$file"; then
    echo "Expected to find: $expected" >&2
    echo "--- file: $file ---" >&2
    cat "$file" >&2
    fail "assert_contains"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  if grep -Fq "$unexpected" "$file"; then
    echo "Did not expect to find: $unexpected" >&2
    echo "--- file: $file ---" >&2
    cat "$file" >&2
    fail "assert_not_contains"
  fi
}

OUTPUT_FILE="$TEST_ROOT/output.txt"

env \
  PATH="$MOCK_BIN:/usr/bin:/bin" \
  HOME="$HOME_DIR" \
  "$SCRIPT_PATH" --with-formulae --export-csv --export-md --export-json --output-dir "$EXPORT_DIR" \
  > "$OUTPUT_FILE"

assert_contains "$OUTPUT_FILE" "=== Homebrew (Formulae) Packages ==="
assert_contains "$OUTPUT_FILE" "=== Homebrew (Cask) Apps ==="
assert_contains "$OUTPUT_FILE" "=== Mac App Store Apps ==="
assert_contains "$OUTPUT_FILE" "=== Manually Installed Apps ==="
assert_contains "$OUTPUT_FILE" "Folder Quick Look              v1.6"
assert_contains "$OUTPUT_FILE" "OrbStack"
assert_contains "$OUTPUT_FILE" "T3 Code (Alpha)"
assert_not_contains "$OUTPUT_FILE" "6753110395"

CSV_FILE="$EXPORT_DIR/installed_apps.csv"
MD_FILE="$EXPORT_DIR/installed_apps.md"
JSON_FILE="$EXPORT_DIR/installed_apps.json"

assert_contains "$CSV_FILE" "\"Mac App Store Apps\",\"Folder Quick Look\",\"1.6\""
assert_contains "$CSV_FILE" "\"Manually Installed Apps\",\"T3 Code (Alpha)\",\"\""
assert_not_contains "$CSV_FILE" "\"Mac App Store Apps\",\"6753110395\""

assert_contains "$MD_FILE" "| Folder Quick Look | 1.6 |"
assert_contains "$MD_FILE" "| T3 Code (Alpha) |  |"
assert_not_contains "$MD_FILE" "| 6753110395 |"

assert_contains "$JSON_FILE" "\"type\":\"Mac App Store Apps\""
assert_contains "$JSON_FILE" "\"app\":\"Folder Quick Look\""
assert_contains "$JSON_FILE" "\"app\":\"T3 Code (Alpha)\""

echo "All tests passed."
