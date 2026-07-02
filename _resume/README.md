# resume

Source for the CV published at `<domain>/resume.pdf`.

- `resume.html` — the CV markup/styles (edit this).
- `fonts/` — Monda + Open Sans Condensed (Light), bundled so the build is reproducible.
- `build.sh` — renders `resume.html` to `../resume.pdf` (repo root) with wkhtmltopdf.

## Build

```sh
./build.sh
```

Outputs `resume.pdf` to the repo root. Commit that file to publish it — Jekyll
ignores this `_resume/` directory (leading underscore), so only the PDF is served.

### Notes
- Needs **wkhtmltopdf 0.12.6** (macos-cocoa). Resolved via `$WKHTMLTOPDF`, then
  `PATH`, then `~/.local/bin/wkhtmltopdf`. Download:
  https://github.com/wkhtmltopdf/packaging/releases
- The build installs the bundled fonts into `~/Library/Fonts` if missing —
  wkhtmltopdf's macOS engine resolves fonts by family name via CoreText and has
  no `--fontdir` option.
- The Google Fonts `<link>`s in `resume.html` are for viewing the file in a
  browser; `build.sh` strips them for the PDF (the old WebKit can't fetch them,
  and a failed load would shadow the local fonts).
