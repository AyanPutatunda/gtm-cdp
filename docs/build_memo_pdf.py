#!/usr/bin/env python3
"""
Render MEMO.md to MEMO.pdf, so the PDF is reproducible rather than a mystery
binary that can silently disagree with the Markdown it came from.

    pip install markdown
    python docs/build_memo_pdf.py

Uses headless Chrome for layout (macOS path by default; override with
CHROME=/path/to/chrome). Typography is tuned to keep the memo inside the
1.5-page limit the brief asks for — the script prints the page count so a
change that pushes it over is caught here rather than by the reader.
"""
from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "MEMO.md"
OUT = ROOT / "MEMO.pdf"
PAGE_LIMIT = 2  # 1.5 pages rounds up to two sheets; three means it has grown

CHROME_CANDIDATES = [
    os.environ.get("CHROME", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
]

CSS = """
@page { size: A4; margin: 13mm 14mm; }
* { box-sizing: border-box; }
body{ font:9.6pt/1.4 -apple-system,"Helvetica Neue",Helvetica,Arial,sans-serif; color:#16181D; margin:0; }
h1{ font-size:15pt; letter-spacing:-.02em; margin:0 0 8pt; }
h3{ font-size:10.6pt; letter-spacing:-.01em; margin:10pt 0 4pt; padding-bottom:3pt; border-bottom:.6pt solid #D8D8D4; }
p{ margin:0 0 5pt; }
ul,ol{ margin:0 0 6pt; padding-left:15pt; }
li{ margin-bottom:2pt; }
code{ font:9pt/1.4 ui-monospace,"SF Mono",Menlo,monospace; background:#F2F2EF; padding:.5pt 2.5pt; border-radius:2pt; }
table{ border-collapse:collapse; width:100%; margin:6pt 0 8pt; font-size:8.7pt; }
th{ text-align:left; font-size:7.6pt; letter-spacing:.06em; text-transform:uppercase; color:#6B7280;
    border-bottom:.8pt solid #16181D; padding:3.5pt 6pt 3.5pt 0; }
td{ padding:4pt 6pt 4pt 0; border-bottom:.5pt solid #E4E4E0; vertical-align:top; }
td:first-child, th:first-child{ padding-left:0; }
strong{ font-weight:640; }
"""


def main() -> int:
    try:
        import markdown
    except ImportError:
        print("error: pip install markdown", file=sys.stderr)
        return 1

    chrome = next((c for c in CHROME_CANDIDATES if c and pathlib.Path(c).exists()), None)
    if not chrome:
        print("error: no Chrome/Chromium found — set CHROME=/path/to/chrome", file=sys.stderr)
        return 1

    html = "<!doctype html><html><head><meta charset='utf-8'><style>%s</style></head><body>%s</body></html>" % (
        CSS, markdown.markdown(SRC.read_text(), extensions=["tables"]))

    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / "memo.html"
        page.write_text(html)
        subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--no-sandbox", "--no-pdf-header-footer",
             f"--print-to-pdf={OUT}", page.as_uri()],
            check=True, capture_output=True,
        )

    pages = len(re.findall(rb"/Type\s*/Page[^s]", OUT.read_bytes()))
    print(f"{OUT.relative_to(ROOT)} · {pages} page(s), {OUT.stat().st_size // 1024} KB")
    if pages > PAGE_LIMIT:
        print(f"warning: the brief asks for 1.5 pages and this is {pages} sheets — trim the memo.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
