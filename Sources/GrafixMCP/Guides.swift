import Foundation

/// Format guides returned by read_*_format and the shared essentials in `instructions`.
enum Guides {
  static let serverInstructions = #"""
    Grafix is a local, Excalidraw-compatible drawing app. Scenes are .excalidraw files grouped in collections.
    Scene ids look like "Collection/Scene name" (e.g. "Personal/Login flow"). Call list_scenes to find them.

    Workflow: (1) get or create a scene (list_scenes / create_scene; or get_editor_state when the user says
    "this drawing" or "the selected box"), (2) read the matching guide once: read_diagram_format for flowcharts and
    architecture, read_presentation_format for slides, read_freeform_format for everything else, (3) write with
    edit_scene_content (and create_slide for decks), (4) verify with take_screenshot and fix problems.

    Essentials: add elements WITHOUT id and give each a tempId to reference it inside the same call. Put text
    inside shapes with label {"text": "..."}, never as a separate text element on top. Arrows between shapes need
    startBinding and endBinding {elementId, mode:"inside"}. Coordinates are absolute scene pixels (y grows down);
    frame children use absolute coordinates too and carry frameId. Labeled shapes at least 160x85, gaps 40-60px,
    body text at least 16px. Colors: strokes #1e1e1e #e03131 #2f9e44 #1971c2 #f08c00; fills #ffc9c9 #b2f2bb
    #a5d8ff #ffec99 #eebefa. Deleting scenes or collections moves them to the macOS Trash.
    """#

  static let diagram = #"""
    # Grafix diagram format (flowcharts, architecture, workflows)

    All work goes through edit_scene_content. `add` is an array of element skeletons. Never include `id`; use
    `tempId` to refer to an element from other skeletons in the same call. Real ids come back in `created`.

    ## Shapes
    {"tempId":"api","type":"rectangle","x":100,"y":100,"width":180,"height":90,
     "backgroundColor":"#a5d8ff","strokeColor":"#1971c2","roundness":{"type":3},
     "label":{"text":"API server"}}

    Required: type, x, y, width, height (text elements need only type, x, y, text). Types: rectangle, ellipse,
    diamond, text, arrow, line, frame. Optional style fields and defaults:
    - strokeColor "#1e1e1e", backgroundColor "transparent", fillStyle "solid" (also hachure, cross-hatch)
    - strokeWidth 2, strokeStyle "solid" (dashed, dotted), roughness 1 (0 clean, 1 sketchy, 2 very sketchy)
    - opacity 100, roundness {"type":3} for rounded rectangles (omit for sharp corners)
    - angle in radians, groupIds ["g1"] (use a tempId-like string shared by all members), locked, link

    ## Labels
    Text inside a shape or on an arrow goes in `label`: {"text":"...", "fontSize":20, "fontFamily":5,
    "strokeColor":"#1e1e1e", "textAlign":"center", "verticalAlign":"middle"}. Labels wrap to the shape width
    and the shape grows taller if needed, so size shapes for the text: roughly 10px per character at fontSize 20,
    one line per 25px of height.
    Never place a loose text element over a shape.

    ## Arrows
    {"type":"arrow","x":0,"y":0,
     "startBinding":{"elementId":"a","mode":"inside"},
     "endBinding":{"elementId":"b","mode":"inside"},
     "label":{"text":"HTTPS"}}
    - Give both bindings for shape-to-shape arrows. Geometry may then be omitted; Grafix routes the arrow
      between the shapes. elementId may be a tempId from the same call or a real id.
    - mode "inside": the arrow ends at the shape edge facing the other end (best default).
      mode "orbit": the arrow keeps a small gap around the shape.
    - fixedPoint [fx, fy] (each 0..1) pins the end to a spot on the shape: [1,0.5] right middle, [0,0.5] left
      middle, [0.5,0] top middle, [0.5,1] bottom middle.
    - endArrowhead "arrow" (default), "triangle", "dot", "bar", or null; startArrowhead likewise (default null).
    - "elbowed":true makes right-angle routes. For explicit geometry give points:[[0,0],[dx,dy]] relative to x,y.
    - Moving or editing a bound shape later re-routes its arrows automatically.

    ## Fonts and sizes
    fontFamily: 5 Excalifont (hand-drawn, default), 6 Nunito (clean sans), 7 Lilita One (headings),
    8 Comic Shanns (code). fontSize: body >= 16, labels 18-20, titles 28-36.
    Labeled shapes at least 160x85. Leave 40-60px between neighbours; align to a grid (multiples of 20).

    ## Layout recipe
    Flow left to right or top to bottom. Pick a column pitch of 260-300px and a row pitch of 140-160px. Group
    related boxes in a large transparent rounded rectangle (strokeStyle "dashed") with a title text above it.
    Use at most four colors; the same role always gets the same color.

    ## Palette (open-color)
    strokes: #1e1e1e black, #e03131 red, #2f9e44 green, #1971c2 blue, #f08c00 orange
    fills:   #ffc9c9 red, #b2f2bb green, #a5d8ff blue, #ffec99 yellow, #eebefa purple, #e9ecef gray

    ## Editing existing content
    get_scene_content or search_scene_content gives real ids. update: [{"id":"...","backgroundColor":"#b2f2bb",
    "label":{"text":"New text"}}]. delete: ["id1","id2"] (bound labels and arrow bindings are cleaned up).
    zOrder: [{"id":"...","at":"front"}]. Operations run in the order delete, update, add, zOrder.

    ## Verify
    Call take_screenshot after the write. Look for overlapping boxes, clipped or overflowing labels, arrows that
    cross boxes, and uneven spacing; fix with update and re-check.
    """#

  static let presentation = #"""
    # Grafix presentation format

    One frame is one slide. Slides are shown in the order of customData.slidesOrder on the frames; the tools keep
    that in sync, so never write slidesOrder yourself. Use create_slide and update_slide for slides.

    ## Workflow
    1. create_scene (or use an existing one).
    2. create_slide {sceneId, title, layout, presenterNotes}. It returns frameId, bounds, safeArea and
       `regions` (suggested rectangles for title, content, left/right, media).
    3. Fill the slide with edit_scene_content. Every element you add must have "frameId": "<frameId>".
    4. take_screenshot {sceneId, frameId} for each slide and fix problems.
    5. list_slides to review the deck; update_slide {slideNumber} to reorder.

    ## Geometry
    - Default slide 854x480 (16:9). A new slide is placed 350px right of the previous one.
    - Safe area: keep all content at least 64px inside the frame edges. create_slide returns it.
    - Coordinates are absolute scene coordinates, not relative to the frame. A box on the slide at frame
      (x:80, y:80) with safe area starting at x+64 would use x:144, y:144.
    - The frame name (title) is shown above the slide on the canvas, not drawn inside it. Add a text element for the
      visible slide heading.

    ## Typography
    Heading: text element, fontFamily 7 (Lilita One) or 6 (Nunito), fontSize 36-48, at the title region.
    Body: fontFamily 6 (Nunito) or 5 (Excalifont), fontSize >= 20 for projected text (never below 16).
    Code: fontFamily 8 (Comic Shanns). One idea per slide, at most 6 short lines; prefer a diagram over bullets.
    A text skeleton needs only {"type":"text","x":..,"y":..,"text":"Hello","fontSize":40,"fontFamily":7,
    "frameId":"<frameId>"}; width and height are measured automatically. Use "\n" for line breaks.

    ## Content patterns
    - Title + content: heading at the title region, then a diagram or bullet list in the content region.
    - Two columns: use the left/right regions; keep both columns balanced.
    - Media left/right: add_image into the media region (give width and keep the aspect ratio), text opposite.
    - Section break: big centered heading in the title region, short subtitle below.
    Labeled shapes at least 160x85 with 40-60px gaps; arrows bound to shapes with startBinding/endBinding.

    ## Color and style
    Keep one background (white or a single pastel rectangle covering the safe area is fine), at most three
    accent colors. Strokes #1e1e1e #e03131 #2f9e44 #1971c2 #f08c00; fills #ffc9c9 #b2f2bb #a5d8ff #ffec99 #eebefa.
    roughness 0 for a clean corporate look, 1 hand-drawn, 2 very sketchy. roundness {"type":3} for rounded boxes.

    ## Presenter notes
    Pass presenterNotes to create_slide or update_slide (plain text or markdown bullets). They are stored on the
    frame as customData.presenterNotes and shown in presenter mode.

    ## Example (title + one box on a fresh slide with frameId F and safe area starting at 144,144)
    edit_scene_content add:
    [{"type":"text","x":144,"y":144,"text":"Q3 roadmap","fontSize":44,"fontFamily":7,"frameId":"F"},
     {"type":"rectangle","x":144,"y":240,"width":220,"height":100,"backgroundColor":"#a5d8ff",
      "strokeColor":"#1971c2","roundness":{"type":3},"label":{"text":"Ship v2"},"frameId":"F"}]
    """#

  static let freeform = #"""
    # Grafix freeform format (sketches, wireframes, notes, charts)

    Use edit_scene_content with `add` skeletons (no id; optional tempId). Coordinates are absolute pixels, y grows
    downwards. Everything not a diagram or a slide deck follows these rules.

    ## Element types
    rectangle, ellipse, diamond (need width/height), text, arrow, line, freedraw (rare), frame, image
    (use add_image). Common fields: strokeColor, backgroundColor, fillStyle (solid, hachure, cross-hatch, zigzag),
    strokeWidth (1, 2, 4), strokeStyle (solid, dashed, dotted), roughness (0, 1, 2), opacity (0-100),
    roundness {"type":3} (rounded rectangle) or omitted (sharp), angle (radians), locked, link, groupIds.

    ## Text
    {"type":"text","x":100,"y":60,"text":"Title","fontSize":36,"fontFamily":7}
    fontFamily 5 Excalifont (hand-drawn), 6 Nunito (clean), 7 Lilita One (headings), 8 Comic Shanns (code).
    textAlign "left"|"center"|"right". Size is measured automatically; use "\n" for line breaks.
    Text inside a shape: use the shape's `label`, e.g. "label":{"text":"Note","fontSize":18}. Do not stack a text
    element over a shape.

    ## Lines and arrows
    {"type":"arrow","x":100,"y":100,"points":[[0,0],[200,80]]} - points are relative to x,y. Bind to shapes with
    startBinding/endBinding {"elementId":..., "fixedPoint":[1,0.5], "mode":"inside"} (fixedPoint optional,
    each value 0..1 across the shape). Arrowheads: "arrow", "triangle", "dot", "bar", null.
    A "line" is the same without arrowheads. Close a line (polygon) by ending at the start point.

    ## Grouping and frames
    groupIds: ["g1"] on every member makes them move together. A frame clips and contains its children: add
    {"type":"frame","name":"Section","x":0,"y":0,"width":600,"height":400} and set "frameId" on children, which
    use absolute coordinates.

    ## Sticky notes and wireframes
    Sticky note: rectangle 200x200, backgroundColor #ffec99, roundness {"type":3}, label text fontSize 20.
    Wireframe: rectangles roughness 0 with light gray fills #e9ecef; buttons are rounded blue rectangles with white
    or dark labels; use dashed rectangles for placeholders and image areas.

    ## Charts
    Bars: rectangles on a common baseline, width 60, gap 20, heights proportional to values; value labels as text
    above each bar; axis as two lines. Use one fill color per series from the palette.

    ## Size and spacing
    Labeled shapes at least 160x85. Gaps of 40-60px. Body text >= 16px; titles 36-48. Align to multiples of 20.
    Keep related things close and distinct things apart. Do not overlap unrelated elements.

    ## Palette
    strokes: #1e1e1e, #e03131, #2f9e44, #1971c2, #f08c00
    fills:   #ffc9c9, #b2f2bb, #a5d8ff, #ffec99, #eebefa, #e9ecef

    ## Edit and verify
    search_scene_content finds ids by text; update patches fields; delete removes; zOrder with at "front"/"back" or
    above/below another id. Always finish with take_screenshot and correct overlaps or clipped text.
    """#
}

func guideTools() -> [Tool] {
  func guide(_ name: String, _ about: String, _ text: String) -> Tool {
    Tool(
      name: name,
      description: "Return the Grafix format guide for \(about). Read it once before your first edit_scene_content in a session. Takes no arguments.",
      inputSchema: schema(),
      run: { _, _ in .text(text) })
  }
  return [
    guide("read_diagram_format", "diagrams (flowcharts, architecture maps, workflows, hierarchies): element fields, labels, arrow bindings, sizes, palette", Guides.diagram),
    guide("read_presentation_format", "presentations (slides as frames, safe area, presenter notes, typography)", Guides.presentation),
    guide("read_freeform_format", "everything else (sketches, wireframes, notes, charts, annotations)", Guides.freeform),
  ]
}
