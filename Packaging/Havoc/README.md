# Havoc manual Debian candidate scope

Torrekie may manually select these local candidates for Havoc submission:

- rooted host Debian (`iphoneos-arm`, `/Applications/Battman.app`);
- rootless host Debian (`iphoneos-arm64`, `/var/jb/Applications/Battman.app`);
- rooted/rootless Debian add-ons for owner-selected Battman plug-ins, including
  future plug-ins, after Havoc confirms an accepted section/classification for
  each product.

Only `.deb` files are Havoc candidates. TIPAs, raw `.battman` bundles,
`.battman.zip` transports, SDK/source archives, checksums, trust metadata, and
other release assets remain outside the Havoc submission scope.

Local preparation and inspection may be automated, but uploading is always a
separate manual action performed by Torrekie. No Battman script or CI workflow
logs in to Havoc, stores Havoc credentials, or publishes a candidate.
`validate-havoc-candidate.py` supports `--artifact-kind host` and
`--artifact-kind plugin`. It rejects Debug metadata, wrong architecture/path
pairs, a non-monotonic version relative to an explicit published version,
unsupported or mismatched `Section` values, an embedded host build identity
that differs from the explicitly reviewed full commit/tree, maintainer
scripts, and unexpected files. Plug-in mode additionally checks the package
identifier, host dependency, and rooted/rootless plug-in layout. Havoc
credentials are not accepted as command-line options and must never be exposed
to pull requests.

For each owner-selected host or plug-in Debian product, record an accepted
Havoc section/classification and review Havoc's current dual-hosting rules
before submission. Product-shape approval is not approval of the eventual
bytes: exact artifact review and Torrekie's explicit submission approval remain
required. After publication, download and compare Havoc-processed packages,
documenting any legitimate repository transformation.

Marketplace availability is not Battman publisher trust. Unless an official
offline delegation covers the exact publisher/plug-in/extension scope, the
normal third-party approval flow still applies.

The owner decision and any artifact-specific approval are maintained in the
owner's private release-review workspace.  They are intentionally not shipped
in this public source tree; the absence of that local record is a release
blocker, never an implicit approval.
