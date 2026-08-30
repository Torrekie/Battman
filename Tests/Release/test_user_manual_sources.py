#!/usr/bin/env python3
"""Static contract checks for Analytics and plug-in user-manual sources."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANUAL = ROOT / "docs/battman-user-manuals"
FEATURES = MANUAL / "docs/features"
INSTALLATION = MANUAL / "docs/installation"
DOC_REQUIREMENTS = ROOT / "Requirements/docs.txt"
DOC_RENDERER = ROOT / "Scripts/Docs/render-user-manual.sh"


def require(text: str, fragments: tuple[str, ...], label: str) -> None:
    missing = [fragment for fragment in fragments if fragment not in text]
    if missing:
        raise AssertionError(f"{label} is missing: {', '.join(missing)}")


def main() -> int:
    configuration = (MANUAL / "mkdocs.yml").read_text(encoding="utf-8")
    locales = re.findall(r"^\s*- locale: ([A-Za-z_]+)\s*$", configuration, re.MULTILINE)
    if locales != ["en", "zh", "zh_TW"]:
        raise AssertionError(f"unexpected manual locale order: {locales}")
    require(configuration, (
        "- Analytics: features/analytics.md",
        "- Native plug-ins: features/plugins.md",
        "name: Traditional Chinese",
        "Native plug-ins: 原生外掛程式",
    ), "mkdocs.yml")

    expected = {
        "analytics.md": ("visible-only metrics", "Unavailable", "Native plug-ins"),
        "analytics.zh.md": ("仅在可见时", "不可用", "原生插件"),
        "analytics.zh_TW.md": ("只在可見時", "無法使用", "原生外掛程式"),
        "plugins.md": ("does not run the plug-in", "native-code warning", "safe mode", "offline", "Diagnostics and support", "filesystem\npaths"),
        "plugins.zh.md": ("不会", "原生代码警告", "安全模式", "离线", "诊断与支持", "文件系统路径"),
        "plugins.zh_TW.md": ("不會", "原生程式碼警告", "安全模式", "離線", "診斷與支援", "檔案系統路徑"),
    }
    for name, fragments in expected.items():
        path = FEATURES / name
        if not path.is_file() or path.is_symlink():
            raise AssertionError(f"missing real manual page: {path}")
        require(path.read_text(encoding="utf-8"), fragments, name)

    installation_expected = {
        "index.md": (
            "declared product boundary", "not an\nindependently completed test",
            "iphoneos-arm64.deb", "not `iphoneos-arm`",
        ),
        "index.zh.md": (
            "产品边界", "并不表示", "iphoneos-arm64.deb", "不要选择 `iphoneos-arm`",
        ),
        "index.zh_TW.md": (
            "產品邊界", "並不表示", "iphoneos-arm64.deb", "不要選擇 `iphoneos-arm`",
        ),
    }
    for name, fragments in installation_expected.items():
        path = INSTALLATION / name
        if not path.is_file() or path.is_symlink():
            raise AssertionError(f"missing real installation page: {path}")
        content = path.read_text(encoding="utf-8")
        require(content, fragments, name)
        if "1.0.4" in content:
            raise AssertionError(f"installation page contains a stale hard-coded release: {path}")

    for path in (FEATURES / "analytics.md", FEATURES / "analytics.zh.md",
                 FEATURES / "analytics.zh_TW.md"):
        content = path.read_text(encoding="utf-8")
        if "(plugins.md)" not in content or not (path.parent / "plugins.md").is_file():
            raise AssertionError(f"broken Analytics-to-plug-ins link: {path}")

    main_template = (MANUAL / "custom_theme/main.html").read_text(encoding="utf-8")
    search_template = (MANUAL / "custom_theme/search.html").read_text(encoding="utf-8")
    javascript = (MANUAL / "docs/javascripts/apple-theme.js").read_text(encoding="utf-8")
    for label, text in (("main theme", main_template), ("search theme", search_template)):
        require(text, ('value="zh_TW"', "lang == 'zh_TW'", "繁體中文"), label)
    require(javascript, (
        "zh_TW: { light: '淺色', dark: '深色', auto: '自動' }",
        "var knownLocales = ['zh', 'zh_TW']",
        "buildPathForLang('zh_TW')",
    ), "language selector script")

    requirements = DOC_REQUIREMENTS.read_text(encoding="utf-8")
    require(requirements, (
        "mkdocs==1.6.1",
        "mkdocs-static-i18n==1.3.1",
        "--hash=sha256:",
    ), "hash-pinned documentation requirements")
    renderer = DOC_RENDERER.read_text(encoding="utf-8")
    require(renderer, (
        "--require-hashes",
        "--no-deps",
        "mkdocs\" build --strict --clean",
        "zh_TW/features/plugins/index.html",
    ), "isolated manual renderer")

    print("Analytics and native plug-in user-manual source contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
