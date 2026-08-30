# Battman release process

Status: production pipeline implemented; no release is authorized by this
document. Alpha, beta, and stable are internal readiness checks, not version
channels; Battman versions remain numeric `MAJ.MIN.PATCH[.REV]` and builds remain
`Debug` or `Release`. GitHub, Havoc, key, support, and publication decisions
remain explicit gates in the owner-private release-review workspace.

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

For 1.1.0, the owner-approved inputs are maintained in the private
release-review workspace: the six existing Analytics cards remain embedded;
Charge Gauge is separately packaged and included in rooted/rootless add-ons
plus replacement TIPAs; and trust uses 2-of-3 offline roots with separate
publisher and checksum keys. Production private keys may be generated on this
Mac only through the separately approved owner-operated ceremony; they must
never enter normal build/release tooling.

The same private workspace holds the SDK review order, Havoc classification and
dual-hosting decision, support ownership decision, readiness ledger, and review
records. These files can contain device identifiers, recovery details, or
release approvals, so they are intentionally excluded from this public tree.
Independent review may occur after code freeze, but must still precede accepting
production fingerprints, signatures, backups, and final artifacts as reviewed
release evidence. A missing local record is a blocker, never an implicit
approval.

## 3. CI boundary

`.github/workflows/ci.yml` uses an Ubuntu runner for the routine Debug IPA build.
It downloads only the pinned Theos iPhoneOS 13.7 SDK and L1ghtmann LLVM
toolchain, verifies their SHA-256 values, extracts them beneath a runner-local
directory, and invokes `make -C Battman ... -j1`; the resulting
`Battman/build/Battman.ipa` is uploaded as a short-lived CI artifact. Every
action is pinned to a full commit SHA and the build uses no Python release
dependencies. Xcode/simulator rendering and native Release packaging remain
owner/manual lanes, so a pull request does not spend a macOS runner on them.

`.github/workflows/release.yml` checks out the exact tag without persistent
credentials, proves tag/version/clean-tree identity, runs focused tests, builds
from fresh runner-local product/intermediate roots, validates the reviewed
checksum public key, and invokes strict assembly. It uploads only a short-lived
inspected candidate without the detached checksum signature. The offline
checksum operator signs exact `SHA256SUMS` bytes. A second job behind the
protected `battman-production-release` environment accepts only that returned
signature, attaches and verifies it, and creates a GitHub **draft** only on
manual dispatch. No hosted runner receives the production checksum private
key; no workflow publishes a release or uploads to Havoc.

For a manual release run, let `build-and-inspect` finish, download and verify
its unsigned candidate, and transfer only exact `SHA256SUMS` bytes to the
offline checksum station. After offline signing, base64-encode only the returned
DER signature into the protected environment secret
`BATTMAN_CHECKSUM_SIGNATURE_BASE64`, then approve the
`battman-production-release` environment. The draft job rejects a stale,
mismatched, malformed, or wrong-key signature. Remove or replace that signature
secret after the run so a later candidate cannot accidentally reuse it. The
public checksum PEM and both reviewed public fingerprints are environment
variables, not private-key secrets.

If the owner dispatches the optional simulator lane, it selects the runner's
available Xcode explicitly and keeps simulator output outside the repository.
Recheck the official runner-image inventory before each such run because hosted
images change.

## 4. Local strict assembly

Start with a clean exact tag and independently finalized Release app copies.
Use fresh output directories and bounded parallelism:

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
- replacement `Battman.tipa` and its embedding/re-sign report;
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
