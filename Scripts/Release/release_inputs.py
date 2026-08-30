#!/usr/bin/env python3
"""Strict release input placement and exact-tag membership checks."""

from __future__ import annotations

import stat
from pathlib import Path

from release_common import ReleaseError, iter_tree, run


def _git(repo: Path, *arguments: str) -> str:
    return run(["git", "-C", str(repo), *arguments]).stdout.strip()


def require_tracked_public_input(repo: Path, path: Path, label: str) -> None:
    """Require every strict public release input byte to exist in the exact tag."""
    repo = repo.expanduser().resolve()
    lexical = path.expanduser().absolute()
    try:
        resolved = lexical.resolve(strict=True)
        relative_root = resolved.relative_to(repo)
    except (OSError, ValueError) as error:
        raise ReleaseError(f"{label} must be inside the exact release checkout") from error
    if resolved == repo:
        raise ReleaseError(f"{label} cannot be the repository root")

    regular_files: list[Path]
    if resolved.is_dir() and not lexical.is_symlink():
        regular_files = [
            Path(relative) for relative, _, entry in iter_tree(resolved)
            if stat.S_ISREG(entry.st_mode)
        ]
    elif resolved.is_file() and not lexical.is_symlink():
        regular_files = [Path(resolved.name)]
    else:
        raise ReleaseError(f"{label} must be one real file or directory")
    if not regular_files:
        raise ReleaseError(f"{label} contains no reviewed public files")

    for relative in regular_files:
        repository_path = (relative_root / relative).as_posix() \
            if resolved.is_dir() else relative_root.as_posix()
        if not _git(repo, "ls-files", "--error-unmatch", "--", repository_path):
            raise ReleaseError(f"{label} contains an input outside the exact release tag")
