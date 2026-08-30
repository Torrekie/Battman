# Official plug-in staging boundary

First-party plug-ins that are shipped separately from the host live here.
Their source, package identity, signing policy, and release artifacts must
remain distinguishable from embedded providers and third-party examples.

`ChargeGauge/` is the first selected production source. The existing six
Analytics cards remain embedded; Charge Gauge itself is built separately,
enters rooted/rootless add-on packages, and is sealed into replacement TIPAs
only from one reviewed signed `.battman` transport package.

The Phase 4 SDK Analytics example is deliberately not an official production
plug-in and is never added to an app target. It is compiled in embedded and
native forms only by the parity test. A separately shipped official plug-in
still requires the owner-approved trust-key and release-scope decisions.

Production public inputs use two exact subdirectories:

- `Trust/PluginTrust/` contains only `RootPolicy.plist`,
  `TrustMetadata.json`, and `TrustMetadata.signatures/<root-id>.sig`. The build
  finalizer copies it into `Battman.app/PluginTrust` only after bounded tree
  validation. The runtime independently validates the P-256 fingerprints,
  root-signature threshold, strict metadata schema, and Keychain rollback
  state before treating any publisher as official.
- `Packages/` contains the already signed, reviewed official `.battman`
  directory packages selected for a release. Strict assembly requires at least
  one and rejects packages outside their signed publisher delegation scope.

Neither directory may contain private keys. The owner has approved the
2-of-3-root trust operations and Charge Gauge split, but the public trust tree
and signed production package remain absent until the production ceremony and
post-code-freeze independent review occur. Engineering builds therefore still load no official
external publisher by default.
