# i18n helpers

Scripts for managing i18n translation keys and YAML files.

## CI localization health

The **Localization health** job runs on macOS with Xcode 26 or newer. From the repository root:

```sh
python3 -m pip install -r mobile/ios/Air/scripts/strings/requirements.txt
python3 -m unittest discover -s dev/locales -p 'test_*.py' -v
python3 dev/locales/check_localization_health.py --exclude-path mobile/ios/Air/SubModules/UIAgent
python3 -m unittest discover -s mobile/ios/Air/scripts/strings -p 'test_*.py' -v
```

The checker reports all findings as `file:line: [category] explanation`, then exits with status 1
if anything needs fixing. It checks:

- Key parity against `en.yaml` within each of `src/i18n`, `src/mfa/i18n`, and `src/push/i18n`.
  Plural categories and string/plural representation may differ between languages.
- Invalid YAML, duplicate keys/forms, non-string translations, and unknown plural categories.
- Positional printf parameters using the same rule as the iOS importer. Use named parameters
  such as `%amount%`; translated parameter names must exist in the English entry.
- Literal keys in web `lang`/`getTranslation`, Swift `lang`/`langMd`, widget `localized`,
  `NSLocalizedString`, `LocalizedStringResource`, `String(localized:)`, and `localizedString(forKey:)` calls.
- Literal keys in Android `LocaleController.getString`, `getStringOrNull`, `getFormattedString`,
  `getStringWithKeyValues`, `getSpannableStringWithKeyValues`, `getPluralOrFormat`, `getPlural`,
  and `getPluralWord`, including unqualified calls and named `key` arguments.

`--exclude-path` skips call sites under a repository-relative file or directory, while retaining
all catalog checks. The release CI excludes `UIAgent` call sites from this new gate so its existing
localization behavior remains unchanged; omit the option for a scan of every module.

An unknown call-site key points to the source file, suggests a nearby spelling when available,
and identifies the catalog that needs it. A key missing only in translations is reported once
per affected YAML file, with the English definition's line. All checks run before the final result;
unreadable or invalid UTF-8 files are reported without stopping the other checks. The CI Foundation
step also runs if the catalog scan fails.

The source scan is deliberately lexical. It handles multiline calls and escaped literals and ignores
comments, JavaScript regex literals at recognized expression starts, tests, generated/ignored files,
interpolation, and concatenated or variable keys. It does
not resolve aliases, imports, shared components' use in other apps, calls inside template strings,
Swift raw/multiline literals, or dynamically assembled keys. MFA and Push source files use their
own catalogs. Multisend and Portfolio are excluded because their builds explicitly use an empty
English catalog and display keys directly. The scan checks key presence, not translation quality.

The [iOS regression suite](../../mobile/ios/Air/scripts/strings/README.md) independently checks
generated argument positions/types and exercises the compiled catalogs and Swift API using real
Foundation in every language. It covers plural counts, repeated arguments, and localized domain
expiry dates. A formatting crash identifies the key, locale, and arguments; the harness resumes
after that case so later failures are also reported.

## Features
1. **Extract Missing Translations**: Scans `src/` for `lang('key')` patterns and identifies missing translations in `src/i18n/`.
2. **Update Locales**: Merges new translations from `dev/locales/input.yaml` into YAML files in `src/i18n/`.

## Usage

### Extract Missing Translations
1. Run `npm run i18n:findMissing`

2. Missing keys are written to `output.yaml`.

### Update Locales
1. Add translations to `dev/locales/input.yaml`:
    ```yaml
    en:
        $key: "English text"
    de:
        $key: "German text"
    ```

2. Run `npm run i18n:update`
