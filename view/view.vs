// Package view draws a vt.Terminal: its cells into RGBA pixels, in a
// monospaced font and a theme, with the cursor, a selection, search
// matches, hyperlinks, sixel images and a scrollbar. It keeps what it
// drew and draws again only the rows that changed, so a frame after one
// line of output costs one row.
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
    "math"
    "terminal/vt"
    "text/font"
)

/// A selection, from one cell to another (ends included), in absolute
/// lines (vt.Terminal.Absolute): it stays on its text as the screen
/// scrolls. A block selection is the rectangle between its corners
/// (Alt-drag) rather than the text between them.
public struct Selection: Equatable {
    public var StartColumn: int
    public var StartLine: int
    public var EndColumn: int
    public var EndLine: int
    public var Block: bool

    public init(startColumn: int, startLine: int, endColumn: int, endLine: int, block: bool = false) {
        StartColumn = startColumn
        StartLine = startLine
        EndColumn = endColumn
        EndLine = endLine
        Block = block
    }

    /// The same selection with its start before its end.
    public var Ordered: Selection {
        if Block {
            return Selection(startColumn: min(StartColumn, EndColumn), startLine: min(StartLine, EndLine),
                             endColumn: max(StartColumn, EndColumn), endLine: max(StartLine, EndLine), block: true)
        }
        if StartLine < EndLine || (StartLine == EndLine && StartColumn <= EndColumn) { return self }
        return Selection(startColumn: EndColumn, startLine: EndLine, endColumn: StartColumn, endLine: StartLine)
    }

    public var IsEmpty: bool { return StartLine == EndLine && StartColumn == EndColumn && !Block }

    /// The columns selected on a line, or nil.
    public func Span(_ line: int, _ columns: int) -> (int, int)? {
        let s = Ordered
        if line < s.StartLine || line > s.EndLine { return nil }
        if Block { return (s.StartColumn, s.EndColumn) }
        let from = line == s.StartLine ? s.StartColumn : 0
        let to = line == s.EndLine ? s.EndColumn : columns - 1
        return from <= to ? (from, to) : nil
    }

    func span(_ line: int, _ columns: int) -> (int, int)? {
        return Span(line, columns)
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

/// The cursor's shapes, as Windows Terminal names them: what a profile
/// sets, and what a program's DECSCUSR replaces.
public enum CursorStyle: Equatable {
    case bar
    case underscore
    case doubleUnderscore
    case filledBox
    case emptyBox
    /// A block of `CursorHeight` percent of the cell, from its bottom.
    case vintage
}

/// What is drawn over the text beyond the selection: search matches, the
/// link under the pointer, the blink phase.
public struct Overlay: Equatable {
    /// Search matches, and the one the search is on.
    public var Highlights: [Selection]
    public var Current: Selection?
    /// The hyperlink under the pointer (its cells underlined solid), or 0.
    public var HoverLink: uint32
    /// A URL found in the text under the pointer (with the modifier
    /// held), underlined.
    public var HoverURL: Selection?
    /// Blinking text's phase: shown or not.
    public var BlinkOn: bool

    public init(highlights: [Selection] = [], current: Selection? = nil, hoverLink: uint32 = 0, hoverURL: Selection? = nil, blinkOn: bool = true) {
        Highlights = highlights
        Current = current
        HoverLink = hoverLink
        HoverURL = hoverURL
        BlinkOn = blinkOn
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
    var marks: [int]
    var images: [int]
    var rendition: int
}

/// Draws terminals. One renderer per view: it keeps the last frame.
public final class Renderer {
    public private(set) var Theme: Theme
    public private(set) var FontFamilies: [string]
    /// The font size, in CSS pixels.
    public private(set) var FontSize: float32
    /// The font's weight for normal text (400), and bold's (700).
    public private(set) var FontWeight: int = 400
    /// Space kept around the grid, in CSS pixels.
    public var Padding: float32 = 6 {
        didSet { scale = 0 }
    }
    /// Extra space between lines, as a fraction of the font's.
    public var LineSpacing: float32 = 1.15 {
        didSet { scale = 0 }
    }
    /// A cell's width, as a fraction of the font's advance.
    public var CellWidthScale: float32 = 1 {
        didSet { scale = 0 }
    }
    /// The cursor's shape where the program hasn't set one, and the
    /// height of the vintage one in percent.
    public var CursorStyle: CursorStyle = .filledBox
    public var CursorHeight = 25
    /// The cursor's color, over the theme's.
    public var CursorColor: draw.Color? = nil
    /// Bold text: in the bold face, and (for colors 0-7) bright.
    public var IntenseBold = true
    public var IntenseBright = true
    /// Foreground colors too close to their background are moved away
    /// from it.
    public var AdjustIndistinguishable = false
    /// The scrollbar's width at the right, in CSS pixels; 0 hides it.
    public var ScrollbarWidth: float32 = 0 {
        didSet { scale = 0 }
    }
    /// Hyperlinks (OSC 8) are underlined with dots until hovered.
    public var UnderlineLinks = true
    /// Blinking text blinks (SGR 5).
    public var BlinkText = true

    var regular: font.Face
    var bold: font.Face
    var italic: font.Face
    var boldItalic: font.Face
    var glyphCache: [uint64: glyphRun] = [:]
    var imageCache: [int: draw.Image] = [:]

    // Metrics at the last scale, in device pixels.
    var scale: float32 = 0
    var cellW: int32 = 8
    var cellH: int32 = 16
    var ascent: int32 = 12
    var pad: int32 = 6
    var barW: int32 = 0

    // The last frame.
    var pixels: [uint8] = []
    var pw = 0
    var ph = 0
    var drawn: [drawnRow?] = []
    var drawnTheme = ""
    var drawnReverse = false
    var drawnPalette = -1
    var drawnBar: [int] = []
    /// Whether the last Draw changed any pixels.
    public private(set) var Drew = false

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
        let w = int32(FontWeight)
        let bw = int32(min(900, max(700, FontWeight + 300)))
        regular = font.Load(font.Spec(families: chosen, size: FontSize, weight: w))
        bold = font.Load(font.Spec(families: chosen, size: FontSize, weight: bw))
        italic = font.Load(font.Spec(families: chosen, size: FontSize, weight: w, italic: true))
        boldItalic = font.Load(font.Spec(families: chosen, size: FontSize, weight: bw, italic: true))
        glyphCache = [:]
        scale = 0
        drawn = []
    }

    /// Changes the font; the grid size changes with it.
    public func SetFont(families: [string]? = nil, size: float32? = nil, weight: int? = nil) {
        if let f = families { FontFamilies = f }
        if let s = size { FontSize = max(6, min(128, s)) }
        if let w = weight { FontWeight = max(100, min(900, w)) }
        loadFaces()
    }

    public func SetTheme(_ theme: Theme) {
        Theme = theme
        drawn = []
    }

    func metrics(_ s: float32) {
        if s == scale { return }
        scale = s
        let adv = regular.Measure("M") * CellWidthScale
        cellW = max(1, int32((adv * s).rounded()))
        let line = (regular.Ascent + regular.Descent) * LineSpacing
        cellH = max(1, int32((line * s).rounded()))
        let extra = float32(cellH) - (regular.Ascent + regular.Descent) * s
        ascent = int32((regular.Ascent * s + extra / 2).rounded())
        pad = int32((Padding * s).rounded())
        barW = int32((ScrollbarWidth * s).rounded())
        drawn = []
    }

    /// One cell's size in CSS pixels at a scale.
    public func CellSize(scale s: float32) -> (Width: float32, Height: float32) {
        metrics(s)
        return (Width: float32(cellW) / s, Height: float32(cellH) / s)
    }

    /// One cell's size in device pixels: what sixel images are drawn in.
    public func CellPixels(scale s: float32) -> (Width: int, Height: int) {
        metrics(s)
        return (Width: int(cellW), Height: int(cellH))
    }

    /// The columns and rows that fit in width × height device pixels.
    public func GridSize(width: int, height: int, scale s: float32) -> (Columns: int, Rows: int) {
        metrics(s)
        let cols = (int32(width) - 2 * pad - barW) / cellW
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

    /// Whether a point (CSS pixels from the view's corner) is on the
    /// scrollbar, for a view width CSS pixels wide.
    public func OnScrollbar(x: float32, width: float32) -> bool {
        return ScrollbarWidth > 0 && x >= width - ScrollbarWidth
    }

    /// The view offset (lines up from the bottom) a point on the
    /// scrollbar stands for: where dragging its thumb there puts it.
    public func ScrollOffsetAt(y: float32, height: float32, _ t: vt.Terminal) -> int {
        let total = t.ScrollbackCount + t.Rows
        if total <= t.Rows || height <= 0 { return 0 }
        let f = max(0, min(1, y / height))
        let top = int(f * float32(total) - float32(t.Rows) / 2)
        let clamped = max(0, min(t.ScrollbackCount, top))
        return t.ScrollbackCount - clamped
    }

    /// Forgets the last frame: the next draws everything.
    public func Invalidate() {
        drawn = []
    }

    // MARK: - Drawing

    /// Draws the terminal's view into width × height device pixels and
    /// answers them (RGBA, premultiplied, top row first).
    public func Draw(_ t: vt.Terminal, width: int, height: int, scale s: float32, cursor: CursorState,
                     selection: Selection? = nil, overlay: Overlay = Overlay()) -> [uint8] {
        metrics(s)
        Drew = false
        if width != pw || height != ph || pixels.count != width * height * 4 {
            pw = width
            ph = height
            pixels = [uint8](repeating: 0, count: max(0, width * height * 4))
            drawn = []
        }
        if width <= 0 || height <= 0 { return pixels }
        let rows = t.Rows
        let all = drawn.count != rows || drawnTheme != Theme.Name || drawnReverse != t.ReverseVideo || drawnPalette != t.PaletteVersion
        if all {
            drawn = [drawnRow?](repeating: nil, count: rows)
            drawnTheme = Theme.Name
            drawnReverse = t.ReverseVideo
            drawnPalette = t.PaletteVersion
            Drew = true
        }
        let bg = defaultBackground(t)
        let top = t.ViewTop
        let cursorRow = t.CursorY + t.ViewOffset
        let showCursor = t.CursorVisible && t.ViewOffset < t.Rows - t.CursorY
        // Search matches by line, for the rows shown.
        var hits: [int: [int]] = [:]
        for h in overlay.Highlights {
            let o = h.Ordered
            if o.EndLine < top || o.StartLine >= top + rows { continue }
            for l in max(top, o.StartLine)...min(top + rows - 1, o.EndLine) {
                if let sp = o.span(l, t.Columns) {
                    var list = hits[l] ?? []
                    let cur = overlay.Current != nil && overlay.Current! == h
                    list.append(contentsOf: [sp.0, sp.1, cur ? 1 : 0])
                    hits[l] = list
                }
            }
        }
        let images = t.ImagesOver(from: top, to: top + rows)
        var me = self
        draw.WithCanvas(&pixels, width: int32(width), height: int32(height)) { c in
            if all {
                c.Clear(bg)
            }
            for y in 0..<rows {
                let line = t.ViewRow(y)
                let abs = top + y
                var sel: [int] = []
                if let s = selection, !s.IsEmpty, let sp = s.span(abs, t.Columns) { sel = [sp.0, sp.1] }
                var cur: [int] = []
                if showCursor && y == cursorRow && cursor.Visible {
                    cur = [t.CursorX, me.cursorCode(t), cursor.Focused ? 1 : 0]
                }
                var marks: [int] = hits[abs] ?? []
                // Links hovered, URLs hovered, the blink phase: what else
                // changes how the row looks.
                if overlay.HoverLink != 0 { marks.append(contentsOf: [-1, int(overlay.HoverLink)]) }
                if let u = overlay.HoverURL, let sp = u.span(abs, t.Columns) { marks.append(contentsOf: [-2, sp.0, sp.1]) }
                if me.BlinkText && !overlay.BlinkOn && hasBlink(line) { marks.append(-3) }
                var ids: [int] = []
                for img in images {
                    let it = t.ImageLine(img)
                    let ir = (img.Height + int(me.cellH) - 1) / max(1, int(me.cellH))
                    if abs >= it && abs < it + ir { ids.append(img.ID) }
                }
                let now = drawnRow(cells: line.Cells, sel: sel, cursor: cur, marks: marks, images: ids, rendition: renditionCode(line.Rendition))
                if !all, let was = me.drawn[y], was == now { continue }
                me.Drew = true
                me.drawLine(c, t, line, y, abs, sel, cur, bg, hits[abs] ?? [], overlay)
                if !ids.isEmpty { me.drawImages(c, t, images, abs, y) }
                me.drawn[y] = now
            }
            // Below the last row: the padding, in the background.
            let used = me.pad + int32(rows) * me.cellH
            if all && used < int32(height) {
                c.Fill(draw.IRect(0, used, int32(width) - me.barW, int32(height) - used), bg)
            }
            if me.barW > 0 { me.drawScrollbar(c, t, overlay, bg, all) }
        }
        return pixels
    }

    func defaultBackground(_ t: vt.Terminal) -> draw.Color {
        var fg = Theme.Foreground
        var bg = Theme.Background
        if let o = t.ForegroundOverride { fg = draw.Color(o.R, o.G, o.B) }
        if let o = t.BackgroundOverride { bg = draw.Color(o.R, o.G, o.B) }
        return t.ReverseVideo ? fg : bg
    }

    func cursorCode(_ t: vt.Terminal) -> int {
        if t.CursorStyleSet {
            switch t.Shape {
            case .block: return 0
            case .underline: return 1
            case .bar: return 2
            }
        }
        switch CursorStyle {
        case .filledBox: return 0
        case .underscore: return 1
        case .bar: return 2
        case .doubleUnderscore: return 3
        case .emptyBox: return 4
        case .vintage: return 5
        }
    }

    func colorOf(_ c: vt.Color, fg: bool, bold: bool, _ t: vt.Terminal) -> draw.Color {
        if c.IsDefault {
            var dfg = Theme.Foreground
            var dbg = Theme.Background
            if let o = t.ForegroundOverride { dfg = draw.Color(o.R, o.G, o.B) }
            if let o = t.BackgroundOverride { dbg = draw.Color(o.R, o.G, o.B) }
            if t.ReverseVideo { return fg ? dbg : dfg }
            return fg ? dfg : dbg
        }
        if c.IsRGB { return draw.Color(c.R, c.G, c.B) }
        var i = c.Index
        if i < 16 && fg && bold && IntenseBright && Theme.BoldIsBright && i < 8 { i += 8 }
        if let o = t.PaletteColor(i) { return draw.Color(o.R, o.G, o.B) }
        if i < 16 { return Theme.ANSI[i] }
        let rgb = vt.PaletteRGB(i)
        return draw.Color(rgb.R, rgb.G, rgb.B)
    }

    /// Draws a row: as it is, or (double width or height) drawn at half
    /// the columns and stretched.
    func drawLine(_ c: draw.Canvas, _ t: vt.Terminal, _ line: vt.Line, _ y: int, _ abs: int, _ sel: [int], _ cur: [int],
                  _ bg: draw.Color, _ hits: [int], _ overlay: Overlay) {
        let py = pad + int32(y) * cellH
        var url: [int] = []
        if let u = overlay.HoverURL, let sp = u.span(abs, t.Columns) { url = [sp.0, sp.1] }
        if line.Rendition == .single {
            var cc = c
            cc.ClipTo(draw.IRect(0, py, c.Width - barW, cellH))
            drawRow(cc, t, line, py, sel, cur, bg, hits, overlay, url)
            return
        }
        // Half the columns, drawn into a strip and stretched twice as
        // wide (and for double height, twice as tall, half of it shown).
        let half = max(1, t.Columns / 2)
        let sw = pad * 2 + int32(half) * cellW
        var strip = [uint8](repeating: 0, count: int(sw) * int(cellH) * 4)
        var cut = line
        if cut.Cells.count > half { cut.Cells.removeLast(cut.Cells.count - half) }
        let me = self
        draw.WithCanvas(&strip, width: sw, height: cellH) { sc in
            me.drawRow(sc, t, cut, 0, sel, cur, bg, hits, overlay, url)
        }
        let img = draw.Image(width: sw, height: cellH, pixels: strip)
        var cc = c
        cc.ClipTo(draw.IRect(0, py, c.Width - barW, cellH))
        cc.Fill(draw.IRect(0, py, c.Width, cellH), bg)
        let dw = sw * 2 - pad
        switch line.Rendition {
        case .doubleTop:
            cc.DrawImage(img, into: draw.IRect(-pad, py, dw, cellH * 2))
        case .doubleBottom:
            cc.DrawImage(img, into: draw.IRect(-pad, py - cellH, dw, cellH * 2))
        default:
            cc.DrawImage(img, into: draw.IRect(-pad, py, dw, cellH))
        }
    }

    func drawRow(_ c: draw.Canvas, _ t: vt.Terminal, _ line: vt.Line, _ py: int32, _ sel: [int], _ cur: [int],
                 _ bg: draw.Color, _ hits: [int], _ overlay: Overlay, _ url: [int]) {
        // The row's whole width, padding included, starts as background.
        c.Fill(draw.IRect(0, py, c.Width, cellH), bg)
        let cols = min(t.Columns, line.Cells.count)
        let curX = cur.isEmpty ? -1 : cur[0]
        let curShape = cur.isEmpty ? 0 : cur[1]
        let curFocused = !cur.isEmpty && cur[2] == 1
        let cursorColor = CursorColor ?? (t.CursorOverride.map { draw.Color($0.R, $0.G, $0.B) } ?? Theme.Cursor)
        // A filled cursor: a block over the cell, the text in CursorText.
        let filled = curFocused && (curShape == 0 || curShape == 5)
        // Backgrounds first, so glyphs that overhang aren't painted over.
        var x = 0
        while x < cols {
            let cell = line.Cells[x]
            var cbg = colorOf(cell.Bg, fg: false, bold: false, t)
            if cell.Has(vt.Attr.inverse) { cbg = colorOf(cell.Fg, fg: true, bold: cell.Has(vt.Attr.bold), t) }
            var h = 0
            while h + 2 < hits.count {
                if x >= hits[h] && x <= hits[h + 1] { cbg = hits[h + 2] == 1 ? Theme.SearchCurrent : Theme.SearchMatch }
                h += 3
            }
            if !sel.isEmpty && x >= sel[0] && x <= sel[1] { cbg = Theme.Selection }
            if cbg != bg {
                c.Fill(draw.IRect(pad + int32(x) * cellW, py, cellW, cellH), cbg)
            }
            x += 1
        }
        // The cursor's block goes under its character.
        if curX >= 0 && curX < cols && filled {
            let w = line.Cells[curX].Has(vt.Attr.wide) ? cellW * 2 : cellW
            if curShape == 5 {
                let ch = max(int32(1), cellH * int32(max(1, min(100, CursorHeight))) / 100)
                c.Fill(draw.IRect(pad + int32(curX) * cellW, py + cellH - ch, w, ch), cursorColor)
            } else {
                c.Fill(draw.IRect(pad + int32(curX) * cellW, py, w, cellH), cursorColor)
            }
        }
        let lineT = max(int32(1), int32(scale.rounded()))
        x = 0
        while x < cols {
            let cell = line.Cells[x]
            if cell.Has(vt.Attr.spacer) {
                x += 1
                continue
            }
            let isBold = cell.Has(vt.Attr.bold)
            var fg = colorOf(cell.Fg, fg: true, bold: isBold, t)
            var under = colorOf(cell.Bg, fg: false, bold: false, t)
            if cell.Has(vt.Attr.inverse) {
                fg = colorOf(cell.Bg, fg: false, bold: false, t)
                under = colorOf(cell.Fg, fg: true, bold: isBold, t)
            }
            if cell.Has(vt.Attr.dim) {
                fg = mix(fg, under, 0.45)
            }
            if AdjustIndistinguishable && !cell.Has(vt.Attr.hidden) { fg = distinguishable(fg, from: under) }
            if x == curX && filled && curShape == 0 { fg = Theme.CursorText }
            let px = pad + int32(x) * cellW
            let w = cell.Has(vt.Attr.wide) ? cellW * 2 : cellW
            let hiddenByBlink = cell.Has(vt.Attr.blink) && BlinkText && !overlay.BlinkOn
            if cell.Rune > 32 && !cell.Has(vt.Attr.hidden) && !hiddenByBlink {
                if isDrawnShape(cell.Rune) {
                    drawShape(c, cell.Rune, px, py, w, cellH, fg, scale: scale)
                } else {
                    drawGlyph(c, cell.Rune, bold: isBold && IntenseBold, italic: cell.Has(vt.Attr.italic), x: px, baseline: py + ascent, fg)
                }
            }
            let ul = cell.Ul.IsDefault ? fg : colorOf(cell.Ul, fg: true, bold: false, t)
            let uy = py + cellH - lineT * 2
            if cell.Has(vt.Attr.underline) {
                c.Fill(draw.IRect(px, uy, w, lineT), ul)
            }
            if cell.Has(vt.Attr.doubleUnderline) {
                c.Fill(draw.IRect(px, py + cellH - lineT * 3, w, lineT), ul)
                c.Fill(draw.IRect(px, py + cellH - lineT, w, lineT), ul)
            }
            if cell.Has(vt.Attr.curlyUnderline) { drawCurly(c, px, w, py + cellH - lineT * 2, lineT, ul) }
            if cell.Has(vt.Attr.dottedUnderline) { drawDashes(c, px, w, uy, lineT, on: lineT, off: lineT, ul) }
            if cell.Has(vt.Attr.dashedUnderline) { drawDashes(c, px, w, uy, lineT, on: lineT * 3, off: lineT * 2, ul) }
            if cell.Link != 0 && !cell.Has(vt.Attr.anyUnderline) {
                if cell.Link == overlay.HoverLink {
                    c.Fill(draw.IRect(px, uy, w, lineT), fg)
                } else if UnderlineLinks {
                    drawDashes(c, px, w, uy, lineT, on: lineT, off: lineT, fg)
                }
            }
            if cell.Has(vt.Attr.strike) {
                c.Fill(draw.IRect(px, py + ascent - int32(float32(ascent) * 0.33), w, lineT), fg)
            }
            if cell.Has(vt.Attr.overline) {
                c.Fill(draw.IRect(px, py, w, lineT), fg)
            }
            x += 1
        }
        // A URL under the pointer: underlined across its cells.
        if url.count == 2 {
            let from = max(0, url[0])
            let to = min(cols - 1, url[1])
            if from <= to {
                let fg = colorOf(line.Cells[from].Fg, fg: true, bold: false, t)
                c.Fill(draw.IRect(pad + int32(from) * cellW, py + cellH - lineT * 2, int32(to - from + 1) * cellW, lineT), fg)
            }
        }
        // The other cursor shapes go over the character.
        if curX >= 0 && curX < cols {
            let px = pad + int32(curX) * cellW
            let w = line.Cells[curX].Has(vt.Attr.wide) ? cellW * 2 : cellW
            let t2 = max(int32(2), int32((scale * 1.5).rounded()))
            let t1 = max(int32(1), int32(scale.rounded()))
            if !curFocused || curShape == 4 {
                c.Fill(draw.IRect(px, py, w, t1), cursorColor)
                c.Fill(draw.IRect(px, py + cellH - t1, w, t1), cursorColor)
                c.Fill(draw.IRect(px, py, t1, cellH), cursorColor)
                c.Fill(draw.IRect(px + w - t1, py, t1, cellH), cursorColor)
            } else if curShape == 1 {
                c.Fill(draw.IRect(px, py + cellH - t2, w, t2), cursorColor)
            } else if curShape == 2 {
                c.Fill(draw.IRect(px, py, t2, cellH), cursorColor)
            } else if curShape == 3 {
                c.Fill(draw.IRect(px, py + cellH - t1, w, t1), cursorColor)
                c.Fill(draw.IRect(px, py + cellH - t1 * 3 - 1, w, t1), cursorColor)
            }
        }
    }

    /// A wavy underline: half a wave per cell's width.
    func drawCurly(_ c: draw.Canvas, _ x: int32, _ w: int32, _ y: int32, _ t: int32, _ color: draw.Color) {
        let amp = float32(max(int32(1), t))
        let period = float32(max(int32(4), cellW))
        var i: int32 = 0
        while i < w {
            let phase = float32(x + i) / period * 2 * float32(math.Pi)
            let dy = int32((math.Sin(phase) * amp).rounded())
            c.Fill(draw.IRect(x + i, y + dy - t / 2, 1, t), color)
            i += 1
        }
    }

    /// A dotted or dashed underline: on, then off, from the cell's edge so
    /// the pattern runs on across cells.
    func drawDashes(_ c: draw.Canvas, _ x: int32, _ w: int32, _ y: int32, _ t: int32, on: int32, off: int32, _ color: draw.Color) {
        let period = on + off
        var i: int32 = 0
        while i < w {
            let p = (x + i) % period
            if p < on {
                let run = min(on - p, w - i)
                c.Fill(draw.IRect(x + i, y, run, t), color)
                i += run
            } else {
                i += period - p
            }
        }
    }

    func drawImages(_ c: draw.Canvas, _ t: vt.Terminal, _ images: [vt.Image], _ abs: int, _ y: int) {
        let py = pad + int32(y) * cellH
        var cc = c
        cc.ClipTo(draw.IRect(pad, py, c.Width - pad - barW, cellH))
        for img in images {
            let top = t.ImageLine(img)
            let rows = (img.Height + int(cellH) - 1) / max(1, int(cellH))
            if abs < top || abs >= top + rows { continue }
            var di = imageCache[img.ID]
            if di == nil {
                let made = draw.Image(width: int32(img.Width), height: int32(img.Height), pixels: img.Pixels)
                if imageCache.count > 64 { imageCache = [:] }
                imageCache[img.ID] = made
                di = made
            }
            let ix = pad + int32(img.Column) * cellW
            let iy = pad + int32(top - t.ViewTop) * cellH
            cc.DrawImage(di!, into: draw.IRect(ix, iy, int32(img.Width), int32(img.Height)))
        }
    }

    /// The scrollbar: a track, a thumb for what is shown, and ticks for
    /// the shell's prompts (red where a command failed) and search
    /// matches.
    func drawScrollbar(_ c: draw.Canvas, _ t: vt.Terminal, _ overlay: Overlay, _ bg: draw.Color, _ all: bool) {
        let total = t.ScrollbackCount + t.Rows
        let h = c.Height
        let state = [t.ScrollbackCount, t.ViewOffset, t.Rows, overlay.Highlights.count, t.Version, int(h)]
        if !all && state == drawnBar { return }
        drawnBar = state
        Drew = true
        let x = c.Width - barW
        let dark = luminance(bg) < 0.5
        let track = mix(bg, dark ? hex(0xFFFFFF) : hex(0x000000), 0.04)
        let thumbColor = mix(bg, dark ? hex(0xFFFFFF) : hex(0x000000), 0.28)
        c.Fill(draw.IRect(x, 0, barW, h), track)
        if total <= t.Rows && overlay.Highlights.isEmpty { return }
        let top = t.ScrollbackCount - t.ViewOffset
        let thumbY = int32(float32(top) / float32(total) * float32(h))
        let thumbH = max(int32(8), int32(float32(t.Rows) / float32(total) * float32(h)))
        let inset = max(int32(1), barW / 4)
        c.FillRounded(draw.IRect(x + inset, thumbY, barW - inset * 2, min(thumbH, h - thumbY)),
                      radii: draw.Radii(all: float32(barW / 3)), thumbColor)
        // Marks: a tick per prompt, and per search match.
        let tick = max(int32(2), int32(scale.rounded()) * 2)
        for m in t.Marks() where m.Mark == .prompt {
            let my = int32(float32(m.Line) / float32(total) * float32(h))
            let color = m.ExitCode > 0 ? hex(0xE5484D) : (m.ExitCode == 0 ? hex(0x3FB950) : Theme.Cursor)
            c.Fill(draw.IRect(x, my, barW / 2, tick), color)
        }
        for hl in overlay.Highlights {
            let my = int32(float32(hl.StartLine) / float32(total) * float32(h))
            c.Fill(draw.IRect(x + barW / 2, my, barW - barW / 2, tick), Theme.SearchCurrent)
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
            let shaped = face.Shape(vt.RuneText(cp))
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

func hasBlink(_ line: vt.Line) -> bool {
    for c in line.Cells where c.Has(vt.Attr.blink) { return true }
    return false
}

func renditionCode(_ r: vt.Rendition) -> int {
    switch r {
    case .single: return 0
    case .doubleWidth: return 1
    case .doubleTop: return 2
    case .doubleBottom: return 3
    }
}
