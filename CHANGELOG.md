# Changelog

This file records user-visible Battman changes. A version entry marked
`Unreleased` is a reviewed release candidate description, not an approval to
tag, sign, upload, publish, or install artifacts.

## [1.1.0] - Unreleased

### Added

- Added ten Analytics cards with shared battery snapshots, cached startup,
  source-aware history, and interactive capacity trends.
- Added the native plug-in host, stable C ABI v1, transactional registry, and
  public PluginSDK authoring/package tools.
- Added offline `.battman` import, bounded verification, quarantine, explicit
  third-party approval, restart-only activation, management, diagnostics,
  safe mode, and crash-loop recovery.
- Added the official Charge Gauge card as a separately shipped `.battman`
  plug-in with rooted and rootless add-on packages and replacement-TIPA
  inclusion.

### Changed

- External plug-in verification runs in the background; saved card layouts are
  restored when plug-ins finish loading. Recovery mode covers official and
  third-party external plug-ins, and Charge Gauge follows the app language.
- Charging-limit operations and history queries no longer wait on the UI thread.
- Data removal waits for Analytics cache writers and reports deletion failures.
- Legacy icons use vector fallbacks without a bundled symbol font.
- Public, GitHub and Havoc builds retain distinct Xcode schemes. Havoc provides
  Debian packages only; its private authorization implementation is required.
- Existing Analytics cards remain embedded but now use the same registry and
  lifecycle contract as external native cards.
- Release packaging uses bounded scripts and gated workflows.
- Versioning uses numeric `MAJ.MIN.PATCH[.REV]`; Debug and Release remain the
  only build configurations.

### Fixed

- Preserved valid cable-change events and prevented gaps in an independent
  history table from hiding available measurements.
- Fixed the lifetime and cleanup of asynchronous power notifications.
- Updated release fixtures and platform dependency hashes; normal CI now runs
  the native regression suite and serial Public/GitHub Xcode Release builds
  before tagging.

### Security

- Official plug-ins use offline publisher verification beneath a planned
  2-of-3 P-256 root policy. Production private keys are intentionally absent
  from the development worktree.
- Unknown third-party native code cannot load until hard package, signature,
  Mach-O, dependency, ABI, rollback, and platform checks pass and the user
  explicitly approves the exact build or publisher.
- Native plug-ins run inside Battman with the app's privileges. Signatures and
  consent authenticate entry; they do not sandbox loaded code.

### Distribution

- The release matrix retains rooted `iphoneos-arm`, rootless
  `iphoneos-arm64`, and GitHub TrollStore replacement-TIPA host delivery.
- Channel markers distinguish Public, GitHub and Havoc executables. Havoc
  validation requires its own build, and Havoc TIPAs are rejected.
- Manual release validation accepts a ref and defaults to validation-only mode.
  Production draft creation still requires an exact tag, signed public inputs,
  offline checksum signing, and protected environment approval.
- Charge Gauge is prepared as rooted/rootless add-ons and sealed replacement-
  TIPA code. APT/dpkg or marketplace availability remains transport evidence,
  not Battman activation trust.
- GitHub and Havoc publication remain gated on production identities, exact-tag
  reproducibility, review, and explicit owner approval.

### Compatibility

- The host ABI and UI deployment target remain arm64 iOS 12.0. Current project
  acceptance uses simulator UI plus arm64/iOS 12 compile and load-command
  evidence; it does not claim an independently tested iOS 12-through-17 device
  matrix.
- `.bundle` is the canonical full-UI native payload. Raw `.so` remains a
  compatibility-only payload with a required canonical `@rpath/<name>.so`
  install name.
- TrollStore third-party activation remains replacement-TIPA-only; direct
  data-container native loading is not claimed.
