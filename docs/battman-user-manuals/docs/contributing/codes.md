---
title: Contributing Code
---

# Contributing Code

Read the [project README](https://github.com/Torrekie/Battman) for the current
build entry points and repository conventions. Battman 1.1.0 uses Objective-C and C, programmatic UI,
an Xcode project, and a Make-based cross-build path.

## Find the relevant component

| Directory | Purpose |
| --- | --- |
| `Battman/` | iOS application and device interfaces |
| `Battman/Features/Analytics/` | Host data services, card layout, and built-in cards |
| `Battman/PluginHost/` | Native plug-in discovery, verification, trust, and lifecycle |
| `PluginSDK/` | Public SDK v1 headers, schemas, templates, tools, and example |
| `OfficialPlugins/` | Charge Gauge developer source example and public trust inputs |
| `Scripts/Build/`, `Scripts/Release/`, `Packaging/` | Build finalization, package construction, and release contracts |
| `Tests/` | Focused host, SDK, Analytics, and release checks |
| `docs/battman-user-manuals/` | This three-language manual |

## Implementation and validation

Keep changes focused and preserve the declared iOS 12 deployment baseline.
Use public SDK contracts for plug-ins; do not depend on private host controllers
or acquire hardware data from drawing callbacks. See the
[plug-in authoring guide](https://github.com/Torrekie/Battman/blob/master/docs/plugin-authoring.md)
for the standalone workflow and signing requirements.

Use existing dependencies and build paths. Xcode's gettext dependency downloads
a fixed archive, checks its digest, and builds it; its first build needs access
to GNU. Do not add an automatic dependency upgrade or require a different
toolchain for an unrelated change. Preserve portable resources and existing
programmatic UI conventions.

Run the smallest relevant checks for your change and describe exactly what was
validated. Simulator or compile success does not prove every device's hardware
behavior. Keep credentials, private signing keys, device identifiers, and private
release records out of commits and public diagnostics.

Update English, Simplified Chinese, and Traditional Chinese manual pages when
user-visible behavior changes. From the repository root, build the manual in
an isolated environment with:

```sh
Scripts/Docs/render-user-manual.sh /tmp/battman-manual-preview
```

The output path must not already exist. This uses the existing hash-pinned
`Requirements/docs.txt`, builds with strict checks, and does not deploy the
site. Serve the result over HTTP to review navigation and search.
