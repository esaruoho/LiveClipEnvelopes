#!/bin/bash
# Edit gumroad/page.md, run this, done.
#
# Renders page.md -> dark-styled HTML -> pushes it to the Gumroad product,
# then screenshots the live page so you can see what actually shipped.
#
#   ./gumroad/deploy.sh              # render, preview-check, publish, screenshot
#   ./gumroad/deploy.sh --dry-run    # render + open the HTML locally, push nothing
set -euo pipefail
cd "$(dirname "$0")/.."

PRODUCT_ID="GvOE3ReUu489krwHo5vKqg=="
MD="gumroad/page.md"
OUT="gumroad/.rendered.html"
SHOT="gumroad/.preview.png"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

echo "==> Rendering $MD"
python3 gumroad/render.py "$MD" "$OUT"
echo "    $(wc -c < "$OUT" | tr -d ' ') bytes"

if [ "$DRY" = "1" ]; then
    echo "==> Dry run -- opening locally, nothing pushed"
    open "$OUT"
    exit 0
fi

echo "==> Sanitizer check"
REMOVED=$(gumroad products page preview "$PRODUCT_ID" "$OUT" --json --no-input --quiet \
    | python3 -c "import json,sys; print((json.load(sys.stdin).get('sanitization_report') or {}).get('total_removed', '?'))")
if [ "$REMOVED" != "0" ]; then
    echo "    ABORT: sanitizer would strip $REMOVED thing(s). Inspect with:"
    echo "      gumroad products page preview $PRODUCT_ID $OUT --json | jq .sanitization_report"
    exit 1
fi
echo "    clean (0 removed)"

echo "==> Publishing"
gumroad products page publish "$PRODUCT_ID" "$OUT" --json --no-input --quiet >/dev/null
echo "    pushed"

URL=$(gumroad products page url "$PRODUCT_ID" --json --no-input --quiet \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['product']['landing_url'])")
echo "==> Live at $URL"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
    echo "==> Screenshotting the live page (Gumroad renders client-side, so this is the only real check)"
    sleep 3
    "$CHROME" --headless --disable-gpu --screenshot="$SHOT" \
        --window-size=1280,1600 --virtual-time-budget=20000 --hide-scrollbars "$URL" 2>/dev/null || true
    if [ -f "$SHOT" ]; then
        echo "    $SHOT"
        open "$SHOT"
    fi
fi
