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
@page { size: A4; margin: 11mm 12mm; }
* { box-sizing: border-box; }
body{ font:8.6pt/1.34 -apple-system,"Helvetica Neue",Helvetica,Arial,sans-serif; color:#16181D; margin:0;
      -webkit-font-smoothing:antialiased; }
h1{ font-size:13pt; letter-spacing:-.02em; margin:0 0 5pt; }
h3{ font-size:9.4pt; letter-spacing:-.01em; margin:8pt 0 3pt; padding-bottom:2pt; border-bottom:.6pt solid #C9C9C4; }
p{ margin:0 0 4pt; }
/* the quoted question: present, but never competing with the answer */
blockquote{ margin:0 0 4pt; padding:0 0 0 7pt; border-left:1.5pt solid #C9C9C4;
            font-size:7.9pt; line-height:1.3; color:#5B6270; }
blockquote em{ font-style:normal; }
blockquote p{ margin:0; }
ul,ol{ margin:0 0 4pt; padding-left:13pt; }
li{ margin-bottom:1.5pt; }
code{ font:7.9pt/1.35 ui-monospace,"SF Mono",Menlo,monospace; background:#F2F2EF; padding:.4pt 2pt; border-radius:2pt; }
table{ border-collapse:collapse; width:100%; margin:4pt 0 6pt; font-size:7.7pt; line-height:1.3; }
th{ text-align:left; font-size:6.9pt; letter-spacing:.05em; text-transform:uppercase; color:#6B7280;
    border-bottom:.8pt solid #16181D; padding:2.5pt 5pt 2.5pt 0; }
td{ padding:3pt 5pt 3pt 0; border-bottom:.5pt solid #E4E4E0; vertical-align:top; }
td:first-child, th:first-child{ padding-left:0; }
strong{ font-weight:650; }
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
