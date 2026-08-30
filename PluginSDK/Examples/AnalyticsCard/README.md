# Analytics card example

`BTAnalyticsExamplePlugin.m` is one implementation with two entry shapes:

- compile with `BT_PLUGIN_EMBEDDED=1`, link the object or static archive into
  the host, and pass `BTAnalyticsExamplePluginDescriptor()` to the embedded
  registration helper;
- compile without that definition as an `MH_BUNDLE`; it exports only
  `BattmanPluginEntryPointV1`.

The example imports only `PluginSDK/include` headers and documented Apple
frameworks. It creates the complete content hierarchy, owns a custom `CALayer`
and Core Graphics drawing, responds to host-delivered immutable snapshots, and
creates no polling timer. The same source is therefore the reference for
embedded-versus-native behavior, not two implementations that can drift.

Build it from the repository root:

```sh
make -C PluginSDK BUILD_DIR=/tmp/battman-sdk-example -j1 example
```

The manifest is deliberately a template. Supply the identifier of an existing
publisher public key using `Tools/publisher-key-id.py` and
`Tools/render-example-manifest.py`; do not replace the placeholder with a
production key in source control. Package/sign steps are in
[`docs/plugin-authoring.md`](../../../docs/plugin-authoring.md).

`BUILD_VERSION`, `Info.plist`, and `ManifestTemplate.json.in` must name the same
build. Both embedded and bundle builds compile that value into
`BTPluginDescriptorV1.pluginVersion`; generated card projects preserve the same
binding. This prevents a signed package from advertising a build that the
native entry point does not actually register.

For a public SDK release, the reviewed signed example is staged under
`PluginSDK/Examples/Packages/` and passed to strict assembly with
`--sdk-example`. It remains a third-party package: Battman does not officially
delegate it, put it in rooted/rootless add-ons, or embed it in the replacement
TIPA. Its GitHub asset is a deterministic `.battman.zip`, and loading still
requires explicit third-party approval. Strict assembly also requires the
reviewed primary publisher fingerprint through `--sdk-example-key-id`; this
pins release provenance without granting official trust.

Battman's simulator parity gate builds embedded and bundle forms in separate
processes and compares registered metadata, lifecycle traces, and rendered
pixels. It lives at `Tests/Simulator/run-analytics-example-parity.sh` and is
host verification, not a dependency of this standalone SDK directory.
