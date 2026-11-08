# Figures written by other tools

The PDF and SVG figures of this directory were written by the tools that
people use to draw figures for print, so that the tests of golem-driver
place each of them in a PDF, every time, without the tools
([docs/adr/0232](../../../../../docs/adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)).
A tool is needed only to write a sample once.

Every PDF draws the same simple figure of 120 by 80 pt (`src/figure.svg`):
a black line 2 pt wide, a red rectangle and a blue one, two circles,
half-transparent where the tool can draw them so, and the word "Golem".
The TeX samples draw the blue rectangle in CMYK and the circles in a
transparency group. The SVGs inside the range of
[golem-pdf ADR 0009](../../../../../docs/golem-pdf/adr/0009-svg-figures.md)
draw the same figure without transparency and with the word as outlines.

The figures were drawn for this repository and, like the manuals, are
under CC0 1.0. The fonts some of them embed keep their own licences:
Source Sans Pro (SIL Open Font License 1.1, from
`modules/golem-font/test/fonts`), Liberation Sans (SIL Open Font License
1.1), DejaVu Sans (the Bitstream Vera licence), Computer Modern and Latin
Modern (the licences of TeX Live).

All were written on 2026-11-08 by Claude Code (an AI assistant) in a
session of the maintainer, tett23, on macOS (Darwin 27.0.0, aarch64). The tools of
nixpkgs came from the binary cache of NixOS.

| File | Tool and version | How it was written | Golem |
| --- | --- | --- | --- |
| `inkscape.pdf` | Inkscape 1.4.4 (cairo 1.18.4) | `inkscape src/figure.svg --export-type=pdf --export-filename=inkscape.pdf`, with `FONTCONFIG_FILE` naming a directory of `SourceSansPro-Regular.otf` | placed |
| `libreoffice-draw.pdf` | LibreOffice 26.2.4.2 (nixpkgs `libreoffice-bin`) | `soffice --headless --convert-to pdf:draw_pdf_Export src/figure.svg`: Draw opens the SVG and writes the PDF; Source Sans Pro is not installed for it, so it uses Liberation Sans | placed |
| `chromium-print.pdf` | Google Chrome 156.0.8078.80, which is Chromium (Skia/PDF m156) | `"Google Chrome" --headless --no-pdf-header-footer --print-to-pdf=chromium-print.pdf src/figure.html`, with `SourceSansPro-Regular.otf` next to the HTML; Skia writes the font as Type 3 | placed |
| `matplotlib.pdf` | matplotlib 3.11.2, Python 3.14 (nixpkgs) | `python3 src/figure.py matplotlib.pdf`; DejaVu Sans as Type 3 | placed |
| `pdftex.pdf` | pdfTeX 1.40.27, TeX Live 2025 (nixpkgs `texliveSmall`) | `pdflatex -jobname=pdftex src/figure.tex` (TikZ) | placed |
| `luatex.pdf` | LuaTeX 1.22.0, TeX Live 2025 (nixpkgs `texliveSmall`) | `lualatex -jobname=luatex src/figure.tex` (TikZ) | placed |
| `pdftex-spot-color.pdf` | pdfTeX 1.40.27 | `pdftex src/spot.tex`: a rectangle in a `Separation` colour space of `PANTONE185C` | refused: `SpotColor` |
| `inkscape.svg` | Inkscape 1.4.4 | `inkscape src/shapes.svg --export-plain-svg --export-text-to-path --export-filename=inkscape.svg` | placed |
| `inkscape-filter.svg` | Inkscape 1.4.4 | `inkscape src/filter.svg --export-plain-svg --export-filename=inkscape-filter.svg`: a Gaussian blur | G08011 |
| `drawio.svg` | draw.io 32.4.1 (nixpkgs `drawio`) | `drawio --export --format svg --theme light --output drawio.svg src/shapes.drawio`: shapes alone, no label | G08011 |
| `drawio-foreign-object.svg` | draw.io 32.4.1 | `drawio --export --format svg --theme light --output drawio-foreign-object.svg src/label.drawio`: a label in HTML, in a `foreignObject` | G08011 |
| `illustrator.pdf` | Adobe Illustrator | written by the maintainer at the release of v1.0.0 | placed |
| `illustrator.svg` | Adobe Illustrator | written by the maintainer at the release of v1.0.0, inside the range of [golem-pdf ADR 0009](../../../../../docs/golem-pdf/adr/0009-svg-figures.md) | placed |

The tests skip a row whose file is not here; the two rows of Illustrator
are checked once the maintainer commits their files.

draw.io 32.4.1 writes `data-cell-id` and `pointer-events` on every shape
and a `style` with `background` and `color-scheme` on the root, which are
outside the range of [golem-pdf ADR 0009](../../../../../docs/golem-pdf/adr/0009-svg-figures.md), so no SVG of draw.io is inside it, even of
shapes alone. `drawio.svg` is kept as that finding.

To write a sample again, run its command from this directory with the
version of the table; the tests then tell whether Golem still places or
refuses it as the table says.
