package vt

extension Terminal {
    /// Parameter i, or def where it is missing or 0 (most sequences treat
    /// 0 as 1).
    func arg(_ i: int, _ def: int) -> int {
        if i >= params.count { return def }
        let v = params[i]
        return v <= 0 ? def : v
    }

    /// Parameter i as given: 0 where missing.
    func raw(_ i: int) -> int {
        if i >= params.count || params[i] < 0 { return 0 }
        return params[i]
    }

    func csiDispatch(_ final: uint8) {
        let inter: uint8 = intermediates.isEmpty ? 0 : intermediates[0]
        if privateMarker == 0x3F {  // ?
            switch final {
            case 0x68: setModes(true, dec: true)      // h
            case 0x6C: setModes(false, dec: true)     // l
            case 0x70:                                 // $p: DECRQM
                if inter == 0x24 { reportMode(raw(0), dec: true) }
            case 0x6E:                                 // n: DECDSR
                if raw(0) == 6 { respond("\u{1b}[?\(cy + 1);\(cx + 1)R") }
            default: break
            }
            return
        }
        if privateMarker == 0x3E {  // >
            switch final {
            case 0x63:  // c: DA2
                respond("\u{1b}[>0;276;0c")
            case 0x71:  // q: XTVERSION
                respond("\u{1b}P>|vertex-terminal 0.1\u{1b}\\")
            default: break
            }
            return
        }
        if privateMarker != 0 { return }
        if inter == 0x20 && final == 0x71 {  // SP q: DECSCUSR
            let s = raw(0)
            switch s {
            case 0, 1: Shape = .block; CursorBlink = true
            case 2: Shape = .block; CursorBlink = false
            case 3: Shape = .underline; CursorBlink = true
            case 4: Shape = .underline; CursorBlink = false
            case 5: Shape = .bar; CursorBlink = true
            case 6: Shape = .bar; CursorBlink = false
            default: break
            }
            Version += 1
            return
        }
        if inter == 0x21 && final == 0x70 {  // ! p: DECSTR
            softReset()
            return
        }
        if inter == 0x24 && final == 0x70 {  // $ p: DECRQM (ANSI)
            reportMode(raw(0), dec: false)
            return
        }
        if inter != 0 { return }
        switch final {
        case 0x40: insertBlanks(arg(0, 1))                                // @ ICH
        case 0x41: moveTo(cx, max(cy - arg(0, 1), cy >= top ? top : 0))   // A CUU
        case 0x42: moveTo(cx, min(cy + arg(0, 1), cy <= bottom ? bottom : Rows - 1))  // B CUD
        case 0x43, 0x61: moveTo(cx + arg(0, 1), cy)                       // C CUF, a HPR
        case 0x44: moveTo(cx - arg(0, 1), cy)                             // D CUB
        case 0x45: moveTo(0, min(cy + arg(0, 1), bottom))                 // E CNL
        case 0x46: moveTo(0, max(cy - arg(0, 1), top))                    // F CPL
        case 0x47, 0x60: moveTo(arg(0, 1) - 1, cy)                        // G CHA, ` HPA
        case 0x48, 0x66:                                                  // H CUP, f HVP
            let y = arg(0, 1) - 1 + (originMode ? top : 0)
            moveTo(arg(1, 1) - 1, y)
        case 0x49: tabForward(arg(0, 1))                                  // I CHT
        case 0x4A: eraseInDisplay(raw(0))                                 // J ED
        case 0x4B: eraseInLine(raw(0))                                    // K EL
        case 0x4C: insertLines(arg(0, 1))                                 // L IL
        case 0x4D: deleteLines(arg(0, 1))                                 // M DL
        case 0x50: deleteChars(arg(0, 1))                                 // P DCH
        case 0x53: scrollUp(arg(0, 1))                                    // S SU
        case 0x54: scrollDown(arg(0, 1))                                  // T SD
        case 0x58: eraseChars(arg(0, 1))                                  // X ECH
        case 0x5A: tabBackward(arg(0, 1))                                 // Z CBT
        case 0x62:                                                        // b REP
            if lastPrinted != 0 {
                for _ in 0..<min(arg(0, 1), Columns * Rows) { put(lastPrinted) }
            }
        case 0x63:                                                        // c DA1
            if raw(0) == 0 { respond("\u{1b}[?62;22c") }
        case 0x64:                                                        // d VPA
            moveTo(cx, arg(0, 1) - 1 + (originMode ? top : 0))
        case 0x65: moveTo(cx, cy + arg(0, 1))                             // e VPR
        case 0x67:                                                        // g TBC
            let m = raw(0)
            if m == 0 && cx < Columns { tabs[cx] = false }
            if m == 3 { tabs = [bool](repeating: false, count: Columns) }
        case 0x68: setModes(true, dec: false)                             // h SM
        case 0x6C: setModes(false, dec: false)                            // l RM
        case 0x6D: sgr()                                                  // m SGR
        case 0x6E:                                                        // n DSR
            switch raw(0) {
            case 5: respond("\u{1b}[0n")
            case 6:
                let y = originMode ? cy - top : cy
                respond("\u{1b}[\(y + 1);\(cx + 1)R")
            default: break
            }
        case 0x72:                                                        // r DECSTBM
            let t = arg(0, 1) - 1
            let b = arg(1, Rows) - 1
            if t < b && b < Rows {
                top = t
                bottom = b
                moveTo(0, originMode ? top : 0)
            }
        case 0x73: saveCursor()                                           // s SCOSC
        case 0x74: windowOp()                                             // t XTWINOPS
        case 0x75: restoreCursor()                                        // u SCORC
        default: break
        }
    }

    func windowOp() {
        switch raw(0) {
        case 18: respond("\u{1b}[8;\(Rows);\(Columns)t")
        case 22, 23: break  // title stack: nothing kept
        default: break
        }
    }

    func setModes(_ on: bool, dec: bool) {
        for i in 0..<params.count {
            let m = params[i]
            if m < 0 { continue }
            if dec { setDECMode(m, on) } else { setANSIMode(m, on) }
        }
        Version += 1
    }

    func setANSIMode(_ m: int, _ on: bool) {
        switch m {
        case 4: insertMode = on
        case 20: newlineMode = on
        default: break
        }
    }

    func setDECMode(_ m: int, _ on: bool) {
        switch m {
        case 1: AppCursorKeys = on
        case 5: ReverseVideo = on
        case 6:
            originMode = on
            moveTo(0, on ? top : 0)
        case 7: autowrap = on
        case 12: CursorBlink = on
        case 25: CursorVisible = on
        case 47, 1047: setAltScreen(on, clear: m == 1047 && !on, cursor: false)
        case 1048: if on { saveCursor() } else { restoreCursor() }
        case 1049: setAltScreen(on, clear: true, cursor: true)
        case 9, 1000: Mouse = on ? .clicks : .off
        case 1002: Mouse = on ? .drag : .off
        case 1003: Mouse = on ? .motion : .off
        case 1004: FocusReporting = on
        case 1006: MouseSGR = on
        case 1007: AlternateScroll = on
        case 2004: BracketedPaste = on
        default: break
        }
    }

    func reportMode(_ m: int, dec: bool) {
        // 1 set, 2 reset, 0 not recognized.
        var v = 0
        if dec {
            switch m {
            case 1: v = AppCursorKeys ? 1 : 2
            case 5: v = ReverseVideo ? 1 : 2
            case 6: v = originMode ? 1 : 2
            case 7: v = autowrap ? 1 : 2
            case 12: v = CursorBlink ? 1 : 2
            case 25: v = CursorVisible ? 1 : 2
            case 47, 1047, 1049: v = AltScreen ? 1 : 2
            case 1000: v = Mouse == .clicks ? 1 : 2
            case 1002: v = Mouse == .drag ? 1 : 2
            case 1003: v = Mouse == .motion ? 1 : 2
            case 1004: v = FocusReporting ? 1 : 2
            case 1006: v = MouseSGR ? 1 : 2
            case 2004: v = BracketedPaste ? 1 : 2
            default: v = 0
            }
            respond("\u{1b}[?\(m);\(v)$y")
        } else {
            switch m {
            case 4: v = insertMode ? 1 : 2
            case 20: v = newlineMode ? 1 : 2
            default: v = 0
            }
            respond("\u{1b}[\(m);\(v)$y")
        }
    }

    // MARK: - SGR

    func sgr() {
        if params.isEmpty {
            pen = Cell.blank
            return
        }
        var i = 0
        while i < params.count {
            let p = params[i] < 0 ? 0 : params[i]
            switch p {
            case 0:
                pen.Fg = .default
                pen.Bg = .default
                pen.Attrs = 0
            case 1: pen.Attrs |= Attr.bold
            case 2: pen.Attrs |= Attr.dim
            case 3: pen.Attrs |= Attr.italic
            case 4:
                pen.Attrs &= ~(Attr.underline | Attr.doubleUnderline | Attr.curlyUnderline)
                // 4:0 none, 4:1 single, 4:2 double, 4:3 curly (and more).
                if i + 1 < params.count && colons[i + 1] {
                    let style = params[i + 1]
                    i += 1
                    switch style {
                    case 0: break
                    case 2: pen.Attrs |= Attr.doubleUnderline
                    case 3, 4, 5: pen.Attrs |= Attr.curlyUnderline
                    default: pen.Attrs |= Attr.underline
                    }
                } else {
                    pen.Attrs |= Attr.underline
                }
            case 5, 6: pen.Attrs |= Attr.blink
            case 7: pen.Attrs |= Attr.inverse
            case 8: pen.Attrs |= Attr.hidden
            case 9: pen.Attrs |= Attr.strike
            case 21: pen.Attrs |= Attr.doubleUnderline
            case 22: pen.Attrs &= ~(Attr.bold | Attr.dim)
            case 23: pen.Attrs &= ~Attr.italic
            case 24: pen.Attrs &= ~(Attr.underline | Attr.doubleUnderline | Attr.curlyUnderline)
            case 25: pen.Attrs &= ~Attr.blink
            case 27: pen.Attrs &= ~Attr.inverse
            case 28: pen.Attrs &= ~Attr.hidden
            case 29: pen.Attrs &= ~Attr.strike
            case 30, 31, 32, 33, 34, 35, 36, 37: pen.Fg = Color.Indexed(p - 30)
            case 38:
                if let (c, used) = extendedColor(i) {
                    pen.Fg = c
                    i += used
                }
            case 39: pen.Fg = .default
            case 40, 41, 42, 43, 44, 45, 46, 47: pen.Bg = Color.Indexed(p - 40)
            case 48:
                if let (c, used) = extendedColor(i) {
                    pen.Bg = c
                    i += used
                }
            case 49: pen.Bg = .default
            case 53: pen.Attrs |= Attr.overline
            case 55: pen.Attrs &= ~Attr.overline
            case 58:
                // Underline color: read and set aside.
                if let (_, used) = extendedColor(i) { i += used }
            case 90, 91, 92, 93, 94, 95, 96, 97: pen.Fg = Color.Indexed(p - 90 + 8)
            case 100, 101, 102, 103, 104, 105, 106, 107: pen.Bg = Color.Indexed(p - 100 + 8)
            default: break
            }
            i += 1
        }
    }

    /// A 38/48/58 color starting at parameter i: the color, and how many
    /// parameters after i it used. Takes both 38;5;n / 38;2;r;g;b and the
    /// colon forms 38:5:n / 38:2::r:g:b (with or without the color space).
    func extendedColor(_ i: int) -> (Color, int)? {
        if i + 1 >= params.count { return nil }
        let kind = params[i + 1]
        if colons.count > i + 1 && colons[i + 1] {
            // Colon form: the sub-parameters run while colons[j] holds.
            var subs: [int] = []
            var j = i + 1
            while j < params.count && colons[j] {
                subs.append(params[j])
                j += 1
            }
            let used = subs.count
            if kind == 5 && subs.count >= 2 { return (Color.Indexed(max(0, subs[1])), used) }
            if kind == 2 {
                // 2:cs:r:g:b, or 2:r:g:b without the color space.
                let rgb = subs.count >= 5 ? [subs[2], subs[3], subs[4]] : (subs.count == 4 ? [subs[1], subs[2], subs[3]] : [])
                if rgb.count == 3 {
                    return (Color.RGB(uint8(clamp255(rgb[0])), uint8(clamp255(rgb[1])), uint8(clamp255(rgb[2]))), used)
                }
            }
            return (Color.default, used)
        }
        if kind == 5 {
            if i + 2 < params.count { return (Color.Indexed(max(0, params[i + 2])), 2) }
            return nil
        }
        if kind == 2 {
            if i + 4 < params.count {
                return (Color.RGB(uint8(clamp255(params[i + 2])), uint8(clamp255(params[i + 3])), uint8(clamp255(params[i + 4]))), 4)
            }
            return nil
        }
        return nil
    }
}

func clamp255(_ v: int) -> int {
    return v < 0 ? 0 : (v > 255 ? 255 : v)
}
