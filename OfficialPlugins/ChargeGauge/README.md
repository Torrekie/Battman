# Battman Charge Gauge

`com.torrekie.battman.plugin.charge-gauge` is the first separately shipped
official Battman plug-in. It owns its complete card content view and custom
gauge layer, consumes only immutable Analytics snapshots, and has no polling
timer or host-private dependency.

The six existing Analytics cards remain embedded. The embedded object produced
here exists only for registry/rendering parity tests; Battman 1.1.0 production
artifacts ship this card as a signed `.battman` bundle, rooted/rootless Debian
add-ons, and sealed code in a replacement TIPA.

Its signed manifest identifies the author as Torrekie and supplies the Battman
repository homepage plus the public support email. These fields improve the
management UI but do not replace official publisher-key verification.

Build the unsigned-source/native layer with bounded parallelism:

```sh
make -C OfficialPlugins/ChargeGauge \
  SDK_ROOT="$PWD/PluginSDK" \
  BUILD_DIR=/tmp/BattmanChargeGauge \
  -j1 all
```

Packaging requires an existing official publisher public key. Render the
manifest, build the deterministic directory package, then sign exact manifest
bytes only on the approved publisher signer:

```sh
python3 PluginSDK/Tools/publisher-key-id.py publisher-public.pem
python3 PluginSDK/Tools/render-example-manifest.py \
  --template OfficialPlugins/ChargeGauge/ManifestTemplate.json.in \
  --publisher-key-id APPROVED_64_HEX_FINGERPRINT \
  --output /new/ChargeGaugeManifest.json
python3 PluginSDK/Tools/Package/build-plugin-package.py \
  --manifest-template /new/ChargeGaugeManifest.json \
  --payload /tmp/BattmanChargeGauge/BattmanChargeGauge.bundle \
  --publisher-public-key publisher-public.p256 \
  --output /new/com.torrekie.battman.plugin.charge-gauge.battman
python3 PluginSDK/Tools/Package/sign-plugin-package.py \
  /new/com.torrekie.battman.plugin.charge-gauge.battman \
  --private-key /offline/publisher-private.pem \
  --password-file /offline/publisher-password
```

The last command is an offline production operation and is deliberately not
run on this development Mac. A signed package enters
`OfficialPlugins/Packages/` only after publisher-signature, platform-signature,
delegation-scope, reproducibility, and independent-fingerprint review.

Strict release assembly preserves that directory as the trust object and emits
`com.torrekie.battman.plugin.charge-gauge_1.0.0.battman.zip` for download. The
archive contains the canonical
`com.torrekie.battman.plugin.charge-gauge.battman/` root; users extract it before
document import. The same signed package bytes also produce the two Debian
add-ons and replacement-TIPA representation.
