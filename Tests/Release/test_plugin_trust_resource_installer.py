#!/usr/bin/env python3
"""Focused safety tests for app-bundled public trust resource installation."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Scripts/Build/install-plugin-trust-resources.py"
SPEC = importlib.util.spec_from_file_location("battman_trust_installer", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def expect_failure(action, label: str) -> None:
    try:
        action()
    except (OSError, MODULE.ResourceError):
        return
    raise AssertionError(f"expected hard failure: {label}")


def fixture(source: Path) -> None:
    signatures = source / "TrustMetadata.signatures"
    signatures.mkdir(parents=True, mode=0o755)
    (source / "RootPolicy.plist").write_bytes(b"root-policy")
    (source / "TrustMetadata.json").write_bytes(b"{}")
    (signatures / ("a" * 64 + ".sig")).write_bytes(b"signature")
    for path in source.rglob("*"):
        path.chmod(0o755 if path.is_dir() else 0o644)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="battman-trust-installer-") as raw:
        temporary = Path(raw)
        absent_source = temporary / "absent"
        empty_app = temporary / "Empty.app"
        empty_app.mkdir(mode=0o755)
        assert MODULE.install(absent_source, empty_app) == "absent"
        assert not (empty_app / "PluginTrust").exists()

        source = temporary / "PluginTrust"
        fixture(source)
        app = temporary / "Battman.app"
        app.mkdir(mode=0o755)
        assert MODULE.install(source, app) == "installed"
        assert MODULE.install(source, app) == "already-current"
        copied = app / "PluginTrust"
        assert (copied / "TrustMetadata.json").read_bytes() == b"{}"

        (copied / "TrustMetadata.json").write_bytes(b"different")
        expect_failure(lambda: MODULE.install(source, app), "stale destination merge")

        stale_app = temporary / "Stale.app"
        stale_app.mkdir(mode=0o755)
        (stale_app / "PluginTrust").mkdir(mode=0o755)
        expect_failure(lambda: MODULE.install(absent_source, stale_app), "stale destination without source")

        linked_source = temporary / "LinkedTrust"
        fixture(linked_source)
        (linked_source / "TrustMetadata.json").unlink()
        (linked_source / "TrustMetadata.json").symlink_to(source / "TrustMetadata.json")
        linked_app = temporary / "Linked.app"
        linked_app.mkdir(mode=0o755)
        expect_failure(lambda: MODULE.install(linked_source, linked_app), "source symlink")

        extra_source = temporary / "ExtraTrust"
        fixture(extra_source)
        (extra_source / "unexpected").write_bytes(b"x")
        extra_app = temporary / "Extra.app"
        extra_app.mkdir(mode=0o755)
        expect_failure(lambda: MODULE.install(extra_source, extra_app), "unexpected resource")

    print("Optional PluginTrust resource installation safety tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
