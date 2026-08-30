# Support policy

Use [GitHub Issues](https://github.com/Torrekie/Battman/issues) for ordinary,
non-sensitive Battman defects and compatibility reports. Search existing issues
first and use a descriptive title. Do not use a public issue for vulnerabilities
or private diagnostics; follow [`SECURITY.md`](SECURITY.md).

Battman 1.1.x support is best-effort, with no response-time SLA. GitHub Issues
handles non-sensitive host, official plug-in, verification, activation,
packaging, and recovery defects. GitHub private vulnerability reporting handles
sensitive reports. Torrekie owns triage, incident response, revocation, and
recovery.

Include the Battman version, Debug/Release build where known, iOS version,
device architecture, installation channel, jailbreak/rootless status, concise
reproduction steps, and the exact result. A plug-in report should also identify
the package source, plug-in ID and version, requested extension points, and
whether the failure happened during import, approval, next-launch activation,
or recovery.

## Plug-in diagnostics and privacy

**More → Plug-ins → Export Diagnostics** produces a plain-text status report.
Battman shows a disclosure before opening the system share sheet. The v1 report
contains:

- Battman version/build and report generation time;
- safe-mode and next-launch third-party activation state;
- installed/quarantined plug-in identifiers and package SHA-256 values;
- package source, trust disposition, and activation state; and
- bounded error domain/code pairs.

It deliberately excludes plug-in files, file contents, localized error text,
filesystem paths, private keys, signing identities, battery measurements, and
device identifiers. The report may still reveal which plug-ins are installed,
so review the text and recipient before sharing. Remove any additional personal
context from screenshots or issue text yourself.

## Maintained scope

Support covers Battman's documented host and package contracts. Third-party authors
own their plug-in code, including its behavior, privacy policy, dependencies, and
support. Battman can help distinguish verification, trust, activation, ABI, and
host-integration failures; it does not certify third-party code as benign or debug
arbitrary private implementations.

TrollStore activation is replacement-TIPA-only for this release scope. Direct
loading of newly imported native code from the app data directory is not a
supported claim. Rooted/rootless system packages should be installed, updated,
and removed through APT/dpkg rather than in-app deletion.

The release's `compatibility-matrix.json` distinguishes verified simulator,
compile, limited device, and artifact-only evidence from community reports.
The declared A11-or-newer/iOS 12-or-newer baseline is not a completed physical
matrix for every device and OS combination. Hardware-backed cards may show
`Unavailable` when their host telemetry is absent; that is a supported state,
not a promise that every metric exists on every device.

GitHub private vulnerability reporting is enabled for the repository as of
2026-08-15. The owner approved this best-effort support scope on 2026-08-20;
an independent private-intake reachability review remains required before the
public plug-in beta gate can pass.
