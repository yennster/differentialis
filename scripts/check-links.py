#!/usr/bin/env python3
"""Fails when README.md or the website reference a local file that doesn't exist.

Catches screenshots or pages that were renamed or removed without updating the links to them.
External URLs and in-page anchors are skipped. Run from anywhere: `python3 scripts/check-links.py`.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Each document, and the directory its relative paths resolve against. The site is deployed with
# `site/` as its root, so its paths are relative to that folder.
DOCUMENTS = {
    ROOT / "README.md": ROOT,
    ROOT / "site" / "index.html": ROOT / "site",
}

PATTERNS = [
    re.compile(r"\]\(([^)\s]+)"),            # Markdown links and images: [text](path)
    re.compile(r"""(?:src|href)=["']([^"']+)"""),  # HTML src/href attributes
]


def is_local(ref: str) -> bool:
    return not (re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", ref) or ref.startswith(("#", "//")))


missing = []
checked = 0
for document, base in DOCUMENTS.items():
    text = document.read_text(encoding="utf-8")
    for pattern in PATTERNS:
        for ref in pattern.findall(text):
            if not is_local(ref):
                continue
            path = ref.split("#", 1)[0].split("?", 1)[0]
            if not path:
                continue
            checked += 1
            if not (base / path).exists():
                missing.append(f"{document.relative_to(ROOT)}: {ref}")

if missing:
    print("Missing local files referenced by the docs:")
    for entry in missing:
        print(f"  {entry}")
    sys.exit(1)

print(f"All {checked} local references resolve.")
