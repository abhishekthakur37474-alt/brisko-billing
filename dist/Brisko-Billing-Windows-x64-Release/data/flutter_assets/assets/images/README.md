# Receipt assets

## `brisko_logo.png` — the outlet logo (REQUIRED for the receipt logo to print)

Drop the official Brisko Pizza logo here as **`brisko_logo.png`** and it prints
automatically at the top of every customer receipt. No code or pubspec change is
needed: the whole `assets/images/` directory is declared in `pubspec.yaml`, and
`lib/app/receipt_logo.dart` loads `assets/images/brisko_logo.png` on start-up,
scales it, and reduces it to a printer-ready monochrome bitmap.

Guidance for a clean thermal print:

- PNG, square or near-square, with a **transparent or white background** (a dark
  background prints as a solid black box on the roll).
- The image is scaled to ~240 dots wide (about 30 mm on 80 mm paper) with its
  aspect ratio preserved, so any reasonably sized source works.
- Simple, high-contrast artwork reads best after monochrome thresholding.

Until this file exists, receipts print correctly with just the outlet name — the
logo is optional and never blocks a receipt. The pipeline (raster encoder, builder,
formatter rendering, loader) is complete and unit-tested with a synthetic bitmap;
only this binary asset is outstanding.
