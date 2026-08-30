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
