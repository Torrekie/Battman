# Battman native plug-in security model

Native plug-ins are a deliberate high-trust feature for jailbreak and
TrollStore-style environments. They execute in Battman's process with its
entitlements and can create unrestricted UIKit/`CALayer` content. There is no
language VM, process sandbox, capability boundary, or safe unload mechanism.
The security objective is therefore to prevent silent or ambiguous loading,
authenticate exact bytes and publisher identity offline, restrict the accepted
Mach-O surface, make trust scope explicit, and preserve recovery—not to claim
untrusted native code is harmless.

## Threats in scope

- a renamed or malformed `.battman`, path traversal, symlink/hard-link escape,
  unlisted executable/resource, case collision, oversized input, JSON confusion;
- payload/resource/manifest/signature tampering and package replacement races;
- an unknown, impersonated, rotated, revoked, or rolled-back publisher;
- wrong architecture/file type/minimum OS/ABI, extra entry symbols, writable +
  executable memory, unsafe runpaths/dependencies, dynamic lookup/interposing;
- a package that registers undeclared, wrong-version, duplicate, or
  nonconforming extension objects;
- silent execution through file import, directory discovery, verification,
  preview metadata, or constructors before final activation;
- crash loops and loss of access to disable/remove a loaded plug-in;
- a compromised build/release pipeline leaking keys or publishing swapped
  artifacts.

## Trust hierarchy and offline operation

Publisher signatures use ECDSA P-256/SHA-256 over the exact signed-manifest
bytes. The key ID is SHA-256 of the 65-byte uncompressed public point. Battman
accepts keys from threshold-signed built-in official metadata, a scoped local
publisher approval, or an exact-build approval. A public key carried in the
package proves only fingerprint consistency; it does not establish identity.

Trust metadata, package signatures, file hashes, platform signatures, local
Keychain approvals, revocation and rollback state are all evaluated without
internet access. Network refresh may deliver newer official metadata later,
but activation never depends on a live service. Metadata sequence/digest state
rejects rollback and same-sequence equivocation. Release sequence is tracked
per plug-in/publisher pair. ABI v1 does not infer a publisher-key successor
from an opaque rotation reference: a same-ID app-data replacement with a new
publisher key must use an explicit exact-build approval, or the prior
representation must be removed before publisher-wide trust is granted.

Official trust is scoped to explicit plug-in and extension-point identifiers.
Third-party publisher approval is also scoped to the observed publisher key,
plug-in ID and requested extension points. Exact-build approval is bound to the
complete package digest. Neither approval overrides a hard failure.

## Non-executing verification boundary

Before native mapping, Battman performs bounded, no-network checks of:

1. canonical package tree, limits, modes and outer metadata;
2. strict signed JSON, exact inventory and every file hash;
3. publisher signatures, local/official scope, revocation and rollback;
4. byte-level arm64 Mach-O type, segments, load commands, entry symbol,
   deployment target, dependencies/runpaths and embedded CodeDirectory hashes;
5. an OS platform-loadability preflight that does not map the image.

Replacement TIPAs are verified against two signed identities. The logical
package digest retains the publisher-signed transport size/hash, while the
optional canonical Mach-O code identity ignores only the four bounded
`__LINKEDIT`/`LC_CODE_SIGNATURE` fields changed by whole-app signing. If
TrollStore supplies its SHA-1 compatibility primary CodeDirectory, Battman
requires the one valid alternate SHA-256 CodeDirectory to cover every unsigned
page and to identify the current Battman host. This exception exists only for
sealed app-bundle payloads; it cannot authorize an app-data or dpkg package.

This path cannot call `NSBundle`, `dlopen`, `dlsym`, an entry point, or a payload
executable. Constructor-sentinel fixtures enforce that boundary. Before any
trust rollback or crash-attempt state advances, the runtime copies only the
accepted payload inventory into a randomized, locked `0700` private stage and
rechecks every file's size, mode, and SHA-256 through no-follow descriptors.
Only the runtime loader contains `dlopen(RTLD_NOW | RTLD_LOCAL)` and `dlsym`, and
it maps the pinned private executable rather than reopening the package source.
Registration is transactional. Native handles and their staged descriptors are
retained permanently because Objective-C classes and callbacks make `dlclose`
unsafe.

## User approval and recovery

An otherwise valid unknown publisher is quarantined and shown as `Approval
Required`. Battman's UI states that native code can read/change anything the
app can, use its entitlements/network access, replace UI and crash the app; it
also states that source availability and a valid signature do not establish
safety. Its everyday summary shows the verification verdict and optional
signed author name, HTTPS homepage, and support email. Those contact fields are
explicitly publisher-provided claims. Publisher fingerprints and package
digests live in a separate technical view, are shortened for scanning, and
copy their full values for independent comparison. The final approval warning
still shows the exact plug-in ID, shortened identifiers, and extension-point
scope before offering destructive-styled choices:

- allow only this exact package build; or
- trust future versions from this publisher only for the same plug-in ID and
  observed extension-point scope.

Nothing loads from that consent screen. The choice is stored locally and
scheduled for a restart. Third-party plug-ins additionally require a global
enable switch. Disable, update, removal, and revocation are restart-only because
mapped native code cannot be safely removed from a live process.

Startup records the plug-in being activated before mapping it and clears that
record only after successful startup. A crash-loop marker causes safe mode on
the next launch and identifies the likely plug-in so the user can disable it.
A one-shot safe-mode request is consumed only when its exact protected marker
is valid; manual/malformed recovery markers remain fail-safe. App-bundle and
dpkg payloads are never deleted by in-app management. A canonical private
app-data package remains removable after revocation or loss of approval only
when a fresh, non-executing structural inspection matches its exact manifest
identifier, complete package digest, safe owned path, and app-data activation
record when one exists. Descriptor-pinned tombstone deletion fails closed on a path swap.
Malformed or structurally tampered trees are not deleted by this API.

## Open source is not an authorization boundary

Because Battman is open for inspection, an attacker can copy the loader,
schemas, identifiers, or UI. That does not yield an official private signing
key, a threshold-signed delegation, an exact local package approval, or a
matching package digest. Conversely, anyone able to modify and resign Battman
itself controls the host and can remove its checks; no in-process open-source
application can defend against a party already authorized to replace the host
binary or a root adversary modifying memory/files. This is outside the promised
boundary and must not be disguised by obfuscation.

Signatures authenticate bytes and key possession; they do not prove code is
benign. Users should approve only publishers/builds they independently trust.
Authors should publish source, reproducible instructions, hashes, a security
contact, privacy behavior, dependency inventory, and honest compatibility
claims. Keep private keys offline and separate publisher signing from platform
signing. Never put release secrets in pull-request CI.

## Residual risks

- Approved native code has Battman's full process authority and can exfiltrate
  data, modify UI, invoke APIs, consume power, or sabotage later checks.
- Root can replace package bytes or the host after verification; the supported
  race model protects normal non-root mutations, not a continuously hostile root.
- Public iOS 12 has no descriptor-backed `dlopen`. Private randomized staging
  removes ordinary package-directory replacement from the mapping boundary,
  but root or code already running with Battman's effective UID can still
  replace the named stage and is outside the in-process enforcement boundary.
- TrollStore signing/library-validation behavior differs by device/version;
  imported code remains replacement-TIPA-only until an exact matrix proves
  direct loading.
- Offline revocation is only as current as the installed signed metadata.
- Safe mode limits repeated startup loading but cannot undo damage already done.

Security reports must follow the public [`SECURITY.md`](../SECURITY.md) policy
rather than publishing exploit details or private diagnostics first. GitHub
private vulnerability reporting is the selected intake mechanism, but it must
be enabled and independently verified before the beta gate can pass. Torrekie
owns incident coordination and recovery; fixed response targets remain an
explicit release-support decision rather than an implied promise.
