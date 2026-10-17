# terminal/view

Draws a `vt.Terminal` into RGBA pixels: a monospaced font, a theme, the
cursor and a selection. It keeps the last frame and redraws only the rows
that changed.

```vertex
import "terminal/view"

let r = view.Renderer(theme: .dark)
let grid = r.GridSize(width: w, height: h, scale: 2)       // what fits
term.Resize(columns: grid.Columns, rows: grid.Rows)
let pixels = r.Draw(term, width: w, height: h, scale: 2,
                    cursor: view.CursorState(visible: true, focused: true), selection: sel)
```

## Types

- **`Renderer`** (class): `Draw`, `GridSize(width:height:scale:)`, `CellSize(scale:)`, `CellAt(x:y:scale:columns:rows:)`, `SetFont(families:size:)`, `SetTheme(_:)`, `Invalidate()`; `Padding`, `LineSpacing`.
- **`Theme`** (struct): foreground, background, cursor, cursor text, selection and the 16 ANSI colors; `.dark` and `.light`.
- **`Selection`** (struct): from one cell to another in absolute lines, so it stays on its text as output scrolls.
- **`CursorState`** (struct): shown (blink), and focused (filled) or not (an outline).

The font is the first of its families that is really monospaced (`SF Mono`,
`Menlo`, `Monaco`, `monospace`); bold and italic use the family's faces.
U+2500–257F and U+2580–259F are drawn as shapes.

Part of the [`terminal`](https://github.com/vertex-language/terminal) repository.
