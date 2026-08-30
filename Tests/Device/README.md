# Rooted Analytics device preflight

`run-analytics-rooted-preflight.sh` is a read-only gate before an explicitly
authorized temporary device deployment. It validates the current app artifact,
its arm64/iOS 12 load command and Analytics symbols, the SSH host identity, the
rooted `iphoneos-arm` environment, the package-owned Battman app, AppleSMC
entitlement, required device tools, storage, and current load.

It deliberately has no install, signing, registration, launch, replacement, or
restore mode. Permission to run the preflight is not permission to modify a
device.

Example using an IP address whose key is already trusted under a caller-defined
`DEVICE_HOST_ALIAS`:

```sh
Tests/Device/run-analytics-rooted-preflight.sh \
  --host root@DEVICE_ADDRESS \
  --host-key-alias DEVICE_HOST_ALIAS
```

Never put a private address, device identifier, password, or SSH key into the
repository. After explicit authorization, preserve the package-owned app,
stage and verify the exact preflighted artifact, sign it with the tracked
entitlements, restore the packaged app after the bounded test, and record the
runtime evidence separately.
