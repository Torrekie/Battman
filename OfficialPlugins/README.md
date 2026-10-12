# Plug-in source examples and public trust resources

`ChargeGauge/` contains a small developer source example of an Analytics card.
It demonstrates a complete content view, custom drawing, localization, and the
public SDK contract. Its existing directory name does not make it a production
release plug-in or grant publisher trust.

Battman 1.1.0 contains ten built-in Analytics cards. Charge Gauge and the SDK
Analytics example are available as source for developers to build and test;
the formal release ships no compiled examples, example `.battman.zip` files,
Debian add-ons, or example code embedded in the TIPA. The source examples keep
their respective licenses: Charge Gauge uses the repository license, while the
`PluginSDK/` subtree and its Analytics example use MIT.

The native/embedded example builds and parity checks are development tools.
Their output must remain outside the formal release asset set. A successful
local build or publisher signature does not approve distribution or make a
publisher official.

Public trust inputs are separate from example source:

- `Trust/PluginTrust/` contains only `RootPolicy.plist`,
  `TrustMetadata.json`, and `TrustMetadata.signatures/<root-id>.sig`. The build
  finalizer copies it into `Battman.app/PluginTrust` only after bounded tree
  validation. The runtime independently validates the P-256 fingerprints,
  root-signature threshold, strict metadata schema, and Keychain rollback
  state before treating any publisher as official.
- `Packages/` is a staging location for signed packages only when a release
  explicitly selects them. Battman 1.1.0 selects no separately distributed
  compiled plug-ins; do not stage Charge Gauge or the SDK example there for
  this release.

Neither location may contain private keys. Public trust metadata and valid
signatures do not authorize adding an example to the release matrix. Root-key
custody, delegation scope, and artifact review remain separate requirements.
