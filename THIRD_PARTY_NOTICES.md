# Third-party notices

Grafix ports code and assets from the following open-source projects.

## Excalidraw (MIT)

https://github.com/excalidraw/excalidraw. Copyright (c) 2020 Excalidraw.

The following are ported from Excalidraw:
- Element model and JSON format
- Shape generation (`packages/element/src/shape.ts` → `Sources/GrafixRender/ShapeGenerator.swift`)
- Arrowheads, bound-text layout, binding, fractional indexing (CC0)
- Theme tokens, palette, UI strings, keyboard shortcuts and icons (`Sources/GrafixPort/Generated`)

Excalidraw's icons derive from Font Awesome (CC BY 4.0 / OFL) and Tabler Icons (MIT), as
attributed in Excalidraw's `components/icons.tsx`.

## Rough.js 4.6.4 (MIT)

https://github.com/rough-stuff/rough. Copyright (c) 2019 Preet Shihn.

Ported line by line to `Sources/GrafixRender/Rough`. This includes its dependencies
`hachure-fill`, `points-on-curve`, `points-on-path` and `path-data-parser` (MIT, Preet Shihn).

## perfect-freehand 1.2.0 (MIT)

https://github.com/steveruizok/perfect-freehand. Copyright (c) 2021 Stephen Ruiz Ltd.

Ported to `Sources/GrafixRender/Freehand`.

## Fonts (SIL Open Font License 1.1 unless noted)

These fonts are bundled in `Sources/GrafixCore/Resources/Fonts`. They are merged from
Excalidraw's distribution by `scripts/port/merge-fonts.py`.

- Excalifont, by Excalidraw / Ján Filípek (OFL)
- Virgil, by Your Own Font Foundry (OFL)
- Nunito, by Vernon Adams et al. (OFL)
- Lilita One, by Juan Montoreano (OFL)
- Comic Shanns, by jesusmgg (MIT)
- Cascadia Code, by Microsoft (OFL)
- Liberation Sans, by Red Hat (OFL)
- Assistant, by Ben Nathan (OFL), when bundled
