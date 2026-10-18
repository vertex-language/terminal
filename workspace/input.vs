package workspace

import (
    "terminal/view"
    "terminal/vt"
    "ui/app"
    "ui/window"
    "web/dom"
)

extension Controller {
    // MARK: - Keys

    func KeyDown(_ e: dom.KeyboardEvent) {
        lastKeyControl = e.Control
        guard let pane = currentPane else { return }
        let shell = pane.shell
        let term = shell.term
        swallowText = false
        if ui.Overlay { return }
        if markMode && markKey(e) {
            e.PreventDefault()
            return
        }
        let chord = chordOf(code: e.Code, key: e.Key, shift: e.Shift, control: e.Control, alt: e.Alt, meta: e.Meta)
        // A pane whose program ended: Enter starts it again.
        if shell.Exited && chord.Key == "enter" && !e.Shift && !e.Control && !e.Alt && !e.Meta {
            shell.Restart()
            e.PreventDefault()
            return
        }
        if let a = settings.ActionFor(chord), Run(a) {
            e.PreventDefault()
            return
        }
        // Escape takes a selection away first, as Windows Terminal does.
        if e.Key == "Escape" && shell.selection != nil && !e.Shift && !e.Control && !e.Alt && !e.Meta {
            shell.selection = nil
            redraw()
            e.PreventDefault()
            return
        }
        if e.Meta { return }
        let mods = vt.Modifiers(shift: e.Shift, alt: e.Alt, control: e.Control, meta: e.Meta)
        if let bytes = term.EncodeKey(key: e.Key, code: e.Code, mods, altSendsEscape: optionAsMeta) {
            e.PreventDefault()
            // The key's text would follow as typing: it was sent already.
            // Control keys bring no text; Option as Meta and the kitty
            // protocol's plain keys do.
            let printable = e.Key.unicodeScalars.count == 1 && !e.Control
            if (e.Alt && optionAsMeta) || (term.KittyFlags != 0 && printable) { swallowText = true }
            if pane.profile.AutoMarkPrompts && e.Key == "Enter" { term.AddMark() }
            typed(pane, bytes)
        }
    }

    func KeyUp(_ e: dom.KeyboardEvent) {
        lastKeyControl = e.Control
        if e.Key == "Control" { SwitcherRelease() }
    }

    func BeforeInput(_ e: dom.InputEvent) {
        if swallowText {
            swallowText = false
            return
        }
        guard let pane = currentPane, !markMode else { return }
        typed(pane, pane.shell.term.EncodeText(e.Data))
    }

    /// Sends what the user typed: the view goes back to the screen, the
    /// selection goes, and the cursor shows. Broadcast sends it to every
    /// pane of the tab; a read-only pane takes nothing.
    func typed(_ pane: Pane, _ bytes: [uint8]) {
        if pane.ReadOnly {
            toast("This pane is read-only (\(settings.KeysFor("Terminal.ToggleReadOnlyMode").isEmpty ? "command palette: Toggle pane read-only mode" : settings.KeysFor("Terminal.ToggleReadOnlyMode")))")
            return
        }
        var targets = [pane]
        if let tab = ws.TabOf(pane: pane.ID), tab.Broadcast {
            targets = tab.Panes.filter { !$0.ReadOnly }
        }
        for p in targets {
            if p.profile.SnapOnInput { p.shell.term.ScrollToBottom() }
            p.shell.selection = nil
            p.shell.Send(bytes)
            p.dirty = true
        }
        blinkOn = true
        blinkEpoch += 1
        hoverURL = nil
        redraw()
    }

    /// A paste: warned about where it is long or has several lines (and
    /// the program didn't ask for bracketed paste), trimmed of trailing
    /// space where it is one line.
    func paste(_ pane: Pane, _ textIn: string) {
        var text = textIn
        if text.isEmpty { return }
        if settings.TrimPaste && !text.contains("\n") { text = trimmed(text) }
        let multi = text.contains("\n") && !pane.shell.term.BracketedPaste
        let large = text.utf8.count > 5 * 1024
        if (multi && settings.MultiLinePasteWarning) || (large && settings.LargePasteWarning) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            let what = large ? "\(text.utf8.count / 1024) KiB of text" : "\(lines) lines"
            openDialog(title: "Paste \(what)?",
                       body: multi ? "Pasting several lines can run them as commands, one after another." : "That is a lot of text to paste at once.",
                       buttons: [("Paste anyway", { self.typed(pane, pane.shell.term.EncodePaste(text)) }), ("Cancel", {})])
            return
        }
        typed(pane, pane.shell.term.EncodePaste(text))
    }

    func copySelection(_ shell: Shell) {
        guard let s = shell.selection, !s.IsEmpty else { return }
        let text = selectionText(shell, s)
        if !text.isEmpty { window.SetClipboardText(text) }
    }

    /// A selection's text; a block selection row by row, trimmed where
    /// the settings ask.
    func selectionText(_ shell: Shell, _ selIn: view.Selection) -> string {
        let s = selIn.Ordered
        let t = shell.term
        if s.Block {
            var rows: [string] = []
            for l in s.StartLine...s.EndLine {
                var r = t.Text(fromColumn: s.StartColumn, line: l, toColumn: s.EndColumn, line: l)
                if settings.TrimBlockSelection { r = trimRight(r) }
                rows.append(r)
            }
            return rows.joined(separator: "\n")
        }
        return t.Text(fromColumn: s.StartColumn, line: s.StartLine, toColumn: s.EndColumn, line: s.EndLine)
    }

    func Focus(_ on: bool) {
        focused = on
        blinkOn = true
        if on, let tab = ws.Current { tab.Bell = false }
        if let shell = current, let report = shell.term.EncodeFocus(on) { shell.Send(report) }
        if let p = currentPane { p.dirty = true }
        redraw()
    }

    // MARK: - Mark mode

    func toggleMarkMode() {
        guard let s = current else { return }
        markMode = !markMode
        if markMode {
            let t = s.term
            markColumn = t.CursorX
            markLine = t.ScrollbackCount + t.CursorY
            if let sel = s.selection, !sel.IsEmpty {
                markColumn = sel.EndColumn
                markLine = sel.EndLine
            }
            markAnchorColumn = markColumn
            markAnchorLine = markLine
            markSelecting = false
            s.selection = nil
            toast("Mark mode: arrows move, ⇧ selects, ↩ copies, ⎋ leaves")
        }
        redraw()
    }

    /// A key in mark mode; true where it was mark mode's.
    func markKey(_ e: dom.KeyboardEvent) -> bool {
        guard let s = current else { return false }
        let t = s.term
        let last = t.ScrollbackCount + t.Rows - 1
        var moved = true
        switch e.Key {
        case "ArrowLeft":
            if e.Control || e.Alt {
                let w = wordAt(t, max(0, markColumn - 1), markLine, settings.WordDelimiters)
                markColumn = max(0, w.0 == markColumn ? markColumn - 1 : w.0)
            } else {
                markColumn = max(0, markColumn - 1)
            }
        case "ArrowRight":
            if e.Control || e.Alt {
                let w = wordAt(t, min(t.Columns - 1, markColumn + 1), markLine, settings.WordDelimiters)
                markColumn = min(t.Columns - 1, w.1 == markColumn ? markColumn + 1 : w.1)
            } else {
                markColumn = min(t.Columns - 1, markColumn + 1)
            }
        case "ArrowUp": markLine = max(0, markLine - 1)
        case "ArrowDown": markLine = min(last, markLine + 1)
        case "PageUp": markLine = max(0, markLine - t.Rows)
        case "PageDown": markLine = min(last, markLine + t.Rows)
        case "Home": markColumn = 0
        case "End": markColumn = t.Columns - 1
        case "Enter":
            copySelection(s)
            s.selection = nil
            markMode = false
            redraw()
            return true
        case "Escape":
            s.selection = nil
            markMode = false
            redraw()
            return true
        default:
            moved = false
        }
        if !moved {
            if e.Key == "a" && e.Control {
                _ = Run(settings.Actions["Terminal.SelectAll"] ?? Action())
                return true
            }
            // Other keys (⌘ shortcuts) go on; typing doesn't reach the shell.
            return !e.Meta
        }
        if e.Shift {
            if !markSelecting {
                markSelecting = true
            }
            s.selection = view.Selection(startColumn: markAnchorColumn, startLine: markAnchorLine, endColumn: markColumn, endLine: markLine, block: e.Alt)
        } else {
            markSelecting = false
            markAnchorColumn = markColumn
            markAnchorLine = markLine
            s.selection = nil
        }
        // The view follows the mark.
        if markLine < t.ViewTop { t.ScrollView(by: t.ViewTop - markLine) }
        if markLine >= t.ViewTop + t.Rows { t.ScrollView(by: -(markLine - (t.ViewTop + t.Rows - 1))) }
        redraw()
        return true
    }

    // MARK: - The pointer

    /// The point in device pixels in the surface.
    func devicePoint(_ x: float32, _ y: float32) -> (int, int) {
        let o = handle?.Origin ?? (X: 0, Y: 0)
        return (int((x - o.X) * scale), int((y - o.Y) * scale))
    }

    /// The pane under a point (CSS pixels in the window).
    func paneAt(_ x: float32, _ y: float32) -> Pane? {
        guard let tab = ws.Current else { return nil }
        let (px, py) = devicePoint(x, y)
        if tab.Zoomed != 0 { return tab.root.Find(tab.Zoomed)?.pane }
        for p in tab.Panes where p.Contains(px, py) { return p }
        return nil
    }

    /// The divider under a point, for dragging.
    func dividerAt(_ x: float32, _ y: float32) -> PaneNode? {
        guard let tab = ws.Current, tab.Zoomed == 0 else { return nil }
        let (px, py) = devicePoint(x, y)
        let slop = int(4 * scale)
        for n in tab.root.Splits {
            if n.vertical {
                if px >= n.divX - slop && px <= n.divX + n.divW + slop && py >= n.divY && py < n.divY + n.divH { return n }
            } else {
                if py >= n.divY - slop && py <= n.divY + n.divH + slop && px >= n.divX && px < n.divX + n.divW { return n }
            }
        }
        return nil
    }

    /// The cell under a point in a pane.
    func cellAt(_ pane: Pane, _ x: float32, _ y: float32) -> (Column: int, Row: int, Right: bool) {
        let o = handle?.Origin ?? (X: 0, Y: 0)
        let t = pane.shell.term
        let lx = x - o.X - float32(pane.X) / scale
        let ly = y - o.Y - float32(pane.Y) / scale
        return pane.renderer.CellAt(x: lx, y: ly, scale: scale, columns: t.Columns, rows: t.Rows)
    }

    func localPoint(_ pane: Pane, _ x: float32, _ y: float32) -> (float32, float32) {
        let o = handle?.Origin ?? (X: 0, Y: 0)
        return (x - o.X - float32(pane.X) / scale, y - o.Y - float32(pane.Y) / scale)
    }

    func mods(_ e: dom.MouseEvent) -> vt.Modifiers {
        return vt.Modifiers(shift: e.Shift, alt: e.Alt, control: e.Control, meta: e.Meta)
    }

    func PointerDown(_ e: dom.PointerEvent) {
        e.PreventDefault()
        focusSurface()
        if ui.Menu { closeMenu() }
        pointerX = e.X
        pointerY = e.Y
        if let d = dividerAt(e.X, e.Y) {
            draggingDivider = d
            return
        }
        guard let pane = paneAt(e.X, e.Y) else { return }
        if let tab = ws.Current, tab.Focused != pane.ID { FocusPane(pane.ID) }
        let shell = pane.shell
        let term = shell.term
        let (lx, ly) = localPoint(pane, e.X, e.Y)
        if pane.renderer.OnScrollbar(x: lx, width: float32(pane.W) / scale) {
            draggingScrollbar = pane.ID
            let off = pane.renderer.ScrollOffsetAt(y: ly, height: float32(pane.H) / scale, term)
            term.ScrollView(by: off - term.ViewOffset)
            redraw()
            return
        }
        let cell = cellAt(pane, e.X, e.Y)
        // ⌘-click opens a link (OSC 8) or a URL in the text.
        if e.Meta && e.Button == 0 {
            if let target = linkAt(pane, cell.Column, cell.Row) {
                openExternal(target)
                return
            }
        }
        // The right button: the menu, or copy-else-paste.
        if e.Button == 2 && (term.Mouse == .off || e.Shift) {
            if pane.profile.RightClickContextMenu {
                openContextMenu(x: e.X, y: e.Y)
            } else if !SelectedText().isEmpty {
                copySelection(shell)
                shell.selection = nil
                redraw()
            } else {
                paste(pane, window.ClipboardText())
            }
            return
        }
        // Shift takes the mouse back from a program that asked for it, to
        // select, as xterm has it.
        mouseReported = term.Mouse != .off && !e.Shift
        if mouseReported {
            mouseButton = int(e.Button)
            let (px, py) = (int(lx * scale) - int(pane.renderer.Padding * scale), int(ly * scale) - int(pane.renderer.Padding * scale))
            if let b = term.EncodeMouse(button: mouseButton, column: cell.Column, row: cell.Row, kind: "press", mods(e), pixelX: max(0, px), pixelY: max(0, py)) {
                shell.Send(b)
            }
            return
        }
        if markMode {
            markMode = false
        }
        let line = term.ViewTop + cell.Row
        if e.Button != 0 { return }
        selectingPane = pane.ID
        blockSelect = e.Alt
        if e.Clicks >= 3 {
            // The whole line, joined with the rows it wrapped onto.
            var a = line
            while a > 0 && term.Absolute(a - 1).Wrapped { a -= 1 }
            var b = line
            while term.Absolute(b).Wrapped && b < term.ScrollbackCount + term.Rows - 1 { b += 1 }
            shell.selection = view.Selection(startColumn: 0, startLine: a, endColumn: term.Columns - 1, endLine: b)
            selecting = false
        } else if e.Clicks == 2 {
            let w = wordAt(term, cell.Column, line, settings.WordDelimiters)
            shell.selection = view.Selection(startColumn: w.0, startLine: line, endColumn: w.1, endLine: line)
            selecting = false
        } else if e.Shift, let sel = shell.selection, !sel.IsEmpty {
            // Shift-click moves the selection's end here.
            let o = sel.Ordered
            shell.selection = view.Selection(startColumn: o.StartColumn, startLine: o.StartLine, endColumn: cell.Column, endLine: line, block: sel.Block)
            anchorColumn = o.StartColumn
            anchorLine = o.StartLine
            selecting = true
        } else {
            shell.selection = nil
            anchorColumn = cell.Column
            anchorLine = line
            selecting = true
        }
        redraw()
    }

    func PointerMove(_ e: dom.PointerEvent) {
        pointerX = e.X
        pointerY = e.Y
        if let d = draggingDivider {
            let (px, py) = devicePoint(e.X, e.Y)
            if d.vertical {
                d.ratio = max(0.05, min(0.95, float32(px - d.spanX) / float32(max(1, d.spanW))))
            } else {
                d.ratio = max(0.05, min(0.95, float32(py - d.spanY) / float32(max(1, d.spanH))))
            }
            frameAll = true
            redraw()
            return
        }
        if draggingScrollbar != 0, let pane = ws.PaneByID(draggingScrollbar) {
            let (_, ly) = localPoint(pane, e.X, e.Y)
            let t = pane.shell.term
            let off = pane.renderer.ScrollOffsetAt(y: ly, height: float32(pane.H) / scale, t)
            t.ScrollView(by: off - t.ViewOffset)
            redraw()
            return
        }
        guard let pane = paneAt(e.X, e.Y) else { return }
        if settings.FocusFollowMouse && !e.Pressed, let tab = ws.Current, tab.Focused != pane.ID {
            FocusPane(pane.ID)
        }
        let shell = pane.shell
        let term = shell.term
        updateHover(pane, e)
        // Movement goes to the program during its own press, or with no
        // button held where it asked for all motion; a Shift press is a
        // selection.
        if term.Mouse != .off && (mouseReported || (!e.Pressed && !selecting)) {
            if term.Mouse == .motion || (e.Pressed && mouseButton >= 0) {
                let cell = cellAt(pane, e.X, e.Y)
                if let b = term.EncodeMouse(button: e.Pressed ? mouseButton : -1, column: cell.Column, row: cell.Row, kind: "move", mods(e)) {
                    shell.Send(b)
                }
            }
            return
        }
        if !selecting || !e.Pressed || pane.ID != selectingPane { return }
        let cell = cellAt(pane, e.X, e.Y)
        // Dragging past the top or bottom scrolls.
        let (_, ly) = localPoint(pane, e.X, e.Y)
        if ly < 0 { term.ScrollView(by: 1) }
        if ly > float32(pane.H) / scale { term.ScrollView(by: -1) }
        let line = term.ViewTop + cell.Row
        if blockSelect || e.Alt {
            shell.selection = view.Selection(startColumn: anchorColumn, startLine: anchorLine, endColumn: cell.Column, endLine: line, block: true)
            redraw()
            return
        }
        var endCol = cell.Column
        let forward = line > anchorLine || (line == anchorLine && cell.Column >= anchorColumn)
        // The edge rounds to the nearer side of the cell under the pointer.
        if forward && !cell.Right { endCol -= 1 }
        var startCol = anchorColumn
        if !forward && cell.Right { endCol += 1 }
        if !forward { startCol = max(0, anchorColumn - 1) }
        if forward && line == anchorLine && endCol < anchorColumn {
            shell.selection = nil
        } else {
            shell.selection = view.Selection(startColumn: startCol, startLine: anchorLine, endColumn: max(0, endCol), endLine: line)
        }
        redraw()
    }

    func PointerUp(_ e: dom.PointerEvent) {
        if draggingDivider != nil || draggingScrollbar != 0 {
            draggingDivider = nil
            draggingScrollbar = 0
            return
        }
        guard let shell = current else { return }
        let term = shell.term
        if mouseReported && mouseButton >= 0, let pane = currentPane {
            let cell = cellAt(pane, e.X, e.Y)
            if let b = term.EncodeMouse(button: mouseButton, column: cell.Column, row: cell.Row, kind: "release", mods(e)) {
                shell.Send(b)
            }
            mouseButton = -1
            mouseReported = false
            return
        }
        mouseReported = false
        if selecting && settings.CopyOnSelect { copySelection(shell) }
        if !selecting && settings.CopyOnSelect, let sel = shell.selection, !sel.IsEmpty { copySelection(shell) }
        selecting = false
    }

    /// The link under the pointer: an OSC 8 hyperlink's cells, or (with
    /// ⌘ held, as Windows Terminal's Ctrl) a URL found in the text.
    func updateHover(_ pane: Pane, _ e: dom.PointerEvent) {
        let cell = cellAt(pane, e.X, e.Y)
        let t = pane.shell.term
        let line = t.ViewTop + cell.Row
        let c = cell.Column < t.Columns ? t.Absolute(line).Cells[cell.Column] : vt.Cell.blank
        let link: uint32 = c.Link
        var url: view.Selection? = nil
        var text = link != 0 ? vt.LinkURI(link) : ""
        if link == 0 && settings.DetectURLs && e.Meta {
            if let u = urlAt(t, cell.Column, line) {
                url = view.Selection(startColumn: u.0, startLine: line, endColumn: u.1, endLine: line)
                text = u.2
            }
        }
        if !e.Meta && link == 0 { text = "" }
        if link != hoverLink || url != hoverURL {
            hoverLink = link
            hoverURL = url
            pane.dirty = true
            redraw()
        }
        if text != hoverText {
            hoverText = text
            ui.Hover = text.isEmpty ? "" : (link != 0 ? text + "  — ⌘-click to open" : text)
        }
    }

    /// What ⌘-click at a cell opens: its hyperlink, or a URL in the text.
    func linkAt(_ pane: Pane, _ col: int, _ row: int) -> string? {
        let t = pane.shell.term
        let line = t.ViewTop + row
        let cells = t.Absolute(line).Cells
        if col < cells.count && cells[col].Link != 0 { return vt.LinkURI(cells[col].Link) }
        if settings.DetectURLs, let u = urlAt(t, col, line) { return u.2 }
        return nil
    }

    func Wheel(_ e: dom.WheelEvent) {
        e.PreventDefault()
        guard let pane = paneAt(e.X, e.Y) ?? currentPane else { return }
        let shell = pane.shell
        let term = shell.term
        // ⌘ with the wheel: the font size; ⌘⇧: the opacity (Windows
        // Terminal's Ctrl and Ctrl+Shift).
        if e.Meta && settings.ScrollToZoom && !e.Shift {
            wheel += e.DeltaY
            if abs(wheel) >= 30 {
                pane.renderer.SetFont(size: pane.renderer.FontSize + (wheel < 0 ? 1 : -1))
                wheel = 0
                pane.dirty = true
                frameAll = true
                redraw()
            }
            return
        }
        if e.Meta && e.Shift && settings.ScrollToChangeOpacity {
            wheel += e.DeltaY
            if abs(wheel) >= 30 {
                pane.profile.Opacity = max(5, min(100, pane.profile.Opacity + (wheel < 0 ? 5 : -5)))
                wheel = 0
                applyOpacity()
            }
            return
        }
        let lineH = pane.renderer.CellSize(scale: scale).Height
        wheel += e.DeltaY
        var lines = int(wheel / lineH)
        if lines == 0 { return }
        wheel -= float32(lines) * lineH
        // rowsToScroll: lines per notch, where the system's is 3.
        if settings.RowsToScroll > 0 {
            let scaled = lines * settings.RowsToScroll / 3
            lines = scaled != 0 ? scaled : (lines > 0 ? 1 : -1)
        }
        if term.Mouse != .off && !e.Shift {
            let cell = cellAt(pane, e.X, e.Y)
            let m = vt.Modifiers(shift: e.Shift, alt: e.Alt, control: e.Control, meta: e.Meta)
            for _ in 0..<abs(lines) {
                if let b = term.EncodeMouse(button: lines < 0 ? 64 : 65, column: cell.Column, row: cell.Row, kind: "press", m) {
                    shell.Send(b)
                }
            }
        } else if term.AltScreen && term.AlternateScroll {
            let key = lines < 0 ? "ArrowUp" : "ArrowDown"
            for _ in 0..<abs(lines) {
                if let b = term.EncodeKey(key: key, code: key, vt.Modifiers()) { shell.Send(b) }
            }
        } else {
            term.ScrollView(by: -lines)
            redraw()
        }
    }
}

/// The word around a cell: the run of characters that aren't spaces or
/// the settings' word delimiters.
func wordAt(_ term: vt.Terminal, _ col: int, _ line: int, _ delimiters: string = " ") -> (int, int) {
    let cells = term.Absolute(line).Cells
    var stops: [uint32] = []
    for u in delimiters.unicodeScalars { stops.append(uint32(u.value)) }
    func isWord(_ i: int) -> bool {
        let r = cells[i].Rune
        if r == 0 || r == 32 { return false }
        if cells[i].Has(vt.Attr.spacer) { return true }
        return !stops.contains(r)
    }
    if col >= cells.count || !isWord(col) { return (col, col) }
    var a = col
    var b = col
    while a > 0 && isWord(a - 1) { a -= 1 }
    while b + 1 < cells.count && isWord(b + 1) { b += 1 }
    return (a, b)
}

/// A URL in a line's text around a column: its first and last column,
/// and the URL. http, https, file, ftp and mailto, as Windows Terminal
/// finds them.
func urlAt(_ term: vt.Terminal, _ col: int, _ line: int) -> (int, int, string)? {
    let cells = term.Absolute(line).Cells
    var chars: [uint8] = []
    var cols: [int] = []
    for x in 0..<cells.count {
        let c = cells[x]
        if c.Has(vt.Attr.spacer) { continue }
        let r = c.Rune
        chars.append(r > 0x20 && r < 0x7F ? uint8(r) : 0x20)
        cols.append(x)
    }
    let s = string(decoding: chars, as: UTF8.self)
    let prefixes = ["https://", "http://", "file://", "ftp://", "mailto:"]
    var start = 0
    while start < chars.count {
        // The next URL start.
        var found = -1
        var i = start
        while i < chars.count && found < 0 {
            for p in prefixes {
                let pb = [uint8](p.utf8)
                if i + pb.count <= chars.count {
                    var ok = true
                    for k in 0..<pb.count where chars[i + k] != pb[k] { ok = false }
                    if ok && (i == 0 || !isURLChar(chars[i - 1]) || chars[i - 1] == 0x28 || chars[i - 1] == 0x3C) {
                        found = i
                        break
                    }
                }
            }
            i += 1
        }
        if found < 0 { return nil }
        var end = found
        while end < chars.count && isURLChar(chars[end]) { end += 1 }
        // Trailing punctuation isn't part of it.
        while end > found && [uint8](".,;:!?)]'\">".utf8).contains(chars[end - 1]) { end -= 1 }
        let ci = cols.firstIndex(where: { $0 >= col }) ?? cols.count
        if ci >= found && ci < end {
            let url = string(decoding: [uint8](chars[found..<end]), as: UTF8.self)
            return (cols[found], cols[end - 1], url)
        }
        start = max(end, found + 1)
    }
    _ = s
    return nil
}

func isURLChar(_ c: uint8) -> bool {
    if c <= 0x20 || c >= 0x7F { return false }
    return ![uint8]("\"<>^`{|}".utf8).contains(c)
}

/// s without spaces at its end.
func trimRight(_ s: string) -> string {
    var b = [uint8](s.utf8)
    while let l = b.last, l == 0x20 || l == 0x09 { b.removeLast() }
    return string(decoding: b, as: UTF8.self)
}
