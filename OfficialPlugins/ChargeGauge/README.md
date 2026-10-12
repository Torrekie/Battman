# Battman Charge Gauge

`com.torrekie.battman.plugin.charge-gauge` is the first separately shipped
official Battman plug-in. It owns its complete card content view and custom
gauge layer, consumes only immutable Analytics snapshots, and has no polling
timer or host-private dependency.

The six existing Analytics cards remain embedded. The embedded object produced
here exists only for registry/rendering parity tests; Battman 1.1.0 production
artifacts ship this card as a signed `.battman` bundle, rooted/rootless Debian
add-ons, and sealed code in a public-channel replacement TIPA. There is no Havoc
TIPA artifact.

Its signed manifest identifies the author as Torrekie and supplies the Battman
repository homepage plus the public support email. These fields improve the
management UI but do not replace official publisher-key verification.

Build the native bundle with bounded parallelism. The Makefile applies its
local ad-hoc platform signature; publisher signing is a separate later step:

```sh
make -C OfficialPlugins/ChargeGauge \
  SDK_ROOT="$PWD/PluginSDK" \
  BUILD_DIR=/tmp/BattmanChargeGauge \
  -j1 all
```

This works from the reference-source archive as well as a full checkout: both
preserve the `OfficialPlugins/ChargeGauge` and `PluginSDK` paths. It requires
Xcode with an iPhoneOS SDK and targets arm64/iOS 12.0. The only link dependencies
are Foundation, UIKit, QuartzCore, and CoreGraphics. No Battman implementation
source, Havoc DRM, third-party native library, or network download is needed.

See [the SDK development guide](../../PluginSDK/DEVELOPING.md) for the complete
public ABI, metric list, tool dependencies, and installation behavior.

## Source map

`BTChargeGaugeRegister` validates the required ABI prefix and registers the
card transactionally. `BTChargeGaugeUseHostLanguage` reads the optional
`preferredLanguage` tail only after checking its size and selects strings from
the plug-in's own bundle. `Resources/` contains all four localizations, copied
before platform signing. `BTChargeGaugeCard` receives state-of-charge and
charging-state metrics; `BTChargeGaugeContentView` and `BTChargeGaugeLayer` own
the UI, gauge drawing, unavailable state, and iOS 12 appearance fallback.

`VERSION` supplies display version `1.0.0`; `BUILD_VERSION` supplies native
descriptor build version `1`. Keep these synchronized with `Info.plist` and
`ManifestTemplate.json.in` when making a new plug-in release. The plug-in
version is independent of the Battman application version.

The complete buildable source consists of the `.h` / `.m` files, `Makefile`,
`Info.plist`, `VERSION`, `BUILD_VERSION`, manifest template, all `Resources/`,
and the public SDK. Distribute these with the repository's `LICENSE/` directory
and `PluginSDK/LICENSE`. Charge Gauge retains the repository's Torrekie
Non-Commercial Attribution License; it is **not** covered by the SDK's MIT
subtree license. For a reusable MIT starting point, use
[`PluginSDK/Examples/AnalyticsCard`](../../PluginSDK/Examples/AnalyticsCard/).

## Publisher package

Packaging requires an existing official publisher public key. Render the
manifest, build the deterministic directory package, then sign exact manifest
bytes only on the approved publisher signer:

```sh
python3 PluginSDK/Tools/publisher-key-id.py publisher-public.pem \
  --raw-output /new/publisher-public.p256
python3 PluginSDK/Tools/render-example-manifest.py \
  --template OfficialPlugins/ChargeGauge/ManifestTemplate.json.in \
  --publisher-key-id APPROVED_64_HEX_FINGERPRINT \
  --output /new/ChargeGaugeManifest.json
python3 PluginSDK/Tools/Package/build-plugin-package.py \
  --manifest-template /new/ChargeGaugeManifest.json \
  --payload /tmp/BattmanChargeGauge/BattmanChargeGauge.bundle \
  --publisher-public-key /new/publisher-public.p256 \
  --output /new/com.torrekie.battman.plugin.charge-gauge.battman
python3 PluginSDK/Tools/Package/sign-plugin-package.py \
  /new/com.torrekie.battman.plugin.charge-gauge.battman \
  --private-key /offline/publisher-private.pem \
  --password-file /offline/publisher-password
python3 PluginSDK/Tools/Package/verify-plugin-package.py \
  /new/com.torrekie.battman.plugin.charge-gauge.battman
```

Create `/new` first and use fresh output paths; substitute the independently
reviewed fingerprint printed by the public-key command for
`APPROVED_64_HEX_FINGERPRINT`. The package builder expects its raw 65-byte public
point rather than PEM. The signing command is an offline production operation
run only on the approved publisher signer. A signed package enters
`OfficialPlugins/Packages/` only after publisher-signature, platform-signature,
delegation-scope, reproducibility, and independent-fingerprint review.

Strict release assembly preserves that directory as the trust object and emits
`com.torrekie.battman.plugin.charge-gauge_1.0.0.battman.zip` for download. The
archive contains the canonical
`com.torrekie.battman.plugin.charge-gauge.battman/` root; users extract it before
document import. The same signed package bytes also produce the two Debian
add-ons and replacement-TIPA representation.
