# Automation boundary

Automation is separated by purpose:

- build helpers compile without publishing;
- plug-in tools package and verify fixtures without executing payloads;
- release helpers require explicit gates for signing, upload, or publication.

`Ceremony/` contains the separately invoked owner-operated production-key
workflow. It is not called by Xcode, Make, CI, or `Scripts/Release`. Its normal
path stops at preflight; production generation additionally requires a local
TTY, exact typed acknowledgement, and an owner-approved private network.

Public plug-in packaging, existing-key signing, and offline verification tools
live under `PluginSDK/Tools/Package/`. They never load payloads, generate
production keys, publish artifacts, or replace the authoritative in-app native
and trust verifier. Focused round-trip and tamper tests remain under `Tests/`.
