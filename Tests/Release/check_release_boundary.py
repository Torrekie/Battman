#!/usr/bin/env python3
"""Static release/build boundary and workflow safety regression test."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise SystemExit(message)


project = (ROOT / "Battman.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
finalizer = 'shellScript = "\\"${PROJECT_DIR}/Scripts/Build/finalize-xcode-app.sh\\"";'
if project.count(finalizer) != 4:
    fail("all four app targets must call the one bounded Xcode finalizer")
generator = 'shellScript = "\\"${PROJECT_DIR}/Scripts/Build/generate-xcode-sources.sh\\"";'
if project.count(generator) != 4:
    fail("all four app targets must call the one bounded source generator")
if project.count('"$(DERIVED_FILE_DIR)/BattmanBuildIdentity.json",') != 4:
    fail("all four app targets must declare the generated build identity")
if project.count('OTHER_LDFLAGS = "$(OLDFL) $(BATTMAN_BUILD_IDENTITY_LDFLAGS)";') != 8:
    fail("all app configurations must embed the generated Mach-O build identity")
for forbidden in (
    "dpkg-deb", "tree-nonfree", "tree-havoc", "deb-nonfree", "deb-havoc",
    "6841152D2E57E166001B76B6 /* control in Sources */",
):
    if forbidden in project:
        fail(f"Xcode project leaked release packaging or local state: {forbidden}")
if re.search(r"/Users/[A-Za-z0-9._-]+(?:/|$)", project):
    fail("Xcode project leaked a machine-local user path")

finalizer_text = (ROOT / "Scripts/Build/finalize-xcode-app.sh").read_text(encoding="utf-8")
generator_text = (ROOT / "Scripts/Build/generate-xcode-sources.sh").read_text(encoding="utf-8")
config_text = (ROOT / "Config.xcconfig").read_text(encoding="utf-8")
if "verify-build-identity.py" not in finalizer_text:
    fail("Xcode finalizer does not verify the linked host build identity")
for required in ("generate-build-identity.py", "BattmanBuildIdentity.json"):
    if required not in generator_text:
        fail(f"Xcode source generator omits build identity input: {required}")
if "-Wl,-sectcreate,__TEXT,__btidentity,$(DERIVED_FILE_DIR)/BattmanBuildIdentity.json" not in config_text:
    fail("Xcode configuration does not define the build identity linker input")
for forbidden in ("dpkg", "apt", "ssh", "scp", "TrollStore", "gh release", "curl"):
    if re.search(rf"\b{re.escape(forbidden)}\b", finalizer_text, re.IGNORECASE):
        fail(f"Xcode finalizer contains an external release/device operation: {forbidden}")

release_tools = "\n".join(
    path.read_text(encoding="utf-8")
    for path in sorted((ROOT / "Scripts/Release").glob("*.py"))
)
for forbidden in ("apt install", "dpkg --install", "dpkg -i", "ssh ", "scp ", "gh release create"):
    if forbidden in release_tools:
        fail(f"local release tools contain an install/upload operation: {forbidden}")
for forbidden in ("generate_private_key", "genpkey", "ecparam -genkey"):
    if forbidden in release_tools:
        fail(f"production release tools contain key-generation behavior: {forbidden}")

ceremony = ROOT / "Scripts/Ceremony/run-production-key-ceremony.py"
ceremony_text = ceremony.read_text(encoding="utf-8")
for required in (
    "GENERATE BATTMAN 1.1.0 PRODUCTION KEYS",
    "BACK UP ENCRYPTED PRODUCTION KEYS",
    "trusted-private-lan-permitted",
    "live-pinned-hosts-required-for-backup-only",
    "manual-private-ipv4-per-live-run",
    "PKCS8-PBES2-scrypt-AES-256-CBC",
    "StrictHostKeyChecking=yes",
    "HostKeyAlgorithms=ssh-ed25519",
):
    if required not in ceremony_text:
        fail(f"owner-only ceremony omits required boundary: {required}")
for path in (
    ROOT / "Battman.xcodeproj/project.pbxproj",
    ROOT / "Battman/Makefile",
    ROOT / ".github/workflows/ci.yml",
    ROOT / ".github/workflows/release.yml",
    *sorted((ROOT / "Scripts/Build").glob("*")),
    *sorted((ROOT / "Scripts/Release").glob("*")),
):
    if path.is_file() and "run-production-key-ceremony" in path.read_text(
        encoding="utf-8", errors="replace"
    ):
        fail(f"normal build/release surface invokes the owner-only ceremony: {path}")

if "BTChargeGaugePlugin.m" in project or "OfficialPlugins/ChargeGauge" in project:
    fail("the separately shipped official Charge Gauge must not be embedded in an app target")
makefile = (ROOT / "Battman/Makefile").read_text(encoding="utf-8")
if "BTChargeGaugePlugin.m" in makefile or "OfficialPlugins/ChargeGauge" in makefile:
    fail("the separately shipped official Charge Gauge must not enter the host Makefile")
for required in (
    "generate-build-identity.py",
    "verify-build-identity.py",
    "-Wl,-sectcreate,__TEXT,__btidentity,$(BUILD_IDENTITY)",
):
    if required not in makefile:
        fail(f"Make host path omits build identity integration: {required}")

for workflow in (ROOT / ".github/workflows/ci.yml", ROOT / ".github/workflows/release.yml"):
    text = workflow.read_text(encoding="utf-8")
    for match in re.finditer(r"uses:\s*([^\s#]+)", text):
        value = match.group(1)
        if not re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", value):
            fail(f"GitHub Action is not pinned to a full commit SHA: {value}")

ci_workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
for required in (
    "linux-debug-ipa:",
    "runs-on: ubuntu-24.04",
    "iPhoneOS13.7.sdk.tar.xz",
    "iOSToolchain-x86_64.tar.xz",
    "661d1a8c518025f084d8c1e70dd8767581fb5730fb5950378f0915d840a7b5c3",
    "cc9fbc7f8a3f9336f926cd4fb7cc2233a17b2ba40504cc8c0ff3211bd9df27e3",
    "make -C Battman THEOS=\"$THEOS\" RELEASE=0 -j1 all",
    "name: Battman-debug-ipa",
):
    if required not in ci_workflow:
        fail(f"Linux Debug IPA workflow omits its bounded contract: {required}")
if "if: ${{ github.event_name == 'workflow_dispatch' && inputs.run_macos_evidence == true }}" not in ci_workflow:
    fail("Xcode/simulator evidence lane must be workflow-dispatch-only")
if "if: ${{ vars.BATTMAN_IOS_SDK_URL" in ci_workflow:
    fail("Linux Debug IPA workflow must not silently skip on unset repository variables")

simulator_root = ROOT / "Tests/Simulator"
simulator_common = simulator_root / "simulator-runner-common.sh"
simulator_runners = (
    simulator_root / "run-analytics-example-parity.sh",
    simulator_root / "run-analytics-card-screenshots.sh",
    simulator_root / "run-charge-gauge-screenshots.sh",
    simulator_root / "run-plugin-application-integration-callbacks.sh",
    simulator_root / "run-plugin-management-screenshots.sh",
)
common_text = simulator_common.read_text(encoding="utf-8")
for required in (
    "${DEVELOPER_DIR:-}",
    "xcode-select -p",
    "${BATTMAN_SIMULATOR_UDID:-}",
    "simctl list devices available --json",
    'item[3] == "Booted"',
):
    if required not in common_text:
        fail(f"Simulator environment selection omits required behavior: {required}")

literal_udid = re.compile(
    r"\b[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\b",
    re.IGNORECASE,
)
simulator_surfaces = (simulator_common, *simulator_runners)
for path in simulator_surfaces:
    text = path.read_text(encoding="utf-8")
    if "/Users/" in text:
        fail(f"Simulator runner contains a machine-local user path: {path}")
    if literal_udid.search(text):
        fail(f"Simulator runner contains a literal local device UDID: {path}")
    for match in re.finditer(r"\bxcrun\s+simctl\s+(create|boot|install)\b", text):
        if path.name == "run-plugin-management-screenshots.sh" and match.group(1) == "install":
            continue
        fail(f"Simulator runner gained an unbounded device mutation: {path}")
for path in simulator_runners:
    if 'source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"' not in path.read_text(
        encoding="utf-8"
    ):
        fail(f"Simulator runner bypasses portable environment selection: {path}")

analytics_harness_text = (simulator_root / "BTAnalyticsCardsScreenshotHarness.m").read_text(
    encoding="utf-8"
)
for required in (
    "ANALYTICS CARDS - SYNTHETIC FIXTURE",
    "NO DEVICE DATA - fixed test metrics",
    "BTSyntheticMetricSnapshot",
):
    if required not in analytics_harness_text:
        fail(f"Analytics screenshot harness omits synthetic boundary: {required}")
for forbidden in ("BAAnalyticsSystemMetricSource", "BAAnalyticsMetricService"):
    if forbidden in analytics_harness_text:
        fail(f"Analytics screenshot harness imports a live metric surface: {forbidden}")

# Review evidence, screenshots, release decisions, and the readiness ledger are
# deliberately owner-local.  The public checkout must prove that none of
# those paths is tracked and that Git will ignore newly-created local files.
local_only_paths = (
    "docs/design-concepts/",
    "docs/evidence/",
    "docs/release-decisions/",
    "docs/review-templates/",
    "docs/plugin-system-plan.md",
    "docs/official-trust-ceremony.md",
    "docs/release-readiness.md",
    "Packaging/Release/readiness-state.json",
    "Scripts/Release/check-release-readiness.py",
    "Tests/Release/test_release_readiness.py",
    "Tests/Release/test_plugin_management_screenshots.py",
)
tracked_local = subprocess.run(
    ["git", "-C", str(ROOT), "ls-files", "-z", "--", *local_only_paths],
    check=True,
    stdout=subprocess.PIPE,
).stdout
if tracked_local:
    fail("owner-local review/evidence paths must not be tracked in the public PR")
for relative in local_only_paths:
    probe_path = relative + "placeholder" if relative.endswith("/") else relative
    probe = subprocess.run(
        ["git", "-C", str(ROOT), "check-ignore", "--no-index", "-q", "--", probe_path],
        check=False,
    )
    if probe.returncode != 0:
        fail(f"owner-local path is not covered by .gitignore: {relative}")

if os.environ.get("BATTMAN_RUN_LOCAL_EVIDENCE") == "1":
    print("Owner-local evidence checks are delegated to the private evidence lane.")

tracked_markdown = subprocess.run(
    ["git", "-C", str(ROOT), "ls-files", "-z", "--", "*.md"],
    check=True,
    stdout=subprocess.PIPE,
).stdout.split(b"\0")
private_ipv4 = re.compile(
    r"(?<![0-9])(?:10(?:\.[0-9]{1,3}){3}|192\.168(?:\.[0-9]{1,3}){2}|"
    r"172\.(?:1[6-9]|2[0-9]|3[01])(?:\.[0-9]{1,3}){2})(?![0-9])"
)
public_markdown_forbidden = (
    ("machine-local user path", re.compile(r"/Users/[^/\s`]+/")),
    ("private network address", private_ipv4),
    ("literal device or container UUID", literal_udid),
    ("private .local hostname", re.compile(r"\b[A-Za-z0-9][A-Za-z0-9.-]*\.local\b")),
    ("actual-run temporary path", re.compile(r"/(?:private/)?tmp/[A-Za-z0-9_.-]+")),
)
for encoded in tracked_markdown:
    if not encoded:
        continue
    try:
        relative = encoded.decode("utf-8")
        text = (ROOT / relative).read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError) as error:
        fail(f"tracked public Markdown is unreadable: {encoded!r}: {error}")
    for label, pattern in public_markdown_forbidden:
        if label == "actual-run temporary path" and not relative.startswith("docs/evidence/"):
            continue
        if pattern.search(text):
            fail(f"tracked public Markdown contains a {label}: {relative}")

release_workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
if "environment: battman-production-release" not in release_workflow or "--draft" not in release_workflow:
    fail("GitHub publication must require the protected environment and remain a draft")
if "persist-credentials: false" not in release_workflow:
    fail("release checkout must not retain a write credential")
for forbidden in (
    "BATTMAN_CHECKSUM_SIGNING_KEY_PEM",
    "--checksum-private-key \"$RUNNER_TEMP",
):
    if forbidden in release_workflow:
        fail(f"hosted release workflow imports a production checksum private key: {forbidden}")
for required in (
    "officialPluginSelection",
    "separatelyShipped",
    "sdkExample",
    "--sdk-example",
    "--sdk-example-key-id",
    "--checksum-public-key",
    "BATTMAN_CHECKSUM_SIGNATURE_BASE64",
    "finalize-release-signature.py",
    "verify-release-directory.py",
    "test -z \"$(git status --porcelain=v1 --untracked-files=all)\"",
    "build-plugin-deb.py",
    "verify-build-identity.py",
):
    surface = release_workflow if required != "build-plugin-deb.py" else release_tools
    if required not in surface:
        fail(f"official plug-in release matrix is not wired through {required}")

matrix = json.loads((ROOT / "Packaging/Release/release-matrix.json").read_text(encoding="utf-8"))
if matrix.get("compatibilityMatrix") != "compatibility-matrix.json":
    fail("release matrix does not bind the canonical compatibility matrix")
for required_asset in (
    "<plugin-identifier>_<plugin-version>.battman.zip",
    "<sdk-example-identifier>_<sdk-example-version>.battman.zip",
    "compatibility-matrix.json",
    "release-manifest.json",
):
    if required_asset not in matrix.get("githubAssets", []):
        fail(f"release matrix omits required GitHub asset: {required_asset}")
if matrix.get("officialPluginSelection") != {
    "embeddedAnalyticsCards": [
        "com.torrekie.battman.analytics.battery.summary",
        "com.torrekie.battman.analytics.temperature.average",
        "com.torrekie.battman.analytics.power.average",
        "com.torrekie.battman.analytics.cycle.summary",
        "com.torrekie.battman.analytics.capacity.remaining",
        "com.torrekie.battman.analytics.charging-limit",
    ],
    "separatelyShipped": ["com.torrekie.battman.plugin.charge-gauge"],
    "replacementTIPAIncludesSeparatelyShipped": True,
}:
    fail("release matrix does not match the owner-approved embedded/separate card split")
if matrix.get("sdkExample") != {
    "pluginIdentifier": "com.torrekie.battman.example.analytics",
    "signedPackageRequired": True,
    "publisherIdentityReviewRequired": True,
    "officialTrustDelegation": False,
    "rootedRootlessAddOns": False,
    "replacementTIPAInclusion": False,
    "activationPolicy": "third-party-explicit-approval-required",
}:
    fail("release matrix does not keep the SDK example signed but third-party")
if matrix.get("perPluginCandidates", {}).get("selectionRequired") is not True:
    fail("owner-approved official plug-in selection must be required")
if matrix.get("havocManualSubmission") != {
    "submissionMode": "manual-owner-upload-only",
    "automaticUpload": False,
    "eligibleArtifactKinds": [
        "host-debian-rooted",
        "host-debian-rootless",
        "plugin-debian-rooted",
        "plugin-debian-rootless",
    ],
    "eligibleFilenameSuffix": ".deb",
    "ownerApprovalRequired": True,
    "classificationReviewRequired": True,
    "dualHostingReviewRequired": True,
    "publicationStateAuthority": "owner-maintained-external-record",
}:
    fail("Havoc policy must remain manual, Deb-only, owner-approved, and externally recorded")

print("Xcode packaging boundary and SHA-pinned gated workflows passed.")
