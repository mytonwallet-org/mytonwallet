# Localization Tools

This directory contains scripts for managing and validating localization files.

## Scripts

### `check_localization_completeness.py`

A Python script that compares localization files against the base English localization to find:
- **Missing keys**: Keys that exist in the base but are missing from the target localization
- **Extraneous keys**: Keys that exist in the target localization but not in the base

**Note**: This script only checks for actual keys, not plural form variations (otherValue, manyValue, fewValue, etc.) since plural forms are language-dependent and expected to vary between languages.

#### Usage

```bash
# Basic usage
python3 check_localization_completeness.py --base /path/to/en.yaml --compare /path/to/ru.yaml

# With verbose output (shows statistics)
python3 check_localization_completeness.py --base /path/to/en.yaml --compare /path/to/ru.yaml --verbose

# Get help
python3 check_localization_completeness.py --help
```

#### Examples

```bash
# Check Russian localization
python3 check_localization_completeness.py \
  --base /Users/nikstar/Developer/mytonwallet-dev/src/i18n/en.yaml \
  --compare /Users/nikstar/Developer/mytonwallet-dev/src/i18n/ru.yaml

# Check air subdirectory localizations
python3 check_localization_completeness.py \
  --base /Users/nikstar/Developer/mytonwallet-dev/src/i18n/air/en.yaml \
  --compare /Users/nikstar/Developer/mytonwallet-dev/src/i18n/air/ru.yaml
```

#### Output

The script provides clear output showing:
- Missing keys in the target localization
- Extraneous keys in the target localization
- Summary counts
- Exit code (0 for success, 1 for issues found)

### `find_unused_localization_keys.py`

A Python script that scans all Swift files in the iOS folder and finds localization keys used in code that are NOT present in the localization YAML files.

**Features**:
- Scans all `.swift` files in the iOS directory
- Uses regex pattern `lang("key"` (no closing paren) to find localization usage
- Compares against both main and air localization files
- **Reports missing keys with source file names in parentheses**
- Shows usage examples with file names and line numbers
- Helps identify hardcoded strings that should be localized

**Output Format**:
```text
❌ MISSING KEYS IN LOCALIZATION FILES:
   Found 166 keys used in Swift code but missing from YAML files

  - 'Try again' (LedgerAddAccountView.swift, LedgerSignView.swift)
  - 'Add Stake' (AddStakeVC.swift, EarnHeaderCell.swift)
  - 'No Camera Access' (NoCameraAccessView.swift)
```

#### Usage

```bash
# Basic usage (from scripts/strings directory)
python3 find_unused_localization_keys.py --ios-path ../../../..

# With verbose output
python3 find_unused_localization_keys.py --ios-path ../../../.. --verbose

# Get help
python3 find_unused_localization_keys.py --help
```

### `check_localizations.sh`

A convenience shell script that automatically checks common localizations against their English base files.

#### Usage

```bash
# Run all checks
./check_localizations.sh

# Or from anywhere
/Users/nikstar/Developer/mytonwallet-dev/mobile/ios/Air/scripts/strings/check_localizations.sh
```

This script will automatically:
- Check main localizations (src/i18n/)
- Check air localizations (src/i18n/air/)
- Provide colored output for easy reading
- Show summary of all checks

## Project Structure

The scripts work with the following localization structure:

```
src/i18n/
├── en.yaml          # Base English localization
├── ru.yaml          # Russian localization
└── air/
    ├── en.yaml      # Base English for air features
    └── ru.yaml      # Russian for air features
```

## Requirements

- Python 3.6+
- PyYAML (`pip install pyyaml`)

## Exit Codes

- `0`: No issues found (localization is complete)
- `1`: Issues found (missing or extraneous keys)

## Integration

These scripts can be integrated into CI/CD pipelines to automatically validate localization completeness:

```bash
#!/bin/bash
# CI script example
python3 check_localization_completeness.py --base src/i18n/en.yaml --compare src/i18n/ru.yaml
if [ $? -ne 0 ]; then
    echo "Localization check failed!"
    exit 1
fi
```
