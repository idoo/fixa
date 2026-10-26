#!/usr/bin/env python3
"""Fail if any catalog key lacks a translated value or has mismatched format specifiers.

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
LANGUAGES = ["en", "sv", "fi", "ar", "uk", "pl"]
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


def main():
    errors = []
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
