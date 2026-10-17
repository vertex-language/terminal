package vt

import "encoding/base64"

// The parser's states: Paul Williams' DEC-compatible state machine
// (vt100.net/emu/dec_ansi_parser), with UTF-8 decoded in the ground state.
enum pstate {
    case ground
    case escape
    case escapeIntermediate
    case csiEntry
    case csiParam
    case csiIntermediate
    case csiIgnore
    case oscString
    /// DCS, SOS, PM and APC: strings that are read to their end and
    /// dropped.
    case ignoredString
}

extension Terminal {
    /// Takes bytes the program wrote: text and escape sequences, in any
    /// pieces (a sequence or a UTF-8 character may be split across calls).
    public func Feed(_ bytes: [uint8]) {
        let n = bytes.count
        var i = 0
        while i < n {
            let b = bytes[i]
            if state == .ground && utf8Need == 0 && b >= 0x20 && b < 0x7F {
                // The common case: a run of printable ASCII.
                put(uint32(b))
                i += 1
                continue
            }
            step(b)
            i += 1
        }
    }

    /// Feeds text, as UTF-8.
    public func Feed(_ text: string) {
        Feed([uint8](text.utf8))
    }

    func step(_ b: uint8) {
        // Bytes that mean the same in every state but a string's.
        if state != .oscString && state != .ignoredString {
            if b == 0x18 || b == 0x1A {  // CAN, SUB: the sequence is abandoned
                state = .ground
                utf8Need = 0
                return
            }
            if b == 0x1B {
                utf8Need = 0
                enterEscape()
                return
            }
        }
        switch state {
        case .ground:
            ground(b)
        case .escape:
            escape(b)
        case .escapeIntermediate:
            if b < 0x20 {
                control(b)
            } else if b < 0x30 {
                intermediates.append(b)
            } else if b < 0x7F {
                escDispatch(b)
                state = .ground
            }
        case .csiEntry, .csiParam:
            csiByte(b)
        case .csiIntermediate:
            if b < 0x20 {
                control(b)
            } else if b < 0x30 {
                intermediates.append(b)
            } else if b < 0x40 {
                state = .csiIgnore
            } else if b < 0x7F {
                csiFinish(b)
            }
        case .csiIgnore:
            if b < 0x20 {
                control(b)
            } else if b >= 0x40 && b < 0x7F {
                state = .ground
            }
        case .oscString:
            oscByte(b)
        case .ignoredString:
            if stringEsc {
                stringEsc = false
                if b == 0x5C {  // ST
                    state = .ground
                    return
                }
            }
            if b == 0x1B {
                stringEsc = true
            } else if b == 0x07 || b == 0x18 || b == 0x1A {
                state = .ground
            }
        }
    }

    func enterEscape() {
        state = .escape
        intermediates = []
    }

    func ground(_ b: uint8) {
        if utf8Need > 0 {
            if b & 0xC0 == 0x80 {
                utf8Code = (utf8Code << 6) | uint32(b & 0x3F)
                utf8Need -= 1
                if utf8Need == 0 { put(utf8Code) }
                return
            }
            // A broken sequence: show the replacement and take this byte
            // afresh.
            utf8Need = 0
            put(0xFFFD)
        }
        if b < 0x20 || b == 0x7F {
            control(b)
        } else if b < 0x80 {
            put(uint32(b))
        } else if b & 0xE0 == 0xC0 {
            utf8Code = uint32(b & 0x1F)
            utf8Need = 1
        } else if b & 0xF0 == 0xE0 {
            utf8Code = uint32(b & 0x0F)
            utf8Need = 2
        } else if b & 0xF8 == 0xF0 {
            utf8Code = uint32(b & 0x07)
            utf8Need = 3
        } else {
            put(0xFFFD)
        }
    }

    /// The C0 controls.
    func control(_ b: uint8) {
        switch b {
        case 0x07:
            Bells += 1
            Version += 1
        case 0x08:
            if pendingWrap {
                pendingWrap = false
            } else if cx > 0 {
                cx -= 1
            }
            Version += 1
        case 0x09:
            tabForward(1)
        case 0x0A, 0x0B, 0x0C:
            lineFeed()
            if newlineMode { cx = 0 }
            pendingWrap = false
        case 0x0D:
            cx = 0
            pendingWrap = false
            Version += 1
        case 0x0E:
            gl = 1
        case 0x0F:
            gl = 0
        default:
            break
        }
    }

    func escape(_ b: uint8) {
        if b < 0x20 {
            control(b)
            return
        }
        switch b {
        case 0x5B:  // [
            state = .csiEntry
            params = []
            colons = []
            nextColon = false
            param = -1
            intermediates = []
            privateMarker = 0
        case 0x5D:  // ]
            state = .oscString
            osc = []
            stringEsc = false
        case 0x50, 0x58, 0x5E, 0x5F:  // P X ^ _: DCS, SOS, PM, APC
            state = .ignoredString
            stringEsc = false
        default:
            if b >= 0x20 && b < 0x30 {
                intermediates.append(b)
                state = .escapeIntermediate
            } else if b < 0x7F {
                escDispatch(b)
                state = .ground
            }
        }
    }

    func escDispatch(_ b: uint8) {
        if !intermediates.isEmpty {
            let i = intermediates[0]
            if i == 0x28 || i == 0x29 {  // ( ) designate G0, G1
                let set: charset = b == 0x30 ? .lineDrawing : .ascii
                if i == 0x28 { g0 = set } else { g1 = set }
            } else if i == 0x23 && b == 0x38 {  // # 8: DECALN, the screen filled with E
                for y in 0..<Rows {
                    for x in 0..<Columns { screen[y].Cells[x] = Cell(rune: 0x45) }
                }
                Version += 1
            }
            return
        }
        switch b {
        case 0x37: saveCursor()          // 7
        case 0x38: restoreCursor()       // 8
        case 0x44:                       // D: IND
            lineFeed()
        case 0x45:                       // E: NEL
            cx = 0
            lineFeed()
        case 0x48:                       // H: HTS
            if cx < Columns { tabs[cx] = true }
        case 0x4D:                       // M: RI
            reverseIndex()
        case 0x63:                       // c: RIS
            fullReset()
        case 0x3D: AppKeypad = true      // =
        case 0x3E: AppKeypad = false     // >
        default:
            break
        }
    }

    // MARK: - OSC

    func oscByte(_ b: uint8) {
        if stringEsc {
            stringEsc = false
            if b == 0x5C {
                oscDispatch()
                state = .ground
                return
            }
            // ESC then something else: the string ends and the escape
            // begins.
            oscDispatch()
            enterEscape()
            escape(b)
            return
        }
        switch b {
        case 0x07:
            oscDispatch()
            state = .ground
        case 0x1B:
            stringEsc = true
        case 0x18, 0x1A:
            state = .ground
        default:
            if osc.count < 1 << 20 { osc.append(b) }
        }
    }

    func oscDispatch() {
        // "Ps ; Pt"
        var i = 0
        var code = 0
        var sawDigit = false
        while i < osc.count && osc[i] >= 0x30 && osc[i] <= 0x39 {
            code = code * 10 + int(osc[i] - 0x30)
            sawDigit = true
            i += 1
        }
        if !sawDigit { return }
        if i < osc.count && osc[i] == 0x3B { i += 1 }
        let text = textOf([uint8](osc[i...]))
        switch code {
        case 0, 2:
            Title = text
            Version += 1
        case 7:
            WorkingDirectory = pathOfFileURL(text)
            Version += 1
        case 10:
            if text == "?" { respond("\u{1b}]10;\(rgbSpec(ForegroundRGB))\u{1b}\\") }
        case 11:
            if text == "?" { respond("\u{1b}]11;\(rgbSpec(BackgroundRGB))\u{1b}\\") }
        case 52:
            // "c;base64": set the clipboard. Reading it back ("?") is not
            // answered: a program has no business reading it.
            if let semi = text.firstIndex(of: ";") {
                let data = String(text[text.index(after: semi)...])
                if data != "?" {
                    if let bytes = try? base64.DecodeString(data) { clipboard = textOf(bytes) }
                }
            }
        default:
            break
        }
    }

    // MARK: - CSI

    func csiByte(_ b: uint8) {
        if b < 0x20 {
            control(b)
            return
        }
        if b >= 0x30 && b <= 0x39 {
            param = (param < 0 ? 0 : param) * 10 + int(b - 0x30)
            if param > 65535 { param = 65535 }
            state = .csiParam
            return
        }
        if b == 0x3B || b == 0x3A {  // ; :
            params.append(param)
            colons.append(nextColon)
            nextColon = b == 0x3A
            param = -1
            state = .csiParam
            return
        }
        if b >= 0x3C && b <= 0x3F {  // < = > ?
            if state == .csiEntry {
                privateMarker = b
                state = .csiParam
            } else {
                state = .csiIgnore
            }
            return
        }
        if b >= 0x20 && b < 0x30 {
            intermediates.append(b)
            state = .csiIntermediate
            return
        }
        if b >= 0x40 && b < 0x7F {
            csiFinish(b)
        }
    }

    func csiFinish(_ final: uint8) {
        params.append(param)
        colons.append(nextColon)
        nextColon = false
        state = .ground
        csiDispatch(final)
    }
}

/// "rgb:RRRR/GGGG/BBBB", as xterm answers a color query.
func rgbSpec(_ c: (R: uint8, G: uint8, B: uint8)) -> string {
    return "rgb:\(hex2(c.R))\(hex2(c.R))/\(hex2(c.G))\(hex2(c.G))/\(hex2(c.B))\(hex2(c.B))"
}

func hex2(_ v: uint8) -> string {
    let digits: [string] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
    return digits[int(v >> 4)] + digits[int(v & 15)]
}

/// The path of a file:// URL (OSC 7's "file://host/path"), percent
/// escapes decoded; nil for anything else.
func pathOfFileURL(_ url: string) -> string? {
    let b = [uint8](url.utf8)
    let prefix = [uint8]("file://".utf8)
    if b.count < prefix.count { return nil }
    for i in 0..<prefix.count where b[i] != prefix[i] { return nil }
    var i = prefix.count
    while i < b.count && b[i] != 0x2F { i += 1 }  // skip the host
    if i >= b.count { return nil }
    var out: [uint8] = []
    while i < b.count {
        if b[i] == 0x25 && i + 2 < b.count, let h = hexValue(b[i + 1]), let l = hexValue(b[i + 2]) {
            out.append(uint8(h * 16 + l))
            i += 3
        } else {
            out.append(b[i])
            i += 1
        }
    }
    return textOf(out)
}

func hexValue(_ c: uint8) -> int? {
    if c >= 0x30 && c <= 0x39 { return int(c - 0x30) }
    if c >= 0x61 && c <= 0x66 { return int(c - 0x61 + 10) }
    if c >= 0x41 && c <= 0x46 { return int(c - 0x41 + 10) }
    return nil
}
