# Production-key ceremony boundary

`run-production-key-ceremony.py` is an owner-operated, interactive tool. It is
deliberately outside `Scripts/Release`, Xcode, Make, and hosted CI. Normal builds
and release assembly cannot invoke it.

Production mode requires:

- a local controlling terminal and no `CI` environment;
- an exact typed production-key acknowledgement;
- verified OpenSSL 3.x;
- two distinct SSH device identities already pinned under stable aliases in
  `known_hosts`;
- a private mode-`0600` target configuration outside the repository, containing
  no persistent network address;
- a mode-`0700` output parent outside the repository;
- the owner-approved trusted private LAN, with both pinned backup devices
  required for `--preflight` and `--backup` but allowed to sleep during local
  `--generate`;
- six distinct high-entropy passphrases entered only at OpenSSL terminal
  prompts, one for each P-256 role.

The six roles are `root-r1`, `root-r2`, `root-r3`,
`official-plugin-publisher`, `release-checksum`, and
`sdk-example-publisher`. Use a different passphrase for every role. The tool
cannot compare them because OpenSSL, not Python, owns the terminal prompts.

Each private key is encrypted independently as PKCS#8 PBES2 using scrypt and
AES-256-CBC, mode `0400`. The tool uploads only those encrypted files over
pinned ED25519 SSH. It restores one copy of every role, compares its digest and
size, asks OpenSSL to decrypt/sign through its own terminal prompt, and creates
role-bound public recovery challenges. Neither passphrases nor unencrypted
private-key bytes enter the filesystem, repository, command line, environment,
CI, or public evidence.

Use `--preflight` to validate tools, paths, pinned SSH identities, and empty
backup destinations without creating a key or output directory. Production is
explicitly split into `--generate` and `--backup` phases so a network
interruption never requires regenerating a valid identity. Both phases run on
the owner-approved trusted LAN. Production execution must not begin until the
owner separately confirms the final generation step.

Remote iOS storage is restricted to:

```text
/private/var/root/BattmanKeyBackups/battman-1.1.0-production-keys-1
```

Never use `/var/jb` for durable backup storage. After a successful ceremony,
power down and physically separate the two devices before an independent
reviewer marks `offlineStorageConfirmed` true.

Invoke the tool with exactly one of `--preflight`, `--generate`, or `--backup`
from a local terminal. The private target configuration supplies two stable
identifiers, pinned aliases, fingerprints, and the dedicated `known_hosts`
file. For every `--preflight` and `--backup`, pass each current private address
as `--target-address IDENTIFIER=PRIVATE_IPV4`; addresses are not persisted.
`--generate` revalidates the configured identities without requiring either
backup host to stay awake. Wake both hosts and run `--backup` as soon as
practical after generation. Local wrappers, addresses, device names, and
recovery status belong in the owner-private workspace, not this repository.
Never send a role passphrase through chat, shell arguments, environment
variables, clipboard history, or a file.

If `--generate` stops after the output directory is created, keep the Mac on
the trusted LAN and do not delete, overwrite, or silently regenerate any
partial role. The launcher intentionally refuses an existing output directory.
Record the failure and decide explicitly whether to finish custody validation
or abandon and rotate every identity that may have been created. An interrupted
`--backup` is retryable: rerun `--backup` with the same frozen script,
interpreter, OpenSSL, target configuration, and output directory, entering each
device's current address again. Exact already-stored ciphertexts are verified
and retained; partial filenames fail closed and must be investigated. Never
accept a changed SSH host key merely to make a retry pass.
