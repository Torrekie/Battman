# Battman plug-in package format v1

Status: format/schema v1 frozen. Verification is always complete before the
separate Phase 4 native loader can map an approved payload.

The transport UTI is `com.torrekie.battman.plugin`, conforms to
`com.apple.package`, and uses the `.battman` extension. A v1 package is a
directory, never a zip file disguised with that extension.

Download channels that cannot conveniently preserve an Apple directory package
may wrap that unchanged directory as
`<plugin-identifier>_<display-version>.battman.zip`. The ZIP suffix is the outer
transport wrapper; the archive must contain exactly one canonical
`<plugin-identifier>.battman/` root and must not be renamed to `.battman` while
still compressed. Battman imports the extracted directory package. Release
inspection reconstructs executable modes and reruns portable package
verification before the wrapper is published.

## Required layout

```text
Example.battman/
  Info.plist
  Manifest.json
  Signatures/
    <64-lowercase-hex-key-id>.sig
  PublisherKeys/                         # optional for unknown publishers
    <64-lowercase-hex-key-id>.p256
  Example.bundle/                        # or one Example.so
    Info.plist
    Example
    ... resources ...
```

`Manifest.json` follows
[`BattmanPluginManifestV1.schema.json`](../PluginSDK/schema/BattmanPluginManifestV1.schema.json).
Battman signs and verifies the exact UTF-8 bytes of that file with
ECDSA P-256 and SHA-256. Parsing and reserializing the JSON before verification
is forbidden. The parser rejects a BOM, invalid UTF-8, duplicate object keys,
trailing data, excess nesting, and any schema/type mismatch.

The key identifier is the lowercase SHA-256 of the 65-byte uncompressed X9.63
P-256 public key. A `.sig` contains one DER-encoded X9.62 ECDSA signature. Every
identifier in `publisher.signatureKeyIdentifiers` must have exactly one
signature file. The primary identifier must be present in that array. A public
key may come from Battman's built-in official metadata, a local approved
publisher record, or a package-listed `PublisherKeys/<id>.p256` file. An
included key proves package consistency only; it does not prove publisher
identity.

The optional signed `author` object is human-facing metadata, separate from
the cryptographic `publisher` block. It requires `name` and may include an
HTTPS-only `homepageURL` and an ASCII `supportEmail`. Names are bounded,
NFC-normalized, and reject control or bidirectional-formatting characters;
URLs reject credentials, whitespace, and non-HTTPS schemes; email addresses
use a conservative bounded form. Unknown fields fail closed. These values are
covered by the publisher signature, but remain publisher-provided claims: an
unknown publisher cannot establish identity merely by writing a familiar name
or support address into its own manifest.

The required signed `displayName` follows the same canonical display-text
policy: it is bounded, NFC-normalized, has no leading or trailing whitespace,
and rejects control, line/paragraph-separator, and bidirectional-formatting
characters. This prevents a
publisher-controlled name from injecting or visually reordering host-owned
approval warnings.

## File inventory

`files` lists every regular package file except `Manifest.json` and the exact
signature files declared by the publisher block. It therefore includes the
outer `Info.plist`, optional publisher keys, the payload executable, bundle
metadata, resources, localizations, and platform code-signature resources.

Entries are sorted by UTF-8 path bytes and contain the relative path, byte size,
mode class, and lowercase SHA-256. `data` means no executable bit;
`executable` means owner/group/other executable and is accepted only for the
declared payload executable or a future schema-defined executable role. Extra,
missing, duplicated, or case-colliding paths are hard failures.

`Manifest.json` is not self-hashed. Exact-build approval instead uses Battman's
package digest, a framed SHA-256 over every regular file—including the manifest,
signatures, and publisher keys—sorted by normalized relative path. The framing
contains the UTF-8 path length and bytes, normalized mode class, file length,
and file SHA-256, preventing concatenation ambiguity.

The package builder also emits `payload.codeIdentity` for a signed Mach-O. Its
v1 algorithm, `macho-codesign-independent-sha256-v1`, records the byte offset
where `LC_CODE_SIGNATURE` begins and hashes only the bytes before that offset.
Within those bytes it zeros exactly the signing-envelope fields that `ldid` or
TrollStore may rewrite: `__LINKEDIT` `vmsize`/`filesize` and
`LC_CODE_SIGNATURE` `dataoff`/`datasize`. No section, instruction, dependency,
symbol, entry point, or other load command is normalized.

This identity does not relax transport-package inventory checks. It is used
only when a verified package has been split into the sealed
`Battman.app/PluginManifests` plus `Battman.app/PlugIns` representation. In that
representation only the declared executable may differ from its transport
size/SHA-256, and its signed code identity must still match; every resource and
metadata byte remains exact. The logical package digest continues to use the
signed transport executable record, so TrollStore re-signing cannot create a
different package identity or bypass publisher/release rollback state.

## Outer Info.plist

The outer property list is non-authoritative preview metadata and must contain:

- `CFBundleIdentifier`, equal to the manifest plug-in identifier;
- `CFBundleDisplayName`, equal to `displayName`;
- `CFBundleShortVersionString`, equal to `displayVersion`;
- `CFBundleVersion`, equal to `buildVersion`;
- `CFBundlePackageType` = `BTPG`;
- `BTPluginPackageFormatVersion` = `1`;
- `BTPluginPublisherKeyIdentifier`, equal to the primary key identifier.

Every field is cross-checked only after `Info.plist` has passed the manifest
hash. `BTPluginPackageFormatVersion` must be the integer property-list type with
the exact value `1`; booleans and real-number encodings fail. Preview text is
never used to grant trust.

## Bundle Info.plist

A `bundle` payload must contain a signed, data-mode
`<payload.path>/Info.plist` no larger than 64 KiB. After exact inventory and
hash verification, the host requires:

- `CFBundleExecutable`, equal to the one direct bundle child named by the
  manifest executable path;
- `CFBundleIdentifier`, equal to the manifest plug-in identifier;
- `CFBundlePackageType` = `BNDL`;
- `CFBundleShortVersionString`, equal to `displayVersion`; and
- `CFBundleVersion`, equal to `buildVersion`.

Transport and sealed replacement-TIPA representations enforce the same signed
identity. A raw `.so` has no inner property list and is unaffected by these
bundle-only rules.

## Structural rules and limits

- package maximum: 128 MiB and 512 regular files;
- one file maximum: 64 MiB;
- manifest maximum: 256 KiB; outer plist maximum: 64 KiB;
- maximum path: 1024 UTF-8 bytes; maximum JSON depth: 16;
- maximum signatures/public keys: 8; signature maximum: 256 bytes;
- paths must be canonical relative NFC strings with no empty, `.`, or `..`
  component, control character, backslash, absolute prefix, or case collision;
- only directories and regular files are allowed; symlinks, hard links,
  sockets, devices, FIFOs, set-id bits, and group/other-writable entries fail;
- `Manifest.json`, `Info.plist`, `Signatures`, and the declared payload live at
  package-root locations fixed by v1;
- the payload is exactly one `.bundle` or `.so`; undeclared Mach-O files fail;
- inspection uses bounded reads and never calls `NSBundle`, `dlopen`, an entry
  point, a constructor, or any executable from the package.

Hard structural, hash, ABI, architecture, dependency, revocation, rollback, or
platform-load failures are not eligible for a dangerous-load override.

## Native payload policy

The byte-only native inspector accepts one canonical arm64 slice (thin, or a
one-slice fat wrapper) and requires `MH_BUNDLE` for `bundle` or `MH_DYLIB` for
`so`. The image must be dyld-linked, use two-level namespaces, declare exactly
one iOS minimum-version command matching the manifest, and export the declared
entry point from an executable section. The global symbol table and dyld export
trie must agree on that one strong external definition; no other external
function or data symbol is allowed. Linker-hidden Objective-C runtime metadata
is not part of this public export surface. It rejects dynamic-lookup/flat
namespace symbols, process entry commands, dyld environment commands,
interposing or termination sections, writable-plus-executable segments,
unexpected required-dyld commands, and malformed or overlapping ranges.

System dependencies are limited to libSystem, libobjc, libc++, Foundation,
CoreFoundation, UIKit, QuartzCore, and CoreGraphics. Other dependencies must be
declared by exact install name and use a contained `@loader_path/` or
`@rpath/` form. The only accepted runpaths are `@loader_path` and
`@loader_path/Frameworks`; re-export, lazy-load, upward-load, absolute, and
escaping paths fail. A raw `.so` uses `@rpath/<payload filename>` as its
install name; a `.bundle` has no dylib install name.

`LC_CODE_SIGNATURE` must be aligned, final in its slice, and contain one
bounded embedded-signature SuperBlob with unique, nonoverlapping blob slots.
Normally the primary CodeDirectory must use contiguous SHA-256 page hashes
covering every byte before the signature and an identifier equal to
`pluginIdentifier`.

A narrow sealed-replacement exception handles TrollStore's whole-app signing
shape. Only after the signed `payload.codeIdentity` matches may the primary be
one bounded SHA-1 compatibility CodeDirectory, and then the SuperBlob must
contain exactly one first alternate CodeDirectory (`0x1000`) using SHA-256,
covering the complete unsigned image, and identifying the containing Battman
app. The transport/app-data representations, a wrong host identifier, another
alternate slot, invalid SHA-256 pages, or changed canonical code bytes all fail
closed. Battman does not treat the compatibility CodeDirectory as publisher
trust.

Battman verifies the selected SHA-256 page hashes itself, then performs a
separate no-network platform loadability check. On iOS this uses the kernel's
`F_ADDFILESIGS_RETURN` and `F_CHECK_LV` preflight without mapping the image; the
macOS test host uses strict `SecStaticCode` validation.

## Offline trust and activation state

Official publisher delegation and revocation arrive in root-threshold-signed
`TrustMetadata.json` following
[`BattmanPluginTrustMetadataV1.schema.json`](../PluginSDK/schema/BattmanPluginTrustMetadataV1.schema.json).
Sequence and digest state rejects metadata rollback and same-sequence
equivocation. Local publisher approvals, exact-build approvals, and per-plugin
release rollback state are stored as this-device-only Keychain records.

The application resource layout is exactly `PluginTrust/RootPolicy.plist`,
`PluginTrust/TrustMetadata.json`, and
`PluginTrust/TrustMetadata.signatures/<root-key-id>.sig`. `RootPolicy.plist`
schema 1 contains `signatureThreshold` and a bytewise-sorted `rootPublicKeys`
array of `{keyIdentifier, publicKeyX963Base64}` records. Absence means there is
no official external publisher; a partial, invalid, removed-after-use, or
rolled-back snapshot fails closed and starts without external native plug-ins.
Only successfully threshold-verified metadata advances the this-device-only
Keychain sequence/digest state.

Unknown, otherwise valid publishers produce `RequiresApproval`; this is the
only non-error unapproved result. Official, scoped publisher, exact-build, and
explicit developer decisions can approve activation. Revocation, package
rollback, signature failure, and all structural/native/platform failures run
first and remain non-overridable. Import copies a fully verified package to
`<private quarantine>/<pluginIdentifier>/<packageSHA256>.battman`, re-verifies
staging and final bytes, and never activates or advances rollback state.

## Build and verification tools

The canonical public tools live under `PluginSDK/Tools/Package/`.
`build-plugin-package.py` creates an unsigned deterministic directory package
and can include an existing 65-byte publisher public point for offline local
approval. `sign-plugin-package.py` signs exact manifest bytes with an existing
P-256 private key. `verify-plugin-package.py` performs portable offline
envelope, inventory, hash, and publisher-signature checks. Release and SDK
automation should invoke these canonical tools directly.

`Scripts/Release/archive-plugin-package.py` creates the deterministic
`.battman.zip` delivery wrapper from an already signed package. It does not
modify package files or sign anything; the canonical signed trust object remains
the inner `.battman` directory.

The tools require Python 3 and the `cryptography` package. They never generate
production keys. `PluginSDK/Tools/publisher-key-id.py` converts only the public
half to the package encoding and fingerprint. Portable verification is not an
activation verdict: the in-app verifier remains authoritative for Mach-O,
platform signature, ABI, trust metadata, revocation, rollback, and local
approvals. The complete author workflow is in
[`plugin-authoring.md`](plugin-authoring.md), and the threat model is in
[`plugin-security.md`](plugin-security.md).
