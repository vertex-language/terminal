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
    eq(text(t.TakeResponses()), "\u{1b}[?65;1;4;6;21;22;28;52c", "device attributes")
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

func reflowing() {
    let t = vt.Terminal(columns: 10, rows: 3)
    t.Feed("abcdefghijKLMNO\r\nxy")
    eq(row(t, 0), "abcdefghij", "a long line wraps")
    t.Resize(columns: 20, rows: 3)
    eq(row(t, 0), "abcdefghijKLMNO", "widening joins it again")
    eq(row(t, 1), "xy", "the next line follows")
    check(t.CursorX == 2 && t.CursorY == 1, "the cursor stays after its text (\(t.CursorX),\(t.CursorY))")
    t.Resize(columns: 5, rows: 3)
    eq(t.ScreenText(), "fghij\nKLMNO\nxy", "narrowing rewraps, the top to the scrollback")
    check(t.ScrollbackCount == 1, "one row above (\(t.ScrollbackCount))")
    eq(t.Text(fromColumn: 0, line: 0, toColumn: 4, line: 2), "abcdefghijKLMNO", "copied whole across the rewrap")
    let w = vt.Terminal(columns: 5, rows: 2)
    w.Feed("ab日本")
    w.Resize(columns: 4, rows: 2)
    eq(row(w, 0), "ab日", "a wide character is not split")
    eq(row(w, 1), "本", "it goes to the next row")
    let a = vt.Terminal(columns: 6, rows: 2)
    a.Feed("\u{1b}[?1049habcdefgh")
    a.Resize(columns: 3, rows: 2)
    check(a.AltScreen && a.Row(0).Cells.count == 3, "the alternate screen is cut, not reflowed")
}

func graphemes() {
    let t = vt.Terminal(columns: 10, rows: 1)
    t.Feed("e\u{301}x")
    eq(row(t, 0), "e\u{301}x", "a combining mark stays with its letter")
    check(t.CursorX == 2, "and takes no cell")
    let f = vt.Terminal(columns: 10, rows: 1)
    f.Feed("\u{1F1EF}\u{1F1F5}!")
    eq(row(f, 0), "\u{1F1EF}\u{1F1F5}!", "a flag is one cluster")
    check(f.CursorX == 3, "two cells wide (\(f.CursorX))")
    let z = vt.Terminal(columns: 10, rows: 1)
    z.Feed("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}.")
    eq(row(z, 0), "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}.", "a ZWJ family is one cluster")
    check(z.CursorX == 3, "in two cells (\(z.CursorX))")
}

func hyperlinks() {
    let t = vt.Terminal(columns: 20, rows: 1)
    t.Feed("a\u{1b}]8;;https://example.com\u{1b}\\link\u{1b}]8;;\u{1b}\\b")
    let r = t.Row(0)
    check(r.Cells[0].Link == 0 && r.Cells[5].Link == 0, "text around a link isn't linked")
    eq(vt.LinkURI(r.Cells[1].Link), "https://example.com", "OSC 8 links its text")
    check(r.Cells[4].Link == r.Cells[1].Link, "all of it")
}

func shellMarks() {
    let t = vt.Terminal(columns: 20, rows: 6)
    t.Feed("\u{1b}]133;A\u{07}$ \u{1b}]133;B\u{07}ls\r\n\u{1b}]133;C\u{07}one\r\ntwo\r\n\u{1b}]133;D;1\u{07}\u{1b}]133;A\u{07}$ ")
    let marks = t.Marks()
    check(marks.count == 3, "prompt, output, prompt marked (\(marks.count))")
    check(t.Row(0).Mark == .prompt && t.Row(1).Mark == .output, "the kinds")
    check(t.Row(0).ExitCode == 1, "the command's status on its prompt")
    check(t.NextPrompt(after: 0) == 3 && t.PreviousPrompt(before: 3) == 0, "prompt to prompt")
    if let out = t.CommandOutput(at: 0) {
        check(out.From == 1 && out.To == 2, "the command's output lines")
    } else {
        check(false, "the command's output lines")
    }
}

func colors() {
    let t = vt.Terminal()
    t.Feed("\u{1b}]4;1;rgb:ff/80/00\u{07}")
    let c = t.PaletteColor(1)
    check(c != nil && c!.R == 0xFF && c!.G == 0x80 && c!.B == 0, "OSC 4 sets a palette color")
    t.Feed("\u{1b}]4;1;?\u{07}")
    eq(text(t.TakeResponses()), "\u{1b}]4;1;rgb:ffff/8080/0000\u{1b}\\", "and reports it")
    t.Feed("\u{1b}]104;1\u{07}")
    check(t.PaletteColor(1) == nil, "OSC 104 resets it")
    t.Feed("\u{1b}]10;#102030\u{07}\u{1b}]11;rgb:4/5/6\u{07}")
    check(t.ForegroundOverride != nil && t.ForegroundOverride!.G == 0x20, "OSC 10 sets the foreground")
    check(t.BackgroundOverride != nil && t.BackgroundOverride!.R == 0x44, "OSC 11, one hex digit each")
    t.Feed("\u{1b}]110\u{07}\u{1b}]111\u{07}")
    check(t.ForegroundOverride == nil && t.BackgroundOverride == nil, "OSC 110, 111 reset them")
    t.Feed("\u{1b}[58:2::1:2:3m\u{1b}[4:4mU")
    check(t.Row(0).Cells[0].Ul == vt.Color.RGB(1, 2, 3) && t.Row(0).Cells[0].Has(vt.Attr.dottedUnderline), "underline color and a dotted underline")
}

func titlesAndReports() {
    let t = vt.Terminal(columns: 80, rows: 24)
    t.Feed("\u{1b}]2;one\u{07}\u{1b}[22t\u{1b}]2;two\u{07}")
    eq(t.Title, "two", "a title set over a pushed one")
    t.Feed("\u{1b}[23t")
    eq(t.Title, "one", "XTWINOPS 23 pops it")
    t.Feed("\u{1b}[1;31m\u{1b}P$qm\u{1b}\\")
    eq(text(t.TakeResponses()), "\u{1b}P1$r0;1;31m\u{1b}\\", "DECRQSS m")
    t.Feed("\u{1b}[5;20r\u{1b}P$qr\u{1b}\\")
    eq(text(t.TakeResponses()), "\u{1b}P1$r5;20r\u{1b}\\", "DECRQSS r")
    t.Feed("\u{1b}[=c")
    eq(text(t.TakeResponses()), "\u{1b}P!|00000000\u{1b}\\", "DA3")
    t.Feed("\u{1b}]9;4;1;42\u{07}")
    check(t.Progress == .normal && t.ProgressValue == 42, "OSC 9;4 progress")
    t.Feed("\u{1b}]777;notify;Done;Build finished\u{07}")
    let n = t.TakeNotifications()
    check(n.count == 1 && n[0].Title == "Done" && n[0].Body == "Build finished", "OSC 777 notification")
    t.Feed("\u{1b}]9;9;\"/tmp/x\"\u{07}")
    eq(t.WorkingDirectory ?? "nil", "/tmp/x", "OSC 9;9 working directory")
    t.Feed("\u{1b}[?2026h")
    check(t.SynchronizedOutput, "2026 synchronized output")
    t.Feed("\u{1b}[?2026$p")
    eq(text(t.TakeResponses()), "\u{1b}[?2026;1$y", "and DECRQM knows it")
}

func margins() {
    let t = vt.Terminal(columns: 10, rows: 3)
    t.Feed("0123456789\r\n0123456789\r\n0123456789")
    t.Feed("\u{1b}[?69h\u{1b}[3;6s")   // columns 3-6
    t.Feed("\u{1b}[1;3H\u{1b}[2@")
    eq(row(t, 0), "01  236789", "ICH inside the margins")
    t.Feed("\u{1b}[2;3H\u{1b}[P")
    eq(row(t, 1), "01345 6789", "DCH inside the margins")
    t.Feed("\u{1b}[3;1H\u{1b}[1;3r\u{1b}[3;3H\n")
    eq(row(t, 1), "0123456789", "scrolling inside the margins moves their columns up")
    eq(row(t, 2), "01    6789", "and blanks them at the bottom")
    let w = vt.Terminal(columns: 10, rows: 2)
    w.Feed("\u{1b}[?69h\u{1b}[1;5s\u{1b}[1;1Habcdefg")
    eq(row(w, 0), "abcde", "text wraps at the right margin")
    eq(row(w, 1), "fg", "onto the left margin")
}

func rectangles() {
    let t = vt.Terminal(columns: 6, rows: 3)
    t.Feed("abcdef\r\nghijkl\r\nmnopqr")
    t.Feed("\u{1b}[42;1;2;2;3$x")
    eq(row(t, 0), "a**def", "DECFRA fills")
    eq(row(t, 1), "g**jkl", "both rows")
    t.Feed("\u{1b}[1;1;2;2$z")
    eq(row(t, 0), "  *def", "DECERA erases")
    t.Feed("\u{1b}[3;4;3;6;1;1$v")
    eq(row(t, 0), "pqrdef", "DECCRA copies")
    t.Feed("\u{1b}[2*x\u{1b}[3;1;3;2;1$r")
    check(t.Row(2).Cells[0].Has(vt.Attr.bold) && !t.Row(2).Cells[2].Has(vt.Attr.bold), "DECCARA in a rectangle")
    t.Feed("\u{1b}[1;1H\u{1b}[1\"qPP\u{1b}[0\"q\u{1b}[?2K")
    eq(row(t, 0), "PP", "DECSEL keeps protected cells")
    t.Feed("\u{1b}[1;1H\u{1b}[2'}")
    eq(row(t, 0), "  PP", "DECIC inserts columns")
}

func kittyKeys() {
    let t = vt.Terminal()
    let none = vt.Modifiers()
    t.Feed("\u{1b}[>1u")
    check(t.KittyFlags == 1, "CSI > u pushes the flags")
    eq(text(t.EncodeKey(key: "Escape", code: "Escape", none)), "\u{1b}[27u", "Escape disambiguated")
    eq(text(t.EncodeKey(key: "c", code: "KeyC", vt.Modifiers(control: true))), "\u{1b}[99;5u", "Ctrl-C as CSI u")
    eq(text(t.EncodeKey(key: "a", code: "KeyA", none)), "nil", "a plain letter is still text")
    eq(text(t.EncodeKey(key: "Enter", code: "Enter", vt.Modifiers(shift: true))), "\u{1b}[13;2u", "Shift-Enter")
    t.Feed("\u{1b}[=9;1u")
    eq(text(t.EncodeKey(key: "a", code: "KeyA", none)), "\u{1b}[97u", "all keys as escapes")
    t.Feed("\u{1b}[?u")
    eq(text(t.TakeResponses()), "\u{1b}[?9u", "the flags, asked")
    t.Feed("\u{1b}[<u")
    check(t.KittyFlags == 0, "CSI < u pops them")
    t.Feed("\u{1b}[?67h")
    eq(text(t.EncodeKey(key: "Backspace", code: "Backspace", none)), "\u{08}", "DECBKM: Backspace sends BS")
}

func mouseFormats() {
    let t = vt.Terminal()
    let none = vt.Modifiers()
    t.Feed("\u{1b}[?1000h\u{1b}[?1015h")
    eq(text(t.EncodeMouse(button: 0, column: 2, row: 3, kind: "press", none)), "\u{1b}[32;3;4M", "urxvt mouse")
    t.Feed("\u{1b}[?1016h")
    eq(text(t.EncodeMouse(button: 0, column: 2, row: 3, kind: "press", none, pixelX: 20, pixelY: 30)), "\u{1b}[<0;21;31M", "SGR pixel mouse")
}

func sixels() {
    let t = vt.Terminal(columns: 20, rows: 10)
    t.CellPixelWidth = 4
    t.CellPixelHeight = 6
    // Two bands of red, 8 pixels wide.
    t.Feed("\u{1b}Pq#1;2;100;0;0#1!8~-!8~\u{1b}\\")
    check(t.Images.count == 1, "a sixel image is kept")
    if let img = t.Images.first {
        check(img.Width == 8 && img.Height == 12, "its size (\(img.Width)×\(img.Height))")
        check(img.Pixels[0] == 255 && img.Pixels[1] == 0 && img.Pixels[3] == 255, "its color")
        check(t.ImageLine(img) == 0 && img.Column == 0, "where it was drawn")
    }
    check(t.CursorY == 2 && t.CursorX == 0, "the cursor goes below it (\(t.CursorX),\(t.CursorY))")
}

func searching() {
    let t = vt.Terminal(columns: 8, rows: 3)
    t.Feed("Hello world\r\nhello")
    let hits = t.Find("hello")
    check(hits.count == 2, "two matches, case folded (\(hits.count))")
    check(hits[0].StartLine == 0 && hits[0].StartColumn == 0, "the first")
    check(t.Find("lo wo").count == 1, "a match across a wrap")
    check(t.Find("hello", caseSensitive: true).count == 1, "case-sensitive")
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
reflowing()
graphemes()
hyperlinks()
shellMarks()
colors()
titlesAndReports()
margins()
rectangles()
kittyKeys()
mouseFormats()
sixels()
searching()
throughput()

if failures > 0 {
    print("\(failures) failed")
    process.Exit(1)
}
print("all ok")
