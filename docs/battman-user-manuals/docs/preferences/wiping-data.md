---
title: Wiping Data
---

# Wiping Data

**More → Preferences → Wipe All Battman Data** removes Battman's preferences
and files in the data locations listed by the confirmation sheet. This includes
saved Analytics layouts, startup readings, completed history caches and locally
imported plug-in copies held there. Check the displayed scope before confirming.

1. Restore any charging or thermal changes you no longer want to their normal settings.
2. Open **More → Preferences → Wipe All Battman Data**.
3. Read the affected locations and confirm. Battman exits after a successful wipe.
4. Reopen Battman to configure it again.

The wipe stops Analytics workers before deleting their caches. It does not
erase the system's original Powerlog history, remove app-bundled or
package-manager-owned plug-ins, or reset global thermal configuration. It also
does not claim to reset plug-in rollback/trust counters retained in Keychain.
Use the plug-in screen and the relevant installation channel to manage those
packages. See [Uninstallation](../uninstallation.md) to remove the app.
