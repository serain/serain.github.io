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

# 3. Render. Zero margins so the full-bleed black bars reach the page edges (A4).
"$WK" -T 0 -B 0 -L 0 -R 0 "$SRC" "$OUT"

echo "wrote $OUT"
