# Battman plug-in host boundary

The host is split into explicit model, discovery, security, import, runtime,
application-integration, management, and UI components. Public SDK types do not
import these private headers.

Only `Runtime/BTPluginNativeImageLoader.m` may call `dlopen` or `dlsym`.
Discovery and import treat packages as data; structural, signature, trust,
platform, activation, and safe-mode checks complete before that loader is
reached. The registry is typed and transactional, and embedded providers use
the same registration contract as native bundles.

See `docs/plugin-system.md` for the architecture and `docs/plugin-security.md`
for the threat model.
