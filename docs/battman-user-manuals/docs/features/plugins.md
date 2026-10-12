---
title: Native plug-ins
---

# Native plug-ins

Battman recognizes `.battman` package documents from Files or another app. An
import first verifies and quarantines the package; it does not run the plug-in.
You can review it under **More → Plug-ins**.

## Trust and activation

Official plug-ins are accepted only when their publisher and exact extension
scope are authorized by Battman's offline, signed trust metadata. A valid
third-party package is still untrusted by default. Battman shows its plug-in
identifier, verification status, requested extension points, and any signed
author name, homepage, or support email. Publisher and package hashes are kept
under **Technical Details**, shortened for readability; tapping either copies
the full value for independent comparison. Author/contact fields are claims
made by the package publisher and do not establish trust. Battman then shows a
native-code warning before offering either:

- approval of this exact build; or
- approval of future versions from this publisher for this same plug-in and
  extension scope.

Neither choice makes native code safe. Once loaded, a plug-in can read or alter
anything Battman can, draw arbitrary UI, use private APIs or the network, crash
the app, and damage data. Do not approve a package whose author and exact bytes
you do not trust. Signature, hash, architecture, ABI, dependency, revocation,
rollback, or platform-load failures cannot be overridden.

Third-party loading also has a global switch and is off initially. Installation
and enable/disable changes take effect after restarting Battman. A jailbreak
installation can load a verified package from Battman's private app-data or
system plug-in directory. A TrollStore-only installation uses a replacement
Battman TIPA with the plug-in embedded and the whole app signed again; importing
a native bundle into the data directory alone is not claimed to work.

## Recovery and removal

If Battman does not finish startup after attempting a third-party plug-in, the
next launch enters safe mode without third-party plug-ins and identifies the
last attempted build. You can also choose **Start Without Third-Party Plug-ins**
for the next launch. Then disable or remove the exact package in the Plug-ins
screen. Battman can remove its own private imported copies, but app-bundled and
APT/dpkg-owned files must be updated or removed through their installation
channel.

All package and trust verification works offline. Network access is not needed
to compare hashes, validate signatures, consult local approval/rollback state,
or start in safe mode.

## Diagnostics and support

**Export Diagnostics** shows a privacy disclosure before the system share
sheet. Its plain-text report contains Battman version/build, generation time,
plug-in identifiers and package hashes, source, trust and activation state, and
bounded error domain/code values. It excludes plug-in files, private keys,
battery measurements, device identifiers, localized error text, and filesystem
paths. The installed plug-in list may still be sensitive, so review both the
text and recipient before sharing.

Use the public issue tracker only for ordinary non-sensitive defects. Security
reports and private diagnostics follow the repository's `SECURITY.md` policy.

## Install your first card

1. Obtain the plug-in from its publisher or the selected Battman release. A
   `.battman.zip` is a download wrapper: extract it and keep the enclosed
   `.battman` directory package intact. Do not edit its manifest or payload.
2. Share/open the `.battman` package with Battman. For a Debian add-on, install
   the package matching your jailbreak layout through your package manager.
3. Open **More → Plug-ins** and review source, verification status, publisher
   fingerprint, requested extensions, and activation state. Compare the full
   fingerprint through an independent publisher channel.
4. If it is third-party code you choose to trust, approve the exact build or
   scoped publisher, then enable third-party loading. A hard verification
   failure requires a corrected package from its publisher.
5. Restart Battman, then open **Analytics → Edit** and add the registered card.
   On TrollStore, complete the replacement-app process first when Battman says
   **Requires Battman Reinstall**.

The 1.1.0 release matrix selects **Charge Gauge** as a separate official
plug-in. Jailbreak add-ons use the rooted or rootless Debian layout; the GitHub
replacement TIPA includes the selected official plug-in. Actual availability
still depends on the release being published with valid signatures and trust
metadata. The SDK Analytics example remains third-party and requires approval;
it is not included in the replacement TIPA.

## Signing and developer entry point

There are two separate signatures. A platform signature covers the native
Mach-O bundle; the package publisher signs the exact manifest with an ECDSA
P-256 key. Neither signature substitutes for the other, and neither alone
makes a package official. A third-party author does not need Battman's offline
root keys: those keys authorize official publisher delegations only.

The public SDK v1 supports native Analytics cards through the documented C ABI
and Objective-C protocols. Its full subtree is MIT licensed, independently of
the host license. Authors can generate and build a standalone card with the
SDK's template, using an iPhoneOS SDK, make, Python 3, and `cryptography` for
package signing and verification. See the
[SDK](https://github.com/Torrekie/Battman/tree/master/PluginSDK) and the complete
[authoring guide](https://github.com/Torrekie/Battman/blob/master/docs/plugin-authoring.md)
for generation, build, existing-key signing, and offline verification commands.
The portable verifier does not prove that iOS can load the code; Battman still
checks platform loading, ABI, dependencies, trust, and rollback state.
