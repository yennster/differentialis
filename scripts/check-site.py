#!/usr/bin/env python3
"""Checks the README and the website for things that silently break.

- Every local file the README or the site references exists (a renamed or removed screenshot fails).
- The site's JSON-LD structured data parses, and its FAQ questions and answers match the visible
  FAQ section.
- The version the site and llms.txt state matches MARKETING_VERSION in project.yml.
- sitemap.xml is well-formed, and its lastmod matches the page's dateModified.

External URLs and in-page anchors are skipped. Run from anywhere: `python3 scripts/check-site.py`.
"""
import html as htmllib
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
    SITE / "404.html": SITE,
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
            # Root-relative paths ("/styles.css") resolve against the document's site root.
            if not (base / path.lstrip("/")).exists():
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


def plain(fragment: str) -> str:
    """Text of an HTML fragment as the JSON-LD spells it: no tags, single spaces, ⌘ as "Command-"."""
    text = htmllib.unescape(re.sub(r"<[^>]+>", "", fragment))
    return re.sub(r"\s+", " ", text.replace("⌘", "Command-")).strip()


def node_of(kind: str):
    return next((node for node in nodes if node.get("@type") == kind), None)


faq = node_of("FAQPage")
visible = [(plain(q), plain(a)) for q, a in
           re.findall(r"<summary>(.*?)</summary>\s*<p>(.*?)</p>", html, re.S)]
if faq is None:
    problems.append("site/index.html: no FAQPage structured data")
else:
    marked_up = [(q["name"], q["acceptedAnswer"]["text"]) for q in faq.get("mainEntity", [])]
    if [q for q, _ in marked_up] != [q for q, _ in visible]:
        problems.append("site/index.html: FAQ structured data and the visible FAQ list different questions\n"
                        f"    structured: {[q for q, _ in marked_up]}\n    visible:    {[q for q, _ in visible]}")
    else:
        for (question, structured), (_, shown) in zip(marked_up, visible):
            if structured != shown:
                problems.append(f"site/index.html: FAQ answer to \"{question}\" differs\n"
                                f"    structured: {structured}\n    visible:    {shown}")

# Version: what the site and llms.txt say vs. the app's MARKETING_VERSION.
version = re.search(r'MARKETING_VERSION:\s*"?([\d.]+)', (ROOT / "project.yml").read_text(encoding="utf-8")).group(1)
app = node_of("SoftwareApplication") or {}
if app.get("softwareVersion") != version:
    problems.append(f"site/index.html: softwareVersion is {app.get('softwareVersion')!r}, project.yml says {version}")
shown_versions = set(re.findall(r"<span data-version>v?([^<]+)</span>", html))
if shown_versions != {version}:
    problems.append(f"site/index.html: visible version {sorted(shown_versions)}, project.yml says {version}")
llms = (SITE / "llms.txt").read_text(encoding="utf-8")
if f"Current version: {version} " not in llms:
    problems.append(f"site/llms.txt: no \"Current version: {version}\" line")

# Sitemap.
try:
    sitemap = xml.dom.minidom.parse(str(SITE / "sitemap.xml"))
    lastmod = [node.firstChild.data.strip() for node in sitemap.getElementsByTagName("lastmod")]
    modified = (node_of("WebPage") or {}).get("dateModified")
    if lastmod != [modified]:
        problems.append(f"site/sitemap.xml: lastmod {lastmod} doesn't match the page's dateModified {modified!r}")
except Exception as error:  # noqa: BLE001 — any parse failure is the finding
    problems.append(f"site/sitemap.xml: not well-formed ({error})")

if problems:
    print("Site and README checks failed:")
    for problem in problems:
        print(f"  {problem}")
    sys.exit(1)

print(f"All {checked} local references resolve; structured data, FAQ, version, and sitemap are valid.")
