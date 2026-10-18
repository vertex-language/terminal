package vt

/// The modifier keys held with a key or a mouse event.
public struct Modifiers: Equatable {
    public var Shift: bool
    public var Alt: bool
    public var Control: bool
    public var Meta: bool

    public init(shift: bool = false, alt: bool = false, control: bool = false, meta: bool = false) {
        Shift = shift
        Alt = alt
        Control = control
        Meta = meta
    }

    /// xterm's modifier parameter: 1 + Shift 1, Alt 2, Control 4, Meta 8.
    var param: int {
        var m = 1
        if Shift { m += 1 }
        if Alt { m += 2 }
        if Control { m += 4 }
        if Meta { m += 8 }
        return m
    }

    var any: bool { return Shift || Alt || Control || Meta }
}

extension Terminal {
    /// What a key sends, by its W3C names (`key` "a", "Enter", "ArrowUp";
    /// `code` "KeyA", "Enter"): the bytes for keys that aren't text --
    /// Enter, arrows, function keys, Control and Alt combinations -- or nil
    /// for a key whose text arrives as text (a letter, a digit) and for
    /// Command combinations, which are the host's shortcuts. With
    /// altSendsEscape, Alt (Option) with a key sends ESC before it, as
    /// shells' Meta bindings want.
    public func EncodeKey(key: string, code: string, _ mods: Modifiers, altSendsEscape: bool = false) -> [uint8]? {
        if mods.Meta { return nil }
        if KittyFlags != 0, let k = kittyKey(key: key, code: code, mods) { return k }
        let m = mods.param
        let esc: uint8 = 0x1B
        func csi(_ final: string, _ n: int = 1) -> [uint8] {
            if m > 1 { return [uint8]("\u{1b}[\(n);\(m)\(final)".utf8) }
            return n == 1 ? [uint8]("\u{1b}[\(final)".utf8) : [uint8]("\u{1b}[\(n)\(final)".utf8)
        }
        func ss3(_ final: string) -> [uint8] {
            if m > 1 { return [uint8]("\u{1b}[1;\(m)\(final)".utf8) }
            return [uint8]("\u{1b}O\(final)".utf8)
        }
        func cursor(_ final: string) -> [uint8] {
            if m == 1 && AppCursorKeys { return [uint8]("\u{1b}O\(final)".utf8) }
            if m > 1 { return [uint8]("\u{1b}[1;\(m)\(final)".utf8) }
            return [uint8]("\u{1b}[\(final)".utf8)
        }
        func tilde(_ n: int) -> [uint8] {
            if m > 1 { return [uint8]("\u{1b}[\(n);\(m)~".utf8) }
            return [uint8]("\u{1b}[\(n)~".utf8)
        }
        let alt = mods.Alt && altSendsEscape
        switch key {
        case "Enter":
            if newlineMode { return alt ? [esc, 13, 10] : [13, 10] }
            return alt ? [esc, 13] : [13]
        case "Backspace":
            // DECBKM swaps them.
            let b: uint8 = mods.Control != BackspaceSendsBS ? 0x08 : 0x7F
            return alt ? [esc, b] : [b]
        case "Tab":
            if mods.Shift { return [uint8]("\u{1b}[Z".utf8) }
            return alt ? [esc, 9] : [9]
        case "Escape":
            return alt ? [esc, esc] : [esc]
        case "ArrowUp": return cursor("A")
        case "ArrowDown": return cursor("B")
        case "ArrowRight": return cursor("C")
        case "ArrowLeft": return cursor("D")
        case "Home": return cursor("H")
        case "End": return cursor("F")
        case "Insert": return tilde(2)
        case "Delete": return tilde(3)
        case "PageUp": return tilde(5)
        case "PageDown": return tilde(6)
        case "F1": return ss3("P")
        case "F2": return ss3("Q")
        case "F3": return ss3("R")
        case "F4": return ss3("S")
        case "F5": return tilde(15)
        case "F6": return tilde(17)
        case "F7": return tilde(18)
        case "F8": return tilde(19)
        case "F9": return tilde(20)
        case "F10": return tilde(21)
        case "F11": return tilde(23)
        case "F12": return tilde(24)
        default: break
        }
        // Control with a key: the C0 control it names. By where the key is
        // (code), so it works whatever the layout makes of it.
        if mods.Control {
            var c: uint8? = nil
            let cb = [uint8](code.utf8)
            if cb.count == 4 && code.hasPrefix("Key") {
                c = cb[3] - 0x40  // KeyA -> 1
            } else {
                switch code {
                case "Space", "Digit2": c = 0
                case "BracketLeft", "Digit3": c = 0x1B
                case "Backslash", "Digit4": c = 0x1C
                case "BracketRight", "Digit5": c = 0x1D
                case "Digit6": c = 0x1E
                case "Minus", "Slash", "Digit7": c = 0x1F
                case "Digit8": c = 0x7F
                default: break
                }
            }
            if let v = c { return alt ? [esc, v] : [v] }
            return nil
        }
        // Alt with a printable key: ESC and the key's unshifted-by-Option
        // character, where Option is Meta.
        if alt {
            let kb = [uint8](key.utf8)
            if kb.count == 1 && kb[0] >= 0x20 && kb[0] < 0x7F { return [esc, kb[0]] }
            let cb = [uint8](code.utf8)
            if cb.count == 4 && code.hasPrefix("Key") {
                let ch = mods.Shift ? cb[3] : cb[3] + 0x20
                return [esc, ch]
            }
            if cb.count == 6 && code.hasPrefix("Digit") { return [esc, cb[5]] }
        }
        return nil
    }

    /// A key as the kitty keyboard protocol sends it, for the flags the
    /// program pushed; nil where the legacy encoding is the same, or the
    /// key is plain text.
    func kittyKey(key: string, code: string, _ mods: Modifiers) -> [uint8]? {
        let f = KittyFlags
        let all = f & 8 != 0
        let m = mods.param
        var number = 0
        var final = "u"
        switch key {
        case "Escape": number = 27
        case "Enter": number = 13
        case "Tab": number = 9
        case "Backspace": number = 127
        case "Insert": number = 2; final = "~"
        case "Delete": number = 3; final = "~"
        case "ArrowLeft": number = 1; final = "D"
        case "ArrowRight": number = 1; final = "C"
        case "ArrowUp": number = 1; final = "A"
        case "ArrowDown": number = 1; final = "B"
        case "Home": number = 1; final = "H"
        case "End": number = 1; final = "F"
        case "PageUp": number = 5; final = "~"
        case "PageDown": number = 6; final = "~"
        case "F1": number = 1; final = "P"
        case "F2": number = 1; final = "Q"
        case "F3": number = 13; final = "~"
        case "F4": number = 1; final = "S"
        case "F5": number = 15; final = "~"
        case "F6": number = 17; final = "~"
        case "F7": number = 18; final = "~"
        case "F8": number = 19; final = "~"
        case "F9": number = 20; final = "~"
        case "F10": number = 21; final = "~"
        case "F11": number = 23; final = "~"
        case "F12": number = 24; final = "~"
        default: break
        }
        func seq(_ n: int, _ fin: string, text: string = "") -> [uint8] {
            var body = n == 1 && fin != "u" && m == 1 ? "" : "\(n)"
            if m > 1 || !text.isEmpty { body += ";\(m)" }
            if !text.isEmpty { body += ";" + text }
            return [uint8]("\u{1b}[\(body)\(fin)".utf8)
        }
        if number != 0 {
            if final != "u" {
                // Arrows, the editing keys and F1-F12: as legacy writes
                // them, unless every key is to be an escape.
                return all ? seq(number, final) : nil
            }
            if number == 27 { return seq(27, "u") }
            if all || (m > 1 && !(number == 9 && m == 2)) { return seq(number, "u") }
            return nil
        }
        // A text key: by its unshifted character, where the layout puts it.
        var cp: uint32 = 0
        let cb = [uint8](code.utf8)
        if cb.count == 4 && code.hasPrefix("Key") {
            cp = uint32(cb[3]) + 0x20
        } else if cb.count == 6 && code.hasPrefix("Digit") {
            cp = uint32(cb[5])
        } else if code == "Space" {
            cp = 32
        } else {
            let scalars = Array(key.unicodeScalars)
            if scalars.count != 1 { return nil }
            cp = foldRune(uint32(scalars[0].value))
        }
        let modsBeyondShift = mods.Control || mods.Alt
        if all {
            var text = ""
            if f & 16 != 0 && !modsBeyondShift {
                let scalars = Array(key.unicodeScalars)
                text = scalars.map { "\($0.value)" }.joined(separator: ":")
            }
            return seq(int(cp), "u", text: text)
        }
        if f & 1 != 0 && modsBeyondShift { return seq(int(cp), "u") }
        return nil
    }

    /// Text typed (or pasted without bracketing): its bytes, with newlines
    /// as carriage returns, as a terminal sends Enter.
    public func EncodeText(_ text: string) -> [uint8] {
        var out: [uint8] = []
        for b in text.utf8 {
            out.append(b == 10 ? 13 : b)
        }
        return out
    }

    /// A paste: bracketed where the program asked (mode 2004), so an
    /// editor or shell knows it wasn't typed; line breaks become carriage
    /// returns either way.
    public func EncodePaste(_ text: string) -> [uint8] {
        var body: [uint8] = []
        let b = [uint8](text.utf8)
        var i = 0
        while i < b.count {
            if b[i] == 13 && i + 1 < b.count && b[i + 1] == 10 {
                body.append(13)
                i += 2
                continue
            }
            // A pasted end-of-paste sequence would end the bracket early.
            if BracketedPaste && b[i] == 0x1B { i += 1; continue }
            body.append(b[i] == 10 ? 13 : b[i])
            i += 1
        }
        if !BracketedPaste { return body }
        var out = [uint8]("\u{1b}[200~".utf8)
        out.append(contentsOf: body)
        out.append(contentsOf: [uint8]("\u{1b}[201~".utf8))
        return out
    }

    /// Focus coming (true) or going: what to send where the program asked
    /// to be told (mode 1004), else nil.
    public func EncodeFocus(_ focused: bool) -> [uint8]? {
        if !FocusReporting { return nil }
        return [uint8](focused ? "\u{1b}[I".utf8 : "\u{1b}[O".utf8)
    }

    /// A mouse event at a cell (column, row from 0) for the program, where
    /// it asked for mouse reports, else nil. button: 0 left, 1 middle, 2
    /// right, 64/65 wheel up and down; kind: "press", "release", "move"
    /// (with the button held, or -1 for none).
    public func EncodeMouse(button: int, column: int, row: int, kind: string, _ mods: Modifiers,
                            pixelX: int = -1, pixelY: int = -1) -> [uint8]? {
        if Mouse == .off { return nil }
        if kind == "move" {
            if Mouse == .clicks { return nil }
            if Mouse == .drag && button < 0 { return nil }
        }
        var b = button < 0 ? 3 : button
        if kind == "move" { b += 32 }
        if mods.Shift { b += 4 }
        if mods.Alt { b += 8 }
        if mods.Control { b += 16 }
        let x = max(0, min(column, Columns - 1)) + 1
        let y = max(0, min(row, Rows - 1)) + 1
        switch MouseFormat {
        case .sgr, .sgrPixels:
            let f = kind == "release" ? "m" : "M"
            if MouseFormat == .sgrPixels && pixelX >= 0 {
                return [uint8]("\u{1b}[<\(b);\(pixelX + 1);\(pixelY + 1)\(f)".utf8)
            }
            return [uint8]("\u{1b}[<\(b);\(x);\(y)\(f)".utf8)
        default:
            break
        }
        // The others: a release is button 3.
        if kind == "release" && button < 64 { b = (b & ~3) | 3 }
        if MouseFormat == .urxvt {
            return [uint8]("\u{1b}[\(32 + b);\(x);\(y)M".utf8)
        }
        if MouseFormat == .utf8 {
            // Each coordinate as UTF-8, to 2015.
            if x > 2015 || y > 2015 { return nil }
            var out: [uint8] = [0x1B, 0x5B, 0x4D, uint8(32 + b)]
            appendUTF8(&out, uint32(32 + x))
            appendUTF8(&out, uint32(32 + y))
            return out
        }
        // X10: coordinates past 223 can't be said.
        if x > 223 || y > 223 { return nil }
        return [0x1B, 0x5B, 0x4D, uint8(32 + b), uint8(32 + x), uint8(32 + y)]
    }
}
