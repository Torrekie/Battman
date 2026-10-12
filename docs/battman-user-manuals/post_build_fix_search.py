#!/usr/bin/env python3
"""Validate the localized search output produced by the MkDocs plug-in.

Kept as a compatible post-build entry point for the existing preview/deploy
scripts. Search generation now runs after i18n in the plug-in itself.
"""
import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


def main():
    site = Path(sys.argv[1] if len(sys.argv) > 1 else "site")
    for locale in ("", "zh", "zh_TW"):
        root = site / locale
        for resource in ("search.html", "search/main.js", "search/worker.js", "search/search_index.json"):
            if not (root / resource).is_file():
                raise ValueError(f"Missing search resource: {locale or 'en'}/{resource}")
        data = json.loads((root / "search/search_index.json").read_text(encoding="utf-8"))
        if not data.get("docs"):
            raise ValueError(f"Empty search index for {locale or 'en'}")
        for entry in data["docs"]:
            path = unquote(urlsplit(entry["location"]).path)
            if path.startswith(("/", "zh/", "zh_TW/")):
                raise ValueError(f"Non-local search result in {locale or 'en'}: {path}")
            target = root / path
            if target.is_dir():
                target /= "index.html"
            if not target.is_file():
                raise ValueError(f"Missing search result in {locale or 'en'}: {path}")
        print(f"{locale or 'en'} search verified: {len(data['docs'])} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
