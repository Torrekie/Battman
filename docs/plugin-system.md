# Battman native plug-in architecture

Battman 1.1 exposes a versioned native extension host for jailbroken and
TrollStore-style installations. Analytics cards are the first extension point.
The registry and package loader remain generic so later releases can add typed
extension points without exposing private enums or view-controller internals.

Native plug-ins execute inside Battman with the host's privileges and
entitlements. The package, trust, and approval layers prevent silent or
ambiguous loading; they do not sandbox code after it is loaded. See
[`plugin-security.md`](plugin-security.md) for the full threat model.

## Code forms

The same card implementation can be registered in two forms:

- embedded code linked into Battman and registered during application startup;
- a separately compiled arm64 Mach-O `.bundle` in a signed `.battman` package.

Raw `.so` payloads are accepted for code-only compatibility under the same ABI,
signature, dependency, and trust checks. Bundles are canonical because they can
carry resources and localizations.

## Host structure

```text
Battman/Features/Analytics/
  Public/       host/card Objective-C contracts
  Host/         grid, persistence, edit controls, and lifecycle
  BuiltIn/      embedded providers using the public card contract
  Data/         immutable host-owned metric snapshots

Battman/PluginHost/
  Model/        strict manifests, sources, and errors
  Discovery/    allowlisted package roots
  Security/     structural, signature, trust, and Mach-O verification
  Import/       quarantine and transactional app-data installation
  Runtime/      activation, safe mode, staging, and the sole native loader
  Application/  app/scene document-open integration
  Management/   inventory, approval, update, disable, and removal
  UI/           consent, details, diagnostics, and recovery controls

PluginSDK/      public ABI, schemas, example, templates, and portable tools
OfficialPlugins/ChargeGauge/
                separately shipped first-party card
```

Public SDK headers do not include private host headers. Embedded and native
providers enter the same typed, transactional registry.

## Package and ABI

The transport UTI is `com.torrekie.battman.plugin`, conforms to
`com.apple.package`, and uses the `.battman` extension. A package is a directory
with bounded metadata, a signed manifest, a complete file inventory, and one
declared native payload. The canonical format is documented in
[`plugin-package-format.md`](plugin-package-format.md).

Native payloads export exactly `BattmanPluginEntryPointV1`. The returned C
descriptor carries an ABI version, structure size, plug-in identity, build
version, declared extension points, and a registration callback. The host
rejects duplicate or out-of-namespace identifiers, undeclared extension points,
and descriptors that disagree with the signed manifest. Plug-ins are never hot
unloaded because Objective-C classes, views, callbacks, and layer delegates may
outlive a loader call.

## Discovery roots

Only direct `.battman` children of these roots are considered:

| Source | Root | Activation boundary |
| --- | --- | --- |
| App distribution | `NSBundle.builtInPlugInsURL` | sealed package and official trust |
| App data | `Library/Application Support/Battman/PlugIns` | exact approved package and activation record |
| Rooted package | `/Library/Battman/PlugIns` | safe root ownership plus Battman trust |
| Rootless package | `/var/jb/Library/Battman/PlugIns` | safe root ownership plus Battman trust |

Arbitrary search paths, environment variables, current directories, recursive
searches, and standalone Mach-O files outside a package are ignored. A package
found in an allowlisted root remains data until every verification and
activation check passes.

## Verification and loading

The runtime applies these boundaries in order:

1. discover a direct package under an allowlisted root;
2. parse bounded canonical metadata and inventory every package byte without
   following links;
3. verify package hashes, publisher signatures, offline trust metadata,
   revocation, rollback state, architecture, dependencies, platform signature,
   and the one-symbol export surface;
4. require official authorization or explicit user approval, then bind the
   exact package digest to its activation record;
5. copy verified payload bytes into a private per-load staging directory and
   recheck every file to close source-path replacement races;
6. commit startup crash-recovery state, call the sole `dlopen`/`dlsym` boundary,
   and commit the registry transaction only if registration succeeds.

Import, management, and verifier code cannot call the native loader. Rejected
packages never reach a constructor. Loaded images are retained for the process
lifetime and are not passed to `dlclose`.

## Import, update, and recovery

Files/AirDrop-style document opens enter a no-execution quarantine. The user can
inspect plug-in identity, author/contact information, requested extension
points, publisher identity, package digest, and native-code warnings before
approving an exact build or an allowed publisher scope.

App-data install, update, and removal use a journaled activation/package
transaction. Startup reconciliation finishes or rolls back interrupted file
operations before discovery. A pending third-party activation attempt is marked
before native loading; an unsettled attempt enables safe mode on the next
launch. Management remains available for disabling and exact structural removal
even when a previously valid publisher has been revoked.

## Distribution

APT/dpkg packages install already signed `.battman` directories into the rooted
or rootless discovery root. Package-manager presence does not replace Battman's
own verification or user trust policy.

On TrollStore-only systems, imported third-party code stays quarantined until a
replacement TIPA is built with the package under `Battman.app/PlugIns` and the
whole app is installed through TrollStore. Battman does not call TrollStore
internals or claim that ad-hoc signing an arbitrary file makes it loadable.

The public SDK authoring workflow is in
[`plugin-authoring.md`](plugin-authoring.md). Release artifact construction and
manual Havoc boundaries are documented in
[`release-process.md`](release-process.md).
