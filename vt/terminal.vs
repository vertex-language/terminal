// Package vt is a terminal emulator's core: it takes the bytes a program
// writes to a terminal -- text, and the escape sequences of xterm and the
// VT100 family -- and keeps the screen they describe: a grid of cells, a
// cursor, the scrollback, the modes. It draws nothing and opens nothing;
// a host gives it bytes (from os/pty, remote/ssh, a test) and reads the
// cells back to draw them.
//
//     let term = vt.Terminal(columns: 80, rows: 24)
//     term.Feed(bytes)                 // what the program wrote
//     let row = term.Row(0)            // cells to draw
//     let reply = term.TakeResponses() // what the program asked to be told
//     term.Resize(columns: 120, rows: 40)
//
// What a key sends is `EncodeKey`; a mouse event, `EncodeMouse`; a paste,
// `EncodePaste`. The sequences understood are xterm's, as `TERM=xterm-256color`
// promises: cursor movement, erasing, scrolling regions, insert and delete,
// SGR colors (16, 256 and 24-bit), the alternate screen, DEC line drawing,
// bracketed paste, mouse reporting, window titles and the working directory
// (OSC 0, 2, 7), and the status reports programs ask for.
package vt

/// Where the cursor is, and what it writes with: what DECSC saves.
struct savedCursor {
    var x = 0
    var y = 0
    var pen = Cell.blank
    var origin = false
    var g0: charset = .ascii
    var g1: charset = .ascii
    var gl = 0
    var pendingWrap = false
}

enum charset {
    case ascii
    case lineDrawing
}

/// How the cursor is drawn, as DECSCUSR sets it.
public enum CursorShape: Equatable {
    case block
    case underline
    case bar
}

/// Which mouse events the program asked to be told of.
public enum MouseTracking: Equatable {
    case off
    /// Presses and releases (1000).
    case clicks
    /// And movement while a button is held (1002).
    case drag
    /// And all movement (1003).
    case motion
}

/// The terminal: screen, scrollback, cursor and modes.
public final class Terminal {
    public private(set) var Columns: int
    public private(set) var Rows: int

    // The screen shown, and the other one (main or alternate).
    var screen: [Line]
    var other: [Line]
    /// Whether the alternate screen is shown (full-screen programs).
    public private(set) var AltScreen = false

    // Scrollback: a ring of lines that scrolled off the top of the main
    // screen, oldest first.
    var ring: [Line] = []
    var ringStart = 0
    var ringCount = 0
    /// How many lines of scrollback are kept.
    public var ScrollbackLimit: int = 10000

    // The cursor.
    var cx = 0
    var cy = 0
    var pendingWrap = false
    var pen = Cell.blank
    var saved = savedCursor()
    var savedAlt = savedCursor()
    var g0: charset = .ascii
    var g1: charset = .ascii
    var gl = 0
    var lastPrinted: uint32 = 0

    // The scrolling region, rows top...bottom.
    var top = 0
    var bottom = 0
    var tabs: [bool] = []

    // Modes.
    var insertMode = false
    var autowrap = true
    var originMode = false
    var newlineMode = false
    /// DECCKM: arrows send ESC O A rather than ESC [ A.
    public private(set) var AppCursorKeys = false
    /// DECKPAM: the keypad sends application sequences.
    public private(set) var AppKeypad = false
    /// DECTCEM: whether the cursor is shown.
    public private(set) var CursorVisible = true
    /// Whether the cursor blinks (DECSCUSR, or mode 12).
    public private(set) var CursorBlink = true
    public private(set) var Shape: CursorShape = .block
    /// Mode 2004: pastes are bracketed.
    public private(set) var BracketedPaste = false
    public private(set) var Mouse: MouseTracking = .off
    /// Mode 1006: mouse reports are SGR-style.
    public private(set) var MouseSGR = false
    /// Mode 1004: focus in and out are reported.
    public private(set) var FocusReporting = false
    /// Mode 5 (DECSCNM): the whole screen is shown reversed.
    public private(set) var ReverseVideo = false
    /// Mode 1007: the wheel on the alternate screen sends arrow keys.
    public private(set) var AlternateScroll = true

    /// The window title the program set (OSC 0 or 2).
    public private(set) var Title = ""
    /// The working directory the shell reported (OSC 7), as a path.
    public private(set) var WorkingDirectory: string? = nil
    /// How many times the bell has rung.
    public private(set) var Bells = 0
    /// Text the program asked to put on the clipboard (OSC 52), taken by
    /// the host with TakeClipboard.
    var clipboard: string? = nil

    /// The colors status reports answer with (OSC 10, 11), as the host
    /// draws them.
    public var ForegroundRGB: (R: uint8, G: uint8, B: uint8) = (R: 0xE6, G: 0xE6, B: 0xE6)
    public var BackgroundRGB: (R: uint8, G: uint8, B: uint8) = (R: 0x1E, G: 0x1E, B: 0x1E)

    // Bytes to send back to the program: answers to its reports.
    var responses: [uint8] = []

    /// How many lines up from the bottom the view is scrolled into the
    /// scrollback: 0 follows the screen.
    public private(set) var ViewOffset = 0

    /// Goes up by one with every change to what is shown.
    public private(set) var Version = 0

    // The parser.
    var state: pstate = .ground
    var params: [int] = []
    /// colons[i]: parameter i followed a colon (a sub-parameter, as in
    /// 38:2::r:g:b).
    var colons: [bool] = []
    var nextColon = false
    var param = -1
    var intermediates: [uint8] = []
    var privateMarker: uint8 = 0
    var osc: [uint8] = []
    var utf8Need = 0
    var utf8Code: uint32 = 0
    var stringEsc = false

    public init(columns: int = 80, rows: int = 24) {
        Columns = max(columns, 2)
        Rows = max(rows, 1)
        screen = []
        other = []
        screen = blankLines(Rows)
        other = blankLines(Rows)
        bottom = Rows - 1
        resetTabs()
    }

    // MARK: - Reading it

    /// The cursor's column and row on the screen.
    public var CursorX: int { return cx }
    public var CursorY: int { return cy }

    /// How many lines of scrollback there are.
    public var ScrollbackCount: int { return ringCount }

    /// A row of the screen, 0 the top.
    public func Row(_ y: int) -> Line {
        return screen[y]
    }

    /// A row as the view shows it: the screen, or the scrollback where the
    /// view is scrolled up. 0 is the view's top.
    public func ViewRow(_ y: int) -> Line {
        return Absolute(ringCount - ViewOffset + y)
    }

    /// A line by its absolute number: scrollback from 0 (the oldest), then
    /// the screen.
    public func Absolute(_ n: int) -> Line {
        if n < 0 { return Line(columns: Columns) }
        if n < ringCount {
            let l = ring[(ringStart + n) % ring.count]
            if l.Cells.count == Columns { return l }
            var fitted = l
            fit(&fitted)
            return fitted
        }
        let y = n - ringCount
        if y < Rows { return screen[y] }
        return Line(columns: Columns)
    }

    /// The absolute line number of the view's top row.
    public var ViewTop: int { return ringCount - ViewOffset }

    /// The text from (x0, line0) to (x1, line1), in absolute lines, ends
    /// included: rows joined with newlines except where one wrapped onto
    /// the next.
    public func Text(fromColumn x0: int, line l0: int, toColumn x1: int, line l1: int) -> string {
        var out: [uint8] = []
        var n = l0
        while n <= l1 {
            let line = Absolute(n)
            let from = n == l0 ? max(0, x0) : 0
            let to = n == l1 ? min(Columns - 1, x1) : Columns - 1
            var end = to + 1
            // Trailing blanks of a row that ends in a newline are not text.
            if !(n < l1 && line.Wrapped) {
                while end > from && (line.Cells[end - 1].Rune == 0 || line.Cells[end - 1].Rune == 32) { end -= 1 }
            }
            var i = from
            while i < end {
                let c = line.Cells[i]
                if !c.Has(Attr.spacer) { appendUTF8(&out, c.Rune == 0 ? 32 : c.Rune) }
                i += 1
            }
            if n < l1 && !line.Wrapped { out.append(10) }
            n += 1
        }
        return textOf(out)
    }

    /// The whole screen's text, a row per line.
    public func ScreenText() -> string {
        var rows: [string] = []
        for l in screen { rows.append(l.Text()) }
        return rows.joined(separator: "\n")
    }

    /// The bytes the program asked for (status reports), to write back to
    /// it; empties them.
    public func TakeResponses() -> [uint8] {
        let r = responses
        responses = []
        return r
    }

    /// Text the program asked to put on the clipboard, once.
    public func TakeClipboard() -> string? {
        let c = clipboard
        clipboard = nil
        return c
    }

    // MARK: - The view

    /// Scrolls the view by lines: up (positive) into the scrollback, down
    /// towards the screen.
    public func ScrollView(by lines: int) {
        let to = max(0, min(ringCount, ViewOffset + lines))
        if to != ViewOffset {
            ViewOffset = to
            Version += 1
        }
    }

    /// Puts the view back on the screen.
    public func ScrollToBottom() {
        if ViewOffset != 0 {
            ViewOffset = 0
            Version += 1
        }
    }

    /// Empties the scrollback (what "Clear" in a menu does).
    public func ClearScrollback() {
        ring = []
        ringStart = 0
        ringCount = 0
        ViewOffset = 0
        Version += 1
    }

    // MARK: - Resizing

    /// Makes the screen columns × rows. Rows dropped off the top go to the
    /// scrollback, and rows come back from it when the screen grows, so
    /// the cursor's row keeps its text. Lines are cut or padded, not
    /// reflowed.
    public func Resize(columns: int, rows: int) {
        let c = max(columns, 2)
        let r = max(rows, 1)
        if c == Columns && r == Rows { return }
        Columns = c
        for i in 0..<screen.count { fit(&screen[i]) }
        for i in 0..<other.count { fit(&other[i]) }
        if r < Rows {
            // Drop rows from the bottom that are below the cursor and
            // empty, then from the top into the scrollback.
            var excess = Rows - r
            while excess > 0 && screen.count - 1 > cy && isBlank(screen[screen.count - 1]) {
                screen.removeLast()
                excess -= 1
            }
            while excess > 0 {
                let gone = screen.removeFirst()
                if !AltScreen { pushScrollback(gone) }
                cy -= 1
                excess -= 1
            }
            while screen.count > r { screen.removeLast() }
            while other.count > r { other.removeFirst() }
        } else if r > Rows {
            var grow = r - Rows
            // Bring lines back from the scrollback to the top.
            while grow > 0 && !AltScreen && ringCount > 0 {
                screen.insert(popScrollback(), at: 0)
                cy += 1
                grow -= 1
            }
            while screen.count < r { screen.append(Line(columns: c)) }
            while other.count < r { other.append(Line(columns: c)) }
        }
        Rows = r
        cy = max(0, min(cy, Rows - 1))
        cx = max(0, min(cx, Columns - 1))
        saved.y = min(saved.y, Rows - 1)
        saved.x = min(saved.x, Columns - 1)
        savedAlt.y = min(savedAlt.y, Rows - 1)
        savedAlt.x = min(savedAlt.x, Columns - 1)
        pendingWrap = false
        top = 0
        bottom = Rows - 1
        let oldTabs = tabs
        resetTabs()
        for i in 0..<min(oldTabs.count, tabs.count) { tabs[i] = oldTabs[i] }
        ViewOffset = min(ViewOffset, ringCount)
        Version += 1
    }

    func fit(_ line: inout Line) {
        if line.Cells.count > Columns {
            line.Cells.removeLast(line.Cells.count - Columns)
            // A wide character cut in half leaves a blank.
            if Columns > 0 && line.Cells[Columns - 1].Has(Attr.wide) { line.Cells[Columns - 1] = Cell.blank }
        } else if line.Cells.count < Columns {
            line.Cells.append(contentsOf: [Cell](repeating: Cell.blank, count: Columns - line.Cells.count))
        }
    }

    func isBlank(_ line: Line) -> bool {
        for c in line.Cells where (c.Rune != 0 && c.Rune != 32) || !c.Bg.IsDefault { return false }
        return true
    }

    func blankLines(_ n: int) -> [Line] {
        return [Line](repeating: Line(columns: Columns), count: n)
    }

    func resetTabs() {
        tabs = [bool](repeating: false, count: Columns)
        var i = 8
        while i < Columns {
            tabs[i] = true
            i += 8
        }
    }

    // MARK: - Scrollback

    func pushScrollback(_ line: Line) {
        if ScrollbackLimit <= 0 { return }
        if ringCount < ring.count {
            // Room left by lines taken back (popScrollback).
            ring[(ringStart + ringCount) % ring.count] = line
            ringCount += 1
        } else if ring.count < ScrollbackLimit {
            if ringStart != 0 {
                // Unroll before growing, so the order stays oldest first.
                var unrolled: [Line] = []
                for i in 0..<ringCount { unrolled.append(ring[(ringStart + i) % ring.count]) }
                ring = unrolled
                ringStart = 0
            }
            ring.append(line)
            ringCount += 1
        } else {
            // Full: the oldest gives way.
            ring[ringStart] = line
            ringStart = (ringStart + 1) % ring.count
        }
        // A view scrolled into the scrollback keeps showing the same lines.
        if ViewOffset > 0 { ViewOffset = min(ViewOffset + 1, ringCount) }
    }

    func popScrollback() -> Line {
        let i = (ringStart + ringCount - 1) % ring.count
        var line = ring[i]
        ringCount -= 1
        if ringCount == 0 {
            ring = []
            ringStart = 0
        }
        fit(&line)
        line.Wrapped = false
        ViewOffset = min(ViewOffset, ringCount)
        return line
    }

    // MARK: - Editing the screen

    func changed() {
        Version += 1
    }

    /// A blank cell in the current background: what erasing leaves (BCE).
    var eraseCell: Cell {
        return Cell(rune: 0, fg: .default, bg: pen.Bg, attrs: 0)
    }

    func put(_ code: uint32) {
        var cp = code
        if (gl == 0 ? g0 : g1) == .lineDrawing && cp >= 0x5F && cp <= 0x7E {
            cp = lineDrawingTable[int(cp - 0x5F)]
        }
        let w = CellWidth(cp)
        if w == 0 {
            // A combining mark: kept with nothing of its own (there is no
            // room in a cell for it yet).
            return
        }
        if pendingWrap {
            if autowrap {
                screen[cy].Wrapped = true
                cx = 0
                lineFeed()
            }
            pendingWrap = false
        }
        if w == 2 && cx == Columns - 1 {
            if !autowrap { return }
            screen[cy].Cells[cx] = eraseCell
            screen[cy].Wrapped = true
            cx = 0
            lineFeed()
        }
        if insertMode { insertBlanks(w) }
        clearWide(cx)
        if w == 2 { clearWide(cx + 1) }
        var c = pen
        c.Rune = cp
        if w == 2 {
            c.Attrs |= Attr.wide
            screen[cy].Cells[cx] = c
            var s = pen
            s.Rune = 0
            s.Attrs |= Attr.spacer
            screen[cy].Cells[cx + 1] = s
        } else {
            screen[cy].Cells[cx] = c
        }
        lastPrinted = cp
        cx += w
        if cx >= Columns {
            cx = Columns - 1
            pendingWrap = autowrap
        }
        Version += 1
    }

    /// Writing over half of a wide character blanks the other half.
    func clearWide(_ x: int) {
        if x < 0 || x >= Columns { return }
        let c = screen[cy].Cells[x]
        if c.Has(Attr.spacer) && x > 0 {
            screen[cy].Cells[x - 1] = eraseCell
        } else if c.Has(Attr.wide) && x + 1 < Columns {
            screen[cy].Cells[x + 1] = eraseCell
        }
    }

    func lineFeed() {
        if cy == bottom {
            scrollUp(1)
        } else if cy < Rows - 1 {
            cy += 1
        }
        Version += 1
    }

    func reverseIndex() {
        if cy == top {
            scrollDown(1)
        } else if cy > 0 {
            cy -= 1
        }
        Version += 1
    }

    /// Scrolls the region up n rows: rows leave at the top (to the
    /// scrollback, where the region is the main screen's top) and blank
    /// rows come in at the bottom.
    func scrollUp(_ count: int) {
        let n = min(count, bottom - top + 1)
        if n <= 0 { return }
        for _ in 0..<n {
            let gone = screen.remove(at: top)
            if top == 0 && !AltScreen { pushScrollback(gone) }
            screen.insert(Line(columns: Columns, fill: eraseCell), at: bottom)
        }
        Version += 1
    }

    func scrollDown(_ count: int) {
        let n = min(count, bottom - top + 1)
        if n <= 0 { return }
        for _ in 0..<n {
            screen.remove(at: bottom)
            screen.insert(Line(columns: Columns, fill: eraseCell), at: top)
        }
        Version += 1
    }

    func insertBlanks(_ count: int) {
        let n = min(count, Columns - cx)
        if n <= 0 { return }
        var cells = screen[cy].Cells
        cells.removeLast(n)
        cells.insert(contentsOf: [Cell](repeating: eraseCell, count: n), at: cx)
        screen[cy].Cells = cells
        Version += 1
    }

    func deleteChars(_ count: int) {
        let n = min(count, Columns - cx)
        if n <= 0 { return }
        var cells = screen[cy].Cells
        cells.removeSubrange(cx..<(cx + n))
        cells.append(contentsOf: [Cell](repeating: eraseCell, count: n))
        screen[cy].Cells = cells
        Version += 1
    }

    func eraseChars(_ count: int) {
        let n = min(count, Columns - cx)
        if n <= 0 { return }
        let blank = eraseCell
        for x in cx..<(cx + n) { screen[cy].Cells[x] = blank }
        Version += 1
    }

    func insertLines(_ count: int) {
        if cy < top || cy > bottom { return }
        let n = min(count, bottom - cy + 1)
        for _ in 0..<n {
            screen.remove(at: bottom)
            screen.insert(Line(columns: Columns, fill: eraseCell), at: cy)
        }
        cx = 0
        Version += 1
    }

    func deleteLines(_ count: int) {
        if cy < top || cy > bottom { return }
        let n = min(count, bottom - cy + 1)
        for _ in 0..<n {
            screen.remove(at: cy)
            screen.insert(Line(columns: Columns, fill: eraseCell), at: bottom)
        }
        cx = 0
        Version += 1
    }

    /// Erases part of the row: 0 from the cursor to the end, 1 from the
    /// start to the cursor, 2 all of it.
    func eraseInLine(_ mode: int) {
        let blank = eraseCell
        var from = 0
        var to = Columns
        switch mode {
        case 0: from = cx
        case 1: to = cx + 1
        default: break
        }
        if from < to {
            for x in from..<to { screen[cy].Cells[x] = blank }
        }
        if mode != 1 { screen[cy].Wrapped = false }
        Version += 1
    }

    /// Erases part of the screen: 0 from the cursor on, 1 up to the
    /// cursor, 2 all of it, 3 the scrollback.
    func eraseInDisplay(_ mode: int) {
        switch mode {
        case 0:
            eraseInLine(0)
            if cy + 1 < Rows {
                for y in (cy + 1)..<Rows { screen[y] = Line(columns: Columns, fill: eraseCell) }
            }
        case 1:
            if cy > 0 {
                for y in 0..<cy { screen[y] = Line(columns: Columns, fill: eraseCell) }
            }
            eraseInLine(1)
        case 2:
            // What a clear leaves on the main screen goes to the
            // scrollback first, as other terminals keep it.
            if !AltScreen {
                var last = Rows - 1
                while last >= 0 && isBlank(screen[last]) { last -= 1 }
                if last >= 0 {
                    for y in 0...last { pushScrollback(screen[y]) }
                }
            }
            for y in 0..<Rows { screen[y] = Line(columns: Columns, fill: eraseCell) }
        case 3:
            ClearScrollback()
        default:
            break
        }
        Version += 1
    }

    func moveTo(_ x: int, _ y: int) {
        let minY = originMode ? top : 0
        let maxY = originMode ? bottom : Rows - 1
        cx = max(0, min(x, Columns - 1))
        cy = max(minY, min(y, maxY))
        pendingWrap = false
        Version += 1
    }

    func tabForward(_ count: int) {
        var n = count
        while n > 0 && cx < Columns - 1 {
            cx += 1
            while cx < Columns - 1 && !tabs[cx] { cx += 1 }
            n -= 1
        }
        pendingWrap = false
        Version += 1
    }

    func tabBackward(_ count: int) {
        var n = count
        while n > 0 && cx > 0 {
            cx -= 1
            while cx > 0 && !tabs[cx] { cx -= 1 }
            n -= 1
        }
        pendingWrap = false
        Version += 1
    }

    func saveCursor() {
        let s = savedCursor(x: cx, y: cy, pen: pen, origin: originMode, g0: g0, g1: g1, gl: gl, pendingWrap: pendingWrap)
        if AltScreen { savedAlt = s } else { saved = s }
    }

    func restoreCursor() {
        let s = AltScreen ? savedAlt : saved
        cx = min(s.x, Columns - 1)
        cy = min(s.y, Rows - 1)
        pen = s.pen
        originMode = s.origin
        g0 = s.g0
        g1 = s.g1
        gl = s.gl
        pendingWrap = s.pendingWrap
        Version += 1
    }

    /// Shows the alternate screen (or the main one again). With clear,
    /// the alternate screen starts blank; with cursor, the main screen's
    /// cursor is saved and restored around it (mode 1049).
    func setAltScreen(_ on: bool, clear: bool, cursor: bool) {
        if on == AltScreen { return }
        if on {
            if cursor { saveCursor() }
            let s = screen
            screen = other
            other = s
            AltScreen = true
            if clear {
                for y in 0..<Rows { screen[y] = Line(columns: Columns) }
            }
        } else {
            if clear {
                for y in 0..<Rows { screen[y] = Line(columns: Columns) }
            }
            let s = screen
            screen = other
            other = s
            AltScreen = false
            if cursor { restoreCursor() }
        }
        top = 0
        bottom = Rows - 1
        ViewOffset = 0
        Version += 1
    }

    /// RIS: everything back as it was when made, scrollback kept.
    func fullReset() {
        screen = blankLines(Rows)
        other = blankLines(Rows)
        AltScreen = false
        cx = 0
        cy = 0
        pendingWrap = false
        pen = Cell.blank
        saved = savedCursor()
        savedAlt = savedCursor()
        g0 = .ascii
        g1 = .ascii
        gl = 0
        top = 0
        bottom = Rows - 1
        resetTabs()
        insertMode = false
        autowrap = true
        originMode = false
        newlineMode = false
        AppCursorKeys = false
        AppKeypad = false
        CursorVisible = true
        CursorBlink = true
        Shape = .block
        BracketedPaste = false
        Mouse = .off
        MouseSGR = false
        FocusReporting = false
        ReverseVideo = false
        Title = ""
        Version += 1
    }

    /// DECSTR: the modes back to their defaults, the screen kept.
    func softReset() {
        insertMode = false
        autowrap = true
        originMode = false
        AppCursorKeys = false
        AppKeypad = false
        CursorVisible = true
        top = 0
        bottom = Rows - 1
        pen = Cell.blank
        g0 = .ascii
        g1 = .ascii
        gl = 0
        saved = savedCursor()
        pendingWrap = false
        Version += 1
    }

    func respond(_ s: string) {
        responses.append(contentsOf: [uint8](s.utf8))
    }
}

// DEC Special Graphics: what 0x5F-0x7E draw while the line-drawing set is
// in use (tmux's and mc's borders).
let lineDrawingTable: [uint32] = [
    0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0, 0x00B1, 0x2424, 0x240B, 0x2518,
    0x2510, 0x250C, 0x2514, 0x253C, 0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534,
    0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7,
]
