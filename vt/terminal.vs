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
// (OSC 0, 2, 7), and the status reports programs ask for. Past xterm's
// core: left and right margins, rectangular editing, selective erase,
// double-width and double-height lines, hyperlinks (OSC 8), the shell's
// prompt marks (OSC 133), palette changes (OSC 4, 10-12, 104-112),
// progress and notifications (OSC 9, 777), the kitty keyboard protocol,
// synchronized output (2026), and sixel images. Lines are reflowed when
// the width changes; combining marks and joined emoji stay with their
// character.
package vt

import "unicode"

/// Where the cursor is, and what it writes with: what DECSC saves.
struct savedCursor {
    var x = 0
    var y = 0
    var pen = Cell.blank
    var origin = false
    var g0: charset = .ascii
    var g1: charset = .ascii
    var g2: charset = .ascii
    var g3: charset = .ascii
    var gl = 0
    var pendingWrap = false
}

enum charset {
    case ascii
    case lineDrawing
    /// The UK set: # is £.
    case uk
}

/// How mouse reports are written (modes 1005, 1006, 1015, 1016).
public enum MouseEncoding: Equatable {
    /// ESC [ M and three bytes: coordinates to 223.
    case x10
    /// The same, coordinates as UTF-8 (1005).
    case utf8
    /// ESC [ < b ; x ; y M/m (1006).
    case sgr
    /// ESC [ b ; x ; y M (1015).
    case urxvt
    /// SGR with pixels, not cells (1016).
    case sgrPixels
}

/// What a program said of its progress (OSC 9;4), shown on its tab.
public enum ProgressState: Equatable {
    case none
    case normal
    case error
    case indeterminate
    case paused
}

/// A notification a program asked for (OSC 9, OSC 777;notify).
public struct Notification: Equatable {
    public var Title: string
    public var Body: string
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
    /// Lines gone off the scrollback's top, ever: what keeps an image on
    /// its line as the lines under it are renumbered.
    var dropped = 0
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

    // The scrolling region, rows top...bottom, and columns left...right
    // where DECLRMM (mode 69) allows margins.
    var top = 0
    var bottom = 0
    var left = 0
    var right = 0
    var lrMarginMode = false
    var tabs: [bool] = []
    // G2 and G3, and a single shift (SS2, SS3) waiting for the next
    // character.
    var g2: charset = .ascii
    var g3: charset = .ascii
    var singleShift = 0
    // The last character joined a cluster with a ZWJ, or was a regional
    // indicator: the next may join it.
    var joinNext = false
    var lastRegional = false
    /// DECSACE: DECCARA and DECRARA work on a rectangle (true), or the
    /// stream of characters between two corners.
    var rectExtent = false

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
    /// Whether the program chose the cursor's shape (DECSCUSR 1-6), or
    /// left it to the user's settings (0, or never).
    public private(set) var CursorStyleSet = false
    /// Mode 2004: pastes are bracketed.
    public private(set) var BracketedPaste = false
    public private(set) var Mouse: MouseTracking = .off
    /// Mode 1006: mouse reports are SGR-style.
    public var MouseSGR: bool { return MouseFormat == .sgr || MouseFormat == .sgrPixels }
    /// How mouse reports are written.
    public private(set) var MouseFormat: MouseEncoding = .x10
    /// DECBKM (mode 67): Backspace sends BS, not DEL.
    public private(set) var BackspaceSendsBS = false
    /// Mode 2026: the program is drawing a frame; the host may wait for
    /// it to end (or a moment) before showing the screen.
    public private(set) var SynchronizedOutput = false
    /// The kitty keyboard protocol's flags: 1 disambiguate, 2 report
    /// event types, 4 alternate keys, 8 all keys as escapes, 16 text.
    public private(set) var KittyFlags = 0
    var kittyStack: [int] = []
    /// Whether programs may turn on the kitty keyboard protocol; the
    /// host's setting.
    public var KittyKeyboard = true
    var kittyStackAlt: [int] = []
    /// Mode 1004: focus in and out are reported.
    public private(set) var FocusReporting = false
    /// Mode 5 (DECSCNM): the whole screen is shown reversed.
    public private(set) var ReverseVideo = false
    /// Mode 1007: the wheel on the alternate screen sends arrow keys.
    public private(set) var AlternateScroll = true
    /// Mode 2031: the program is told when the color scheme changes.
    public private(set) var ThemeReports = false
    /// Whether the host shows a dark color scheme (for mode 2031 and
    /// CSI ? 996 n).
    public var DarkMode = true
    var autorepeat = true
    var allowColumnMode = false

    /// The window title the program set (OSC 0 or 2).
    public private(set) var Title = ""
    var titleStack: [string] = []
    /// What a program said of its progress (OSC 9;4): a state and a
    /// percentage.
    public private(set) var Progress: ProgressState = .none
    public private(set) var ProgressValue = 0
    var notifications: [Notification] = []
    /// What ENQ is answered with.
    public var Answerback = ""
    /// A cell's size in pixels, for the reports that ask (XTWINOPS 14,
    /// 16) and for sixel images; the host sets it.
    public var CellPixelWidth = 8
    public var CellPixelHeight = 16
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
    public var CursorRGB: (R: uint8, G: uint8, B: uint8) = (R: 0xE6, G: 0xE6, B: 0xE6)
    /// The theme's 16 ANSI colors as 0xRRGGBB, what OSC 4 queries answer
    /// with where a program hasn't changed them; the host sets them.
    public var ThemePalette: [uint32] = []

    // Colors the program changed (OSC 4, 10, 11, 12), 0xRRGGBB, or
    // noColor where it didn't.
    var palette: [uint32] = [uint32](repeating: noColor, count: 256)
    var fgOverride: uint32 = noColor
    var bgOverride: uint32 = noColor
    var cursorOverride: uint32 = noColor
    /// Goes up when a program changes a color: what is drawn in it must
    /// be drawn again.
    public private(set) var PaletteVersion = 0

    /// Sixel images, placed in the cells they cover.
    public private(set) var Images: [Image] = []
    /// Goes up when an image is added or goes.
    public private(set) var ImagesVersion = 0

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
    var dcs: [uint8] = []
    var dcsKind: uint8 = 0
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
        right = Columns - 1
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

    /// The notifications the program asked for since the last call.
    public func TakeNotifications() -> [Notification] {
        let n = notifications
        notifications = []
        return n
    }

    // MARK: - Colors

    /// A palette color the program set (OSC 4), else nil: the theme's.
    public func PaletteColor(_ index: int) -> (R: uint8, G: uint8, B: uint8)? {
        if index < 0 || index > 255 || palette[index] == noColor { return nil }
        return rgbOf(palette[index])
    }

    /// The default foreground, background and cursor colors the program
    /// set (OSC 10, 11, 12), else nil.
    public var ForegroundOverride: (R: uint8, G: uint8, B: uint8)? { return fgOverride == noColor ? nil : rgbOf(fgOverride) }
    public var BackgroundOverride: (R: uint8, G: uint8, B: uint8)? { return bgOverride == noColor ? nil : rgbOf(bgOverride) }
    public var CursorOverride: (R: uint8, G: uint8, B: uint8)? { return cursorOverride == noColor ? nil : rgbOf(cursorOverride) }

    /// A palette color as it is shown: what the program set, the theme's,
    /// or xterm's.
    func currentColor(_ index: int) -> uint32 {
        if palette[index] != noColor { return palette[index] }
        if index < 16 && index < ThemePalette.count { return ThemePalette[index] }
        let c = PaletteRGB(index)
        return (uint32(c.R) << 16) | (uint32(c.G) << 8) | uint32(c.B)
    }

    // MARK: - Marks

    /// The absolute line of the prompt before line n (OSC 133;A), or nil.
    public func PreviousPrompt(before n: int) -> int? {
        var i = min(n - 1, ringCount + Rows - 1)
        while i >= 0 {
            if Absolute(i).Mark == .prompt { return i }
            i -= 1
        }
        return nil
    }

    /// The absolute line of the prompt after line n, or nil.
    public func NextPrompt(after n: int) -> int? {
        var i = max(0, n + 1)
        while i < ringCount + Rows {
            if Absolute(i).Mark == .prompt { return i }
            i += 1
        }
        return nil
    }

    /// Every marked line: its absolute number and its mark.
    public func Marks() -> [(Line: int, Mark: Mark, ExitCode: int)] {
        var out: [(Line: int, Mark: Mark, ExitCode: int)] = []
        for i in 0..<(ringCount + Rows) {
            let l = Absolute(i)
            if l.Mark != .none { out.append((Line: i, Mark: l.Mark, ExitCode: l.ExitCode)) }
        }
        return out
    }

    /// Marks the cursor's line (what the addMark action does).
    public func AddMark() {
        screen[cy].Mark = .prompt
        Version += 1
    }

    /// Takes every mark away.
    public func ClearMarks() {
        for i in 0..<screen.count { screen[i].Mark = .none }
        for i in 0..<ring.count { ring[i].Mark = .none }
        Version += 1
    }

    /// The output of the command whose prompt is on line n: from the line
    /// after its command to the line before the next prompt, absolute.
    public func CommandOutput(at n: int) -> (From: int, To: int)? {
        var i = n
        let end = ringCount + Rows
        // The output's start: an output mark at or after n, before the
        // next prompt.
        while i < end {
            let m = Absolute(i).Mark
            if m == .output { break }
            if m == .prompt && i != n { return nil }
            i += 1
        }
        if i >= end { return nil }
        let from = i
        var to = from
        var j = from + 1
        while j < end && Absolute(j).Mark != .prompt {
            to = j
            j += 1
        }
        return (From: from, To: to)
    }

    // MARK: - Searching

    /// Where needle appears in the screen and the scrollback, oldest
    /// first, each as the cells it covers (absolute lines, ends included).
    /// Wrapped rows are searched as one line.
    public func Find(_ needle: string, caseSensitive: bool = false) -> [(StartColumn: int, StartLine: int, EndColumn: int, EndLine: int)] {
        var out: [(StartColumn: int, StartLine: int, EndColumn: int, EndLine: int)] = []
        let want = foldText(needle, caseSensitive)
        if want.isEmpty { return out }
        let total = ringCount + Rows
        var n = 0
        while n < total {
            // A logical line: rows joined while they wrap.
            var cps: [uint32] = []
            var at: [(int, int)] = []
            var m = n
            while true {
                let line = Absolute(m)
                for x in 0..<line.Cells.count {
                    let c = line.Cells[x]
                    if c.Has(Attr.spacer) { continue }
                    for cp in Cluster(c.Rune == 0 ? 32 : c.Rune) {
                        cps.append(caseSensitive ? cp : foldRune(cp))
                        at.append((x, m))
                    }
                }
                if !line.Wrapped || m + 1 >= total { break }
                m += 1
            }
            if cps.count >= want.count {
                var i = 0
                while i + want.count <= cps.count {
                    var j = 0
                    while j < want.count && cps[i + j] == want[j] { j += 1 }
                    if j == want.count {
                        let a = at[i]
                        let b = at[i + want.count - 1]
                        var endX = b.0
                        if Absolute(b.1).Cells[endX].Has(Attr.wide) { endX += 1 }
                        out.append((StartColumn: a.0, StartLine: a.1, EndColumn: endX, EndLine: b.1))
                        i += want.count
                    } else {
                        i += 1
                    }
                }
            }
            n = m + 1
        }
        return out
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
        dropped += ringCount
        if !Images.isEmpty { pruneImages() }
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
        if c != Columns && Reflow {
            reflow(c, r)
            return
        }
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
        afterResize()
    }

    /// Whether lines are rewrapped when the width changes (the main
    /// screen's and the scrollback's), rather than cut or padded.
    public var Reflow = true

    func afterResize() {
        top = 0
        bottom = Rows - 1
        left = 0
        right = Columns - 1
        let oldTabs = tabs
        resetTabs()
        for i in 0..<min(oldTabs.count, tabs.count) { tabs[i] = oldTabs[i] }
        ViewOffset = min(ViewOffset, ringCount)
        Images = []
        ImagesVersion += 1
        Version += 1
    }

    /// Resizes to c × r, rewrapping the main screen and the scrollback to
    /// the new width: a line that wrapped becomes one again and wraps
    /// where the new margin is, and the cursor stays on its character.
    /// The alternate screen is cut or padded: its program draws it again.
    func reflow(_ c: int, _ r: int) {
        let mainScreen = AltScreen ? other : screen
        // The main screen's cursor: saved, where the alternate is shown.
        var curX = AltScreen ? saved.x : cx
        let curY = AltScreen ? saved.y : cy
        if !AltScreen && pendingWrap { curX += 1 }
        // The logical lines: runs of rows joined where they wrapped. Blank
        // rows below the cursor are dropped.
        var lastRow = Rows - 1
        while lastRow > curY && isBlank(mainScreen[lastRow]) { lastRow -= 1 }
        var logical: [[Cell]] = []
        var heads: [Line] = []
        var cursorLogical = 0
        var cursorOffset = 0
        var run: [Cell] = []
        var head = Line(columns: 0)
        var starting = true
        let count = ringCount + lastRow + 1
        for n in 0..<count {
            let line = n < ringCount ? ring[(ringStart + n) % ring.count] : mainScreen[n - ringCount]
            if starting {
                head = line
                starting = false
            }
            if n == ringCount + curY {
                cursorLogical = logical.count
                cursorOffset = run.count + curX
            }
            if line.Wrapped {
                run.append(contentsOf: line.Cells)
                continue
            }
            // The run's end: its trailing blanks are not text.
            var end = line.Cells.count
            while end > 0 && blankCell(line.Cells[end - 1]) { end -= 1 }
            run.append(contentsOf: line.Cells[0..<end])
            logical.append(run)
            heads.append(head)
            run = []
            starting = true
        }
        if !starting {
            logical.append(run)
            heads.append(head)
        }
        // Wrapped again at the new width.
        var rows: [Line] = []
        var newCX = 0
        var newCY = 0
        for li in 0..<logical.count {
            let cells = logical[li]
            var row = Line(columns: c)
            row.Mark = heads[li].Mark
            row.ExitCode = heads[li].ExitCode
            var x = 0
            var i = 0
            let hasCursor = li == cursorLogical
            var placed = false
            while i < cells.count {
                if hasCursor && i == cursorOffset {
                    newCY = rows.count
                    newCX = x
                    placed = true
                }
                var cell = cells[i]
                let wide = cell.Has(Attr.wide)
                let w = wide && c > 1 ? 2 : 1
                if !wide && cell.Has(Attr.spacer) {
                    // Padding where a wide character wrapped early, or a
                    // half cut by an old resize: not text.
                    i += 1
                    continue
                }
                if x + w > c {
                    row.Wrapped = true
                    rows.append(row)
                    row = Line(columns: c)
                    x = 0
                    if hasCursor && i == cursorOffset {
                        newCY = rows.count
                        newCX = 0
                    }
                }
                if wide && w == 1 { cell.Attrs &= ~Attr.wide }
                row.Cells[x] = cell
                if w == 2 {
                    var s = cell
                    s.Rune = 0
                    s.Attrs = (cell.Attrs & ~Attr.wide) | Attr.spacer
                    row.Cells[x + 1] = s
                }
                x += w
                i += wide && i + 1 < cells.count && cells[i + 1].Has(Attr.spacer) ? 2 : 1
            }
            if hasCursor && !placed {
                // Past the text: as far again as it was past it.
                var at = x + (cursorOffset - cells.count)
                while at >= c {
                    row.Wrapped = true
                    rows.append(row)
                    row = Line(columns: c)
                    at -= c
                }
                newCY = rows.count
                newCX = max(0, at)
            }
            rows.append(row)
        }
        if rows.isEmpty { rows.append(Line(columns: c)) }
        // The screen is the last r rows, with the cursor's on it.
        var start = max(0, rows.count - r)
        if newCY < start { start = newCY }
        var kept: [Line] = []
        for i in 0..<start { kept.append(rows[i]) }
        if kept.count > ScrollbackLimit { kept.removeFirst(kept.count - ScrollbackLimit) }
        ring = kept
        ringStart = 0
        ringCount = kept.count
        var shown: [Line] = []
        var y = start
        while y < rows.count && shown.count < r {
            shown.append(rows[y])
            y += 1
        }
        while shown.count < r { shown.append(Line(columns: c)) }
        let wasColumns = Columns
        Columns = c
        Rows = r
        if AltScreen {
            other = shown
            saved.x = min(newCX, c - 1)
            saved.y = min(newCY - start, r - 1)
            // The alternate screen: cut or padded.
            while screen.count > r { screen.removeFirst() }
            while screen.count < r { screen.append(Line(columns: c)) }
            for i in 0..<screen.count { fit(&screen[i]) }
            cx = min(cx, c - 1)
            cy = min(cy, r - 1)
        } else {
            screen = shown
            cx = min(newCX, c - 1)
            cy = max(0, min(newCY - start, r - 1))
            pendingWrap = false
            other = blankLines(r)
        }
        _ = wasColumns
        savedAlt.y = min(savedAlt.y, r - 1)
        savedAlt.x = min(savedAlt.x, c - 1)
        afterResize()
    }

    func blankCell(_ c: Cell) -> bool {
        return (c.Rune == 0 || c.Rune == 32) && c.Bg.IsDefault && c.Attrs & (Attr.inverse | Attr.anyUnderline) == 0 && c.Link == 0
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
            dropped += 1
            if !Images.isEmpty { pruneImages() }
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

    /// The charset a character is drawn from: G0-G3 as shifted.
    var activeSet: charset {
        if singleShift == 2 { return g2 }
        if singleShift == 3 { return g3 }
        switch gl {
        case 1: return g1
        case 2: return g2
        case 3: return g3
        default: return g0
        }
    }

    func put(_ code: uint32) {
        var cp = code
        let set = activeSet
        singleShift = 0
        if set == .lineDrawing && cp >= 0x5F && cp <= 0x7E {
            cp = lineDrawingTable[int(cp - 0x5F)]
        } else if set == .uk && cp == 0x23 {
            cp = 0xA3
        }
        // What joins the character before it: a mark, a joiner and what
        // it joins, a variation selector, a flag's second half.
        let regional = cp >= 0x1F1E6 && cp <= 0x1F1FF
        if joinNext || (regional && lastRegional) {
            joinNext = false
            lastRegional = false
            // A flag is two cells, whatever its halves are alone.
            if attach(cp, widen: regional) { return }
        }
        let w = CellWidth(cp)
        if w == 0 {
            joinNext = cp == 0x200D
            // VS16 asks for the emoji form: two cells.
            if !attach(cp, widen: cp == 0xFE0F) { joinNext = false }
            return
        }
        lastRegional = regional
        // The margin a line wraps at: the right margin, for a cursor
        // inside the margins.
        let edge = cx <= right ? right : Columns - 1
        let home = cx >= left && cx <= right ? left : 0
        if pendingWrap {
            if autowrap {
                screen[cy].Wrapped = true
                cx = home
                lineFeed()
            }
            pendingWrap = false
        }
        if w == 2 && cx == edge {
            if !autowrap { return }
            // The column left over is padding, not text: a spacer with no
            // wide character before it.
            var pad = eraseCell
            pad.Attrs |= Attr.spacer
            screen[cy].Cells[cx] = pad
            screen[cy].Wrapped = true
            cx = home
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
        let stop = cx - w <= right ? right : Columns - 1
        if cx > stop {
            cx = stop
            pendingWrap = autowrap
        }
        Version += 1
    }

    /// Joins a code point to the character last written, making a
    /// cluster of them; false where there is none to join.
    /// With widen, a character in one cell grows into the next, where the
    /// cursor is just after it.
    func attach(_ cp: uint32, widen: bool = false) -> bool {
        var x = pendingWrap ? cx : cx - 1
        if x < 0 { return false }
        if screen[cy].Cells[x].Has(Attr.spacer) && x > 0 && screen[cy].Cells[x - 1].Has(Attr.wide) { x -= 1 }
        var c = screen[cy].Cells[x]
        if c.Rune == 0 || c.Rune == 32 { return false }
        var cps = Cluster(c.Rune)
        if cps.count >= 32 { return true }
        cps.append(cp)
        c.Rune = internCluster(cps)
        if widen && !c.Has(Attr.wide) && !pendingWrap && x == cx - 1 && cx <= rightEdge {
            c.Attrs |= Attr.wide
            var s = c
            s.Rune = 0
            s.Attrs = (c.Attrs & ~Attr.wide) | Attr.spacer
            clearWide(cx)
            screen[cy].Cells[cx] = s
            if cx == rightEdge {
                pendingWrap = autowrap
            } else {
                cx += 1
            }
        }
        screen[cy].Cells[x] = c
        Version += 1
        return true
    }

    /// Writing over half of a wide character blanks the other half.
    func clearWide(_ x: int) {
        if x < 0 || x >= Columns { return }
        let c = screen[cy].Cells[x]
        if c.Has(Attr.spacer) && x > 0 && screen[cy].Cells[x - 1].Has(Attr.wide) {
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
        if !fullWidth {
            shiftRect(top: top, bottom: bottom, left: left, right: right, by: -n)
            return
        }
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
        if !fullWidth {
            shiftRect(top: top, bottom: bottom, left: left, right: right, by: n)
            return
        }
        for _ in 0..<n {
            screen.remove(at: bottom)
            screen.insert(Line(columns: Columns, fill: eraseCell), at: top)
        }
        Version += 1
    }

    /// The margins are the whole width: lines scroll whole.
    var fullWidth: bool { return left == 0 && right == Columns - 1 }

    /// The edge of the margins the cursor is inside, or the screen's.
    var rightEdge: int { return cx <= right ? right : Columns - 1 }

    func insertBlanks(_ count: int) {
        if cx < left || cx > right { return }
        let edge = right
        let n = min(count, edge - cx + 1)
        if n <= 0 { return }
        var cells = screen[cy].Cells
        cells.removeSubrange((edge + 1 - n)..<(edge + 1))
        cells.insert(contentsOf: [Cell](repeating: eraseCell, count: n), at: cx)
        screen[cy].Cells = cells
        pendingWrap = false
        Version += 1
    }

    func deleteChars(_ count: int) {
        if cx < left || cx > right { return }
        let edge = right
        let n = min(count, edge - cx + 1)
        if n <= 0 { return }
        var cells = screen[cy].Cells
        cells.removeSubrange(cx..<(cx + n))
        cells.insert(contentsOf: [Cell](repeating: eraseCell, count: n), at: edge + 1 - n)
        screen[cy].Cells = cells
        pendingWrap = false
        Version += 1
    }

    /// Moves the cells of rows top...bottom, columns l...r, down by (up
    /// where negative) rows, blanks coming in: scrolling inside margins.
    func shiftRect(top t: int, bottom b: int, left l: int, right r: int, by: int) {
        if by == 0 || l > r || t > b { return }
        let blank = eraseCell
        if by < 0 {
            let n = -by
            var y = t
            while y <= b {
                for x in l...r { screen[y].Cells[x] = y + n <= b ? screen[y + n].Cells[x] : blank }
                y += 1
            }
        } else {
            var y = b
            while y >= t {
                for x in l...r { screen[y].Cells[x] = y - by >= t ? screen[y - by].Cells[x] : blank }
                y -= 1
            }
        }
        Version += 1
    }

    /// Moves columns l...r of rows t...b right by (left where negative),
    /// blanks coming in: DECIC, DECDC, and scrolling sideways.
    func shiftColumns(top t: int, bottom b: int, left l: int, right r: int, by: int) {
        if by == 0 || l > r || t > b { return }
        let blank = eraseCell
        for y in t...b {
            if by > 0 {
                var x = r
                while x >= l {
                    screen[y].Cells[x] = x - by >= l ? screen[y].Cells[x - by] : blank
                    x -= 1
                }
            } else {
                let n = -by
                for x in l...r { screen[y].Cells[x] = x + n <= r ? screen[y].Cells[x + n] : blank }
            }
        }
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
        if cy < top || cy > bottom || cx < left || cx > right { return }
        let n = min(count, bottom - cy + 1)
        if !fullWidth {
            shiftRect(top: cy, bottom: bottom, left: left, right: right, by: n)
            cx = left
            return
        }
        for _ in 0..<n {
            screen.remove(at: bottom)
            screen.insert(Line(columns: Columns, fill: eraseCell), at: cy)
        }
        cx = left
        Version += 1
    }

    func deleteLines(_ count: int) {
        if cy < top || cy > bottom || cx < left || cx > right { return }
        let n = min(count, bottom - cy + 1)
        if !fullWidth {
            shiftRect(top: cy, bottom: bottom, left: left, right: right, by: -n)
            cx = left
            return
        }
        for _ in 0..<n {
            screen.remove(at: cy)
            screen.insert(Line(columns: Columns, fill: eraseCell), at: bottom)
        }
        cx = left
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
            clearScreenImages()
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
        let minX = originMode ? left : 0
        let maxX = originMode ? right : Columns - 1
        cx = max(minX, min(x, maxX))
        cy = max(minY, min(y, maxY))
        pendingWrap = false
        Version += 1
    }

    func tabForward(_ count: int) {
        var n = count
        let edge = rightEdge
        while n > 0 && cx < edge {
            cx += 1
            while cx < edge && !tabs[cx] { cx += 1 }
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
        let s = savedCursor(x: cx, y: cy, pen: pen, origin: originMode, g0: g0, g1: g1, g2: g2, g3: g3, gl: gl, pendingWrap: pendingWrap)
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
        g2 = s.g2
        g3 = s.g3
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
        // Each screen keeps its own keyboard flags (kitty's protocol).
        let k = kittyStack
        kittyStack = kittyStackAlt
        kittyStackAlt = k
        KittyFlags = kittyStack.last ?? 0
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
        g2 = .ascii
        g3 = .ascii
        gl = 0
        singleShift = 0
        top = 0
        bottom = Rows - 1
        left = 0
        right = Columns - 1
        lrMarginMode = false
        rectExtent = false
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
        CursorStyleSet = false
        BracketedPaste = false
        Mouse = .off
        MouseFormat = .x10
        FocusReporting = false
        ReverseVideo = false
        BackspaceSendsBS = false
        SynchronizedOutput = false
        KittyFlags = 0
        kittyStack = []
        kittyStackAlt = []
        Title = ""
        titleStack = []
        Progress = .none
        ProgressValue = 0
        palette = [uint32](repeating: noColor, count: 256)
        fgOverride = noColor
        bgOverride = noColor
        cursorOverride = noColor
        PaletteVersion += 1
        Images = []
        ImagesVersion += 1
        for i in 0..<Rows { screen[i].Rendition = .single }
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
        left = 0
        right = Columns - 1
        lrMarginMode = false
        pen = Cell.blank
        g0 = .ascii
        g1 = .ascii
        g2 = .ascii
        g3 = .ascii
        gl = 0
        singleShift = 0
        saved = savedCursor()
        pendingWrap = false
        Version += 1
    }

    func respond(_ s: string) {
        responses.append(contentsOf: [uint8](s.utf8))
    }
}

/// No color set: the theme's.
let noColor: uint32 = 0xFFFFFFFF

func rgbOf(_ v: uint32) -> (R: uint8, G: uint8, B: uint8) {
    return (R: uint8((v >> 16) & 0xFF), G: uint8((v >> 8) & 0xFF), B: uint8(v & 0xFF))
}

/// Text for a case-insensitive search: its code points, folded.
func foldText(_ s: string, _ caseSensitive: bool) -> [uint32] {
    var out: [uint32] = []
    for u in s.unicodeScalars { out.append(caseSensitive ? uint32(u.value) : foldRune(uint32(u.value))) }
    return out
}

/// A code point as a case-insensitive search compares it.
func foldRune(_ cp: uint32) -> uint32 {
    if cp < 0x80 { return cp >= 0x41 && cp <= 0x5A ? cp + 32 : cp }
    return unicode.CaseFold(cp)
}

// DEC Special Graphics: what 0x5F-0x7E draw while the line-drawing set is
// in use (tmux's and mc's borders).
let lineDrawingTable: [uint32] = [
    0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0, 0x00B1, 0x2424, 0x240B, 0x2518,
    0x2510, 0x250C, 0x2514, 0x253C, 0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534,
    0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7,
]
