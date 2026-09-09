import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import check_localization_health as health


class LocalizationHealthTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_reports_all_catalog_and_call_errors_together(self):
        self.write("src/i18n/en.yaml", 'First: First\nSecond: Second\nAmount: "%amount%"\n')
        self.write("src/i18n/ru.yaml", 'Extra: Extra\nAmount: "%wrong% %@ %2$d"\n')
        self.write("src/i18n/de.yaml", 'First: [broken\n')
        swift = self.write("mobile/ios/Screen.swift", 'lang("Missing iOS")\nlangMd("Another missing key")')
        web = self.write("src/Screen.tsx", "lang('Missing web')")
        android = self.write("mobile/android/Screen.kt", 'LocaleController.getString("Missing Android")')
        issues = health.check(self.root, [(swift, "ios"), (web, "web"), (android, "android")])
        self.assertEqual(len(issues), 10)
        self.assertCountEqual([issue.code for issue in issues], [
            "missing-key", "missing-key", "extra-key", "positional", "placeholder", "yaml",
            "unlocalized-call", "unlocalized-call", "unlocalized-call", "unlocalized-call",
        ])
        report = "\n".join(issue.render(self.root) for issue in issues)
        for expected in ("Screen.swift:2:", "en.yaml:2", "'%@', '%2$d'", "Allowed by en.yaml: amount"):
            self.assertIn(expected, report)

    def test_plural_categories_and_string_vs_plural_may_differ_by_language(self):
        self.write("src/i18n/en.yaml", 'Words: "%count% words"\nDays:\n  oneValue: One day\n  otherValue: "%count% days"\nPercent: 50% off\n')
        self.write("src/i18n/ru.yaml", 'Words:\n  oneValue: "%count% слово"\n  manyValue: "%count% слов"\nDays: "%count% дней"\nPercent: 50% скидка\n')
        self.assertEqual(health.check(self.root, []), [])

    def test_call_site_exclusion_preserves_catalog_and_other_source_checks(self):
        self.write("src/i18n/en.yaml", "Existing: Existing\n")
        self.write("src/i18n/ru.yaml", "Existing: Existing\nExtra: Extra\n")
        excluded = self.write("mobile/ios/Deferred/Screen.swift", 'lang("Deferred key")')
        included = self.write("mobile/ios/Screen.swift", 'lang("Missing key")')
        sources = [(excluded, "ios"), (included, "ios")]
        self.assertEqual(len(health.check(self.root, sources)), 3)
        issues = health.check(self.root, sources, [Path("mobile/ios/Deferred")])
        self.assertCountEqual([issue.code for issue in issues], ["extra-key", "unlocalized-call"])
        self.assertEqual(next(issue.path for issue in issues if issue.code == "unlocalized-call"), included)

    def test_duplicate_keys_invalid_types_and_plural_forms_are_actionable(self):
        self.write("src/i18n/en.yaml", '"No": No\nKey: value\nKey: duplicate\nPlural:\n  oneValue: One\n  oneValue: Again\n  wrongValue: Wrong\n')
        issues = health.check(self.root, [])
        self.assertCountEqual([issue.code for issue in issues], ["value", "duplicate", "duplicate", "plural"])
        self.assertEqual([issue.line for issue in issues], [1, 3, 6, 7])

    def test_plural_errors_and_legacy_placeholders_are_all_reported(self):
        self.write("src/i18n/en.yaml", 'A: "%@"\nB:\n  oneValue: "%1$lld"\n  otherValue: "%2$@ %3$d"\nC: null\nD: {}\n')
        issues = health.check(self.root, [])
        self.assertCountEqual([issue.code for issue in issues], ["positional"] * 3 + ["value", "plural"])

    def test_empty_or_missing_source_does_not_hide_errors_in_other_files(self):
        self.write("src/i18n/ru.yaml", 'A: "%@"\n')
        self.assertCountEqual([issue.code for issue in health.check(self.root, [])], ["source", "positional"])
        self.write("src/i18n/en.yaml", "")
        self.assertCountEqual([issue.code for issue in health.check(self.root, [])], ["yaml", "positional"])

    def test_each_app_uses_its_own_catalog(self):
        self.write("src/i18n/en.yaml", "Main: Main\n")
        self.write("src/mfa/i18n/en.yaml", "MFA: MFA\n")
        self.write("src/push/i18n/en.yaml", "Push: Push\n")
        self.write("src/push/i18n/ru.yaml", "Extra: Extra\n")
        mfa = self.write("src/mfa/App.tsx", "lang('MFA'); lang('Main');")
        push = self.write("src/push/App.tsx", "lang('Push');")
        issues = health.check(self.root, [(mfa, "web"), (push, "web")])
        self.assertCountEqual([issue.code for issue in issues], ["unlocalized-call", "missing-key", "extra-key"])
        self.assertIn("src/mfa/i18n/en.yaml", next(issue.message for issue in issues if issue.code == "unlocalized-call"))

    def test_web_literals_escapes_multiline_comments_and_dynamic_calls(self):
        text = r'''// lang('Comment')
/* getTranslation('Block comment') */
const example = "lang('Example')";
lang(
  'It\'s ready', amount
);
getTranslation("First\nSecond"); lang(`Static template`);
lang(`Dynamic ${key}`); lang('Prefix ' + variable); lang(key);
lang("\u0041\u{42}\x43");
'''
        self.assertEqual(list(health.literal_calls(text, "web")), [
            ("It's ready", 5), ("First\nSecond", 7), ("Static template", 7), ("ABC", 9),
        ])

    def test_web_regex_literals_do_not_create_calls_or_hide_real_calls(self):
        examples = [
            'const pattern = /lang("Missing")/;',
            'function pattern() { return /getTranslation("Missing")/g; }',
            'const pattern = () => /lang("Missing")/;',
            'test(/lang("Missing")/);',
            'const patterns = [/lang("Missing")/];',
            r'const pattern = /[/]lang("Missing")\//;',
            'if (test(value)) /lang("Missing")/.test(value);',
            # A quote inside a regex must not consume code after the regex.
            'const quote = /"/;',
            # Production Markdown escaping patterns in agentV2Copy.ts and AgentV2SemanticContent.tsx.
            r"value.replace(/([\\|`*_{}[\]()#+.!~-])/gu, '\\$1');",
            r"value.replace(/([|`*_{}()#+.!<>~-])/gu, '\\$1');",
        ]
        for source in examples:
            with self.subTest(source=source):
                source += '\nlang("Real");\nconst template = `Later template`;'
                self.assertEqual(list(health.literal_calls(source, "web")), [("Real", 2)])

        for source in (
            'value / lang("Real") / divisor;',
            'getValue() / lang("Real") / divisor;',
            'value++ / lang("Real") / divisor;',
            '<span></span><span>{lang("Real")}</span>;',
        ):
            with self.subTest(source=source):
                self.assertEqual(list(health.literal_calls(source, "web")), [("Real", 1)])

    def test_invalid_utf8_does_not_hide_other_catalog_or_source_errors(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("src/i18n/en.yaml", "Existing: Existing\n")
        self.write("src/i18n/ru.yaml", "Extra: Extra\n")
        self.write("src/i18n/de.yaml", "").write_bytes(b"Existing: \xff\n")
        self.write("src/Broken.ts", "").write_bytes(b"\xff")
        self.write("mobile/ios/Screen.swift", 'lang("Missing iOS")')
        result = subprocess.run([sys.executable, str(Path(health.__file__)), "--root", str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "")
        for expected in ("src/i18n/de.yaml:1: [yaml]", "src/Broken.ts:1: [source]", "UTF-8", "Missing iOS", "[missing-key]", "[extra-key]", "Localization health: 5 issue(s)."):
            self.assertIn(expected, result.stdout)

    def test_swift_helpers_and_interpolation(self):
        text = r'''lang("Hello"); langMd("Markdown"); localized("Widget");
NSLocalizedString("System", comment: "");
LocalizedStringResource("Resource", defaultValue: "Fallback");
Bundle.main.localizedString(forKey: "Bundle key", value: nil, table: nil);
lang("Prefix \(value)"); lang("First" + "Second");
lang("Escaped \\(literal)"); lang("Привет");
String(localized: "Localized constructor"); String("Ordinary string");
'''
        self.assertEqual(list(health.literal_calls(text, "ios")), [
            ("Hello", 1), ("Markdown", 1), ("Widget", 1), ("System", 2), ("Resource", 3),
            ("Bundle key", 4), (r"Escaped \(literal)", 6), ("Привет", 6),
            ("Localized constructor", 7),
        ])

    def test_android_helpers_named_arguments_and_dollar_escapes(self):
        text = r'''LocaleController.getString("\$key"); getStringOrNull("Nullable");
LocaleController.getPlural(count(foo, bar), "\$plural");
LocaleController.getPluralWord(key = "Words", amount = count);
LocaleController.getPluralOrFormat("Format", count);
LocaleController.getStringWithKeyValues("Values", listOf("%value%" to value));
LocaleController.getSpannableStringWithKeyValues("Spans", listOf());
LocaleController.getFormattedString("Legacy helper", listOf());
LocaleController.getString("$dynamic"); LocaleController.getString("${expression}");
LocaleController.getString("Prefix" + suffix); context.getString("Unrelated");
'''
        self.assertEqual(list(health.literal_calls(text, "android")), [
            ("$key", 1), ("Nullable", 1), ("$plural", 2), ("Words", 3), ("Format", 4),
            ("Values", 5), ("Spans", 6), ("Legacy helper", 7),
        ])

    def test_cli_failure_lists_all_findings_and_honors_source_exclusions(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write(".gitignore", "ignored/\n")
        self.write("src/i18n/en.yaml", "Existing: Existing\n")
        self.write("src/i18n/ru.yaml", "Extra: Extra\n")
        self.write("src/Screen.tsx", "lang('Missing one'); getTranslation('Missing two');")
        for name in ("src/Screen.test.ts", "src/ignored/Screen.ts", "src/multisend/Screen.ts", "mobile/ios/Tests/Screen.swift"):
            self.write(name, 'lang("Ignored")')
        result = subprocess.run([sys.executable, str(Path(health.__file__)), "--root", str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Localization health: 4 issue(s).", result.stdout)
        for expected in ("Missing one", "Missing two", "[missing-key]", "[extra-key]"):
            self.assertIn(expected, result.stdout)
        self.assertNotIn("Ignored", result.stdout)


if __name__ == "__main__":
    unittest.main()
