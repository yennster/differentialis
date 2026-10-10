#!/usr/bin/env python3
"""Checks the README and the website for things that silently break.

- Every local file the README or the site references exists (a renamed or removed screenshot fails).
- The site's JSON-LD structured data parses, and its FAQ questions match the visible FAQ section.
- sitemap.xml is well-formed.

External URLs and in-page anchors are skipped. Run from anywhere: `python3 scripts/check-site.py`.
"""
import json
import re
import sys
import xml.dom.minidom
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

# Each document, and the directory its relative paths resolve against. The site is deployed with
# `site/` as its root, so its paths are relative to that folder.
DOCUMENTS = {
    ROOT / "README.md": ROOT,
    SITE / "index.html": SITE,
}

LINK_PATTERNS = [
    re.compile(r"\]\(([^)\s]+)"),                  # Markdown links and images: [text](path)
    re.compile(r"""(?:src|href)=["']([^"']+)"""),  # HTML src/href attributes
]

problems = []


def is_local(ref: str) -> bool:
    return not (re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", ref) or ref.startswith(("#", "//")))


# Local links and images.
checked = 0
for document, base in DOCUMENTS.items():
    text = document.read_text(encoding="utf-8")
    for pattern in LINK_PATTERNS:
        for ref in pattern.findall(text):
            path = ref.split("#", 1)[0].split("?", 1)[0]
            if not is_local(ref) or not path:
                continue
            checked += 1
            if not (base / path).exists():
                problems.append(f"{document.relative_to(ROOT)}: missing file {ref}")

# Structured data, and the FAQ it repeats.
html = (SITE / "index.html").read_text(encoding="utf-8")
blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.S)
nodes = []
for block in blocks:
    try:
        data = json.loads(block)
        nodes += data.get("@graph", [data])
    except json.JSONDecodeError as error:
        problems.append(f"site/index.html: JSON-LD doesn't parse ({error})")
faq = next((node for node in nodes if node.get("@type") == "FAQPage"), None)
visible = [re.sub(r"<[^>]+>", "", q).strip() for q in re.findall(r"<summary>(.*?)</summary>", html, re.S)]
if faq is not None:
    marked_up = [question["name"] for question in faq.get("mainEntity", [])]
    if marked_up != visible:
        problems.append("site/index.html: FAQ structured data and the visible FAQ list different questions\n"
                        f"    structured: {marked_up}\n    visible:    {visible}")

# Sitemap.
try:
    xml.dom.minidom.parse(str(SITE / "sitemap.xml"))
except Exception as error:  # noqa: BLE001 — any parse failure is the finding
    problems.append(f"site/sitemap.xml: not well-formed ({error})")

if problems:
    print("Site and README checks failed:")
    for problem in problems:
        print(f"  {problem}")
    sys.exit(1)

print(f"All {checked} local references resolve; structured data, FAQ, and sitemap are valid.")
