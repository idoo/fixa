#!/usr/bin/env python3
"""Fail if any catalog key lacks a translated value or has mismatched format specifiers, or if
a Swift `String(localized:` call lacks `bundle:` (it would ignore the in-app language).

Usage: python3 scripts/check-strings.py
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    ROOT / "Fixa/Resources/Localizable.xcstrings",
    ROOT / "Fixa/Resources/InfoPlist.xcstrings",
]
LANGUAGES = ["en", "sv", "cs", "da", "de", "et", "es", "fr", "it", "lv", "lt", "hu", "nl", "nb", "pl", "pt", "ro", "fi", "el", "ru", "uk", "ar"]
# %@, %lld, %d, %.5f, positional %1$@ … ; %% is a literal percent sign.
SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDuUxXoOfFeEgGcCsSaAp%]")


def specifiers(text):
    found = []
    for match in SPECIFIER.findall(text):
        if match == "%%":
            continue
        found.append(re.sub(r"^%\d+\$", "%", match))
    return Counter(found)


def values(entry, language):
    """Every translated value for a language (plain or plural/device variations)."""
    localization = entry.get("localizations", {}).get(language)
    if localization is None:
        return None
    units = []

    def collect(node):
        if "stringUnit" in node:
            units.append(node["stringUnit"])
        for variants in node.get("variations", {}).values():
            for child in variants.values():
                collect(child)

    collect(localization)
    return units


def missing_bundle():
    """`String(localized:` calls without `bundle:`; they resolve the iPhone's language, not Fixa's."""
    found = []
    for path in sorted((ROOT / "Fixa").rglob("*.swift")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            calls = line.split("String(localized:")[1:]
            for call in calls:
                if "bundle:" not in call:
                    found.append(f"{path.relative_to(ROOT)}:{number}: String(localized:) without bundle: L10n.bundle")
    return found


def main():
    errors = []
    errors.extend(missing_bundle())
    counts = {}
    for path in CATALOGS:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        source_language = catalog.get("sourceLanguage", "en")
        counts[path.name] = Counter()
        for key, entry in catalog["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            source_units = values(entry, source_language)
            source_text = source_units[0]["value"] if source_units else key
            expected = specifiers(source_text)
            for language in LANGUAGES:
                units = values(entry, language)
                if not units:
                    if language == source_language:
                        counts[path.name][language] += 1
                        continue
                    errors.append(f"{path.name}: {key!r}: missing {language}")
                    continue
                ok = True
                for unit in units:
                    if unit.get("state") != "translated" or not unit.get("value", "").strip():
                        errors.append(f"{path.name}: {key!r}: {language} not translated")
                        ok = False
                    elif specifiers(unit["value"]) != expected:
                        errors.append(
                            f"{path.name}: {key!r}: {language} specifiers "
                            f"{dict(specifiers(unit['value']))} != {dict(expected)}"
                        )
                        ok = False
                if ok:
                    counts[path.name][language] += 1
        total = sum(1 for e in catalog["strings"].values() if e.get("shouldTranslate") is not False)
        summary = ", ".join(f"{lang} {counts[path.name][lang]}/{total}" for lang in LANGUAGES)
        print(f"{path.name}: {summary}")

    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} problem(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
