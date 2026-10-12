# Battman release process

Release tooling and validation workflows are implemented. Production trust
metadata, signed packages, reviewed key fingerprints, and publication approval
remain separate requirements; a passing build does not establish that these
materials are complete. Battman versions use numeric `MAJ.MIN.PATCH[.REV]`, with
`Debug` and `Release` build configurations. Alpha, beta, and stable describe
readiness rather than additional version or build channels.

The three application variants are distinct:

| Distribution | Xcode scheme | Release use |
| --- | --- | --- |
| Public | `Battman` | Public-source app and CI validation |
| GitHub | `Battman (rel-nonfree)` | GitHub host Debian packages and replacement TIPA |
| Havoc | `Battman-havoc` | Havoc host Debian packages, including the existing private authorization implementation |

The GitHub scheme selects the `Battman-nonfree` target; use the scheme's full
name, including spaces and parentheses, with `xcodebuild -scheme`.

The executable records `public`, `github`, or `havoc` in its
`__TEXT,__btchannel` section. Finalization verifies this against the selected
target, and package inspection reports it separately from source identity.
Havoc requires its private implementation and definitions; public CI does not
supply them. There is no Havoc TIPA target, and the TIPA builder and inspector
reject a Havoc executable.

## 1. Roles and separation

The source reviewer approves the exact commit and tag. Offline root holders
approve official publisher delegation/revocation metadata. The official
plug-in publisher signs exact `Manifest.json` bytes. The checksum signer signs
the complete release asset list. A separate non-official example publisher
signs the SDK example if it ships. A release reviewer independently compares
public-key fingerprints, artifact inspection, checksums, SBOM/provenance, and
release notes. A protected GitHub environment reviewer may create a draft only;
Havoc submission is a separate artifact-specific approval and manual action by
Torrekie.

One person may hold several roles in a small project, but the steps and key
material remain separate. No private root or publisher key belongs in Git,
ordinary pull-request CI, an app bundle, a package, logs, or local automation state.
For the complete 1.1.0 matrix this means six distinct Battman private keys:
three roots, official publisher, SDK-example publisher, and release checksum.
Apple/ad-hoc/TrollStore platform signing is a separate mechanism and does not
replace any of them.

Xcode app products embed the built `intl.framework` and its LGPL license.
The app finalizer signs this framework before signing the app; framework-target
signing is disabled so recent Xcode versions do not request a development
certificate for a distributable ad-hoc build. The compiled gettext catalogs
remain in the app's `locales` directory.

## 2. Required decisions and inputs

Before strict assembly:

- choose a release version and make the exact `v<VERSION>` tag agree with
  `VERSION`;
- retain the exact owner-approved MIT `PluginSDK/LICENSE` and its complete SDK
  subtree scope if the SDK ships;
- decide which official cards are embedded, separately packaged, and included
  in the replacement TIPA;
- establish root threshold, root/release key custody, rotation, revocation,
  backup, incident, and recovery operators;
- create reviewed public root policy plus threshold-signed trust metadata under
  `OfficialPlugins/Trust/PluginTrust/` without placing private keys there, then
  commit the reviewed public-only tree into the exact release tag;
- commit already signed public official `.battman` packages under
  `OfficialPlugins/Packages/` into that exact tag;
- commit the separately signed public SDK Analytics example under
  `PluginSDK/Examples/Packages/` into the exact tag; it remains third-party and receives no
  official delegation, add-on package, or replacement-TIPA inclusion;
- record the reviewed SDK example publisher-key fingerprint without treating
  that publisher as officially delegated;
- record the independently published checksum public-key fingerprint;
- supply the reviewed checksum public key to strict assembly and retain its
  private key exclusively on the offline checksum station;
- approve support/privacy/security intake and Havoc product classification.

For 1.1.0, `Packaging/Release/release-matrix.json` selects ten embedded
Analytics cards. Charge Gauge is separately packaged and included in
rooted/rootless add-ons and GitHub replacement TIPAs. The trust policy calls
for 2-of-3 offline roots with separate publisher and checksum keys. These
requirements describe the intended release inputs; they do not attest that
production signatures or custody reviews have been completed. Production
private keys remain confined to the owner-operated signing ceremony and never
enter normal build or CI tooling.

The same private workspace holds the SDK review order, Havoc classification and
dual-hosting decision, support ownership decision, readiness ledger, and review
records. These files can contain device identifiers, recovery details, or
release approvals, so they are intentionally excluded from this public tree.
Independent review may occur after code freeze, but must still precede accepting
production fingerprints, signatures, backups, and final artifacts as reviewed
release evidence. A missing local record is a blocker, never an implicit
approval.

## 3. CI boundary

`.github/workflows/ci.yml` runs on pull requests, pushes to `master`, and
manual dispatch. Its Ubuntu job downloads the digest-pinned iPhoneOS SDK and
LLVM toolchain, checks source and release boundaries, and builds one Debug IPA
with `-j1`. That IPA is a short-lived CI artifact.

After the Ubuntu job succeeds, the macOS `release-tests` job runs the focused
plug-in, Analytics, and strict release regression suite, then builds the Public
`Battman` and GitHub `Battman (rel-nonfree)` schemes in `Release`. Those two builds run
serially with one build worker. They exercise the public source tree without
production signing inputs. The optional `run_macos_evidence` input additionally
runs simulator rendering, user-manual generation, and a Simulator build. Havoc's
private authorization inputs are not part of either public CI lane.

`.github/workflows/release.yml` supports three entry paths:

| Trigger | Validation and output |
| --- | --- |
| Manual dispatch with `validate_only: true` (default) | `tag` accepts a branch, commit, or tag ref. Requires a clean checkout, runs focused tests and synthetic signed-package regressions, and builds the GitHub Release app. It creates no production candidate, signature, tag, or GitHub draft. |
| Push of a `v*` tag | Requires an exact clean `v<VERSION>` tag and the production public inputs, then builds and inspects an unsigned candidate for offline checksum signing. It does not create a GitHub draft. |
| Manual dispatch with `validate_only: false` | Requires that same exact tag and production inputs. After candidate inspection and offline signature return, a protected job may create a GitHub draft. |

The production build job requires reviewed public trust metadata and signed
plug-in packages tracked in the exact tag. It also requires the public
repository variables `BATTMAN_CHECKSUM_PUBLIC_KEY_PEM`,
`BATTMAN_CHECKSUM_SIGNING_KEY_ID`, and
`BATTMAN_SDK_EXAMPLE_PUBLISHER_KEY_ID`. These variables contain public material,
not private keys. Validation-only runs skip these production-input steps;
their synthetic package tests do not certify a production release matrix.

For a production manual run, let `build-and-inspect` finish, download and verify
its unsigned candidate, and transfer exact `SHA256SUMS` bytes to the offline
checksum station. Base64-encode the returned DER signature into the protected
`battman-production-release` environment secret
`BATTMAN_CHECKSUM_SIGNATURE_BASE64`, then approve that environment. The job
checks the reviewed checksum fingerprint and rejects stale, malformed,
mismatched, or wrong-key signatures before creating a **draft**. Remove or
replace the signature secret after the run. The build and protected jobs must
use the same reviewed public checksum fingerprint.

Every action is pinned to a full commit SHA. Native jobs select Xcode
explicitly and keep product, intermediate, and simulator output outside the
checkout. No hosted runner receives a production checksum private key, no
workflow publishes a GitHub draft, and no workflow uploads to Havoc.

## 4. Local strict assembly

Start with a clean exact tag and independently finalized GitHub Release app
copies built with `Battman (rel-nonfree)`. Use fresh output directories and bounded
parallelism. Build Havoc Debian inputs separately with `Battman-havoc`; do not
substitute them into the GitHub matrix or replacement TIPA:

```sh
export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
test "$(git describe --tags --exact-match HEAD)" = "v$(cat VERSION)"
test -z "$(git status --porcelain=v1 --untracked-files=all)"

python3 Scripts/Release/assemble-release.py \
  --repo . \
  --deb-app /reviewed/input/Battman-deb.app \
  --tipa-app /reviewed/input/Battman-tipa.app \
  --plugin OfficialPlugins/Packages/com.torrekie.battman.plugin.charge-gauge.battman \
  --sdk-example PluginSDK/Examples/Packages/com.torrekie.battman.example.analytics.battman \
  --sdk-example-key-id REVIEWED_SDK_EXAMPLE_64_HEX_FINGERPRINT \
  --version "$(cat VERSION)" \
  --checksum-public-key /reviewed/input/checksum-public.pem \
  --checksum-key-id APPROVED_64_HEX_FINGERPRINT \
  --output-directory /new/output/Battman-release \
  --source-date-epoch "$SOURCE_DATE_EPOCH" \
  --builder-id urn:battman:reviewed-local-builder
```

Add each reviewed signed official package with `--plugin`. The TIPA tool embeds
bundle payloads in the standard nested-code location and keeps signed metadata
separate. Rooted/rootless plug-in Debian files are built independently with
`build-plugin-deb.py`; strict assembly also wraps the unchanged signed directory
package as `<identifier>_<version>.battman.zip`, with the canonical
`<identifier>.battman` root inside. It emits the transport and both add-on
variants for every selected official package and includes them in inspection,
SBOM, provenance, checksums, and release notes.

`Packaging/Release/compatibility-matrix.json` is validated against the selected
cards, public metric namespace, minimum deployment targets, readiness policy,
and named evidence before assembly. The exact checked file is copied into the
release directory and enters the same inspection/checksum chain. Do not edit a
candidate copy to broaden hardware, iOS, jailbreak, or TrollStore claims.

Add the one reviewed signed SDK example with `--sdk-example`. Its
`com.torrekie.battman.example.analytics` identity is fixed by the release
matrix. Assembly creates only its `.battman.zip` transport, marks it as requiring
third-party explicit approval, rejects overlap with official selection, and in
strict mode requires its primary publisher key to match the independently
reviewed `--sdk-example-key-id` fingerprint.

Before accepting either official or SDK-example bytes, assembly validates the
matrix's `signedPluginReleasePins` against the canonical source manifest,
bundle `Info.plist`, and version files, then compares identifier, display/build
versions, and release sequence with the signed package. The SDK example's
`BUILD_VERSION` is also compiled into its native descriptor. A plug-in release
version change must update this complete source-bound set and pass
`Tests/Release/test_plugin_release_pins.py`; do not rename an old signed package
to satisfy the matrix.

Strict assembly first runs `validate-official-trust.py`, requires at least one
official package, checks every package identity and extension point against its
signed delegation, and requires both app inputs to contain a byte-identical
`PluginTrust` snapshot. The release workflow deterministically passes every
top-level `OfficialPlugins/Packages/*.battman` directory; nested or linked
inputs are rejected. Strict assembly also rejects any trust/package file that
is outside the repository or is not tracked by the exact release tag; ignored
or runner-injected public release inputs cannot enter the candidate.
Engineering assembly skips production delegation only; it
still requires the exact owner-approved official plug-in identifier set so a
green mechanics test cannot silently omit Charge Gauge.
Strict assembly has no production private-key option. It validates and copies
only the reviewed checksum public key; the private key remains offline.

Every Xcode and Make host link also embeds canonical JSON in the thin arm64
executable's `__TEXT,__btidentity` section. It records schema version, numeric
Battman version, Debug/Release configuration, bundle identifier, full Git
commit, full Git tree, and whether the build worktree was dirty. The build
finalizer verifies that section against its current checkout before signing.
Strict assembly requires `Release`, the exact tagged commit/tree, and
`sourceDirty=false`; copying plist values or marker strings onto another
executable therefore cannot manufacture valid release provenance. Artifact
inspection repeats the section check after Debian and TIPA extraction and
records the decoded identity in `artifact-inspection.json`.

Run assembly twice from independent staging roots. The filename set and bytes
must match. A mismatch is a release blocker; do not “fix” checksums by accepting
one arbitrary run.

## 5. Inspection and offline verification

The matrix contains:

- rooted `iphoneos-arm` and rootless `iphoneos-arm64` host Debian files;
- GitHub replacement `Battman.tipa` and its embedding/re-sign report;
- signed official `.battman.zip` transports plus rooted/rootless plug-in add-ons;
- the separately signed third-party SDK example `.battman.zip`;
- SDK source archive after its license gate closes;
- the conservative `compatibility-matrix.json` evidence/claim record;
- artifact inspection, release notes, CycloneDX SBOM and in-toto provenance;
- `release-manifest.json`, containing the exact final filename set and each
  ordinary artifact's role, channels, activation policy, size, and SHA-256;
- `SHA256SUMS`, P-256 signature, and the public verification key.

For the strict unsigned candidate:

```sh
python3 Scripts/Release/verify-release-directory.py \
  /candidate --allow-missing-offline-signature
python3 Scripts/Release/verify-checksums.py /candidate/SHA256SUMS
```

Transfer exact `SHA256SUMS` bytes to the offline checksum station. There, sign
into the same temporary directory with the existing production key:

```sh
python3 Scripts/Release/sign-checksums.py \
  --private-key /offline/checksum-private.pem \
  --password-file /offline/checksum-password \
  --checksums /offline/SHA256SUMS \
  --signature /offline/SHA256SUMS.p256.sig \
  --source-date-epoch "$SOURCE_DATE_EPOCH"
```

Return only `SHA256SUMS.p256.sig`, then attach it into a new final directory:

```sh
python3 Scripts/Release/finalize-release-signature.py \
  --candidate /candidate \
  --signature /returned/SHA256SUMS.p256.sig \
  --expected-key-id APPROVED_64_HEX_FINGERPRINT \
  --output-directory /new/final-candidate \
  --source-date-epoch "$SOURCE_DATE_EPOCH"
python3 Scripts/Release/verify-release-directory.py /new/final-candidate
python3 Scripts/Release/sign-checksums.py \
  --public-key /new/final-candidate/SHA256SUMS.p256.pub \
  --checksums /new/final-candidate/SHA256SUMS \
  --signature /new/final-candidate/SHA256SUMS.p256.sig
```

After these byte-level checks pass, compare the candidate with the owner-private
readiness ledger and review records. Those local records authorize nothing by
their mere presence; all required decisions must be explicitly complete.

The directory verifier fails on any missing, extra, linked, malformed, or
changed file. It also requires `SHA256SUMS` to cover the manifest and every
final asset except `SHA256SUMS` itself and its detached signature. The
manifest's `publicationAuthorized` value is always `false`; protected human
approval remains a separate action.

Strict assembly additionally scans the bounded host executable for every
owner-selected embedded Analytics identifier and the frozen plug-in-host
contract markers. That content check and the exact embedded build identity are
independent requirements: a differently built arm64 app cannot enter the
matrix merely by copying Battman's bundle identifier, version, commit plist
values, trust resources, marker strings, and an otherwise valid signature.

Independently compare the printed key identifier with the approved fingerprint.
A public key distributed beside its signature proves self-consistency, not
identity. Inspect Debian metadata/layout with both Battman's strict reader and
`dpkg-deb --info/--contents`. Confirm arm64/iOS load commands, embedded platform
signatures, exact `appBuildIdentity` commit/tree/clean-Release fields, no
maintainer scripts, no links or foreign paths, and the replacement TIPA's
`requiresOuterResign` status.

## 6. Channel handling

GitHub receives only the reviewed matrix and remains a draft until explicit
approval. Prefer immutable release settings once the owner decides to publish.
After publication, download every asset into a new directory and repeat
checksum/signature/inspection checks.

Havoc host candidates must be built separately using `Battman-havoc` in
`Release`, with its existing private authorization implementation and
definitions. Package that finalized app using `build-host-deb.py` for the
rooted and rootless layouts. `validate-havoc-candidate.py --artifact-kind host`
requires the embedded `havoc` channel; a Public or GitHub host Debian is not a
substitute. GitHub host Debian records do not receive the
`havoc-manual-candidate` label. Separately shipped official plug-in Debian
records may receive that label, subject to their own Havoc validation and
manual approval.

Owner-selected host or plug-in Debian candidates must separately pass the
applicable `validate-havoc-candidate.py` checks against the explicit
last-published version and the independently reviewed full
`--commit`/`--source-tree`. Do not assume that a plug-in inherits the host
classification or that a `Plugins` section exists. Review the current Havoc
classification and dual-hosting policy for each product, then manually upload
only the exact `.deb` bytes after support scope, screenshots/copy, and
artifact-specific owner approval are recorded. No release script or workflow
uploads to Havoc. Download and compare Havoc-processed artifacts afterward,
documenting any legitimate repository transformation.

APT/dpkg and marketplace transport never grants Battman plug-in trust. Official
packages still require scoped offline delegation; third-party packages still
require explicit exact-build or publisher approval. TrollStore replacement
TIPAs remain unsigned at this tool boundary and require explicit outer signing
and user installation.

## 7. Abort, recovery, and records

Abort on any tag/version/commit mismatch, dirty checkout, missing license,
unknown key fingerprint, non-release app, inspection error, non-reproducible
byte, unreviewed owner decision, or unavailable support/revocation operator.
Never overwrite a candidate in place.

Keep the signed checksums, public keys/fingerprints, inspection report,
provenance, source commit/tag, workflow run, owner approvals, and post-download
verification with the release record. Keep private keys, passwords, device
identifiers, and user trust databases out of that record.

An emergency response disables publication, distributes threshold-signed
revocation metadata through the next trusted channel, tests rollback handling,
and invokes safe-mode/support instructions. Native code already mapped cannot
be unloaded; remediation takes effect on restart or replacement install.
