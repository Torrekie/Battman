# Authoring native Battman plug-ins

Status: SDK v1 release candidate. The technical workflow is complete and works
offline. The complete [`PluginSDK/`](../PluginSDK/) subtree is MIT licensed;
that license does not publish a release or relicense the Battman host.

## Choose the native shape

Use an Objective-C/C Mach-O bundle when a card must own arbitrary UIKit views,
Core Animation layers, Core Graphics drawing, gestures, animations, resources,
or localizations. It has native-call overhead and needs no interpreter, VM,
JIT, or polling loop. `.bundle` is canonical because it carries resources,
metadata, and a nested platform signature. A raw `.so` is retained only for a
future code-only compatibility use; the SDK card template does not recommend it.

The same provider may be built embedded into Battman by an official build or as
a loadable bundle. Both forms enter the same descriptor, transactional registry,
extension protocol, lifecycle, and trust policy. A plug-in selects where it
plugs in by registering a published extension-point identifier. It never calls
private controller selectors or exposes internal `BI_SECT` ordinals.

## 1. Create and build a card

Requirements: Xcode command-line tools, an iPhoneOS SDK, `make`, Python 3, and
Python `cryptography` for package signing and portable verification.

```sh
python3 PluginSDK/Tools/create-analytics-card.py \
  --plugin-id com.example.battman.charge \
  --card-id com.example.battman.charge.primary \
  --display-name "Charge Card" \
  --author-name "Example Developer" \
  --homepage-url "https://example.com/battman-card" \
  --support-email "support@example.com" \
  --output /tmp/ChargeCard

make -C /tmp/ChargeCard \
  SDK_ROOT="$PWD/PluginSDK" \
  BUILD_DIR=/tmp/ChargeCard-build \
  -j1
```

The plug-in and extension identifiers must be lowercase reverse-DNS names. A
card identifier belongs under its plug-in identifier. The validator confirms
the bundle identity, code signature, dependency surface, and that the only
global entry symbol is `BattmanPluginEntryPointV1`.

Author metadata is optional and covered by the publisher signature. `name` is
human-facing; `homepageURL` must use HTTPS, and `supportEmail` is a bounded
address suitable for a `mailto:` link. These are publisher-provided claims,
not substitutes for the publisher fingerprint or Battman's trust verdict.

Implement `BAAnalyticsCard` using only the public headers. Create and retain
your entire content hierarchy from `makeAnalyticsCardContentView`; Battman
retains the returned root as cell content. Do not depend on the host cell or
walk private view-controller hierarchies. The card owns:

- all subviews and `CALayer` trees, delegates, drawing, gestures and animations;
- content accessibility, resources and localizations;
- bounded property-list restoration state and its migrations;
- handling of missing metrics and memory warnings.

Battman owns the outer cell, clipping, selection, grid size, editing controls,
reordering, snapshot scheduling, and lifecycle delivery. Every UIKit callback
is on the main thread. Metric snapshots are immutable. Do not read AppleSMC or
start an independent sensor timer from drawing/layout callbacks. Stop animation
and discretionary work in `analyticsCardDidEndDisplayingContentView:` and shed
caches in `analyticsCardDidReceiveMemoryWarning`.

## 2. Use the v1 ABI safely

Export only:

```c
const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void);
```

Validate `host`, `abiVersion`, `BT_PLUGIN_HOST_V1_MINIMUM_SIZE`, and
`registerExtension` before calling the host. The optional `log` callback is
usable only if `structSize` includes it and the pointer is non-null. Set each
structure's `structSize` to the size used when compiling it. Ignore unknown
tail fields supplied by a newer v1 host. Do not link against symbols from the
Battman executable; metric identifiers are header literals and host objects are
used through documented protocols.

Registration is all-or-nothing. The descriptor identity/version must equal the
signed manifest, and every registered extension point must be declared there.
If any object has the wrong protocol/version/identifier, the host rolls back the
whole callback. Native images cannot safely unload, so enable, update, disable,
and revocation changes take effect on restart.

See [`PluginSDK/COMPATIBILITY.md`](../PluginSDK/COMPATIBILITY.md) for evolution
rules and [`PluginSDK/SDKContractV1.json`](../PluginSDK/SDKContractV1.json) for
the checked v1 surface.

## 3. Prepare an existing publisher key

Publisher identity is ECDSA P-256 over exact `Manifest.json` bytes. Platform
code signing and publisher signing are separate: an ad-hoc/TrollStore-valid
Mach-O signature does not identify its publisher.

Battman's public SDK and package tools deliberately do not generate production
keys. Generate and custody a key outside this authoring workflow, then inspect
only its public half:

```sh
python3 PluginSDK/Tools/publisher-key-id.py publisher-public.pem \
  --raw-output /tmp/publisher-public.p256
```

The printed lowercase SHA-256 is the publisher key identifier. Put it into a
manifest copied from `ManifestTemplate.json.in`:

```sh
python3 PluginSDK/Tools/render-example-manifest.py \
  --template /tmp/ChargeCard/ManifestTemplate.json.in \
  --publisher-key-id KEY_IDENTIFIER \
  --output /tmp/ChargeCard-manifest.json
```

Never commit a private key or its password. For third-party publisher-wide
approval, include the 65-byte public point in the package so Battman can pin it
locally. Exact-build approval can remain narrower, but including it makes the
package independently verifiable offline.

## 4. Build, sign, and verify `.battman`

The transport is a directory package with extension `.battman`, UTI
`com.torrekie.battman.plugin`, conforming to Apple's `com.apple.package`. Its
minimal executable shape is outer `Info.plist`, signed `Manifest.json`, one
signature, and one loadable `.bundle` (or schema-approved `.so`). The builder
creates the plist, normalized inventory, and exact file modes:

```sh
python3 PluginSDK/Tools/Package/build-plugin-package.py \
  --manifest-template /tmp/ChargeCard-manifest.json \
  --payload /tmp/ChargeCard-build/BTAnalyticsExample.bundle \
  --publisher-public-key /tmp/publisher-public.p256 \
  --output /tmp/ChargeCard.battman

python3 PluginSDK/Tools/Package/sign-plugin-package.py \
  /tmp/ChargeCard.battman \
  --private-key /secure/location/publisher-private.pem \
  --password-file /secure/location/password

python3 PluginSDK/Tools/Package/verify-plugin-package.py \
  /tmp/ChargeCard.battman
```

All three operations are offline. The portable verifier proves envelope,
inventory, hashes, public-key identity, and publisher signatures; its JSON
report says `nativeVerificationRequired: true`. It does not claim that iOS can
load the Mach-O or that the publisher is trusted. Battman's in-app verifier is
authoritative for architecture, dependencies, platform signature, ABI, trust
metadata, revocation, rollback, and local approval.

Increase `releaseSequence` monotonically for each release under a publisher
key. Reusing a sequence for different package bytes is rejected as equivocation;
decreasing it is rejected as rollback. Update all plug-in and payload identities
together. Full format details are in
[`plugin-package-format.md`](plugin-package-format.md).

## 5. Import and activation behavior

Files/APT/dpkg delivery does not imply execution. Battman discovers only its
bounded app-bundle, private app-data, rooted `/Library/Battman/PlugIns`, and
rootless `/var/jb/Library/Battman/PlugIns` roots. File-open import always copies
to private quarantine and re-verifies before any installation or activation.

Official, correctly scoped packages can be approved by Battman's offline root
metadata. Unknown third-party packages remain `Approval Required`; the user can
allow exact bytes or explicitly trust that publisher for the same plug-in ID
and extension points after a native-code warning. Hard verification failures
are never consent-overridable. Third-party loading also has a global switch,
and activation occurs only on a later launch.

On TrollStore installations, newly imported native code defaults to `Requires
Battman Reinstall`: it remains quarantined until a desktop/on-device helper
embeds it in a replacement TIPA, signs the nested code and outer app in the
correct order, and the user installs that app explicitly. Battman does not call
private TrollStore signing internals.

## 6. Pre-release checklist

- Build in a directory containing only the SDK, not Battman source.
- Run the bundle validator and portable package verifier offline.
- Confirm only the documented entry symbol is exported and every dependency is
  declared/allowed.
- Exercise all card sizes, appearance, Dynamic Type, accessibility, rotation,
  background/foreground, memory pressure, editing and restoration.
- Measure idle/visible CPU and eliminate independent polling.
- Treat signature verification as identity/integrity, never a safety audit.
- Publish source or an auditable build process, security contact, supported
  iOS/device range, permission/privacy behavior, checksums and release notes.
- Do not advertise commercial/open SDK rights until the SDK license gate closes.
