---
title: Updating on iOS
---

# Updating on iOS

Use the same channel and jailbreak layout as your current installation. Review
the selected release's notes and checksums before updating. GitHub and Havoc
hosts are separate build variants; a package from one channel is not a
substitute for the other's candidate.

For a package-manager installation, refresh the relevant source and use its
**Upgrade** action, or install the matching release Debian through the package
manager. For TrollStore, explicitly install the selected replacement
`Battman.tipa` through TrollStore as described in [Installation](../installation/index.md).

After a host or plug-in update, restart Battman. A plug-in update is verified
again; exact-build approval does not approve different bytes. Publisher approval
applies only to the same plug-in and extension scope, and never overrides a
failed signature or rollback check. An old package can therefore be rejected
even if you previously used it.

TrollStore plug-in changes require an appropriately signed replacement app.
Check which plug-ins that TIPA includes before installing it. If a saved
Analytics provider is absent, its position remains **Unavailable** until the
provider is restored or the card is removed. See [Native plug-ins](../features/plugins.md)
for safe mode and recovery.
