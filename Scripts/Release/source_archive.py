"""Shared source-only archive boundaries; generated and signing inputs never ship."""

from pathlib import PurePosixPath
from release_common import ReleaseError


def require_source_path(relative: str) -> None:
    """Fail closed when a working SDK contains generated or signing inputs."""
    path = PurePosixPath(relative)
    generated_directories = {"build", "dist", ".git", ".venv", "venv", "__pycache__", "Packages"}
    generated_suffixes = {
        ".o", ".a", ".dylib", ".so", ".bundle", ".battman", ".pyc", ".pyo",
        ".ipa", ".tipa", ".deb", ".zip", ".gz", ".pem", ".key", ".p12", ".pfx", ".p256",
    }
    if any(
        part in generated_directories or part == ".DS_Store" or
        PurePosixPath(part).suffix.lower() in generated_suffixes
        for part in path.parts
    ):
        raise ReleaseError(
            f"non-source input present in SDK tree: {relative}; "
            "export a clean SDK source tree before archiving"
        )
