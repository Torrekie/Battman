# Battman Plugin SDK compatibility policy

Status: ABI v1 freeze. The SDK is MIT licensed. This policy becomes a public
support promise only when the SDK release channel is approved.

## Independent versions

Five numbers evolve independently:

| Contract | Current | Change rule |
| --- | ---: | --- |
| SDK major | 1 | Bump for a deliberately incompatible public SDK surface |
| native host ABI | 1 | Bump when the C entry boundary cannot remain append-only |
| package format | 1 | Bump when a v1 package cannot be safely parsed under v1 rules |
| manifest schema | 1 | Bump for an incompatible signed-manifest shape |
| Analytics extension point | 1 | Publish a new identifier/version for a breaking object contract |

The app release version and plug-in display/build versions are not ABI
versions. A new optional Objective-C protocol method, optional manifest field,
or appended C tail does not itself require all other numbers to change.

## Native ABI v1 rules

- The only entry symbol is `BattmanPluginEntryPointV1`.
- Public C structures start with `structSize` and `abiVersion`.
- Required v1 prefixes are the `*_MINIMUM_SIZE` constants in
  `BattmanPluginABI.h`; callers check a field exists before reading it.
- A v1 producer may append fields and advertise a larger `structSize`.
  Consumers ignore unknown tails. Existing fields never move, change type, or
  change meaning.
- A shorter-than-required structure fails closed. Registration is transactional,
  so it cannot leave partially registered objects.
- `BTPluginHostV1.log` is optional. A plug-in may use it only when `structSize`
  includes that field and the callback is non-null.
- A plug-in declares the host-ABI range it supports. ABI v1 hosts reject a
  range that excludes v1.
- Plug-ins do not resolve Battman executable symbols. They may link only the
  documented Apple frameworks and communicate through the host table and
  registered Objective-C protocol objects.
- Native images remain mapped for the process lifetime. Updating, disabling,
  or revoking takes effect after a restart.

The frozen initial-v1 fixture deliberately has a 24-byte LP64 host table,
without `log`; the current host table is 32 bytes. Tests build that fixture
against its old header and load it through the current native loader. Separate
tests accept appended descriptor/registration tails and reject truncated
prefixes atomically.

## Analytics card v1 rules

Battman owns the outer cell, grid, editing controls, scheduling, restoration
envelope, and delivery of immutable metric snapshots. The plug-in owns its
content view, subviews, layers, drawing, actions, gestures, animations,
resources, and content accessibility.

All UIKit callbacks arrive on the main thread. Optional methods may be added to
v1 only when older cards and hosts continue to work without them. A semantic or
signature break receives a new extension-point identifier such as a future
`...analytics.card.v2`; the host may support v1 and v2 together. Internal
`BI_SECT` values and private controllers will never become v1 ABI.

Metric identifiers are string literals, not host-exported globals. Unknown
metrics must be ignored, and unavailable metrics remain absent rather than
being replaced with invented values. Card restoration state is bounded
property-list data and must be migrated using the supplied schema version.

## Platform support and evidence

The build contract is arm64 with an iOS 12.0 minimum. The project's current
product input is A11-and-newer on iOS 12–17, but that range is community
reported rather than a completed physical-device matrix. Simulator and
minimum-deployment compile/load-command evidence are the accepted gate for the
current implementation goal. Hardware-specific cards must document narrower
requirements honestly.

## Deprecation and failure policy

No ABI-v1 removal window is promised before the first public SDK release.
Once public, removals require a new ABI or extension-point version and a
published migration period. Unknown future extension-point versions and
unsupported points fail before registration commits. Structural, signature,
revocation, rollback, architecture, dependency, ABI, and platform failures can
never be bypassed by user consent.
