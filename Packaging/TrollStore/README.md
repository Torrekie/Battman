# TrollStore replacement TIPA boundary

`Scripts/Release/build-tipa.py` accepts an existing Battman `.app` and zero or
more already signed/portable-verified `.battman` packages. For every bundle
payload it creates the exact sealed installed representation consumed by the
host:

```text
Payload/Battman.app/
  PlugIns/<pluginIdentifier>.bundle/
  PluginManifests/<pluginIdentifier>/
    Info.plist
    Manifest.json
    Signatures/
    PublisherKeys/                 # when present
```

It preserves each nested bundle's platform signature, removes only the copied
outer app's now-invalid `_CodeSignature` directory from its private staging
tree, writes a deterministic TIPA plus JSON report, and stops. It never signs
the outer app, installs, launches, contacts a device, or invokes TrollStore.
The report therefore marks the result `requiresOuterResign: true` and
`requiresExplicitInstall: true`.

Battman 1.1.0 selects the separately shipped official Charge Gauge package for
this sealed representation. The release assembler passes every reviewed
official package to this tool and emits its rooted/rootless add-ons from the
same signed bytes.

The user's TrollStore installation step is the point at which the replacement
app and nested code may be re-signed. Direct data-container loading remains
unsupported until an exact device/version matrix proves library-validation
behavior; importing inside Battman therefore continues to report `Requires
Battman Reinstall`.
