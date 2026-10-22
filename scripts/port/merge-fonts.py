"""Merge Excalidraw's unicode-range WOFF2 subsets into one TTF per family.

Excalidraw ships each font split into subsets for the web. Grafix is native, so
it bundles one complete font per family instead.

Usage:
  uv run --with fonttools --with brotli scripts/port/merge-fonts.py [EXCALIDRAW_REPO]
"""

import sys
from pathlib import Path

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Workspace/oss/excalidraw")
FONTS = REPO / "packages/excalidraw/fonts"
OUT = Path(__file__).resolve().parents[2] / "Sources/GrafixCore/Resources/Fonts"

# Output name -> source folder. Nunito/Lilita/ComicShanns/Excalifont are split.
FAMILIES = {
    "Virgil": "Virgil",
    "Excalifont": "Excalifont",
    "Cascadia": "Cascadia",
    "Nunito": "Nunito",
    "LilitaOne": "Lilita",
    "ComicShanns": "ComicShanns",
    "LiberationSans": "Liberation",
}


def merge(files: list[Path]) -> TTFont:
    """Copies every glyph and cmap entry from the subsets into the largest one."""
    fonts = [TTFont(f) for f in files]
    fonts.sort(key=lambda f: -f["maxp"].numGlyphs)
    base = fonts[0]
    if len(fonts) == 1:
        return base
    glyf_based = "glyf" in base
    base_cmap = base.getBestCmap()
    order = base.getGlyphOrder()
    hmtx = base["hmtx"].metrics
    for other in fonts[1:]:
        if ("glyf" in other) != glyf_based:
            raise SystemExit(f"mixed outline formats in {files[0].parent}")
        rename: dict[str, str] = {}
        for code, name in other.getBestCmap().items():
            if code in base_cmap:
                continue
            new = name if name not in order else f"{name}.m{len(order)}"
            if name not in rename:
                rename[name] = new
                order.append(new)
                hmtx[new] = other["hmtx"].metrics[name]
                if glyf_based:
                    glyph = other["glyf"][name]
                    if glyph.isComposite():
                        # Component glyphs may not exist in the base; flatten them.
                        recorder = DecomposingRecordingPen(other.getGlyphSet())
                        other.getGlyphSet()[name].draw(recorder)
                        pen = TTGlyphPen(None)
                        recorder.replay(pen)
                        glyph = pen.glyph()
                    base["glyf"].glyphs[new] = glyph
                else:
                    raise SystemExit("CFF merge not supported")
            base_cmap[code] = rename[name]
    base.setGlyphOrder(order)
    if glyf_based:
        base["glyf"].glyphOrder = order
    base["maxp"].numGlyphs = len(order)
    for table in base["cmap"].tables:
        if table.isUnicode():
            table.cmap = {c: n for c, n in base_cmap.items() if table.format != 4 or c <= 0xFFFF}
    # Kerning/GSUB from subsets would reference missing glyphs; keep base layout only.
    for tag in ("post",):
        if tag in base:
            base[tag].formatType = 3.0
    base.flavor = None
    return base


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for out_name, folder in FAMILIES.items():
        files = sorted((FONTS / folder).glob("*.woff2"))
        if not files:
            print(f"skip {folder}: no woff2")
            continue
        font = merge(files)
        font.flavor = None
        target = OUT / f"{out_name}.ttf"
        font.save(target)
        print(f"{target.name}: {len(files)} subsets, {font['maxp'].numGlyphs} glyphs")


main()
