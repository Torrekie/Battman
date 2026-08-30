#!/usr/bin/env python3

"""Keep all native mapping behind the verifier-gated private loader."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PLUGIN_HOST = ROOT / "Battman" / "PluginHost"
LOADER = PLUGIN_HOST / "Runtime" / "BTPluginNativeImageLoader.m"
PRIVATE_HEADER = "BTPluginNativeImageLoaderPrivate.h"


def main() -> None:
    mapping_calls: list[tuple[Path, str]] = []
    private_imports: list[Path] = []
    call_pattern = re.compile(r"\b(dl(?:open|sym|close))\s*\(")
    for path in sorted(PLUGIN_HOST.rglob("*.m")):
        source = path.read_text(encoding="utf-8")
        mapping_calls.extend((path, match.group(1)) for match in call_pattern.finditer(source))
        if PRIVATE_HEADER in source:
            private_imports.append(path)

    unexpected_calls = [
        (path, call) for path, call in mapping_calls
        if path != LOADER or call == "dlclose"
    ]
    if unexpected_calls:
        details = ", ".join(f"{path.relative_to(ROOT)}:{call}" for path, call in unexpected_calls)
        raise SystemExit(f"native mapping escaped the private no-unload loader: {details}")
    calls = [call for path, call in mapping_calls if path == LOADER]
    if calls.count("dlopen") != 1 or calls.count("dlsym") != 1:
        raise SystemExit(f"private loader mapping surface changed: {calls}")

    allowed_private_imports = {
        LOADER,
        PLUGIN_HOST / "Runtime" / "BTPluginRuntimeLoader.m",
    }
    unexpected_imports = sorted(set(private_imports) - allowed_private_imports)
    if unexpected_imports:
        details = ", ".join(str(path.relative_to(ROOT)) for path in unexpected_imports)
        raise SystemExit(f"private image loader imported outside runtime composition: {details}")

    print("Verifier-gated native mapping boundary passed: one dlopen, one dlsym, and no dlclose.")


if __name__ == "__main__":
    main()
