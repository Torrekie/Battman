# Charge Gauge developer source example

`com.torrekie.battman.plugin.charge-gauge` is a small developer source example.
It owns its complete card content view and custom gauge layer, consumes only
immutable Analytics snapshots, and has no polling timer or host-private
dependency.

Battman 1.1.0 has ten built-in Analytics cards. Charge Gauge is not one of them
and is not a shipped production plug-in: the formal release contains no
compiled Charge Gauge bundle, `.battman.zip`, Debian add-on, or TIPA-embedded
Charge Gauge code. The source remains available for separate developer builds
and registry/rendering tests. The SDK Analytics example is also source-only in
the release.

The manifest template names Torrekie and provides the repository homepage and
public support email. These are author metadata, not permission to claim an
official publisher identity. A developer-signed test build must pass the normal
publisher-signature, platform, trust, and approval checks.

Build the native bundle for local development/testing with bounded parallelism.
The Makefile applies its local ad-hoc platform signature; package publisher
signing is a separate later step:

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

## Build a test package

For a development test, use an existing developer-controlled publisher key.
Render the manifest, build the deterministic directory package, then sign the
exact manifest bytes on the machine holding that test key. These steps do not
produce a formal Battman 1.1.0 release asset or grant official trust:

```sh
python3 PluginSDK/Tools/publisher-key-id.py publisher-public.pem \
  --raw-output /new/publisher-public.p256
python3 PluginSDK/Tools/render-example-manifest.py \
  --template OfficialPlugins/ChargeGauge/ManifestTemplate.json.in \
  --publisher-key-id TEST_PUBLISHER_64_HEX_FINGERPRINT \
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

Create `/new` first and use fresh output paths; substitute the fingerprint
printed by the public-key command for `TEST_PUBLISHER_64_HEX_FINGERPRINT`. The
package builder expects the raw 65-byte public point rather than PEM. Keep the
private key and password outside source, build output, and release materials.
Use the verification and installation requirements in the SDK development guide;
portable verification alone does not establish native loadability or trust.

Keep the resulting test package outside `OfficialPlugins/Packages/` and outside
the formal 1.1.0 release. Do not generate release ZIPs or Debian add-ons from it,
and do not embed it in the release TIPA. Developers testing TrollStore loading
need their own explicitly installed, correctly signed replacement app; that
platform requirement does not change this release's source-only example scope.
