# Security policy

Battman accepts security reports for the current `1.1.x` development line and
the latest publicly released version. Older releases may be used to reproduce
an issue, but fixes are delivered on a current supported line.

## Report privately

Do not open a public issue for a vulnerability, suspected signing-key exposure,
malicious plug-in package, signature or verification bypass, unsafe native-code
load, or a report containing private diagnostics.

Battman's private intake is GitHub private vulnerability reporting for the
[`Torrekie/Battman`](https://github.com/Torrekie/Battman) repository. The owner
enabled that repository feature on 2026-08-15 and approved the best-effort
support scope on 2026-08-20. An independent reachability review is still
required before the public plug-in beta gate can pass. Do not publish exploit
details or diagnostics in a public issue. The enabled feature is not a
response-time promise.

A useful private report includes:

- the affected Battman version, installation type, iOS version, and architecture;
- whether the plug-in came from the app bundle, APT/dpkg, or `.battman` import;
- the plug-in identifier, publisher key ID, package SHA-256, and extension points;
- the smallest reproduction and expected versus observed behavior;
- sanitized plug-in diagnostics, if relevant; and
- whether a signing key, published artifact, or user device may be compromised.

Never send private keys, provisioning profiles, signing identities, an entire
user data directory, battery telemetry, or an unreviewed filesystem archive.

## Response and disclosure

Torrekie owns triage, incident response, release suspension, revocation, and
recovery. Battman 1.1.x support is best-effort and has no response-time or
remediation SLA. Reporter and maintainer should agree on coordinated disclosure
after affected artifacts and users have a safe recovery path.

If an official root, publisher, or checksum key may be compromised, stop using
or distributing the affected artifact. Follow the public ceremony boundary in
[`Scripts/Ceremony/README.md`](Scripts/Ceremony/README.md) together with the
owner-private incident record; production private keys must never be uploaded
to GitHub or imported onto ordinary build machines.

## Native plug-in boundary

A loaded native plug-in has Battman's full in-process authority. A signature
authenticates bytes and publisher-key possession; it does not prove code is
safe. Reports about expected behavior from code the user explicitly approved
may still be security-relevant, but Battman cannot sandbox or safely unload that
code. See [`docs/plugin-security.md`](docs/plugin-security.md) for the complete
threat model and residual risks.
