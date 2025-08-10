# list-macOS-apps

A shell script to list all installed applications on macOS, from various sources.

## Description

This script lists installed applications from:

*   Homebrew (Casks)
*   Mac App Store
*   Manually installed applications (in `/Applications` and `~/Applications`)
*   Homebrew (Formulae) (optional)

## Usage

```bash
./list-installed-apps.sh [options]
```

### Options

*   `--with-formulae`: Include Homebrew formulae in the list.
*   `--export-csv`: Export the list to a CSV file (`installed_apps.csv`).
*   `--export-md`: Export the list to a Markdown file (`installed_apps.md`).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
