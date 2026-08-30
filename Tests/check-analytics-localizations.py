#!/usr/bin/env python3

"""Keep Analytics source strings synchronized with Battman's tracked catalogs."""

from __future__ import annotations

import ast
import re
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ANALYTICS_ROOT = REPO_ROOT / "Battman" / "Features" / "Analytics"
CATALOG_ROOT = REPO_ROOT / "Battman" / "Localizations"
CATALOGS = (
    CATALOG_ROOT / "base.pot",
    CATALOG_ROOT / "en.po",
    CATALOG_ROOT / "de.po",
    CATALOG_ROOT / "zh_CN.po",
    CATALOG_ROOT / "zh_TW.po",
)
LOCALIZED_STRING_PATTERN = re.compile(r'_\(\s*"((?:\\.|[^"\\])*)"\s*\)')


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


def analytics_source_strings() -> set[str]:
    strings: set[str] = set()
    for path in sorted(ANALYTICS_ROOT.rglob("*")):
        if path.suffix not in {".h", ".m"}:
            continue
        source = path.read_text(encoding="utf-8")
        for encoded in LOCALIZED_STRING_PATTERN.findall(source):
            strings.add(decode_po_string(f'"{encoded}"'))
    return strings


def main() -> None:
    required = analytics_source_strings()
    if not required:
        raise SystemExit("no Analytics localization strings were discovered")

    parsed_catalogs = {path: parse_catalog(path) for path in CATALOGS}
    for path, entries in parsed_catalogs.items():
        missing = sorted(required - entries.keys())
        if missing:
            raise SystemExit(f"{path}: missing Analytics msgids: {', '.join(missing)}")
        if path.suffix == ".po":
            untranslated = sorted(msgid for msgid in required if not entries[msgid].strip())
            if untranslated:
                raise SystemExit(f"{path}: untranslated Analytics msgids: {', '.join(untranslated)}")

    msgfmt = shutil.which("msgfmt")
    if msgfmt:
        for path in CATALOGS[1:]:
            subprocess.run([msgfmt, "--check", "-o", "/dev/null", str(path)], check=True)

    print(
        f"Analytics localization coverage passed: {len(required)} strings "
        f"across {len(CATALOGS)} tracked catalogs."
    )


if __name__ == "__main__":
    main()
