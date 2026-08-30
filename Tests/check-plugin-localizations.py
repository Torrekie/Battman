#!/usr/bin/env python3

"""Keep plug-in management and consent copy synchronized across catalogs."""

from __future__ import annotations

import ast
from collections import Counter
import re
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATHS = (
    REPO_ROOT / "Battman" / "PluginHost" / "UI",
    REPO_ROOT / "Battman" / "SettingsViewController.m",
)
CATALOG_ROOT = REPO_ROOT / "Battman" / "Localizations"
CATALOGS = tuple(
    CATALOG_ROOT / name
    for name in ("base.pot", "en.po", "de.po", "zh_CN.po", "zh_TW.po")
)
LOCALIZED_STRING_PATTERN = re.compile(r'_\(\s*"((?:\\.|[^"\\])*)"\s*\)')
FORMAT_PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?(?:@|lu|ld|u|d|s)")


def decode_po_string(fragment: str) -> str:
    value = ast.literal_eval(fragment)
    if not isinstance(value, str):
        raise ValueError(f"expected a quoted string, got {fragment!r}")
    return value


def parse_catalog(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    msgid: str | None = None
    msgstr = ""
    active_field: str | None = None

    def finish_entry() -> None:
        nonlocal msgid, msgstr, active_field
        if msgid is not None:
            if msgid in entries:
                raise ValueError(f"{path}: duplicate msgid {msgid!r}")
            entries[msgid] = msgstr
        msgid = None
        msgstr = ""
        active_field = None

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if line.startswith("#~"):
            raise ValueError(f"{path}:{line_number}: obsolete gettext entry is not allowed")
        if line.startswith("msgid "):
            finish_entry()
            msgid = decode_po_string(line[len("msgid ") :])
            active_field = "msgid"
        elif line.startswith("msgstr "):
            if msgid is None:
                raise ValueError(f"{path}:{line_number}: msgstr without msgid")
            msgstr = decode_po_string(line[len("msgstr ") :])
            active_field = "msgstr"
        elif line.startswith('"'):
            continuation = decode_po_string(line)
            if active_field == "msgid" and msgid is not None:
                msgid += continuation
            elif active_field == "msgstr":
                msgstr += continuation
        elif not line:
            finish_entry()
    finish_entry()
    return entries


def source_files():
    for path in SOURCE_PATHS:
        if path.is_dir():
            yield from sorted(path.rglob("*.m"))
        else:
            yield path


def required_strings() -> set[str]:
    strings: set[str] = set()
    for path in source_files():
        source = path.read_text(encoding="utf-8")
        for encoded in LOCALIZED_STRING_PATTERN.findall(source):
            strings.add(decode_po_string(f'"{encoded}"'))
    return strings


def main() -> None:
    required = required_strings()
    if not required:
        raise SystemExit("no plug-in UI localization strings were discovered")
    for path in CATALOGS:
        entries = parse_catalog(path)
        missing = sorted(required - entries.keys())
        if missing:
            raise SystemExit(f"{path}: missing plug-in UI msgids: {', '.join(missing)}")
        if path.suffix == ".po":
            untranslated = sorted(msgid for msgid in required if not entries[msgid].strip())
            if untranslated:
                raise SystemExit(f"{path}: untranslated plug-in UI msgids: {', '.join(untranslated)}")
            placeholder_mismatches = sorted(
                msgid
                for msgid in required
                if Counter(FORMAT_PLACEHOLDER_PATTERN.findall(msgid))
                != Counter(FORMAT_PLACEHOLDER_PATTERN.findall(entries[msgid]))
            )
            if placeholder_mismatches:
                raise SystemExit(
                    f"{path}: format placeholders differ from msgid: "
                    f"{', '.join(placeholder_mismatches)}"
                )
    msgfmt = shutil.which("msgfmt")
    if msgfmt:
        for path in CATALOGS[1:]:
            subprocess.run([msgfmt, "--check", "-o", "/dev/null", str(path)], check=True)
    print(
        f"Plug-in consent and management localization coverage passed: "
        f"{len(required)} strings across {len(CATALOGS)} tracked catalogs."
    )


if __name__ == "__main__":
    main()
