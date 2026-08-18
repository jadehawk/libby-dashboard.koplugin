#!/usr/bin/env python3
"""Synchronize README's displayed plugin version from _meta.lua."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
META_PATH = ROOT / "libby-dashboard.koplugin" / "_meta.lua"
README_PATH = ROOT / "README.md"

META_VERSION_RE = re.compile(r'^\s*version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*,?\s*$', re.MULTILINE)
README_VERSION_RE = re.compile(r"^Current plugin version: \*\*[^*]+\*\*$", re.MULTILINE)


def main() -> None:
    meta = META_PATH.read_text(encoding="utf-8")
    match = META_VERSION_RE.search(meta)
    if not match:
        raise SystemExit(f"Could not read semantic version from {META_PATH}")

    version = match.group(1)
    readme = README_PATH.read_text(encoding="utf-8")
    updated, count = README_VERSION_RE.subn(
        f"Current plugin version: **{version}**",
        readme,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"Expected exactly one README version line in {README_PATH}")

    README_PATH.write_text(updated, encoding="utf-8")
    print(version)


if __name__ == "__main__":
    main()
