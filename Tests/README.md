# Plug-in and Analytics tests

Test code is grouped by the contract it proves: Analytics behavior,
host/registry invariants, public SDK/ABI compatibility, and positive or
adversarial package fixtures.

The low-cost runner covers the `PluginHost`/`PluginSDK` contracts, immutable
Analytics snapshots, bounded layout migration, visible-only metric scheduling,
package verification, runtime loading, quarantine, and release tooling. Its
historical filename remains stable for existing automation. Test payloads must
never enter an app target through source discovery.

`check-analytics-localizations.py` discovers every Analytics `_()` source
string and requires it to have a non-empty translation in the tracked English,
German, Simplified Chinese, and Traditional Chinese catalogs. It also rejects
obsolete `#~` entries and runs `msgfmt --check` when Gettext is available.

`check-analytics-metric-safety.py` is a host-only static regression check for
bounded SMC/cell-temperature reads, explicit unavailable/stale states, and
health/cycle-count explanations.

`Device/run-analytics-rooted-preflight.sh` is a read-only rooted-device gate.
It validates the exact local artifact and remote environment but contains no
installation path. Device mutation still requires separate owner approval.

`Simulator/run-analytics-example-parity.sh` uses an already-booted simulator
without installing an app. It compiles the public SDK example once embedded
and once as a loadable bundle, runs each in a separate process, requires a
one-symbol native export surface and system-only dependencies, and compares
registration metadata, lifecycle order, and deterministic raw-pixel hashes.

`Simulator/run-plugin-application-integration-callbacks.sh` is an opt-in,
non-mutating simulator contract test for the application and scene URL
forwarding boundary. It requires an already-booted simulator, uses a recording
platform stub, and covers cold/warm ordering, fallback, the 16-context bound,
and idempotent installation. It does not replace package-verifier or native
runtime tests.

`check-plugin-loader-boundary.py` enforces that import and management code
cannot reach `dlopen`; the one private image loader has exactly one `dlopen`,
one `dlsym`, and intentionally no `dlclose`.
