#!/usr/bin/env python3
"""
Renders a Gumroad landing page from markdown, dark-mode by default.

    python3 gumroad/render.py gumroad/page.md gumroad/.rendered.html

Why this exists: Gumroad has no dark mode and no markdown support for custom
pages, so writing the copy means hand-editing styled HTML. This lets the copy
live in markdown and keeps the styling in one place.

Supported markdown (deliberately a small subset -- this is a sales page, not a
document): # / ## headings, paragraphs, - bullet lists, **bold**, *italic*,
[text](url), `code`, --- rule, and two extras:

    ![alt](panel)   image by IMAGES key below (Gumroad-hosted, see the rule file)
    [[BUY]]         the checkout button (data-gumroad-action="buy")

No external dependencies -- stdlib only, so it runs anywhere.
"""
import html
import re
import sys

# Gumroad-hosted images. Landing pages must NOT hotlink an external host, so
# upload with `gumroad products covers add <id> --image f.png` and put the
# returned public-files URL here.
IMAGES = {
    "icon": "https://public-files.gumroad.com/l0pot78cssiunscu57qkja7exv7e",
    "panel": "https://public-files.gumroad.com/ucmrvrlzn5lvafq0c9s466kufh1c",
}

BG = "#121214"
FG = "#e8e8ea"
HEAD = "#ffffff"
MUTED = "#b8b8bd"
DIM = "#8a8a90"
ACCENT = "#5eead4"
ACCENT_TEXT = "#08211c"

#--------------------------------------------------------------------------------
# The <style> block is what makes the page *actually* dark rather than a dark card
# floating on Gumroad's white page. Verified: Gumroad's sanitizer passes <style>
# through untouched (total_removed == 0). html/body/#main are all forced, because
# overscroll and any area the content doesn't reach otherwise shows white.
#--------------------------------------------------------------------------------
STYLE = f"""<style>
html, body {{
  background: {BG} !important;
  color: {FG} !important;
}}
body main, body #main, body > div, .product-page, .responsive-container {{
  background: {BG} !important;
  color: {FG} !important;
}}
.lce {{
  max-width: 760px;
  margin: 0 auto;
  padding: 2em 0 4em;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  line-height: 1.6;
  color: {FG};
}}
.lce h1 {{ font-size: 2.1rem; margin: 0 0 .4em; letter-spacing: -.02em; color: {HEAD}; }}
.lce h2 {{ font-size: 1.25rem; margin: 2em 0 .6em; color: {HEAD}; }}
.lce p  {{ color: {MUTED}; margin: 0 0 1.2em; }}
.lce li {{ color: {MUTED}; margin-bottom: .5em; }}
.lce ul {{ padding-left: 1.3em; margin: 0 0 1.5em; }}
.lce strong {{ color: {HEAD}; }}
.lce em {{ color: {MUTED}; }}
.lce a {{ color: {ACCENT}; }}
.lce code {{
  background: #1e1e22; color: {ACCENT}; padding: .15em .4em;
  border-radius: 4px; font-size: .9em;
}}
.lce img {{ display: block; max-width: 100%; height: auto; border-radius: 8px; margin: 0 0 1.6em; }}
.lce hr {{ border: 0; border-top: 1px solid #2a2a30; margin: 2.4em 0 1.4em; }}
.lce .buy {{
  display: inline-block; background: {ACCENT}; color: {ACCENT_TEXT};
  padding: .9em 2em; border-radius: 6px; font-weight: 700;
  text-decoration: none; margin: 0 0 1em;
}}
.lce .byline {{ color: {DIM}; font-size: .95rem; }}
</style>"""


def inline(text: str) -> str:
    """Inline markdown -> HTML. Escapes first, so copy can contain < and &."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def render(md: str) -> str:
    out = []
    lines = md.split("\n")
    i = 0
    saw_h1 = False

    while i < len(lines):
        line = lines[i].rstrip()

        if not line:
            i += 1
            continue

        # [[BUY]] -> checkout button. data-gumroad-field="price" keeps the price
        # in sync with the product instead of hardcoding it in the copy.
        if line.strip() == "[[BUY]]":
            out.append(
                '<p><a class="buy" data-gumroad-action="buy">'
                'Get it — <span data-gumroad-field="price">€10</span></a></p>'
            )
            i += 1
            continue

        if line.strip() == "---":
            out.append("<hr>")
            i += 1
            continue

        image = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)$", line.strip())
        if image:
            alt, key = image.group(1), image.group(2).strip()
            src = IMAGES.get(key, key)
            if key not in IMAGES and not key.startswith("http"):
                sys.exit(f"render.py: unknown image key {key!r}; add it to IMAGES")
            width = ' width="120" height="120"' if key == "icon" else ""
            out.append(f'<img src="{src}" alt="{html.escape(alt)}"{width}>')
            i += 1
            continue

        if line.startswith("## "):
            out.append(f"<h2>{inline(line[3:])}</h2>")
            i += 1
            continue

        if line.startswith("# "):
            # The first h1 carries data-gumroad-field="name" so it tracks the
            # product name rather than drifting from it.
            attr = ' data-gumroad-field="name"' if not saw_h1 else ""
            saw_h1 = True
            out.append(f"<h1{attr}>{inline(line[2:])}</h1>")
            i += 1
            continue

        if line.startswith("- "):
            items = []
            while i < len(lines) and lines[i].rstrip().startswith("- "):
                items.append(f"<li>{inline(lines[i].rstrip()[2:])}</li>")
                i += 1
            out.append("<ul>" + "".join(items) + "</ul>")
            continue

        # Paragraph: gather until a blank line or a block-level marker.
        para = []
        while i < len(lines):
            nxt = lines[i].rstrip()
            if not nxt or nxt.startswith(("# ", "## ", "- ", "---", "![")) or nxt.strip() == "[[BUY]]":
                break
            para.append(nxt)
            i += 1
        joined = " ".join(para)
        # A trailing byline (after the --- rule) gets the dimmer style.
        cls = ' class="byline"' if out and out[-1] == "<hr>" else ""
        out.append(f"<p{cls}>{inline(joined)}</p>")

    return STYLE + '\n<div class="lce">\n' + "\n".join(out) + "\n</div>"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source = open(sys.argv[1], encoding="utf-8").read()
    open(sys.argv[2], "w", encoding="utf-8").write(render(source))
