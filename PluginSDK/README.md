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

## Build without Battman source

Requirements are Xcode command-line tools with an iPhoneOS SDK, `make`, Python
3, and `cryptography` for package signing/verification. The default toolchain
comes from `xcode-select`; override it explicitly when needed.

```sh
make -C PluginSDK BUILD_DIR=/tmp/battman-sdk-build -j1 example
```

The result contains `BTAnalyticsExample.bundle` and
`BTAnalyticsExample.embedded.o`. The bundle validator requires the one
documented entry symbol, an arm64 iOS payload, a valid platform signature, and
only approved system dependencies.

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

The generator creates no keys and performs no publisher signing. Follow
[`docs/plugin-authoring.md`](../docs/plugin-authoring.md) for the complete
package flow and [`docs/plugin-security.md`](../docs/plugin-security.md) before
distributing native code.

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
