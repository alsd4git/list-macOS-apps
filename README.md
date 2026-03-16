# list-macOS-apps

CLI script to inventory installed macOS apps across Homebrew, Mac App Store, and local Applications folders.

## Features

- Lists Homebrew casks.
- Lists Mac App Store applications when `mas` is available.
- Lists manually installed `.app` bundles from `/Applications` and `~/Applications`.
- Optionally includes Homebrew formulae.
- Exports the same canonical inventory to CSV, Markdown, and JSON.

## Requirements

- macOS
- Bash
- `brew` for Homebrew sections
- `mas` for Mac App Store sections

The script does not install dependencies automatically. If a command is not available, the related section is skipped with a warning.

## Usage

```bash
./list-installed-apps.sh [options]
```

## Options

- `--with-formulae`: Include Homebrew formulae in the output.
- `--export-csv`: Export the inventory to `installed_apps.csv`.
- `--export-md`: Export the inventory to `installed_apps.md`.
- `--export-json`: Export the inventory to `installed_apps.json`.
- `--output-dir DIR`: Write export files into `DIR`.
- `--help`: Print usage information.

## Output model

All output formats are generated from a single internal inventory model so app names with spaces, Mac App Store entries, and manual-app deduplication stay consistent across console output and exports.

## Development

Validation commands:

```bash
bash -n list-installed-apps.sh
shellcheck list-installed-apps.sh
./tests/test-list-installed-apps.sh
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
