import copy
import functools
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from dataclasses import replace
from pathlib import Path

import import_localizations as importer


SCRIPT_DIR = Path(__file__).resolve().parent
LOCALES_DIR = SCRIPT_DIR.parents[4] / "src/i18n"
COUNTS = (0, 1, 2, 3, 5, 11, 21, 101)
REPEATED_KEY = "$test_repeated_interpolation"
REPEATED_VALUE = "%name%, %name%: %count%"
DOMAIN_EXPIRY_FORMS = {
    "zeroValue": "No domains expire %days%",
    "oneValue": "**%domain% domain** expires %days%",
    "otherValue": "**%domain% domains** expire %days%",
}


@functools.cache
def load_locales():
    return {path.stem: importer.load_yaml(path) for path in sorted(LOCALES_DIR.glob("*.yaml"))}


def string_units(value):
    if isinstance(value, dict):
        if "stringUnit" in value:
            yield value["stringUnit"]["value"]
        for child in value.values():
            yield from string_units(child)


def normalize_output(value):
    return "".join(
        str(unicodedata.decimal(char)) if char.isdecimal() else char
        for char in value if char not in "\u2066\u2067\u2068\u2069"
    )


class ImportLocalizationsTests(unittest.TestCase):
    def test_domain_plural_uses_interpolation_order(self):
        definition = importer.build_entry_definitions({"$domains_expire": DOMAIN_EXPIRY_FORMS})["$domains_expire"]
        self.assertEqual(
            [(p.name, p.index, p.kind.swift_type) for p in definition.parameters],
            [("days", 2, "String"), ("domain", 1, "Int")],
        )
        self.assertEqual(
            importer.replace_named_placeholders(definition.key, definition.default_value, definition),
            "**%1$(domain)lld domains** expire %2$(days)@",
        )

    def test_repeated_interpolation_reserves_argument_slot(self):
        definition = importer.build_entry_definitions({REPEATED_KEY: REPEATED_VALUE})[REPEATED_KEY]
        self.assertEqual([(p.name, p.index) for p in definition.parameters], [("name", 1), ("count", 3)])
        self.assertEqual(
            importer.replace_named_placeholders(REPEATED_KEY, "%count%: %name%", definition),
            "%3$(count)lld: %1$(name)@",
        )

    def test_invalid_indices_fail_generation_validation(self):
        definition = importer.build_entry_definitions({"$domains_expire": DOMAIN_EXPIRY_FORMS})["$domains_expire"]
        for invalid_index in (0, 1, 3):
            with self.subTest(index=invalid_index):
                invalid = replace(definition, parameters=(replace(definition.parameters[0], index=invalid_index),))
                with self.assertRaisesRegex(ValueError, "interpolation order"):
                    importer.validate_parameter_indices(invalid)

    def test_translation_cannot_introduce_an_argument_or_printf_specifier(self):
        definition = importer.build_entry_definitions({"Hello %name%": "Hello %name%"})["Hello %name%"]
        for value in ("Hello %unknown%", "Hello %@", "Hello %2$lld"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                importer.replace_named_placeholders(definition.key, value, definition)

    def test_literal_percent_is_escaped_without_changing_argument_positions(self):
        definition = importer.build_entry_definitions({"$test_percent": "%name%: 50% of %count%"})["$test_percent"]
        self.assertEqual(
            importer.replace_named_placeholders(definition.key, definition.default_value, definition),
            "%1$(name)@: 50%% of %2$(count)lld",
        )

    def test_every_catalog_argument_matches_the_emitted_swift_interpolation(self):
        locales = load_locales()
        definitions = importer.build_entry_definitions(locales["en"])
        catalog = importer.build_strings_map(locales, "en", list(locales), definitions)
        with tempfile.TemporaryDirectory() as directory:
            swift_path = Path(directory) / "L10n.swift"
            importer.write_swift_interface(swift_path, definitions)
            swift = swift_path.read_text()

        # Read the emitted Swift independently of Parameter.index, including repeated arguments.
        functions = dict(re.findall(
            r'public static func (\w+)\([^\n]*\).*?defaultValue: "([^\n]*)",', swift, re.DOTALL,
        ))
        self.assertEqual(len(functions), len(definitions))
        for key, definition in definitions.items():
            interpolations = re.findall(r'(?<!\\)\\\((\w+)(?:, specifier: "%(lld|f)")?\)', functions[definition.swift_name])
            swift_names = {p.name: p.swift_name for p in definition.parameters}
            for locale, unit in catalog[key]["localizations"].items():
                for text in string_units(unit):
                    for index, name, specifier in re.findall(r'%(\d+)\$\((\w+)\)(@|lld|f)', text):
                        with self.subTest(key=key, locale=locale, text=text, argument=name):
                            self.assertGreater(int(index), 0)
                            self.assertLessEqual(int(index), len(interpolations))
                            self.assertEqual(interpolations[int(index) - 1], (swift_names[name], "" if specifier == "@" else specifier))


@unittest.skipUnless(sys.platform == "darwin", "Foundation integration requires Xcode on macOS")
class FoundationLocalizationTests(unittest.TestCase):
    def test_generated_catalogs_and_swift_format_all_languages(self):
        xcode_version = self.run_command(["xcodebuild", "-version"])
        version_match = re.search(r"^Xcode (\d+)", xcode_version)
        self.assertIsNotNone(version_match, xcode_version)
        self.assertGreaterEqual(
            int(version_match.group(1)), 26,
            f"Named catalog placeholders require Xcode 26 or newer. Select it with DEVELOPER_DIR.\n{xcode_version}",
        )
        locales = copy.deepcopy(load_locales())
        for locale, translations in locales.items():
            translations[REPEATED_KEY] = REPEATED_VALUE if locale == "en" else "%count%: %name%, %name%"
        definitions = importer.build_entry_definitions(locales["en"])
        cases = []
        for key, definition in definitions.items():
            for count in COUNTS if definition.is_plural else (7,):
                arguments = {
                    p.name: f"ТЕСТ_{p.name}_END" if p.kind == importer.ParameterKind.STRING else count
                    for p in definition.parameters
                }
                swift_arguments = ", ".join(
                    f'{p.swift_name}: "{arguments[p.name]}"' if isinstance(arguments[p.name], str)
                    else f"{p.swift_name}: {arguments[p.name]}"
                    for p in definition.parameters
                )
                cases.append({"key": key, "arguments": arguments, "call": f"L10n.{definition.swift_name}({swift_arguments})"})

        # Real localized inputs matter: short ASCII strings can mask the Russian crash.
        for days in range(15):
            cases.append({
                "key": "$domains_expire", "arguments": {"domain": 2}, "relative_days": days,
                "call": f"L10n.domainsExpire(days: relativeDays({days}), domain: 2)",
            })

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog = importer.build_strings_map(locales, "en", list(locales), definitions)
            importer.write_catalog(root / "Localizable.xcstrings", "en", catalog)
            importer.write_swift_interface(root / "L10n.swift", definitions)
            bundle = root / "Localizations.bundle"
            bundle.mkdir()
            self.run_command(["xcrun", "xcstringstool", "compile", str(root / "Localizable.xcstrings"), "--output-directory", str(bundle)])
            switches = "\n".join(f"case {index}: return {case['call']}" for index, case in enumerate(cases))
            main = '''import Foundation
let AirBundle = Bundle(path: CommandLine.arguments[1])!
func relativeDays(_ days: Int) -> String {
    switch days {
    case 0: return AirBundle.localizedString(forKey: "$relative_today", value: nil, table: nil)
    case 1: return AirBundle.localizedString(forKey: "$relative_tomorrow", value: nil, table: nil)
    default: return L10n.inDays(count: days)
    }
}
func evaluate(_ index: Int) -> String {
    switch index {
''' + switches + '''
    default: fatalError()
    }
}
func emit(_ value: [String: Any]) {
    var data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    data.append(10)
    FileHandle.standardOutput.write(data)
}
for index in 0..<''' + str(len(cases)) + ''' {
    emit(["starting": index])
    emit(["index": index, "value": evaluate(index)])
}
'''
            (root / "main.swift").write_text(main)
            executable = root / "check-localizations"
            compiler = ["xcrun", "swiftc"]
            runner = []
            simulator = os.environ.get("LOCALIZATION_TEST_SIMULATOR_UDID")
            if simulator:
                sdk = self.run_command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).strip()
                compiler += ["-target", f"{os.uname().machine}-apple-ios18.0-simulator", "-sdk", sdk]
                runner = ["xcrun", "simctl", "spawn", simulator]
            self.run_command(compiler + [str(root / "L10n.swift"), str(root / "main.swift"), "-o", str(executable)])
            for locale, translations in locales.items():
                with self.subTest(locale=locale):
                    output = self.run_command(runner + [
                        str(executable), str(bundle / f"{locale}.lproj"),
                        "-AppleLanguages", f"({locale})", "-AppleLocale", locale,
                    ])
                    rows = [json.loads(line) for line in output.splitlines()]
                    rows = [row for row in rows if "value" in row]
                    self.assertEqual(len(rows), len(cases))
                    for row in rows:
                        case = cases[row["index"]]
                        expected = self.expected_values(case, translations, locales["en"])
                        with self.subTest(locale=locale, key=case["key"], arguments=case["arguments"], days=case.get("relative_days")):
                            self.assertIn(normalize_output(row["value"]), [normalize_output(value) for value in expected])

    def run_command(self, arguments):
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, f"{arguments}\n{result.stdout[-2000:]}\n{result.stderr[-4000:]}")
        return result.stdout

    def expected_values(self, case, translations, english):
        def forms(key):
            return importer.strings_in_value(translations.get(key, english[key]))

        arguments = case["arguments"]
        if "relative_days" in case:
            days = case["relative_days"]
            if days < 2:
                day_values = forms("$relative_today" if days == 0 else "$relative_tomorrow")
            else:
                day_values = [text.replace("%count%", str(days)) for text in forms("$in_days")]
            argument_sets = [dict(arguments, days=text) for text in day_values]
        else:
            argument_sets = [arguments]
        return [
            importer.NAMED_PLACEHOLDER_RE.sub(lambda match: str(values[match.group(1)]), text)
            for values in argument_sets for text in forms(case["key"])
        ]


if __name__ == "__main__":
    unittest.main()
