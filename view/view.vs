// Package view draws a vt.Terminal: its cells into RGBA pixels, in a
// monospaced font and a theme, with the cursor and a selection. It keeps
// what it drew and draws again only the rows that changed, so a frame
// after one line of output costs one row.
//
//     let r = view.Renderer()
//     let size = r.GridSize(width: w, height: h, scale: 2)   // columns and rows that fit
//     term.Resize(columns: size.Columns, rows: size.Rows)
//     let pixels = r.Draw(term, width: w, height: h, scale: 2, cursor: .init(visible: true, focused: true))
//
// It knows nothing of windows: ui/viewport takes the pixels.
package view

import (
    "image/draw"
    "terminal/vt"
    "text/font"
)

/// A selection, from one cell to another (ends included), in absolute
/// lines (vt.Terminal.Absolute): it stays on its text as the screen
/// scrolls.
public struct Selection: Equatable {
    public var StartColumn: int
    public var StartLine: int
    public var EndColumn: int
    public var EndLine: int

    public init(startColumn: int, startLine: int, endColumn: int, endLine: int) {
        StartColumn = startColumn
        StartLine = startLine
        EndColumn = endColumn
        EndLine = endLine
    }

    /// The same selection with its start before its end.
    public var Ordered: Selection {
        if StartLine < EndLine || (StartLine == EndLine && StartColumn <= EndColumn) { return self }
        return Selection(startColumn: EndColumn, startLine: EndLine, endColumn: StartColumn, endLine: StartLine)
    }

    public var IsEmpty: bool { return StartLine == EndLine && StartColumn == EndColumn }

    /// The columns selected on a line, or nil.
    func span(_ line: int, _ columns: int) -> (int, int)? {
        let s = Ordered
        if line < s.StartLine || line > s.EndLine { return nil }
        let from = line == s.StartLine ? s.StartColumn : 0
        let to = line == s.EndLine ? s.EndColumn : columns - 1
        return from <= to ? (from, to) : nil
    }
}

/// How the cursor is to be drawn this frame.
public struct CursorState: Equatable {
    /// Shown at all: false between blinks.
    public var Visible: bool
    /// The terminal has keyboard focus: a filled cursor, else an outline.
    public var Focused: bool

    public init(visible: bool, focused: bool) {
        Visible = visible
        Focused = focused
    }
}

// A code point's glyphs in a face: what the font shaped it into.
struct glyphRun {
    var faces: [int32]
    var glyphs: [uint32]
    var advances: [float32]
}

// What was drawn on a row, to tell whether it must be drawn again.
struct drawnRow: Equatable {
    var cells: [vt.Cell]
    var sel: [int]
    var cursor: [int]
}

/// Draws terminals. One renderer per view: it keeps the last frame.
public final class Renderer {
    public private(set) var Theme: Theme
    public private(set) var FontFamilies: [string]
    /// The font size, in CSS pixels.
    public private(set) var FontSize: float32
    /// Space kept around the grid, in CSS pixels.
    public var Padding: float32 = 6
    /// Extra space between lines, as a fraction of the font's.
    public var LineSpacing: float32 = 1.15

    var regular: font.Face
    var bold: font.Face
    var italic: font.Face
    var boldItalic: font.Face
    var glyphCache: [uint64: glyphRun] = [:]

    // Metrics at the last scale, in device pixels.
    var scale: float32 = 0
    var cellW: int32 = 8
    var cellH: int32 = 16
    var ascent: int32 = 12
    var pad: int32 = 6

    // The last frame.
    var pixels: [uint8] = []
    var pw = 0
    var ph = 0
    var drawn: [drawnRow?] = []
    var drawnTheme = ""
    var drawnReverse = false

    public init(theme: Theme = .dark, families: [string] = ["SF Mono", "Menlo", "Monaco", "monospace"], size: float32 = 13) {
        Theme = theme
        FontFamilies = families
        FontSize = size
        regular = font.Load(font.Spec(families: families, size: size))
        bold = regular
        italic = regular
        boldItalic = regular
        loadFaces()
    }

    func loadFaces() {
        // The first family that is really monospaced: a name the system
        // doesn't have answers with a proportional fallback.
        var chosen = FontFamilies
        for f in FontFamilies {
            let face = font.Load(font.Spec(family: f, size: FontSize))
            if face.Measure("i") == face.Measure("M") && face.Measure("M") > 0 {
                chosen = [f]
                break
            }
        }
        regular = font.Load(font.Spec(families: chosen, size: FontSize))
        bold = font.Load(font.Spec(families: chosen, size: FontSize, weight: 700))
        italic = font.Load(font.Spec(families: chosen, size: FontSize, italic: true))
        boldItalic = font.Load(font.Spec(families: chosen, size: FontSize, weight: 700, italic: true))
        glyphCache = [:]
        scale = 0
        drawn = []
    }

    /// Changes the font; the grid size changes with it.
    public func SetFont(families: [string]? = nil, size: float32? = nil) {
        if let f = families { FontFamilies = f }
        if let s = size { FontSize = max(6, min(72, s)) }
        loadFaces()
    }

    public func SetTheme(_ theme: Theme) {
        Theme = theme
        drawn = []
    }

    func metrics(_ s: float32) {
        if s == scale { return }
        scale = s
        let adv = regular.Measure("M")
        cellW = max(1, int32((adv * s).rounded()))
        let line = (regular.Ascent + regular.Descent) * LineSpacing
        cellH = max(1, int32((line * s).rounded()))
        let extra = float32(cellH) - (regular.Ascent + regular.Descent) * s
        ascent = int32((regular.Ascent * s + extra / 2).rounded())
        pad = int32((Padding * s).rounded())
        drawn = []
    }

    /// One cell's size in CSS pixels at a scale.
    public func CellSize(scale s: float32) -> (Width: float32, Height: float32) {
        metrics(s)
        return (Width: float32(cellW) / s, Height: float32(cellH) / s)
    }

    /// The columns and rows that fit in width × height device pixels.
    public func GridSize(width: int, height: int, scale s: float32) -> (Columns: int, Rows: int) {
        metrics(s)
        let cols = (int32(width) - 2 * pad) / cellW
        let rows = (int32(height) - 2 * pad) / cellH
        return (Columns: max(2, int(cols)), Rows: max(1, int(rows)))
    }

    /// The cell under a point given in CSS pixels from the view's corner,
    /// clamped to the grid; `right` is whether it is in the cell's right
    /// half (where a selection's edge rounds to the next cell).
    public func CellAt(x: float32, y: float32, scale s: float32, columns: int, rows: int) -> (Column: int, Row: int, Right: bool) {
        metrics(s)
        let px = x * s - float32(pad)
        let py = y * s - float32(pad)
        var col = int((px / float32(cellW)).rounded(.down))
        var row = int((py / float32(cellH)).rounded(.down))
        let right = px - float32(col) * float32(cellW) > float32(cellW) / 2
        col = max(0, min(columns - 1, col))
        row = max(0, min(rows - 1, row))
        return (Column: col, Row: row, Right: right)
    }

    /// Forgets the last frame: the next draws everything.
    public func Invalidate() {
        drawn = []
    }

    // MARK: - Drawing

    /// Draws the terminal's view into width × height device pixels and
    /// answers them (RGBA, premultiplied, top row first).
    public func Draw(_ t: vt.Terminal, width: int, height: int, scale s: float32, cursor: CursorState,
                     selection: Selection? = nil) -> [uint8] {
        metrics(s)
        if width != pw || height != ph || pixels.count != width * height * 4 {
            pw = width
            ph = height
            pixels = [uint8](repeating: 0, count: max(0, width * height * 4))
            drawn = []
        }
        if width <= 0 || height <= 0 { return pixels }
        let rows = t.Rows
        let all = drawn.count != rows || drawnTheme != Theme.Name || drawnReverse != t.ReverseVideo
        if all {
            drawn = [drawnRow?](repeating: nil, count: rows)
            drawnTheme = Theme.Name
            drawnReverse = t.ReverseVideo
        }
        let bg = t.ReverseVideo ? Theme.Foreground : Theme.Background
        let top = t.ViewTop
        let cursorRow = t.CursorY + t.ViewOffset
        let showCursor = t.CursorVisible && t.ViewOffset < t.Rows - t.CursorY
        var me = self
        draw.WithCanvas(&pixels, width: int32(width), height: int32(height)) { c in
            if all {
                c.Clear(bg)
            }
            for y in 0..<rows {
                let line = t.ViewRow(y)
                var sel: [int] = []
                if let s = selection, !s.IsEmpty, let sp = s.span(top + y, t.Columns) { sel = [sp.0, sp.1] }
                var cur: [int] = []
                if showCursor && y == cursorRow && cursor.Visible {
                    cur = [t.CursorX, shapeCode(t.Shape), cursor.Focused ? 1 : 0]
                }
                let now = drawnRow(cells: line.Cells, sel: sel, cursor: cur)
                if !all, let was = me.drawn[y], was == now { continue }
                me.drawRow(c, t, line, y, sel, cur, bg)
                me.drawn[y] = now
            }
            // Below the last row: the padding, in the background.
            let used = me.pad + int32(rows) * me.cellH
            if all && used < int32(height) {
                c.Fill(draw.IRect(0, used, int32(width), int32(height) - used), bg)
            }
        }
        return pixels
    }

    func colorOf(_ c: vt.Color, fg: bool, bold: bool, _ t: vt.Terminal) -> draw.Color {
        if c.IsDefault {
            if t.ReverseVideo { return fg ? Theme.Background : Theme.Foreground }
            return fg ? Theme.Foreground : Theme.Background
        }
        if c.IsRGB { return draw.Color(c.R, c.G, c.B) }
        var i = c.Index
        if i < 16 {
            if fg && bold && Theme.BoldIsBright && i < 8 { i += 8 }
            return Theme.ANSI[i]
        }
        let rgb = vt.PaletteRGB(i)
        return draw.Color(rgb.R, rgb.G, rgb.B)
    }

    func drawRow(_ c: draw.Canvas, _ t: vt.Terminal, _ line: vt.Line, _ y: int, _ sel: [int], _ cur: [int], _ bg: draw.Color) {
        let py = pad + int32(y) * cellH
        // The row's whole width, padding included, starts as background.
        c.Fill(draw.IRect(0, py, c.Width, cellH), bg)
        let cols = min(t.Columns, line.Cells.count)
        let curX = cur.isEmpty ? -1 : cur[0]
        let curShape = cur.isEmpty ? 0 : cur[1]
        let curFocused = !cur.isEmpty && cur[2] == 1
        // Backgrounds first, so glyphs that overhang aren't painted over.
        var x = 0
        while x < cols {
            let cell = line.Cells[x]
            var cbg = colorOf(cell.Bg, fg: false, bold: false, t)
            if cell.Has(vt.Attr.inverse) { cbg = colorOf(cell.Fg, fg: true, bold: cell.Has(vt.Attr.bold), t) }
            if !sel.isEmpty && x >= sel[0] && x <= sel[1] { cbg = Theme.Selection }
            if cbg != bg {
                c.Fill(draw.IRect(pad + int32(x) * cellW, py, cellW, cellH), cbg)
            }
            x += 1
        }
        // The cursor's block goes under its character.
        if curX >= 0 && curX < cols && curShape == 0 && curFocused {
            let w = line.Cells[curX].Has(vt.Attr.wide) ? cellW * 2 : cellW
            c.Fill(draw.IRect(pad + int32(curX) * cellW, py, w, cellH), Theme.Cursor)
        }
        x = 0
        while x < cols {
            let cell = line.Cells[x]
            if cell.Has(vt.Attr.spacer) {
                x += 1
                continue
            }
            let isBold = cell.Has(vt.Attr.bold)
            var fg = colorOf(cell.Fg, fg: true, bold: isBold, t)
            if cell.Has(vt.Attr.inverse) {
                fg = colorOf(cell.Bg, fg: false, bold: false, t)
            }
            if cell.Has(vt.Attr.dim) {
                let under = cell.Has(vt.Attr.inverse) ? colorOf(cell.Fg, fg: true, bold: isBold, t) : colorOf(cell.Bg, fg: false, bold: false, t)
                fg = mix(fg, under, 0.45)
            }
            if x == curX && curShape == 0 && curFocused { fg = Theme.CursorText }
            let px = pad + int32(x) * cellW
            let w = cell.Has(vt.Attr.wide) ? cellW * 2 : cellW
            if cell.Rune > 32 && !cell.Has(vt.Attr.hidden) {
                if isDrawnShape(cell.Rune) {
                    drawShape(c, cell.Rune, px, py, w, cellH, fg, scale: scale)
                } else {
                    drawGlyph(c, cell.Rune, bold: isBold, italic: cell.Has(vt.Attr.italic), x: px, baseline: py + ascent, fg)
                }
            }
            let lineT = max(int32(1), int32(scale.rounded()))
            if cell.Has(vt.Attr.underline) || cell.Has(vt.Attr.curlyUnderline) {
                c.Fill(draw.IRect(px, py + cellH - lineT * 2, w, lineT), fg)
            }
            if cell.Has(vt.Attr.doubleUnderline) {
                c.Fill(draw.IRect(px, py + cellH - lineT * 3, w, lineT), fg)
                c.Fill(draw.IRect(px, py + cellH - lineT, w, lineT), fg)
            }
            if cell.Has(vt.Attr.strike) {
                c.Fill(draw.IRect(px, py + ascent - int32(float32(ascent) * 0.33), w, lineT), fg)
            }
            if cell.Has(vt.Attr.overline) {
                c.Fill(draw.IRect(px, py, w, lineT), fg)
            }
            x += 1
        }
        // The other cursor shapes go over the character.
        if curX >= 0 && curX < cols {
            let px = pad + int32(curX) * cellW
            let w = line.Cells[curX].Has(vt.Attr.wide) ? cellW * 2 : cellW
            let t2 = max(int32(2), int32((scale * 1.5).rounded()))
            if !curFocused {
                let t1 = max(int32(1), int32(scale.rounded()))
                c.Fill(draw.IRect(px, py, w, t1), Theme.Cursor)
                c.Fill(draw.IRect(px, py + cellH - t1, w, t1), Theme.Cursor)
                c.Fill(draw.IRect(px, py, t1, cellH), Theme.Cursor)
                c.Fill(draw.IRect(px + w - t1, py, t1, cellH), Theme.Cursor)
            } else if curShape == 1 {
                c.Fill(draw.IRect(px, py + cellH - t2, w, t2), Theme.Cursor)
            } else if curShape == 2 {
                c.Fill(draw.IRect(px, py, t2, cellH), Theme.Cursor)
            }
        }
    }

    func drawGlyph(_ c: draw.Canvas, _ cp: uint32, bold: bool, italic: bool, x: int32, baseline: int32, _ color: draw.Color) {
        let style: uint64 = (bold ? 1 : 0) | (italic ? 2 : 0)
        let key = uint64(cp) | (style << 32)
        var run: glyphRun
        if let cached = glyphCache[key] {
            run = cached
        } else {
            let face = bold ? (italic ? boldItalic : self.bold) : (italic ? self.italic : regular)
            var b: [uint8] = []
            appendUTF8(&b, cp)
            let shaped = face.Shape(string(decoding: b, as: UTF8.self))
            run = glyphRun(faces: shaped.Faces, glyphs: shaped.Glyphs, advances: shaped.Advances)
            glyphCache[key] = run
        }
        var pen = float32(x)
        var i = 0
        while i < run.glyphs.count {
            if let img = font.GlyphImage(face: run.faces[i], glyph: run.glyphs[i], scale: scale) {
                // An emoji: its own colors.
                let gx = draw.RoundToInt(pen) + img.Left
                c.DrawImage(img.Image, into: draw.IRect(gx, baseline - img.Top, img.Image.Width, img.Image.Height))
                pen += run.advances[i] * scale
                i += 1
                continue
            }
            let g = font.GlyphMask(face: run.faces[i], glyph: run.glyphs[i], scale: scale)
            if !g.IsEmpty {
                c.DrawMask(g.Mask, x: draw.RoundToInt(pen) + g.Left, y: baseline - g.Top, color)
            }
            pen += run.advances[i] * scale
            i += 1
        }
    }
}

func shapeCode(_ s: vt.CursorShape) -> int {
    switch s {
    case .block: return 0
    case .underline: return 1
    case .bar: return 2
    }
}

func appendUTF8(_ out: inout [uint8], _ cp: uint32) {
    if cp < 0x80 {
        out.append(uint8(cp))
    } else if cp < 0x800 {
        out.append(uint8(0xC0 | (cp >> 6)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    } else if cp < 0x10000 {
        out.append(uint8(0xE0 | (cp >> 12)))
        out.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    } else {
        out.append(uint8(0xF0 | (cp >> 18)))
        out.append(uint8(0x80 | ((cp >> 12) & 0x3F)))
        out.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    }
}
