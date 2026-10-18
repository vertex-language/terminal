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
    /// DCS: its parameters, intermediates and final are read as CSI's
    /// are, then its string to ST.
    case dcsEntry
    case dcsString
    /// SOS, PM and APC: strings that are read to their end and dropped.
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
        if state != .oscString && state != .ignoredString && state != .dcsString {
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
        case .dcsEntry:
            dcsEntryByte(b)
        case .dcsString:
            dcsByte(b)
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
        case 0x05:  // ENQ: the answerback message
            if !Answerback.isEmpty { respond(Answerback) }
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
            if newlineMode { cx = cx >= left ? left : 0 }
            pendingWrap = false
        case 0x0D:
            cx = cx >= left ? left : 0
            pendingWrap = false
            Version += 1
        case 0x0E:
            gl = 1
        case 0x0F:
            gl = 0
        case 0x84:  // IND, NEL, HTS, RI as 8-bit controls: not in UTF-8
            break
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
        case 0x50:  // P: DCS
            state = .dcsEntry
            params = []
            colons = []
            nextColon = false
            param = -1
            intermediates = []
            privateMarker = 0
            dcs = []
            stringEsc = false
        case 0x58, 0x5E, 0x5F:  // X ^ _: SOS, PM, APC
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
            if i == 0x28 || i == 0x29 || i == 0x2A || i == 0x2B {  // ( ) * + designate G0-G3
                let set: charset = b == 0x30 ? .lineDrawing : (b == 0x41 ? .uk : .ascii)
                switch i {
                case 0x28: g0 = set
                case 0x29: g1 = set
                case 0x2A: g2 = set
                default: g3 = set
                }
            } else if i == 0x23 {
                switch b {
                case 0x38:  // # 8: DECALN, the screen filled with E
                    for y in 0..<Rows {
                        for x in 0..<Columns { screen[y].Cells[x] = Cell(rune: 0x45) }
                        screen[y].Rendition = .single
                    }
                    top = 0
                    bottom = Rows - 1
                    left = 0
                    right = Columns - 1
                    moveTo(0, 0)
                case 0x33: setRendition(.doubleTop)     // # 3: DECDHL top
                case 0x34: setRendition(.doubleBottom)  // # 4: DECDHL bottom
                case 0x35: setRendition(.single)        // # 5: DECSWL
                case 0x36: setRendition(.doubleWidth)   // # 6: DECDWL
                default: break
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
        case 0x36: backIndex()           // 6: DECBI
        case 0x39: forwardIndex()        // 9: DECFI
        case 0x4E: singleShift = 2       // N: SS2
        case 0x4F: singleShift = 3       // O: SS3
        case 0x6E: gl = 2                // n: LS2
        case 0x6F: gl = 3                // o: LS3
        case 0x5C: break                 // \: a stray ST
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
        case 1:
            break  // the icon's name
        case 4:
            // "c;spec;c;spec…": set or ("?") report palette colors.
            let parts = text.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
            var k = 0
            while k + 1 < parts.count {
                if let idx = int(parts[k]), idx >= 0 && idx < 256 {
                    if parts[k + 1] == "?" {
                        respond("\u{1b}]4;\(idx);\(rgbSpec(rgbOf(currentColor(idx))))\u{1b}\\")
                    } else if let c = parseColorSpec(parts[k + 1]) {
                        palette[idx] = c
                        PaletteVersion += 1
                        Version += 1
                    }
                }
                k += 2
            }
        case 7:
            WorkingDirectory = pathOfFileURL(text)
            Version += 1
        case 8:
            // "params;URI": the text that follows links to URI, until an
            // empty URI ends it.
            if let semi = text.firstIndex(of: ";") {
                let uri = String(text[text.index(after: semi)...])
                pen.Link = internLink(uri)
            }
        case 9:
            osc9(text)
        case 10, 11, 12:
            // Each ";" after the first moves to the next of 10, 11, 12.
            var which = code
            for part in text.split(separator: ";", omittingEmptySubsequences: false).map({ String($0) }) {
                if part == "?" {
                    let c = which == 10 ? (fgOverride == noColor ? ForegroundRGB : rgbOf(fgOverride))
                        : (which == 11 ? (bgOverride == noColor ? BackgroundRGB : rgbOf(bgOverride))
                        : (cursorOverride == noColor ? CursorRGB : rgbOf(cursorOverride)))
                    respond("\u{1b}]\(which);\(rgbSpec(c))\u{1b}\\")
                } else if let c = parseColorSpec(part) {
                    if which == 10 { fgOverride = c } else if which == 11 { bgOverride = c } else { cursorOverride = c }
                    PaletteVersion += 1
                    Version += 1
                }
                which += 1
                if which > 12 { break }
            }
        case 52:
            // "c;base64": set the clipboard. Reading it back ("?") is not
            // answered: a program has no business reading it.
            if let semi = text.firstIndex(of: ";") {
                let data = String(text[text.index(after: semi)...])
                if data != "?" {
                    if let bytes = try? base64.DecodeString(data) { clipboard = textOf(bytes) }
                }
            }
        case 104:
            // Palette colors back to the theme's: those listed, or all.
            if text.isEmpty {
                palette = [uint32](repeating: noColor, count: 256)
            } else {
                for part in text.split(separator: ";") {
                    if let idx = int(String(part)), idx >= 0 && idx < 256 { palette[idx] = noColor }
                }
            }
            PaletteVersion += 1
            Version += 1
        case 110:
            fgOverride = noColor
            PaletteVersion += 1
            Version += 1
        case 111:
            bgOverride = noColor
            PaletteVersion += 1
            Version += 1
        case 112:
            cursorOverride = noColor
            PaletteVersion += 1
            Version += 1
        case 133, 633:
            // FinalTerm's shell integration (and VS Code's): A the prompt,
            // B the command, C its output, D;status its end.
            shellMark(text)
        case 777:
            // "notify;title;body"
            let parts = text.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false).map { String($0) }
            if parts.count >= 2 && parts[0] == "notify" {
                notifications.append(Notification(Title: parts[1], Body: parts.count > 2 ? parts[2] : ""))
            }
        case 1337:
            // iTerm2's: CurrentDir=path, SetMark.
            if text.hasPrefix("CurrentDir=") {
                WorkingDirectory = String(text.dropFirst(11))
                Version += 1
            } else if text == "SetMark" {
                AddMark()
            }
        default:
            break
        }
    }

    /// OSC 9: ConEmu's progress (4;state;percent) and working directory
    /// (9;path), or else a notification of the text (iTerm2's growl).
    func osc9(_ text: string) {
        let parts = text.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        if parts.count >= 1 && parts[0] == "4" {
            let st = parts.count > 1 ? (int(parts[1]) ?? 0) : 0
            let v = parts.count > 2 ? (int(parts[2]) ?? 0) : 0
            switch st {
            case 1: Progress = .normal
            case 2: Progress = .error
            case 3: Progress = .indeterminate
            case 4: Progress = .paused
            default: Progress = .none
            }
            if st != 3 { ProgressValue = max(0, min(100, v)) }
            if st == 0 { ProgressValue = 0 }
            Version += 1
            return
        }
        if parts.count >= 2 && parts[0] == "9" {
            var path = parts[1]
            if path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2 { path = String(path.dropFirst().dropLast()) }
            WorkingDirectory = path
            Version += 1
            return
        }
        if let first = parts.first, int(first) != nil { return }
        notifications.append(Notification(Title: "", Body: text))
    }

    func shellMark(_ text: string) {
        let b = [uint8](text.utf8)
        if b.isEmpty { return }
        switch b[0] {
        case 0x41:  // A
            screen[cy].Mark = .prompt
        case 0x42:  // B
            if screen[cy].Mark == .none { screen[cy].Mark = .command }
        case 0x43:  // C
            if screen[cy].Mark == .none || screen[cy].Mark == .command { screen[cy].Mark = .output }
        case 0x44:  // D;status
            var status = 0
            let parts = text.split(separator: ";")
            if parts.count > 1 { status = int(String(parts[1])) ?? 0 }
            // The status goes on the command's prompt line.
            var y = cy
            var n = ringCount + y
            while n >= 0 {
                let l = Absolute(n)
                if l.Mark == .prompt { break }
                n -= 1
            }
            if n >= 0 {
                if n >= ringCount {
                    y = n - ringCount
                    screen[y].ExitCode = status
                } else {
                    ring[(ringStart + n) % ring.count].ExitCode = status
                }
            }
        default:
            break
        }
        Version += 1
    }

    // MARK: - DCS

    func dcsEntryByte(_ b: uint8) {
        if b < 0x20 { return }
        if b >= 0x30 && b <= 0x39 {
            param = (param < 0 ? 0 : param) * 10 + int(b - 0x30)
            if param > 65535 { param = 65535 }
            return
        }
        if b == 0x3B || b == 0x3A {
            params.append(param)
            param = -1
            return
        }
        if b >= 0x3C && b <= 0x3F {
            privateMarker = b
            return
        }
        if b >= 0x20 && b < 0x30 {
            intermediates.append(b)
            return
        }
        if b >= 0x40 && b < 0x7F {
            params.append(param)
            dcsKind = b
            dcs = []
            state = .dcsString
        }
    }

    func dcsByte(_ b: uint8) {
        if stringEsc {
            stringEsc = false
            if b == 0x5C {
                dcsDispatch()
                state = .ground
                return
            }
            dcsDispatch()
            enterEscape()
            escape(b)
            return
        }
        switch b {
        case 0x1B:
            stringEsc = true
        case 0x18, 0x1A:
            state = .ground
        default:
            if dcs.count < 32 << 20 { dcs.append(b) }
        }
    }

    func dcsDispatch() {
        let inter: uint8 = intermediates.isEmpty ? 0 : intermediates[0]
        if dcsKind == 0x71 && inter == 0x24 {  // $ q: DECRQSS
            requestSetting(textOf(dcs))
        } else if dcsKind == 0x71 && inter == 0 && privateMarker == 0 {  // q: sixel
            sixel(params.map { max(0, $0) }, dcs)
        }
        dcs = []
    }

    /// DECRQSS: what a setting is, as the sequence that would set it.
    func requestSetting(_ what: string) {
        var answer: string? = nil
        switch what {
        case "m": answer = sgrString() + "m"
        case "r": answer = "\(top + 1);\(bottom + 1)r"
        case "s": answer = "\(left + 1);\(right + 1)s"
        case " q":
            var n = 1
            switch Shape {
            case .block: n = CursorBlink ? 1 : 2
            case .underline: n = CursorBlink ? 3 : 4
            case .bar: n = CursorBlink ? 5 : 6
            }
            answer = "\(n) q"
        case "\"q": answer = (pen.Has(Attr.protected) ? "1" : "0") + "\"q"
        case "\"p": answer = "65;1\"p"
        case "t": answer = "\(max(24, Rows))t"
        case "$|": answer = "\(Columns)$|"
        case "*|": answer = "\(Rows)*|"
        case "*x": answer = (rectExtent ? "2" : "1") + "*x"
        default: break
        }
        if let a = answer {
            respond("\u{1b}P1$r\(a)\u{1b}\\")
        } else {
            respond("\u{1b}P0$r\u{1b}\\")
        }
    }

    /// The pen's attributes as SGR parameters.
    func sgrString() -> string {
        var p: [string] = ["0"]
        let a = pen.Attrs
        if a & Attr.bold != 0 { p.append("1") }
        if a & Attr.dim != 0 { p.append("2") }
        if a & Attr.italic != 0 { p.append("3") }
        if a & Attr.underline != 0 { p.append("4") }
        if a & Attr.blink != 0 { p.append("5") }
        if a & Attr.inverse != 0 { p.append("7") }
        if a & Attr.hidden != 0 { p.append("8") }
        if a & Attr.strike != 0 { p.append("9") }
        if a & Attr.doubleUnderline != 0 { p.append("21") }
        if a & Attr.curlyUnderline != 0 { p.append("4:3") }
        if a & Attr.dottedUnderline != 0 { p.append("4:4") }
        if a & Attr.dashedUnderline != 0 { p.append("4:5") }
        if a & Attr.overline != 0 { p.append("53") }
        func color(_ c: Color, _ base: int, _ ext: int) {
            if c.IsDefault { return }
            if c.IsRGB {
                p.append("\(ext):2::\(c.R):\(c.G):\(c.B)")
            } else if c.Index < 8 {
                p.append("\(base + c.Index)")
            } else if c.Index < 16 && base != 0 {
                p.append("\(base + 60 + c.Index - 8)")
            } else {
                p.append("\(ext):5:\(c.Index)")
            }
        }
        color(pen.Fg, 30, 38)
        color(pen.Bg, 40, 48)
        color(pen.Ul, 0, 58)
        return p.joined(separator: ";")
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

/// A color as X11 writes it: "rgb:R/G/B" (1-4 hex digits each), "#RGB",
/// "#RRGGBB", or a few names.
func parseColorSpec(_ spec: string) -> uint32? {
    let b = [uint8](spec.utf8)
    func hexRun(_ from: int, _ to: int) -> uint32? {
        if to <= from || to - from > 4 { return nil }
        var v: uint32 = 0
        for i in from..<to {
            guard let h = hexValue(b[i]) else { return nil }
            v = v * 16 + uint32(h)
        }
        // Scaled to 8 bits from however many digits there were.
        let digits = to - from
        switch digits {
        case 1: return v * 17
        case 2: return v
        case 3: return v >> 4
        default: return v >> 8
        }
    }
    if spec.hasPrefix("rgb:") {
        var parts: [(int, int)] = []
        var s = 4
        for i in 4...b.count {
            if i == b.count || b[i] == 0x2F {
                parts.append((s, i))
                s = i + 1
            }
        }
        if parts.count != 3 { return nil }
        guard let r = hexRun(parts[0].0, parts[0].1), let g = hexRun(parts[1].0, parts[1].1),
              let bl = hexRun(parts[2].0, parts[2].1) else { return nil }
        return (r << 16) | (g << 8) | bl
    }
    if b.count > 1 && b[0] == 0x23 {
        let n = (b.count - 1) / 3
        if n * 3 != b.count - 1 || n < 1 || n > 4 { return nil }
        guard let r = hexRun(1, 1 + n), let g = hexRun(1 + n, 1 + 2 * n), let bl = hexRun(1 + 2 * n, 1 + 3 * n) else { return nil }
        return (r << 16) | (g << 8) | bl
    }
    switch spec.lowercased() {
    case "black": return 0x000000
    case "white": return 0xFFFFFF
    case "red": return 0xFF0000
    case "green": return 0x00FF00
    case "blue": return 0x0000FF
    case "yellow": return 0xFFFF00
    case "cyan": return 0x00FFFF
    case "magenta": return 0xFF00FF
    case "gray", "grey": return 0xBEBEBE
    default: return nil
    }
}

func hexValue(_ c: uint8) -> int? {
    if c >= 0x30 && c <= 0x39 { return int(c - 0x30) }
    if c >= 0x61 && c <= 0x66 { return int(c - 0x61 + 10) }
    if c >= 0x41 && c <= 0x46 { return int(c - 0x41 + 10) }
    return nil
}
