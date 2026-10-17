// check: the terminal repository's offline checks. vt is fed what
// programs write and the screen it keeps is compared with what xterm
// shows; the keys, mouse and paste encodings with what xterm sends.
//
//     vsc run check
package main

import (
    "os/process"
    "terminal/vt"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok   \(what)")
    } else {
        print("FAIL \(what)")
        failures += 1
    }
}

func eq(_ got: string, _ want: string, _ what: string) {
    check(got == want, got == want ? what : "\(what): got \(got.debugDescription), want \(want.debugDescription)")
}

func bytes(_ s: string) -> [uint8] { return [uint8](s.utf8) }

func text(_ b: [uint8]?) -> string {
    guard let b = b else { return "nil" }
    return string(decoding: b, as: UTF8.self)
}

func row(_ t: vt.Terminal, _ y: int) -> string { return t.Row(y).Text() }

func basics() {
    let t = vt.Terminal(columns: 10, rows: 3)
    t.Feed("hello")
    eq(row(t, 0), "hello", "plain text")
    check(t.CursorX == 5 && t.CursorY == 0, "cursor after text")
    t.Feed("\r\nworld")
    eq(row(t, 1), "world", "CR LF")
    t.Feed("\r\nabcdefghijKL")
    eq(row(t, 2), "KL", "wrap scrolls")
    eq(row(t, 1), "abcdefghij", "wrapped row")
    check(t.Row(1).Wrapped, "soft wrap marked")
    check(t.ScrollbackCount == 1, "scrolled line kept (\(t.ScrollbackCount))")
    eq(t.Absolute(0).Text(), "hello", "scrollback line")
    eq(t.Text(fromColumn: 0, line: 2, toColumn: 9, line: 3), "abcdefghijKL", "copy joins a wrap")
}

func pendingWrap() {
    let t = vt.Terminal(columns: 5, rows: 2)
    t.Feed("abcde")
    check(t.CursorX == 4 && t.CursorY == 0, "cursor stays at the margin")
    t.Feed("\r")
    t.Feed("X")
    eq(row(t, 0), "Xbcde", "CR clears the pending wrap")
    t.Feed("\u{1b}[?7l\u{1b}[1;1Hhello world")
    eq(row(t, 0), "helld", "no autowrap overwrites the last column")
}

func cursorAndErase() {
    let t = vt.Terminal(columns: 10, rows: 4)
    t.Feed("0123456789\r\n0123456789\r\n0123456789\r\n0123456789")
    t.Feed("\u{1b}[2;3H")
    check(t.CursorX == 2 && t.CursorY == 1, "CUP")
    t.Feed("\u{1b}[K")
    eq(row(t, 1), "01", "EL 0")
    t.Feed("\u{1b}[3;5H\u{1b}[1K")
    eq(row(t, 2), "     56789", "EL 1")
    t.Feed("\u{1b}[4;1H\u{1b}[2K")
    eq(row(t, 3), "", "EL 2")
    t.Feed("\u{1b}[1;4H\u{1b}[2P")
    eq(row(t, 0), "01256789", "DCH")
    t.Feed("\u{1b}[2@")
    eq(row(t, 0), "012  56789", "ICH")
    t.Feed("\u{1b}[3X")
    eq(row(t, 0), "012   6789", "ECH")
    t.Feed("\u{1b}[5C")
    check(t.CursorX == 8, "CUF")
    t.Feed("\u{1b}[20C")
    check(t.CursorX == 9, "CUF stops at the margin")
    t.Feed("\u{1b}[2J")
    eq(t.ScreenText(), "\n\n\n", "ED 2")
}

func scrolling() {
    let t = vt.Terminal(columns: 5, rows: 5)
    t.Feed("a\r\nb\r\nc\r\nd\r\ne")
    t.Feed("\u{1b}[2;4r")        // region rows 2-4
    t.Feed("\u{1b}[4;1H\n")       // LF at the region's bottom
    eq(t.ScreenText(), "a\nc\nd\n\ne", "region scroll up")
    check(t.ScrollbackCount == 0, "region scroll keeps no scrollback")
    t.Feed("\u{1b}[2;1H\u{1b}M")  // RI at the region's top
    eq(t.ScreenText(), "a\n\nc\nd\ne", "reverse index scrolls down")
    t.Feed("\u{1b}[3;1H\u{1b}[L")
    eq(t.ScreenText(), "a\n\n\nc\ne", "IL in region")
    t.Feed("\u{1b}[2;1H\u{1b}[2M")
    eq(t.ScreenText(), "a\nc\n\n\ne", "DL in region")
    t.Feed("\u{1b}[r\u{1b}[5;1H\n")
    eq(t.ScreenText(), "c\n\n\ne\n", "region reset, full scroll")
    check(t.ScrollbackCount == 1, "full-screen scroll keeps the line")
    t.Feed("\u{1b}[2S")
    eq(t.ScreenText(), "\ne\n\n\n", "SU")
    t.Feed("\u{1b}[T")
    eq(t.ScreenText(), "\n\ne\n\n", "SD")
}

func sgr() {
    let t = vt.Terminal(columns: 20, rows: 2)
    t.Feed("\u{1b}[1;31mA\u{1b}[0mB\u{1b}[38;5;200mC\u{1b}[38;2;1;2;3mD\u{1b}[48:2::10:20:30mE\u{1b}[4:3;7mF\u{1b}[92;104mG\u{1b}[39;49;22;24;27mH")
    let r = t.Row(0)
    check(r.Cells[0].Has(vt.Attr.bold) && r.Cells[0].Fg == vt.Color.Indexed(1), "bold red")
    check(r.Cells[1].Attrs == 0 && r.Cells[1].Fg.IsDefault, "reset")
    check(r.Cells[2].Fg == vt.Color.Indexed(200), "256 colors")
    check(r.Cells[3].Fg == vt.Color.RGB(1, 2, 3), "truecolor, semicolons")
    check(r.Cells[4].Bg == vt.Color.RGB(10, 20, 30), "truecolor, colons")
    check(r.Cells[5].Has(vt.Attr.curlyUnderline) && r.Cells[5].Has(vt.Attr.inverse), "curly underline and inverse")
    check(r.Cells[6].Fg == vt.Color.Indexed(10) && r.Cells[6].Bg == vt.Color.Indexed(12), "bright colors")
    check(r.Cells[7].Attrs == 0 && r.Cells[7].Fg.IsDefault && r.Cells[7].Bg.IsDefault, "individual resets")
    t.Feed("\u{1b}[44m\u{1b}[2;1H\u{1b}[K")
    check(t.Row(1).Cells[5].Bg == vt.Color.Indexed(4), "erase uses the background (BCE)")
}

func unicodeText() {
    let t = vt.Terminal(columns: 6, rows: 2)
    t.Feed("é日本")
    let r = t.Row(0)
    check(r.Cells[0].Rune == 0xE9, "two-byte UTF-8")
    check(r.Cells[1].Rune == 0x65E5 && r.Cells[1].Has(vt.Attr.wide) && r.Cells[2].Has(vt.Attr.spacer), "wide character takes two cells")
    check(t.CursorX == 5, "cursor after wide characters (\(t.CursorX))")
    eq(row(t, 0), "é日本", "row text skips spacers")
    t.Feed("x日")
    eq(row(t, 1), "日", "a wide character that doesn't fit wraps")
    let split = vt.Terminal(columns: 6, rows: 1)
    split.Feed([0xE2, 0x82])
    split.Feed([0xAC])
    check(split.Row(0).Cells[0].Rune == 0x20AC, "UTF-8 split across feeds")
    split.Feed([0xFF, 0x41])
    check(split.Row(0).Cells[1].Rune == 0xFFFD && split.Row(0).Cells[2].Rune == 0x41, "invalid byte is U+FFFD")
    let o = vt.Terminal(columns: 6, rows: 1)
    o.Feed("ab日")
    o.Feed("\u{1b}[1;4Hx")
    check(o.Row(0).Cells[2].Rune == 0 && o.Row(0).Cells[3].Rune == 0x78, "overwriting a spacer blanks its wide half")
}

func lineDrawing() {
    let t = vt.Terminal(columns: 6, rows: 1)
    t.Feed("\u{1b}(0lqk\u{1b}(Bq")
    eq(row(t, 0), "┌─┐q", "DEC special graphics")
    let s = vt.Terminal(columns: 6, rows: 1)
    s.Feed("\u{1b})0a\u{0e}x\u{0f}x")
    eq(row(s, 0), "a│x", "G1 with SO and SI")
}

func altScreen() {
    let t = vt.Terminal(columns: 8, rows: 3)
    t.Feed("shell$ ")
    t.Feed("\u{1b}[?1049h")
    check(t.AltScreen, "1049 enters the alternate screen")
    eq(t.ScreenText(), "\n\n", "alternate screen is blank")
    t.Feed("\u{1b}[2;2Hvim")
    t.Feed("\u{1b}[?1049l")
    check(!t.AltScreen, "1049 leaves")
    eq(row(t, 0), "shell$", "main screen is back")
    check(t.CursorX == 7 && t.CursorY == 0, "cursor restored")
    check(t.ScrollbackCount == 0, "the alternate screen keeps no scrollback")
}

func modesAndReports() {
    let t = vt.Terminal(columns: 80, rows: 24)
    t.Feed("\u{1b}[5;10H\u{1b}[6n")
    eq(text(t.TakeResponses()), "\u{1b}[5;10R", "cursor position report")
    t.Feed("\u{1b}[c")
    eq(text(t.TakeResponses()), "\u{1b}[?62;22c", "device attributes")
    t.Feed("\u{1b}[18t")
    eq(text(t.TakeResponses()), "\u{1b}[8;24;80t", "size report")
    t.Feed("\u{1b}[?1h\u{1b}[?2004h\u{1b}[?1006h\u{1b}[?1002h\u{1b}[?25l\u{1b}[5 q")
    check(t.AppCursorKeys && t.BracketedPaste && t.MouseSGR && t.Mouse == .drag && !t.CursorVisible, "DEC private modes")
    check(t.Shape == .bar && t.CursorBlink, "cursor shape")
    t.Feed("\u{1b}[?2004$p")
    eq(text(t.TakeResponses()), "\u{1b}[?2004;1$y", "DECRQM")
    t.Feed("\u{1b}]0;my title\u{07}")
    eq(t.Title, "my title", "OSC 0 title, BEL")
    t.Feed("\u{1b}]2;other\u{1b}\\")
    eq(t.Title, "other", "OSC 2 title, ST")
    t.Feed("\u{1b}]7;file://host/Users/me/a%20b\u{07}")
    eq(t.WorkingDirectory ?? "nil", "/Users/me/a b", "OSC 7 working directory")
    t.Feed("\u{1b}]11;?\u{07}")
    check(text(t.TakeResponses()).hasPrefix("\u{1b}]11;rgb:"), "OSC 11 query")
    t.Feed("\u{1b}]52;c;aGVsbG8=\u{07}")
    eq(t.TakeClipboard() ?? "nil", "hello", "OSC 52 clipboard")
    t.Feed("\u{1b}P+q544e\u{1b}\\after")
    eq(row(t, 4).hasSuffix("after") ? "after" : row(t, 4), "after", "DCS is skipped")
    t.Feed("\u{07}")
    check(t.Bells == 1, "bell")
    t.Feed("\u{1b}c")
    check(!t.AppCursorKeys && t.CursorVisible && t.ScreenText().allSatisfy { $0 == "\n" }, "RIS")
}

func tabsAndBackspace() {
    let t = vt.Terminal(columns: 20, rows: 1)
    t.Feed("a\tb")
    check(t.Row(0).Cells[8].Rune == 0x62, "tab stop at 8")
    t.Feed("\u{08}\u{08}X")
    check(t.Row(0).Cells[7].Rune == 0x58, "backspace")
    t.Feed("\r\u{1b}[3g\u{1b}[5G\u{1b}H\r\tY")
    check(t.Row(0).Cells[4].Rune == 0x59, "TBC and HTS")
}

func resize() {
    let t = vt.Terminal(columns: 10, rows: 4)
    t.Feed("1\r\n2\r\n3\r\n4")
    t.Resize(columns: 10, rows: 2)
    eq(t.ScreenText(), "3\n4", "shrinking keeps the cursor's rows")
    check(t.ScrollbackCount == 2, "rows above go to the scrollback")
    t.Resize(columns: 10, rows: 4)
    eq(t.ScreenText(), "1\n2\n3\n4", "growing brings them back")
    check(t.CursorY == 3, "cursor follows its row")
    t.Resize(columns: 3, rows: 4)
    check(t.Row(0).Cells.count == 3 && t.Columns == 3, "narrower")
    let b = vt.Terminal(columns: 10, rows: 4)
    b.Feed("top")
    b.Resize(columns: 10, rows: 2)
    eq(b.ScreenText(), "top\n", "empty rows below the cursor go first")
}

func scrollbackView() {
    let t = vt.Terminal(columns: 5, rows: 2)
    t.ScrollbackLimit = 3
    for i in 0..<6 { t.Feed("\(i)\r\n") }
    check(t.ScrollbackCount == 3, "scrollback limit (\(t.ScrollbackCount))")
    eq(t.Absolute(0).Text(), "2", "oldest kept line")
    t.ScrollView(by: 2)
    eq(t.ViewRow(0).Text(), "3", "view scrolled up")
    t.Feed("x\r\n")
    eq(t.ViewRow(0).Text(), "3", "a scrolled view stays put as output arrives")
    t.ScrollToBottom()
    check(t.ViewOffset == 0, "back to the bottom")
    t.Feed("\u{1b}[3J")
    check(t.ScrollbackCount == 0, "ED 3 clears the scrollback")
}

func keys() {
    let t = vt.Terminal()
    let none = vt.Modifiers()
    eq(text(t.EncodeKey(key: "Enter", code: "Enter", none)), "\r", "Enter")
    eq(text(t.EncodeKey(key: "Backspace", code: "Backspace", none)), "\u{7f}", "Backspace")
    eq(text(t.EncodeKey(key: "ArrowUp", code: "ArrowUp", none)), "\u{1b}[A", "Up")
    eq(text(t.EncodeKey(key: "ArrowLeft", code: "ArrowLeft", vt.Modifiers(control: true))), "\u{1b}[1;5D", "Ctrl-Left")
    eq(text(t.EncodeKey(key: "c", code: "KeyC", vt.Modifiers(control: true))), "\u{03}", "Ctrl-C")
    eq(text(t.EncodeKey(key: "[", code: "BracketLeft", vt.Modifiers(control: true))), "\u{1b}", "Ctrl-[")
    eq(text(t.EncodeKey(key: "Tab", code: "Tab", vt.Modifiers(shift: true))), "\u{1b}[Z", "Shift-Tab")
    eq(text(t.EncodeKey(key: "F5", code: "F5", none)), "\u{1b}[15~", "F5")
    eq(text(t.EncodeKey(key: "F1", code: "F1", none)), "\u{1b}OP", "F1")
    eq(text(t.EncodeKey(key: "PageUp", code: "PageUp", vt.Modifiers(shift: true))), "\u{1b}[5;2~", "Shift-PageUp")
    eq(text(t.EncodeKey(key: "a", code: "KeyA", none)), "nil", "a letter is text")
    eq(text(t.EncodeKey(key: "c", code: "KeyC", vt.Modifiers(meta: true))), "nil", "Command is the host's")
    eq(text(t.EncodeKey(key: "b", code: "KeyB", vt.Modifiers(alt: true), altSendsEscape: true)), "\u{1b}b", "Alt as Meta")
    t.Feed("\u{1b}[?1h")
    eq(text(t.EncodeKey(key: "ArrowUp", code: "ArrowUp", none)), "\u{1b}OA", "application cursor keys")
    eq(text(t.EncodePaste("a\nb")), "a\rb", "paste without brackets")
    t.Feed("\u{1b}[?2004h")
    eq(text(t.EncodePaste("x\u{1b}[201~y")), "\u{1b}[200~x[201~y\u{1b}[201~", "bracketed paste, escapes dropped")
}

func mouse() {
    let t = vt.Terminal()
    let none = vt.Modifiers()
    eq(text(t.EncodeMouse(button: 0, column: 0, row: 0, kind: "press", none)), "nil", "no reports unless asked")
    t.Feed("\u{1b}[?1000h")
    eq(text(t.EncodeMouse(button: 0, column: 2, row: 3, kind: "press", none)), "\u{1b}[M #$", "X10 press")
    eq(text(t.EncodeMouse(button: 0, column: 2, row: 3, kind: "move", none)), "nil", "1000 has no motion")
    t.Feed("\u{1b}[?1006h\u{1b}[?1002h")
    eq(text(t.EncodeMouse(button: 0, column: 2, row: 3, kind: "release", none)), "\u{1b}[<0;3;4m", "SGR release")
    eq(text(t.EncodeMouse(button: 0, column: 4, row: 3, kind: "move", none)), "\u{1b}[<32;5;4M", "SGR drag")
    eq(text(t.EncodeMouse(button: 64, column: 0, row: 0, kind: "press", vt.Modifiers(control: true))), "\u{1b}[<80;1;1M", "wheel with Control")
}

func widths() {
    check(vt.CellWidth(0x41) == 1, "ASCII is one cell")
    check(vt.CellWidth(0x4E2D) == 2, "CJK is two")
    check(vt.CellWidth(0x1F600) == 2, "emoji is two")
    check(vt.CellWidth(0x301) == 0, "combining mark is none")
    check(vt.CellWidth(0xAC00) == 2, "Hangul is two")
    check(vt.CellWidth(0xFF21) == 2 && vt.CellWidth(0xFF76) == 1, "fullwidth is two, halfwidth one")
    check(vt.CellWidth(0x3B1) == 1, "ambiguous (α) is one")
    check(vt.CellWidth(0x20000) == 2 && vt.CellWidth(0x9FFF) == 2, "plane 2 and unassigned CJK are two (the UCD's defaults)")
}

func throughput() {
    // A big feed doesn't fall over: 2 MB of colored text through a small
    // screen with a scrollback.
    let t = vt.Terminal(columns: 120, rows: 40)
    var chunk: [uint8] = []
    for i in 0..<200 {
        chunk.append(contentsOf: bytes("\u{1b}[3\(i % 8)mline \(i) the quick brown fox jumps over the lazy dog\u{1b}[0m\r\n"))
    }
    var total = 0
    while total < 2_000_000 {
        t.Feed(chunk)
        total += chunk.count
    }
    check(t.ScrollbackCount == t.ScrollbackLimit, "scrollback full after a big feed")
}

basics()
pendingWrap()
cursorAndErase()
scrolling()
sgr()
unicodeText()
lineDrawing()
altScreen()
modesAndReports()
tabsAndBackspace()
resize()
scrollbackView()
keys()
mouse()
widths()
throughput()

if failures > 0 {
    print("\(failures) failed")
    process.Exit(1)
}
print("all ok")
