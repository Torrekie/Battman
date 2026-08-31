#!/usr/bin/env python3
"""Static contracts for public plug-in support and diagnostic privacy."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def require(text: str, fragments: tuple[str, ...], label: str) -> None:
    missing = [fragment for fragment in fragments if fragment not in text]
    if missing:
        raise AssertionError(f"{label} is missing: {', '.join(missing)}")


def require_any(text: str, fragments: tuple[str, ...], label: str) -> None:
    if not any(fragment in text for fragment in fragments):
        raise AssertionError(f"{label} is missing one of: {', '.join(fragments)}")


def main() -> int:
    security = (ROOT / "SECURITY.md").read_text(encoding="utf-8")
    support = (ROOT / "SUPPORT.md").read_text(encoding="utf-8")
    source = (ROOT / "Battman/PluginHost/UI/BTPluginManagementViewController.m").read_text(
        encoding="utf-8"
    )
    settings_source = (ROOT / "Battman/SettingsViewController.m").read_text(encoding="utf-8")
    donation_source = (ROOT / "Battman/DonationViewController.m").read_text(encoding="utf-8")
    preferences_source = (ROOT / "Battman/PreferencesViewController.m").read_text(encoding="utf-8")
    issue_form = (ROOT / ".github/ISSUE_TEMPLATE/plugin-report.yml").read_text(
        encoding="utf-8"
    )
    generic_issue_template = (ROOT / ".github/ISSUE_TEMPLATE/bug_report.md").read_text(
        encoding="utf-8"
    )
    require(security, (
        "Do not open a public issue",
        "GitHub private vulnerability reporting",
        "Torrekie owns triage",
        "best-effort",
        "no response-time",
        "independent reachability review",
        "private keys,",
    ), "SECURITY.md")
    require_any(security, ("must enable", "enabled that repository feature"), "SECURITY.md private-intake state")
    require(support, (
        "GitHub Issues",
        "Plug-in diagnostics and privacy",
        "error domain/code pairs",
        "filesystem paths",
        "replacement-TIPA-only",
        "compatibility-matrix.json",
        "not a completed physical",
        "no response-time SLA",
        "best-effort",
        "official plug-in",
        "Third-party authors",
        "own their plug-in code",
        "incident response, revocation, and",
        "independent private-intake reachability review",
    ), "SUPPORT.md")
    require(source, (
        '_("Review Diagnostics Before Sharing")',
        "presentDiagnosticShareFromSourceView",
        "Battman plug-in diagnostics v1",
        "BTPluginDiagnosticErrorValue",
        "error domain/code values",
    ), "plug-in management diagnostics")
    require(issue_form, (
        "Do not use a public issue for a vulnerability",
        "Plug-in installation channel",
        "Sanitized plug-in diagnostics",
        "filesystem paths",
        "Privacy confirmation",
    ), "GitHub plug-in issue form")
    require(generic_issue_template, (
        "Do not use a public issue for a vulnerability",
        "GitHub private vulnerability reporting",
        "SECURITY.md",
        "private keys",
        "device identifiers",
        "battery measurements",
        "filesystem paths",
    ), "GitHub generic issue template")

    # Ordinary users are routed to the public issue template.  The app must
    # not construct mailto links or collect device identifiers as a side
    # effect of opening the support screen; sensitive reporting belongs in
    # SECURITY.md, outside this ordinary-user flow.
    require(settings_source, (
        "issues/new?template=bug_report.md",
        "Use GitHub Issues for ordinary bugs and feature requests.",
    ), "Settings support route")
    require(donation_source, ("issues/new?template=bug_report.md", "Create a new GitHub issue"), "Donation support route")
    require(preferences_source, ("issues/new?template=bug_report.md",), "Preferences support route")
    settings_flow = settings_source.split('NSString *title = _("Gonna tell us something?")', 1)[-1].split(
        "if (indexPath.section == SS_SECT_PLUGINS)", 1
    )[0]
    for label, text in (
        ("Settings support flow", settings_flow),
        ("Donation support flow", donation_source),
        ("Preferences support flow", preferences_source),
    ):
        if "mailto:" in text or "MGCopyAnswerPtr" in text or "identifierForVendor" in text or "uname(" in text:
            raise AssertionError(f"{label} must not collect or construct private device contact data")

    diagnostic_method = source.split("- (NSString *)diagnosticText", 1)[1].split(
        "- (void)presentDiagnosticShareFromSourceView", 1
    )[0]
    forbidden = (
        "localizedDescription",
        "relativePath",
        "absoluteString",
        ".path",
        "UIDevice",
        "identifierForVendor",
        "BAAnalyticsMetric",
    )
    leaked = [fragment for fragment in forbidden if fragment in diagnostic_method]
    if leaked:
        raise AssertionError(f"diagnostic export regained privacy-sensitive fields: {leaked}")

    print("Public security/support policy and bounded plug-in diagnostic contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
