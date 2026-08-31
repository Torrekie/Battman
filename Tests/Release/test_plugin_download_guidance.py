#!/usr/bin/env python3
"""Static contract checks for the in-app plug-in download guidance."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Battman/PluginHost/UI/BTPluginManagementViewController.m"
IMPORT_PRESENTER = ROOT / "Battman/PluginHost/UI/BTPluginImportPresenter.m"
CATALOGS = (
    ROOT / "Battman/Localizations/base.pot",
    ROOT / "Battman/Localizations/en.po",
    ROOT / "Battman/Localizations/de.po",
    ROOT / "Battman/Localizations/zh_CN.po",
    ROOT / "Battman/Localizations/zh_TW.po",
)


GUIDANCE_STRINGS = (
    "Download Guide",
    "Use the package that matches how Battman is installed.",
    "Rooted jailbreak (iOS 12+): install the matching host or plug-in iphoneos-arm .deb with APT/dpkg; do not use iphoneos-arm64.",
    "Rootless jailbreak (iOS 15+): install the matching host or plug-in iphoneos-arm64 .deb with APT/dpkg; do not use iphoneos-arm.",
    "TrollStore (iOS 14+): install the replacement Battman.tipa. Native plug-ins must be embedded in that replacement app; newly imported native code is not loaded directly from the app data directory.",
    "A .battman file is an import transport. Battman verifies it before approval; it is not a direct installer.",
    "Havoc is a manually selected Debian-only channel. GitHub Releases is the canonical place for reviewed artifacts. Never install a package for another architecture.",
    "Use Download Guide for architecture-specific package instructions.",
    "Open GitHub Releases",
    "Open Installation Guide",
    "Open Havoc",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def translated_value(catalog: str, msgid: str) -> str | None:
    escaped = re.escape(msgid)
    match = re.search(
        rf'msgid "{escaped}"\nmsgstr "(?P<value>[^"]*)"',
        catalog,
    )
    return match.group("value") if match else None


def main() -> int:
    source = SOURCE.read_text(encoding="utf-8")
    import_presenter = IMPORT_PRESENTER.read_text(encoding="utf-8")
    require("BTPluginDownloadGuideMessage" in source, "download guide helper is missing")
    require("presentDownloadGuide" in source, "download guide action is missing")
    require("BTPluginOpenExternalURL" in source, "external URL helper is missing")
    require("rightBarButtonItems" in source, "download guide is not discoverable in navigation")
    require("Use Download Guide for architecture-specific package instructions." in import_presenter,
            "quarantine alert does not point to the download guide")
    for fragment in (
        "https://github.com/Torrekie/Battman/releases/latest",
        "https://havoc.app/package/battman",
        "/installation/",
        "BATTMAN_DOC_URL",
    ):
        require(fragment in source, f"download route is missing: {fragment}")
    for string in GUIDANCE_STRINGS:
        require(f'_(\"{string}\")' in source, f"source is missing guidance string: {string}")

    # Keep every shipped locale aligned with the generated localization table.
    # An empty translation is allowed only in the POT template, never in a PO.
    for catalog_path in CATALOGS:
        catalog = catalog_path.read_text(encoding="utf-8")
        for string in GUIDANCE_STRINGS:
            require(f'msgid "{string}"' in catalog,
                    f"{catalog_path.name} is missing msgid: {string}")
            value = translated_value(catalog, string)
            if catalog_path.suffix == ".po":
                require(value is not None and value != "",
                        f"{catalog_path.name} has no translation: {string}")

    # Guidance must remain conservative: imports are verification/quarantine
    # transports, not an implicit data-directory native loader.
    require("not a direct installer" in source, "transport boundary wording drifted")
    require("not loaded directly from the app data directory" in source,
            "TrollStore data-directory boundary wording drifted")
    print("Plug-in download and architecture guidance contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
