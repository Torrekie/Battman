# Battman Plugin SDK v1

This directory is a standalone, public-header-only development kit for native
Battman plug-ins. It builds an Analytics card as either an embedded object or
an arm64/iOS 12 `MH_BUNDLE`, creates deterministic `.battman` packages, signs
exact manifest bytes with an existing P-256 key, and verifies those packages
without network access or executing their payloads.

The interface is frozen by `SDKContractV1.json`. The complete `PluginSDK/`
subtree is available under the [MIT License](LICENSE), including its public
headers, schemas, examples, templates, tools, test support, and documentation.
This subtree license does not relicense the Battman host outside `PluginSDK/`.
Independent plug-ins may use, implement, link against, modify, and redistribute
the SDK while retaining their own license terms.

The license decision does not publish a release by itself. Public archives and
compatibility promises remain subject to the repository's documented release
gates.

## Contents

- `include/`: the C ABI and Objective-C Analytics-card contract;
- `Examples/AnalyticsCard/`: one timer-free card owning its complete `UIView`
  and `CALayer` content tree;
- `Templates/NativeAnalyticsCard/`: the generated-project build template;
- `schema/`: package and offline trust-metadata schemas;
- `Tools/Package/`: deterministic build, existing-key signing, and portable
  offline verification;
- `SDKContractV1.json`: checked ABI/layout/interface and public-file hashes;
- `COMPATIBILITY.md`: the v1 evolution and support policy.
- `DEVELOPING.md`: standalone build, metrics, localization, signing, and
  installation instructions, also usable from an extracted SDK archive;
- `requirements.txt`: the pinned Python package-tool dependencies.

## Build without Battman source

Requirements are a macOS Xcode installation with an iPhoneOS SDK, `make`, and
Python 3.10 or newer. The separately installed Command Line Tools package does
not supply the iPhoneOS SDK. Package signing/verification also needs Python
`cryptography`; [the standalone guide](DEVELOPING.md#toolchain-and-dependencies)
provides the pinned dependency setup. The default toolchain comes from
`xcode-select`; override `DEVELOPER_DIR` explicitly when needed.

```sh
make -C PluginSDK BUILD_DIR=/tmp/battman-sdk-build -j1 example
```

From an extracted `BattmanPluginSDK-1.1.0` archive, change into that directory
and use `make BUILD_DIR=/tmp/battman-sdk-build -j1 example`. The archive root
is the SDK itself; a nested `PluginSDK/` directory is not required.

The result contains `BTAnalyticsExample.bundle` and
`BTAnalyticsExample.embedded.o`. The default build targets arm64 and iOS 12.0.
The bundle validator checks the one documented entry symbol, the bundle
identity, platform signature, and system-library dependency paths. Battman
performs the additional native architecture, deployment, dependency-policy,
and loadability checks at import.

`Examples/AnalyticsCard/BUILD_VERSION` is the example's canonical native build
version. The Makefiles bind that value into the plug-in descriptor and require
it to match `Info.plist`; the manifest template carries the same value. Change
all three together for a deliberate example release, then run the clean-room
and release-pin tests. A metadata-only version bump is rejected because the
host compares the signed manifest build version with the loaded descriptor.

Generate a separate project:

```sh
python3 PluginSDK/Tools/create-analytics-card.py \
  --plugin-id com.example.battman.charge \
  --card-id com.example.battman.charge.primary \
  --display-name "Charge Card" \
  --author-name "Example Developer" \
  --homepage-url "https://example.com/battman-card" \
  --support-email "support@example.com" \
  --output /tmp/ChargeCard
make -C /tmp/ChargeCard SDK_ROOT="$PWD/PluginSDK" -j1
```

The generator creates no keys and performs no publisher signing. It includes
the MIT license with the copied example source. Follow
[`DEVELOPING.md`](DEVELOPING.md) for the complete package flow, host contract,
and trust behavior. The Analytics example is included as editable source;
neither its source nor a signed example package grants official publisher trust.

Release maintainers export the SDK from a clean source staging directory.
`Scripts/Release/build-sdk-archive.py` in the full repository rejects build
products, caches, and signing inputs. The separately released signed example
under `Examples/Packages/` is excluded from the SDK source archive.

`build-plugin-package.py` inventories exact payload bytes and automatically
adds the bounded `macho-codesign-independent-sha256-v1` identity. Authors must
leave `payload.codeIdentity` out of templates; it is derived from the final
signed Mach-O, not entered by hand. Battman uses it only to recognize the same
code after a sealed replacement app is re-signed, never to waive resource,
publisher, rollback, or transport-package checks.

## Contract drift

Run this after any public header or schema change:

```sh
python3 PluginSDK/Tools/generate-sdk-contract.py --check
```

A failure is a required compatibility review, not an invitation to update the
hashes mechanically. Intentional compatible changes regenerate the JSON from
the command's standard output after the ABI fixtures and clean-room suite pass.
