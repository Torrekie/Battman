# Changelog

This file records user-visible Battman changes. A version entry marked
`Unreleased` is a reviewed release candidate description, not an approval to
tag, sign, upload, publish, or install artifacts.

## [1.1.0] - Unreleased

### Added

- Added the production Analytics page with six embedded cards backed by shared,
  immutable battery metric snapshots and visible-only updates.
- Added the native plug-in host, stable C ABI v1, transactional registry, and
  public PluginSDK authoring/package tools.
- Added offline `.battman` import, bounded verification, quarantine, explicit
  third-party approval, restart-only activation, management, diagnostics,
  safe mode, and crash-loop recovery.
- Added the official Charge Gauge card as a separately shipped `.battman`
  plug-in with rooted and rootless add-on packages and replacement-TIPA
  inclusion.

### Changed

- Existing Analytics cards remain embedded but now use the same registry and
  lifecycle contract as external native cards.
- Release packaging is handled by bounded scripts and gated workflows instead
  of the former push-to-master IPA workflow.
- Versioning uses numeric `MAJ.MIN.PATCH[.REV]`; Debug and Release remain the
  only build configurations.

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
  `iphoneos-arm64`, and TrollStore replacement-TIPA host delivery.
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
