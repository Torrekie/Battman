"""Portable, offline validation for Battman's public official-trust assets."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import plistlib
import re
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.hashes import SHA256

from release_common import IDENTIFIER, ReleaseError, iter_tree, tree_digest


KEY_IDENTIFIER = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_ROOT_FILES = {"RootPolicy.plist", "TrustMetadata.json", "TrustMetadata.signatures"}
MAX_ROOT_POLICY_BYTES = 64 * 1024
MAX_METADATA_BYTES = 256 * 1024
MAX_SIGNATURE_BYTES = 256
MAX_JSON_INTEGER = 9_007_199_254_740_991


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseError(f"duplicate JSON key in TrustMetadata.json: {key}")
        result[key] = value
    return result


def _exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected or any(not isinstance(key, str) for key in value):
        raise ReleaseError(f"{label} has missing, malformed, or unknown keys")
    return value


def _integer(value: Any, minimum: int, maximum: int, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ReleaseError(f"{label} is not a bounded integer")
    return value


def _raw_public_key(base64_value: Any, identifier: Any, label: str) -> bytes:
    if not isinstance(identifier, str) or not KEY_IDENTIFIER.fullmatch(identifier):
        raise ReleaseError(f"{label} has an invalid key identifier")
    if not isinstance(base64_value, str) or len(base64_value) != 88:
        raise ReleaseError(f"{label} has an invalid public-key encoding")
    try:
        raw = base64.b64decode(base64_value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ReleaseError(f"{label} has an invalid public-key encoding") from error
    if len(raw) != 65 or raw[0] != 4 or hashlib.sha256(raw).hexdigest() != identifier or base64.b64encode(raw).decode() != base64_value:
        raise ReleaseError(f"{label} has an invalid public-key fingerprint or canonical encoding")
    try:
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)
    except ValueError as error:
        raise ReleaseError(f"{label} is not a valid P-256 curve point") from error
    return raw


def _canonical_p256_der(signature: bytes, label: str) -> None:
    if not 8 <= len(signature) <= 72 or signature[0] != 0x30 or signature[1] != len(signature) - 2 or signature[1] & 0x80:
        raise ReleaseError(f"{label} is not canonical DER")
    try:
        r, s = decode_dss_signature(signature)
    except ValueError as error:
        raise ReleaseError(f"{label} is not canonical DER") from error
    if r <= 0 or s <= 0:
        raise ReleaseError(f"{label} contains a zero ECDSA integer")
    # The paired encoder rejects alternate length or integer representations.
    if signature != encode_dss_signature(r, s):
        raise ReleaseError(f"{label} is not canonical DER")


def _identifiers(value: Any, label: str) -> set[str]:
    if not isinstance(value, list) or not 1 <= len(value) <= 64:
        raise ReleaseError(f"{label} must contain one to 64 unique identifiers")
    if any(not isinstance(item, str) or len(item) > 255 or not IDENTIFIER.fullmatch(item) for item in value):
        raise ReleaseError(f"{label} contains an invalid identifier")
    if len(set(value)) != len(value):
        raise ReleaseError(f"{label} must contain one to 64 unique identifiers")
    return set(value)


def validate_official_trust(root: Path) -> dict[str, Any]:
    lexical_root = root.expanduser().absolute()
    if lexical_root.is_symlink():
        raise ReleaseError("PluginTrust must be a real directory, not a symbolic link")
    root = lexical_root.resolve()
    entries = list(iter_tree(root))
    top_level = {relative for relative, _, _ in entries if "/" not in relative}
    if top_level != EXPECTED_ROOT_FILES:
        raise ReleaseError("PluginTrust must contain exactly RootPolicy.plist, TrustMetadata.json, and TrustMetadata.signatures")
    root_policy_path = root / "RootPolicy.plist"
    metadata_path = root / "TrustMetadata.json"
    if root_policy_path.stat().st_size <= 0 or root_policy_path.stat().st_size > MAX_ROOT_POLICY_BYTES:
        raise ReleaseError("RootPolicy.plist is empty or exceeds 64 KiB")
    if metadata_path.stat().st_size <= 0 or metadata_path.stat().st_size > MAX_METADATA_BYTES:
        raise ReleaseError("TrustMetadata.json is empty or exceeds 256 KiB")
    try:
        root_policy = plistlib.loads(root_policy_path.read_bytes())
    except (plistlib.InvalidFileException, ValueError) as error:
        raise ReleaseError("RootPolicy.plist is not a valid property list") from error
    root_policy = _exact_keys(root_policy,
        {"schemaVersion", "signatureThreshold", "rootPublicKeys"}, "RootPolicy.plist")
    _integer(root_policy["schemaVersion"], 1, 1, "root-policy schemaVersion")
    threshold = _integer(root_policy["signatureThreshold"], 1, 8, "root-policy signatureThreshold")
    root_records = root_policy["rootPublicKeys"]
    if not isinstance(root_records, list) or not 1 <= len(root_records) <= 8 or threshold > len(root_records):
        raise ReleaseError("RootPolicy.plist has an invalid root-key count or threshold")
    root_keys: dict[str, bytes] = {}
    previous: str | None = None
    for record in root_records:
        record = _exact_keys(record, {"keyIdentifier", "publicKeyX963Base64"}, "root-key record")
        identifier = record["keyIdentifier"]
        if not isinstance(identifier, str) or previous is not None and identifier <= previous:
            raise ReleaseError("root-key records must be bytewise sorted and unique")
        root_keys[identifier] = _raw_public_key(record["publicKeyX963Base64"], identifier, "root-key record")
        previous = identifier

    metadata_data = metadata_path.read_bytes()
    if metadata_data.startswith(b"\xef\xbb\xbf"):
        raise ReleaseError("TrustMetadata.json must not contain a UTF-8 BOM")
    try:
        metadata = json.loads(metadata_data.decode("utf-8"), object_pairs_hook=_object_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError("TrustMetadata.json is not strict UTF-8 JSON") from error
    metadata = _exact_keys(metadata, {
        "schemaVersion", "sequence", "generatedAtUnixSeconds",
        "officialPublishers", "revokedKeyIdentifiers",
    }, "TrustMetadata.json")
    _integer(metadata["schemaVersion"], 1, 1, "metadata schemaVersion")
    sequence = _integer(metadata["sequence"], 1, MAX_JSON_INTEGER, "metadata sequence")
    generated_at = _integer(metadata["generatedAtUnixSeconds"], 0, MAX_JSON_INTEGER, "metadata generatedAtUnixSeconds")

    publisher_records = metadata["officialPublishers"]
    if not isinstance(publisher_records, list) or len(publisher_records) > 16:
        raise ReleaseError("officialPublishers is not a bounded array")
    publishers: dict[str, dict[str, Any]] = {}
    for record in publisher_records:
        record = _exact_keys(record, {
            "keyIdentifier", "publicKeyX963Base64", "pluginIdentifiers", "extensionPointIdentifiers",
        }, "official publisher record")
        identifier = record["keyIdentifier"]
        if not isinstance(identifier, str) or not KEY_IDENTIFIER.fullmatch(identifier):
            raise ReleaseError("official publisher record has an invalid key identifier")
        if identifier in publishers:
            raise ReleaseError("official publisher keys must be unique")
        publishers[identifier] = {
            "publicKey": _raw_public_key(record["publicKeyX963Base64"], identifier, "official publisher record"),
            "pluginIdentifiers": _identifiers(record["pluginIdentifiers"], "official pluginIdentifiers"),
            "extensionPointIdentifiers": _identifiers(record["extensionPointIdentifiers"], "official extensionPointIdentifiers"),
        }
    revoked = metadata["revokedKeyIdentifiers"]
    if not isinstance(revoked, list) or len(revoked) > 64 or any(
        not isinstance(identifier, str) or not KEY_IDENTIFIER.fullmatch(identifier) for identifier in revoked
    ):
        raise ReleaseError("revokedKeyIdentifiers is malformed")
    if len(set(revoked)) != len(revoked):
        raise ReleaseError("revokedKeyIdentifiers is malformed")
    if set(publishers) & set(revoked):
        raise ReleaseError("trust metadata cannot delegate and revoke one key")

    signature_directory = root / "TrustMetadata.signatures"
    signature_files = sorted(signature_directory.iterdir(), key=lambda path: path.name.encode("utf-8"))
    if not 1 <= len(signature_files) <= len(root_keys):
        raise ReleaseError("the trust-metadata signature count is invalid")
    verified: list[str] = []
    for signature_path in signature_files:
        identifier = signature_path.name.removesuffix(".sig")
        if signature_path.name != f"{identifier}.sig" or not KEY_IDENTIFIER.fullmatch(identifier) or identifier not in root_keys:
            raise ReleaseError(f"invalid or unknown root signature filename: {signature_path.name}")
        signature = signature_path.read_bytes()
        if not 1 <= len(signature) <= MAX_SIGNATURE_BYTES:
            raise ReleaseError(f"root signature has an invalid size: {signature_path.name}")
        _canonical_p256_der(signature, f"root signature {signature_path.name}")
        public_key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), root_keys[identifier])
        try:
            public_key.verify(signature, metadata_data, ec.ECDSA(SHA256()))
        except (InvalidSignature, ValueError) as error:
            raise ReleaseError(f"root signature does not match exact TrustMetadata.json bytes: {identifier}") from error
        verified.append(identifier)
    if len(verified) < threshold:
        raise ReleaseError("TrustMetadata.json does not meet the root-signature threshold")
    return {
        "treeSHA256": tree_digest(root),
        "metadataSHA256": hashlib.sha256(metadata_data).hexdigest(),
        "sequence": sequence,
        "generatedAtUnixSeconds": generated_at,
        "signatureThreshold": threshold,
        "verifiedRootKeyIdentifiers": verified,
        "publishers": publishers,
        "revokedKeyIdentifiers": set(revoked),
    }


def require_official_plugins(packages: list[Path], trust: dict[str, Any]) -> None:
    if not packages:
        raise ReleaseError("strict release assembly requires at least one reviewed signed official plug-in package")
    from battman_plugin_format import load_strict_json  # type: ignore

    seen: set[str] = set()
    for package in packages:
        lexical_package = package.expanduser().absolute()
        if lexical_package.suffix != ".battman" or not lexical_package.is_dir() or lexical_package.is_symlink():
            raise ReleaseError(f"official plug-in input must be a real .battman directory: {lexical_package}")
        package = lexical_package.resolve()
        manifest = load_strict_json((package / "Manifest.json").read_bytes())
        if not isinstance(manifest, dict):
            raise ReleaseError(f"official plug-in manifest must be an object: {package}")
        plugin_identifier = manifest.get("pluginIdentifier")
        publisher = manifest.get("publisher")
        extension_points = manifest.get("extensionPoints")
        if not isinstance(plugin_identifier, str) or plugin_identifier in seen or not isinstance(publisher, dict) or not isinstance(extension_points, list):
            raise ReleaseError(f"official plug-in manifest identity is malformed or duplicated: {package}")
        key_identifier = publisher.get("primaryKeyIdentifier")
        delegation = trust["publishers"].get(key_identifier)
        requested_values = [value.get("identifier") for value in extension_points if isinstance(value, dict)]
        if len(requested_values) != len(extension_points) or any(not isinstance(value, str) for value in requested_values):
            raise ReleaseError(f"official plug-in extension-point scope is malformed: {package}")
        requested = set(requested_values)
        if len(requested) != len(requested_values) or not delegation or plugin_identifier not in delegation["pluginIdentifiers"] or not requested <= delegation["extensionPointIdentifiers"]:
            raise ReleaseError(f"official plug-in is outside its signed delegation scope: {package}")
        seen.add(plugin_identifier)
