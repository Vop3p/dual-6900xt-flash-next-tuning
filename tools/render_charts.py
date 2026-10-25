#!/usr/bin/env python3
"""Render the README images from index.html: the "now" cards and the charts, light and dark, Chinese and English.

    CHROME=/path/to/chrome-headless-shell python3 tools/render_charts.py

Each image is index.html with only one section of <main> left, a fixed theme (data-theme) and a fixed language
(window.PAGE_LANG; the page carries both languages). Output: docs/now-{en,zh}-{light,dark}.png and
docs/speed-chart-en-{light,dark}.png and docs/speed-chart-{light,dark}.png (Chinese), docs/win1x-chart-{en,zh}-{light,dark}.png (2200 px wide, device scale 2.2); OUT=dir writes them elsewhere."""
import json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHROME = os.environ.get("CHROME", "chrome-headless-shell")
OUT = os.environ.get("OUT", os.path.join(ROOT, "docs"))   # where the PNGs go
SRC = open(os.path.join(ROOT, "index.html"), encoding="utf-8").read()
# target -> (index of the <section> to keep, CSS width in px, extra CSS); the height is trimmed to the content afterwards
TARGETS = {"now": (0, 1000, ".now-more{display:none!important}"),
           "speed-chart": (1, 1000, "section h2,section .panel+.foot,section p.foot{display:none!important}"),
           "win1x-chart": (3, 1000, "section h2,section .panel+.foot,section p.foot,section .panel .foot{display:none!important}")}

def page(section, theme, lang, extra):
    html = SRC.replace('<html lang="zh-CN" data-lang="zh">', f'<html lang="{"en" if lang == "en" else "zh-CN"}" data-lang="{lang}" data-theme="{theme}">')
    keep = f"main>section:nth-of-type({section + 1})"
    css = (f"<style>aside,main>section:not({keep}),main>p.foot,.swipe{{display:none!important}}"
           f".layout{{display:block!important;max-width:none!important;margin:0!important;padding:14px!important}}body{{margin:0}}{extra}</style>"
           f"<script>window.PAGE_LANG='{lang}'</script></head>")
    return html.replace("</head>", css, 1)

def trim(path, pad=30):
    """Cut the rows below the content: the bottom rows that are all the page background."""
    from PIL import Image
    im = Image.open(path).convert("RGB")
    w, h = im.size
    bg = im.getpixel((2, h - 2))
    px = im.load()
    y = h - 1
    while y > 0 and all(px[x, y] == bg for x in range(0, w, 4)):
        y -= 1
    im.crop((0, 0, w, min(h, y + pad))).save(path)

def main():
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, (sec, w, extra) in TARGETS.items():
            for lang in ("zh", "en"):
                for theme in ("light", "dark"):
                    f = os.path.join(tmp, f"{name}-{lang}-{theme}.html")
                    open(f, "w", encoding="utf-8").write(page(sec, theme, lang, extra))
                    # the Chinese speed chart keeps its first name (speed-chart-light.png), which README.zh-CN.md links
                    stem = f"{name}-{theme}" if (name == "speed-chart" and lang == "zh") else f"{name}-{lang}-{theme}"
                    out = os.path.join(OUT, stem + ".png")
                    subprocess.run([CHROME, "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2.2",
                                    f"--window-size={w},1400", f"--screenshot={out}", "--virtual-time-budget=3000",
                                    "file://" + f], check=True, capture_output=True)
                    trim(out)
                    print(out)

if __name__ == "__main__":
    main()
