# Battman release packaging

Packaging is an explicit post-build operation. Xcode produces/finalizes an app;
it does not assemble Debian or TIPA trees. Every release tool requires resolved
input/output paths, stages in a newly created sibling temporary directory,
refuses to overwrite artifacts, normalizes modes/timestamps, and never uploads,
installs, invokes APT/dpkg installation, or calls TrollStore.

```text
Packaging/
  Debian/Host/control.in
  Debian/Plugins/control.in
  Havoc/README.md
  Release/compatibility-matrix.json
  Release/release-matrix.json
  Release/release-notes.md.in
  TrollStore/README.md
Scripts/Release/
  build-host-deb.py
  build-plugin-deb.py
  build-tipa.py
  ...inspection, checksum, SBOM, provenance and orchestration tools...
```

Owner decisions, evidence, and the readiness ledger are deliberately maintained
outside the public source tree. A clean checkout builds and verifies artifacts;
it does not authorize publication.

Rooted and rootless roots are constructed independently:

| Artifact | Architecture | Install root |
| --- | --- | --- |
| rooted host | `iphoneos-arm` | `/Applications/Battman.app` |
| rootless host | `iphoneos-arm64` | `/var/jb/Applications/Battman.app` |
| rooted plug-in | `iphoneos-arm` | `/Library/Battman/PlugIns/<ID>.battman` |
| rootless plug-in | `iphoneos-arm64` | `/var/jb/Library/Battman/PlugIns/<ID>.battman` |

Maintainer scripts are intentionally absent. APT/dpkg publication and install
are delivery mechanisms only; Battman still verifies publisher signatures,
package bytes, native policy and local trust before restart activation.

All candidate builds take `SOURCE_DATE_EPOCH` (or an explicit
`--source-date-epoch`) so independent staging roots can produce identical
archives. Publisher/checksum signing accepts existing keys only. Production
keys and release credentials never belong in this tree or pull-request CI.
Strict assembly machine-checks that split: reviewed public trust/package inputs
must be tracked in the exact tag, and only the reviewed checksum public key is
accepted. `SHA256SUMS` is signed on the owner-controlled key station; the
returned detached signature is attached and fully reverified before draft
creation.

The strict matrix also exports `SHA256SUMS.p256.pub` and requires its lowercase
P-256 key fingerprint as an independent owner-approved input. The bundled
public key makes offline verification possible; users must compare its
fingerprint with a value published through a separate trusted channel.

`release-manifest.json` expands the matrix templates into the one exact final
filename set and assigns each ordinary artifact its role, delivery channels,
activation policy, byte size, and SHA-256. It is itself listed in signed
`SHA256SUMS`. Final verification rejects missing or extra files, including a
package that was built correctly but was not selected for the release.

For every selected signed official package, strict assembly also creates the
rooted and rootless plug-in Debian add-ons, creates a deterministic downloadable
`.battman.zip` containing the canonical signed directory package, verifies the
independent layouts, seals the same package into the replacement TIPA, and
includes every delivery form in artifact inspection, SBOM, provenance, and
checksums. The release also carries the exact checked compatibility matrix so
channel copy cannot silently broaden device or TrollStore claims.

The release matrix additionally pins the signed identity of every selected
official package and the separate SDK example: plug-in identifier, display
version, build version, and monotonic release sequence. Those values are bound
to the source manifest, bundle property list, and canonical version files, then
rechecked from the signed package and carried into inspection and the signed
release manifest. Advancing a plug-in version is therefore an explicit matrix
and source change, not a filename inference.

The release also requires one independently signed SDK Analytics example. It is
archived for GitHub but deliberately receives no official trust delegation,
Debian add-on, or replacement-TIPA inclusion; users must approve it as
third-party native code.

## Manual Havoc Debian candidates

Havoc is a Debian-only, owner-operated submission channel. The release manifest
may mark owner-selected rooted/rootless host and plug-in `.deb` files as
`havoc-manual-candidate`. TIPAs, raw `.battman` directories,
`.battman.zip` transports, SDK/source archives, and other release assets are
not eligible for Havoc submission.

`Scripts/Release/validate-havoc-candidate.py` validates either a host or plug-in
rooted/rootless Debian pair. It checks the applicable package layout,
identifier/version, explicit Havoc section, and published-version boundary; the
host mode also verifies the embedded commit/tree, while plug-in mode verifies
the minimum host dependency. Its report remains
`candidate-only-not-uploaded`.

Candidate construction and inspection may be automated, but uploading may not.
Torrekie manually uploads exact reviewed bytes only after the package's current
Havoc classification, dual-hosting policy, support/copy, digest, and separate
submission approval are recorded. No Havoc credential or publication action
belongs in this tree or CI. See [`Havoc/README.md`](Havoc/README.md); the
artifact-specific decision remains in the owner's private release-review
workspace.

The operator workflow is documented in
[`docs/release-process.md`](../docs/release-process.md). Alpha/beta/stable state
is evaluated from the reviewed, fail-closed owner-local readiness ledger;
unset decisions are blockers and are never inferred from a successful
engineering build.
