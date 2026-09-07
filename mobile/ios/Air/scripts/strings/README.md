# Localization Tools

This directory contains scripts for managing and validating localization files.

## Generation pipeline

`import_localizations.py` treats `src/i18n/*.yaml` as the source of truth and generates:

- the WalletResources, app, and widget `.xcstrings` catalogs;
- `WalletContext/Localization/GeneratedLocalizations.swift`, the public, typed `L10n` API.

Formatted entries keep their existing localization key and use named placeholders:

```yaml
"%amount% NFTs":
  zeroValue: No NFTs
  oneValue: "%amount% NFT"
  otherValue: "%amount% NFTs"
```

The importer derives a lower-camel-case Swift symbol from the raw key, including placeholder names
and excluding punctuation. For example, `Open %nft_marketplace%` becomes `openNftMarketplace`.
Generation fails if two formatted keys produce the same symbol. The importer also infers argument
types, converts placeholders to Apple's named format syntax in the catalog, and disables Xcode's
automatic symbol generation for every catalog entry. Integer/plural heuristics and the small
exception table live in `import_localizations.py`; a wrong inferred type therefore fails at a typed
Swift call site during compilation instead of reaching `String(format:)` at runtime.

Run the importer from the repository root with:

```bash
mobile/ios/Air/scripts/strings/.venv/bin/python \
  mobile/ios/Air/scripts/strings/import_localizations.py
```

Do not add positional `%@`, `%d`, or `%1$…` placeholders to YAML. Non-iOS clients keep the named
placeholder spelling and use the English definition to map existing positional call arguments.

Catalog argument positions follow the interpolation occurrences in the selected Swift default
value, including repeated placeholders. Public Swift parameter order is independent: a zero plural
form may mention parameters in a different order or omit them. The importer rejects inconsistent
argument positions before writing generated files.

Run the regression suite with:

```bash
PYTHONDONTWRITEBYTECODE=1 mobile/ios/Air/scripts/strings/.venv/bin/python -m unittest discover \
  -s mobile/ios/Air/scripts/strings -p 'test_*.py' -v
```

CI runs the suite on `macos-26`, matching the iOS release runner. Xcode 26 or newer is required
to compile the named catalog placeholders; the integration test checks this before compilation.
It checks every catalog placeholder against the emitted
Swift interpolation, then uses Xcode and Foundation to compile and format all generated
functions in all languages. Runtime cases include repeated placeholders, plural counts, and real
localized domain-expiry date strings. To run the Foundation check on an already booted iOS Simulator,
set `LOCALIZATION_TEST_SIMULATOR_UDID` to its UDID before running the command above.

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
# Check Russian localization (paths relative to this directory)
python3 check_localization_completeness.py \
  --base ../../../../../src/i18n/en.yaml \
  --compare ../../../../../src/i18n/ru.yaml
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
- Compares against the main localization file
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
# Basic usage; the repository root is found from the script's own location
python3 find_unused_localization_keys.py

# With verbose output
python3 find_unused_localization_keys.py --verbose

# Point it at a different checkout
python3 find_unused_localization_keys.py --ios-path /path/to/repo

# Get help
python3 find_unused_localization_keys.py --help
```

### `check_localizations.sh`

A convenience shell script that automatically checks common localizations against their English base files.

#### Usage

```bash
# Run all checks
./check_localizations.sh

# Or from anywhere — the repo root is derived from the script's own location
path/to/repo/mobile/ios/Air/scripts/strings/check_localizations.sh

# Override the repo root if the scripts were copied out of the repository
BASE_DIR=/path/to/repo ./check_localizations.sh
```

This script will automatically:
- Check every non-English main localization in `src/i18n/` against English
- Check literal Swift `lang("...")` keys against the English catalog
- Provide colored output for easy reading
- Show summary of all checks

## Project Structure

The scripts work with the following localization structure:

```
src/i18n/
├── en.yaml          # Base English localization
├── ar.yaml          # Arabic localization
├── de.yaml          # German localization
├── ...
└── zh-Hant.yaml     # Traditional Chinese localization
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
