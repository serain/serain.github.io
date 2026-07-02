#!/usr/bin/env bash
#
# Build resume.pdf from resume.html.
#
# The PDF is written to the repository root so GitHub Pages serves it at
# <your-domain>/resume.pdf. This _resume/ directory is ignored by Jekyll
# (leading underscore), so the source and this script are never published.
#
# Requirements:
#   - wkhtmltopdf 0.12.6 (macos-cocoa). Found via, in order:
#       $WKHTMLTOPDF  ->  PATH  ->  ~/.local/bin/wkhtmltopdf
#     Get it from https://github.com/wkhtmltopdf/packaging/releases
#   - python3 (ships with macOS) for the HTML transform.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$HERE/resume.html"
OUT="$ROOT/resume.pdf"
FONTDIR="$HERE/fonts"

# 1. Locate wkhtmltopdf.
WK="${WKHTMLTOPDF:-}"
if [[ -z "$WK" ]]; then
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    WK="$(command -v wkhtmltopdf)"
  elif [[ -x "$HOME/.local/bin/wkhtmltopdf" ]]; then
    WK="$HOME/.local/bin/wkhtmltopdf"
  fi
fi
if [[ -z "$WK" || ! -x "$WK" ]]; then
  echo "error: wkhtmltopdf not found (set \$WKHTMLTOPDF or put it on PATH)." >&2
  echo "  macOS build: https://github.com/wkhtmltopdf/packaging/releases (0.12.6 macos-cocoa)" >&2
  exit 1
fi

# 2. Make the resume fonts available to the renderer.
#    wkhtmltopdf's macOS engine resolves fonts by family name via CoreText,
#    so the bundled fonts must be installed for the user (idempotent copy).
mkdir -p "$HOME/Library/Fonts"
for f in "$FONTDIR"/*.ttf; do
  dest="$HOME/Library/Fonts/$(basename "$f")"
  [[ -f "$dest" ]] || cp "$f" "$dest"
done

# 3. Transform the source for the PDF pass and render it.
#    - Drop the block marked <!-- pdf-build:strip --> ... <!-- /pdf-build:strip -->
#      in resume.html (the Google Fonts <link>s): the old WebKit can't fetch
#      them and a failed load shadows the locally-installed fonts, forcing
#      Helvetica. Browsers still load them fine; only this PDF pass skips them.
#    - Reference Open Sans Condensed by its installed family name.
TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT
TMP="$TMPDIR_BUILD/resume.html"
python3 - "$SRC" "$TMP" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
html = open(src).read()
html = re.sub(
    r'<!-- pdf-build:strip -->.*?<!-- /pdf-build:strip -->',
    '', html, flags=re.S,
)
html = html.replace('"Open Sans Condensed"', '"Open Sans Condensed Light"')
open(dst, 'w').write(html)
PY

# Zero margins so the full-bleed black bars reach the page edges (A4).
"$WK" -T 0 -B 0 -L 0 -R 0 "$TMP" "$OUT"

echo "wrote $OUT"
