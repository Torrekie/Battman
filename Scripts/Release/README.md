# Release tools

These commands form a bounded, non-publishing post-build pipeline. They accept
resolved local inputs, create only new outputs, reject links/special files and
unexpected archive members, normalize timestamps/modes, and never install,
upload, contact a device, invoke TrollStore, or generate a production key.

## Channels and workflow entry points

| Distribution | Xcode scheme | Packaging |
| --- | --- | --- |
| Public | `Battman` | Public-source app and CI validation |
| GitHub | `Battman (rel-nonfree)` | Rooted/rootless host Debian and replacement TIPA |
| Havoc | `Battman-havoc` | Rooted/rootless host Debian only, preserving existing private configuration and source exclusions |

The GitHub scheme's underlying target is `Battman-nonfree`; command-line
builds must quote the full `Battman (rel-nonfree)` scheme name. Build and
inspection tools validate the executable's `__TEXT,__btchannel` marker. The Havoc variant retains its private configuration headers, but
`nonfree-havoc.m` remains excluded from compilation and `DISABLE_PROTECT=1`
remains unchanged. The channel marker does not enable or restore DRM. There is
no Havoc TIPA target. `build-tipa.py` and TIPA inspection
reject the `havoc` channel, while the Havoc host validator requires it.

Routine CI runs the Linux Debug cross-build, followed by the native regression
suite and serial Public/GitHub Release builds. Simulator evidence is an
additional opt-in lane. The manual release workflow defaults to
`validate_only: true`, accepts a ref in its `tag` input, and runs focused tests,
synthetic signed-package regressions, and the GitHub Release build without
production signing inputs or draft creation.

Production runs require an exact clean `v<VERSION>` tag, tracked public trust
metadata, and the reviewed public checksum fingerprint. Battman 1.1.0 selects
no compiled plug-in or SDK-example packages. A tag push only prepares an unsigned
candidate. Manual production dispatch can create a draft after the offline checksum signature is
returned and the `battman-production-release` environment is approved. A green
validation-only run does not establish production-material readiness. Neither
workflow publishes the draft or uploads to Havoc.

## Assembly and inspection

`assemble-release.py` has two intentionally different modes:

- strict mode requires a clean exact `v<VERSION>` checkout, the commit timestamp
  as `SOURCE_DATE_EPOCH`, Release-marked apps whose executable embeds the exact
  full commit/tree and a clean-source flag in `__TEXT,__btidentity`,
  `PluginSDK/LICENSE`, and a portable-verified official trust snapshot embedded
  byte-identically in both apps. Public trust bytes must be tracked in that
  exact tag. Compiled Charge Gauge and SDK-example packages are outside the
  1.1.0 release selection and must not enter its assets or TIPA. Strict mode also
  requires the reviewed P-256 checksum public key and its independently
  approved fingerprint. It never accepts the production checksum private key;
- `--engineering-candidate` relaxes only tag/dirty-tree, Release-mark,
  production-trust, and approved-fingerprint gates so the mechanics can be tested. Its
  release notes identify it as non-publishable.

Both modes fail closed unless the release artifact matrix and the conservative
compatibility matrix agree with the selected cards, public metrics, minimum
deployment targets, channel policy, and exact owner-approved official plug-in
input set. That set is empty for 1.1.0: the ten built-in Analytics cards are
host code, while Charge Gauge and the SDK Analytics card are developer source
examples only. Neither assembly mode may silently add compiled examples.
Generic plug-in package tools and source-version checks remain useful for
separate developer tests; those outputs are not release artifacts.

The normal order is:

1. build/finalize a GitHub Release app using `Battman (rel-nonfree)`;
2. export the SDK and any selected reference sources without compiled examples,
   test packages, keys, caches, or build output;
3. assemble rooted/rootless host Debian files and the replacement TIPA;
4. inspect all code, metadata, layouts, signatures, and SDK contents;
5. generate release notes, CycloneDX SBOM, SLSA-style in-toto provenance, and
   `release-manifest.json`, which records the exact final filename set plus each
   ordinary artifact's role, channel, activation policy, size, and digest;
6. generate checksums with the reviewed public key, verify the exact unsigned
   directory, and transfer exact `SHA256SUMS` bytes to the offline checksum
   signer;
7. attach the returned detached signature with
   `finalize-release-signature.py`, which rechecks the key fingerprint,
   signature, checksums, and final directory without overwriting the candidate;
8. hand the immutable directory to a human reviewer, who evaluates the
   owner-private readiness ledger separately from the public build tree.

For separate plug-in development/testing, `archive-plugin-package.py` can wrap
a signed directory package in a deterministic
`<identifier>_<version>.battman.zip` download while preserving the canonical `<identifier>.battman` directory inside. `build-plugin-deb.py`
independently produces rooted and rootless delivery packages from the same
signed bytes. These generic tools do not select Charge Gauge or the SDK sample
for the formal 1.1.0 release. `validate-havoc-candidate.py` checks an owner-selected
rooted and rootless Debian pair for manual Havoc submission. Its `--artifact-kind host`
mode requires a separately built `Battman-havoc` Release app in each package
and applies embedded `havoc` channel, host layout, exact commit/tree, version,
and `Section: Applications` checks. Its `--artifact-kind plugin` mode applies the
plug-in Debian layout, identifier/version, minimum-host dependency, and the
explicit owner-reviewed Havoc section. Host mode requires an explicit
last-published version; plug-in mode may use `--initial-submission` for a new
package. Both modes emit a
`candidate-only-not-uploaded` report, and retain classification,
dual-hosting-policy, exact-artifact, and owner-approval gates. The validator
never logs in, uploads, or records publication. `build-tipa.py` separates a
package's nested bundle and signed metadata, preserves its nested platform
signature, removes the now-invalid copied outer resource seal, and reports that
explicit outer re-signing and installation are still required.

`validate-official-trust.py` verifies the bounded `PluginTrust` tree, public
P-256 fingerprints, exact metadata bytes, root signature threshold, metadata
schema, delegation scopes, and revocations without private keys or network
access. The app repeats these checks and additionally persists monotonic
metadata sequence/digest state in this-device-only Keychain storage.

`validate-production-key-evidence.py` verifies the public-only six-role
ceremony record, distinct P-256 fingerprints, the exact encrypted PKCS#8 digest
and size on two distinct pinned SSH backup hosts per role, and one restored
role-bound signed recovery challenge per key. `--require-reviewed` also
requires a frozen source commit and post-code-freeze reviewer record. It rejects
private/extra files and never treats key generation alone as release evidence.
A ceremony role or existing publisher key is not a request to ship a compiled
example; 1.1.0 requires no SDK-example package or example-publisher release input.

The deterministic Debian codec supports only Battman's deliberately small
subset: Debian format 2.0, exact `debian-binary`, `control.tar.xz`, and
`data.tar.xz` members, root-owned regular files/directories, and no maintainer
scripts or links. It is tested for `dpkg-deb` compatibility but does not depend
on `dpkg-deb` to create release bytes.

`check-compatibility-matrix.py` binds minimum OS, installation-channel claims,
card metric availability, TrollStore replacement-only activation, and the
distinction between verified evidence and community reports. Strict and
engineering release assembly both include that exact matrix in inspection,
SBOM, provenance, and checksums.

Charge Gauge and the SDK Analytics example are distributed as source only.
Their developer build/signing instructions remain available, but 1.1.0 release
assembly takes no `--plugin`, `--sdk-example`, or `--sdk-example-key-id` input.
The final asset list contains no example `.battman.zip` or plug-in Debian files,
and the release TIPA contains no compiled example code.

`generate-release-manifest.py` fails if the concrete asset set differs from
`Packaging/Release/release-matrix.json`, if inspection contains an unselected
asset, or if the TIPA's sealed official set differs from owner selection.
The 1.1.0 GitHub matrix contains no plug-in Debian records. GitHub host Debian
records do not receive the `havoc-manual-candidate` label: Havoc host packages
require a separate `Battman-havoc` build and channel validation. The label does
not authorize publication. TIPAs, raw
`.battman` packages, `.battman.zip` transports, SDK/source archives, and other
assets are never Havoc candidates.
`verify-release-directory.py` rejects missing, extra, linked, malformed, or
changed files and requires `SHA256SUMS` to cover every final file except itself
and its detached signature. The checksum signature therefore binds the
manifest and exported public key; the independently published public-key
fingerprint remains the identity anchor.

`release_inputs.py` enforces the strict source/secrets split: reviewed public
trust inputs must be tracked in the exact checkout. Any plug-in inputs selected
by a future release must meet the same boundary; source examples do not count
as selected production packages. Strict assembly accepts only the checksum public key; production private-key use is
confined to the separate owner-operated `sign-checksums.py` ceremony. Engineering
fixtures use only ephemeral local keys and do not claim production identity.
`sign-checksums.py --password-file` supports the ceremony's encrypted P-256
private key without exposing its password in a command line or environment.
`export-checksum-public-key.py` is confined to unencrypted ephemeral engineering
keys; production public-key export occurs only on the owner-controlled key
station.

`host_build_identity.py` is the bounded shared codec for the build and release
boundaries. `Scripts/Build/generate-build-identity.py` emits canonical JSON
before the host link; Xcode and Make pass it to `ld` with `-sectcreate`;
`verify-build-identity.py` checks the linked bytes before app finalization.
Strict assembly and post-package inspection parse the Mach-O load commands
directly, reject missing/duplicate/noncanonical sections, and require the exact
clean tagged commit/tree. Host-content marker scanning remains a separate
defense-in-depth check.

Strict host inputs are also checked for every owner-selected embedded Analytics
card identifier plus the frozen Analytics extension, native entry-point, and
import-notification contract markers. This is a fail-closed substitution check
in addition to bundle identifier, Release configuration, exact source commit,
code-signature inspection, and app-bundled `PluginTrust` equality; plist
metadata alone is not sufficient to identify the release host.

Run the local safety suite with:

```sh
bash Tests/Release/run-release-tool-tests.sh
```

Read [`docs/release-process.md`](../../docs/release-process.md) before operating
strict mode. Release-gate decisions and their evidence remain in the
owner-private review workspace and are never inferred from a successful build.
