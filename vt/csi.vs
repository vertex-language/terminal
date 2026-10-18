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
                switch raw(0) {
                case 6: respond("\u{1b}[?\(cy + 1);\(cx + 1);1R")
                case 15: respond("\u{1b}[?13n")       // no printer
                case 25: respond("\u{1b}[?21n")       // user keys locked
                case 26: respond("\u{1b}[?27;1;0;0n") // a North American keyboard
                case 996: respond("\u{1b}[?997;\(DarkMode ? 1 : 2)n")
                default: break
                }
            case 0x4A: selectiveEraseInDisplay(raw(0))  // J: DECSED
            case 0x4B: selectiveEraseInLine(raw(0))     // K: DECSEL
            case 0x57:                                  // W: DECST8C
                if raw(0) == 5 { resetTabs() }
            case 0x75:                                  // u: the kitty flags, asked
                respond("\u{1b}[?\(KittyFlags)u")
            default: break
            }
            return
        }
        if privateMarker == 0x3E {  // >
            switch final {
            case 0x63:  // c: DA2
                if inter == 0 { respond("\u{1b}[>0;10;1c") }
            case 0x71:  // q: XTVERSION
                respond("\u{1b}P>|vertex-terminal 0.2\u{1b}\\")
            case 0x75:  // u: push kitty flags
                pushKitty(raw(0))
            default: break
            }
            return
        }
        if privateMarker == 0x3C {  // <
            if final == 0x75 { popKitty(arg(0, 1)) }  // u: pop kitty flags
            return
        }
        if privateMarker == 0x3D {  // =
            switch final {
            case 0x63:  // c: DA3, the unit's ID
                respond("\u{1b}P!|00000000\u{1b}\\")
            case 0x75:  // u: set kitty flags (1 all, 2 these on, 3 these off)
                let f = raw(0)
                switch arg(1, 1) {
                case 2: setKitty(KittyFlags | f)
                case 3: setKitty(KittyFlags & ~f)
                default: setKitty(f)
                }
            default: break
            }
            return
        }
        if privateMarker != 0 { return }
        switch inter {
        case 0x20:  // SP
            switch final {
            case 0x71: cursorStyle(raw(0))                 // q: DECSCUSR
            case 0x40: scrollSideways(-arg(0, 1))          // @: SL
            case 0x41: scrollSideways(arg(0, 1))           // A: SR
            default: break
            }
            return
        case 0x21:  // !
            if final == 0x70 { softReset() }                // p: DECSTR
            return
        case 0x22:  // "
            if final == 0x71 {                              // q: DECSCA
                if raw(0) == 1 { pen.Attrs |= Attr.protected } else { pen.Attrs &= ~Attr.protected }
            }
            return
        case 0x24:  // $
            switch final {
            case 0x70: reportMode(raw(0), dec: false)       // p: DECRQM
            case 0x76: copyRect()                           // v: DECCRA
            case 0x7A:                                      // z: DECERA
                let r = rectArgs(0)
                eraseRect(r.0, r.1, r.2, r.3, selective: false)
            case 0x7B:                                      // {: DECSERA
                let r = rectArgs(0)
                eraseRect(r.0, r.1, r.2, r.3, selective: true)
            case 0x78:                                      // x: DECFRA
                fillRect()
            case 0x72: changeAttrsRect(reverse: false)      // r: DECCARA
            case 0x74: changeAttrsRect(reverse: true)       // t: DECRARA
            case 0x77:                                      // w: DECRQPSR
                if raw(0) == 2 { tabStopReport() }
            default: break
            }
            return
        case 0x2A:  // *
            switch final {
            case 0x78: rectExtent = raw(0) == 2             // x: DECSACE
            case 0x79: checksumRect()                       // y: DECRQCRA
            default: break
            }
            return
        case 0x27:  // '
            if cx >= left && cx <= right {
                switch final {
                case 0x7D: shiftColumns(top: top, bottom: bottom, left: cx, right: right, by: arg(0, 1))   // }: DECIC
                case 0x7E: shiftColumns(top: top, bottom: bottom, left: cx, right: right, by: -arg(0, 1))  // ~: DECDC
                default: break
                }
            }
            return
        default:
            if inter != 0 { return }
        }
        switch final {
        case 0x40: insertBlanks(arg(0, 1))                                // @ ICH
        case 0x41: moveTo(cx, max(cy - arg(0, 1), cy >= top ? top : 0))   // A CUU
        case 0x42: moveTo(cx, min(cy + arg(0, 1), cy <= bottom ? bottom : Rows - 1))  // B CUD
        case 0x43, 0x61: moveTo(min(cx + arg(0, 1), rightEdge), cy)      // C CUF, a HPR
        case 0x44: moveTo(max(cx - arg(0, 1), cx >= left ? left : 0), cy) // D CUB
        case 0x45: moveTo(cx >= left ? left : 0, min(cy + arg(0, 1), bottom))  // E CNL
        case 0x46: moveTo(cx >= left ? left : 0, max(cy - arg(0, 1), top))     // F CPL
        case 0x47, 0x60: moveTo(arg(0, 1) - 1 + (originMode ? left : 0), cy)  // G CHA, ` HPA
        case 0x48, 0x66:                                                  // H CUP, f HVP
            let y = arg(0, 1) - 1 + (originMode ? top : 0)
            moveTo(arg(1, 1) - 1 + (originMode ? left : 0), y)
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
            // A VT525: 132 columns, sixel, selective erase, horizontal
            // scrolling, ANSI color, rectangular editing, clipboard access.
            if raw(0) == 0 { respond("\u{1b}[?65;1;4;6;21;22;28;52c") }
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
                let x = originMode ? cx - left : cx
                respond("\u{1b}[\(y + 1);\(x + 1)R")
            default: break
            }
        case 0x72:                                                        // r DECSTBM
            let t = arg(0, 1) - 1
            let b = arg(1, Rows) - 1
            if t < b && b < Rows {
                top = t
                bottom = b
                moveTo(originMode ? left : 0, originMode ? top : 0)
            }
        case 0x73:                                                        // s DECSLRM, or SCOSC
            if lrMarginMode {
                let l = arg(0, 1) - 1
                let r = arg(1, Columns) - 1
                if l < r && r < Columns {
                    left = l
                    right = r
                    moveTo(originMode ? left : 0, originMode ? top : 0)
                }
            } else {
                saveCursor()
            }
        case 0x74: windowOp()                                             // t XTWINOPS
        case 0x75: restoreCursor()                                        // u SCORC
        case 0x78:                                                        // x DECREQTPARM
            let p = raw(0)
            if p <= 1 { respond("\u{1b}[\(p + 2);1;1;128;128;1;0x") }
        default: break
        }
    }

    // MARK: - Cursor style, keyboard flags

    func cursorStyle(_ s: int) {
        switch s {
        case 0, 1: Shape = .block; CursorBlink = true
        case 2: Shape = .block; CursorBlink = false
        case 3: Shape = .underline; CursorBlink = true
        case 4: Shape = .underline; CursorBlink = false
        case 5: Shape = .bar; CursorBlink = true
        case 6: Shape = .bar; CursorBlink = false
        default: break
        }
        CursorStyleSet = s >= 1 && s <= 6
        Version += 1
    }

    func setKitty(_ f: int) {
        if !KittyKeyboard { return }
        let v = f & 31
        if kittyStack.isEmpty { kittyStack.append(v) } else { kittyStack[kittyStack.count - 1] = v }
        KittyFlags = v
    }

    func pushKitty(_ f: int) {
        if !KittyKeyboard { return }
        if kittyStack.count >= 16 { kittyStack.removeFirst() }
        kittyStack.append(f & 31)
        KittyFlags = f & 31
    }

    func popKitty(_ n: int) {
        for _ in 0..<min(n, kittyStack.count) { kittyStack.removeLast() }
        KittyFlags = kittyStack.last ?? 0
    }

    // MARK: - Lines and columns

    func setRendition(_ r: Rendition) {
        screen[cy].Rendition = r
        // A double-width line has half the columns.
        if r != .single { cx = min(cx, Columns / 2 - 1) }
        Version += 1
    }

    /// DECBI: left one column, or the margins' columns right where the
    /// cursor is at the left margin.
    func backIndex() {
        if cx == left && cy >= top && cy <= bottom {
            shiftColumns(top: top, bottom: bottom, left: left, right: right, by: 1)
        } else if cx > 0 {
            cx -= 1
            pendingWrap = false
            Version += 1
        }
    }

    /// DECFI: right one column, or the margins' columns left where the
    /// cursor is at the right margin.
    func forwardIndex() {
        if cx == right && cy >= top && cy <= bottom {
            shiftColumns(top: top, bottom: bottom, left: left, right: right, by: -1)
        } else if cx < Columns - 1 {
            cx += 1
            pendingWrap = false
            Version += 1
        }
    }

    /// SL and SR: the margins' contents left (negative) or right.
    func scrollSideways(_ by: int) {
        shiftColumns(top: top, bottom: bottom, left: left, right: right, by: by)
    }

    // MARK: - Selective erase

    func selectiveEraseInLine(_ mode: int) {
        var from = 0
        var to = Columns - 1
        switch mode {
        case 0: from = cx
        case 1: to = cx
        default: break
        }
        eraseRect(cy, from, cy, to, selective: true)
    }

    func selectiveEraseInDisplay(_ mode: int) {
        switch mode {
        case 0:
            selectiveEraseInLine(0)
            if cy + 1 < Rows { eraseRect(cy + 1, 0, Rows - 1, Columns - 1, selective: true) }
        case 1:
            if cy > 0 { eraseRect(0, 0, cy - 1, Columns - 1, selective: true) }
            selectiveEraseInLine(1)
        case 2:
            eraseRect(0, 0, Rows - 1, Columns - 1, selective: true)
        default:
            break
        }
    }

    // MARK: - Rectangles

    /// A rectangle's top, left, bottom and right from parameters i..i+3
    /// (1-based, from the origin in origin mode), clamped to the screen.
    func rectArgs(_ i: int) -> (int, int, int, int) {
        let oy = originMode ? top : 0
        let ox = originMode ? left : 0
        let maxY = originMode ? bottom : Rows - 1
        let maxX = originMode ? right : Columns - 1
        let t = min(arg(i, 1) - 1 + oy, maxY)
        let l = min(arg(i + 1, 1) - 1 + ox, maxX)
        let b = min(arg(i + 2, maxY - oy + 1) - 1 + oy, maxY)
        let r = min(arg(i + 3, maxX - ox + 1) - 1 + ox, maxX)
        return (t, l, b, r)
    }

    /// Blanks a rectangle: every cell, or (selective) those not
    /// protected (DECSCA). The pen's background is kept for DECERA, as
    /// erasing does; selective erase keeps the cells' own attributes.
    func eraseRect(_ t: int, _ l: int, _ b: int, _ r: int, selective: bool) {
        if t > b || l > r { return }
        let blank = Cell(rune: 0x20, fg: .default, bg: pen.Bg)
        for y in t...b {
            for x in l...r {
                let c = screen[y].Cells[x]
                if selective {
                    if c.Has(Attr.protected) { continue }
                    var e = c
                    e.Rune = 0x20
                    e.Attrs &= ~(Attr.wide | Attr.spacer)
                    e.Link = 0
                    screen[y].Cells[x] = e
                } else {
                    screen[y].Cells[x] = blank
                }
            }
        }
        Version += 1
    }

    /// DECFRA: a rectangle filled with a character, in the pen's colors
    /// and attributes.
    func fillRect() {
        let ch = raw(0)
        // Printable characters only (and Latin-1's).
        if !((ch >= 32 && ch <= 126) || (ch >= 160 && ch <= 255)) { return }
        let r = rectArgs(1)
        if r.0 > r.2 || r.1 > r.3 { return }
        var c = pen
        c.Rune = uint32(ch)
        c.Attrs &= ~(Attr.wide | Attr.spacer)
        for y in r.0...r.2 {
            for x in r.1...r.3 { screen[y].Cells[x] = c }
        }
        Version += 1
    }

    /// DECCRA: a rectangle copied elsewhere on the screen (one page).
    func copyRect() {
        let src = rectArgs(0)
        let oy = originMode ? top : 0
        let ox = originMode ? left : 0
        let dt = arg(5, 1) - 1 + oy
        let dl = arg(6, 1) - 1 + ox
        if src.0 > src.2 || src.1 > src.3 || dt >= Rows || dl >= Columns { return }
        let h = min(src.2 - src.0, Rows - 1 - dt)
        let w = min(src.3 - src.1, Columns - 1 - dl)
        var copy: [[Cell]] = []
        for y in 0...h { copy.append([Cell](screen[src.0 + y].Cells[src.1...(src.1 + w)])) }
        for y in 0...h {
            for x in 0...w { screen[dt + y].Cells[dl + x] = copy[y][x] }
        }
        Version += 1
    }

    /// DECCARA and DECRARA: attributes (and with DECCARA colors) set or
    /// reversed in a rectangle, or in the stream between its corners
    /// (DECSACE).
    func changeAttrsRect(reverse: bool) {
        let r = rectArgs(0)
        if r.0 > r.2 { return }
        var set: uint16 = 0
        var clear: uint16 = 0
        var fg: Color? = nil
        var bg: Color? = nil
        var i = 4
        if params.count <= 4 { clear = Attr.bold | Attr.anyUnderline | Attr.blink | Attr.inverse }
        while i < params.count {
            let p = max(0, params[i])
            switch p {
            case 0: clear |= Attr.bold | Attr.anyUnderline | Attr.blink | Attr.inverse
            case 1: set |= Attr.bold
            case 4: set |= Attr.underline
            case 5: set |= Attr.blink
            case 7: set |= Attr.inverse
            case 22: clear |= Attr.bold
            case 24: clear |= Attr.anyUnderline
            case 25: clear |= Attr.blink
            case 27: clear |= Attr.inverse
            case 30, 31, 32, 33, 34, 35, 36, 37: fg = Color.Indexed(p - 30)
            case 39: fg = .default
            case 40, 41, 42, 43, 44, 45, 46, 47: bg = Color.Indexed(p - 40)
            case 49: bg = .default
            case 90, 91, 92, 93, 94, 95, 96, 97: fg = Color.Indexed(p - 90 + 8)
            case 100, 101, 102, 103, 104, 105, 106, 107: bg = Color.Indexed(p - 100 + 8)
            default: break
            }
            i += 1
        }
        if reverse {
            // DECRARA reverses what is named; 0 is all four.
            set &= Attr.bold | Attr.underline | Attr.blink | Attr.inverse
            if set == 0 { set = Attr.bold | Attr.underline | Attr.blink | Attr.inverse }
        }
        for y in r.0...r.2 {
            var from = r.1
            var to = r.3
            if !rectExtent {
                // The stream: the first row from its column, the last to
                // its column, the rows between whole.
                from = y == r.0 ? r.1 : (originMode ? left : 0)
                to = y == r.2 ? r.3 : (originMode ? right : Columns - 1)
            }
            if from > to { continue }
            for x in from...to {
                var c = screen[y].Cells[x]
                if reverse {
                    c.Attrs ^= set
                } else {
                    c.Attrs = (c.Attrs & ~clear) | set
                    if let f = fg { c.Fg = f }
                    if let b = bg { c.Bg = b }
                }
                screen[y].Cells[x] = c
            }
        }
        Version += 1
    }

    /// DECRQCRA: a checksum of a rectangle's characters, as the VT525
    /// sums them.
    func checksumRect() {
        let id = raw(0)
        let r = rectArgs(2)
        var sum: uint32 = 0
        if r.0 <= r.2 && r.1 <= r.3 {
            for y in r.0...r.2 {
                for x in r.1...r.3 {
                    let c = screen[y].Cells[x]
                    let ch = c.Rune == 0 ? uint32(0x20) : (c.Rune >= ClusterBase ? Cluster(c.Rune)[0] : c.Rune)
                    sum = sum &+ ch
                    if c.Has(Attr.protected) { sum = sum &+ 0x04 }
                    if c.Has(Attr.inverse) { sum = sum &+ 0x08 }
                    if c.Has(Attr.blink) { sum = sum &+ 0x10 }
                    if c.Has(Attr.anyUnderline) { sum = sum &+ 0x20 }
                    if c.Has(Attr.bold) { sum = sum &+ 0x80 }
                }
            }
        }
        let v = (0 &- sum) & 0xFFFF
        respond("\u{1b}P\(id)!~\(hex2(uint8(v >> 8)).uppercased())\(hex2(uint8(v & 0xFF)).uppercased())\u{1b}\\")
    }

    /// DECTABSR: where the tab stops are.
    func tabStopReport() {
        var stops: [string] = []
        for x in 0..<tabs.count where tabs[x] { stops.append("\(x + 1)") }
        respond("\u{1b}P2$u\(stops.joined(separator: "/"))\u{1b}\\")
    }

    func windowOp() {
        switch raw(0) {
        case 14:  // the text area in pixels
            respond("\u{1b}[4;\(Rows * CellPixelHeight);\(Columns * CellPixelWidth)t")
        case 16:  // a cell in pixels
            respond("\u{1b}[6;\(CellPixelHeight);\(CellPixelWidth)t")
        case 18: respond("\u{1b}[8;\(Rows);\(Columns)t")
        case 19: respond("\u{1b}[9;\(Rows);\(Columns)t")
        case 22:  // push the title
            if titleStack.count >= 10 { titleStack.removeFirst() }
            titleStack.append(Title)
        case 23:  // pop it
            if let t = titleStack.popLast() {
                Title = t
                Version += 1
            }
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
        case 3:
            // DECCOLM: the window keeps its size; the screen is cleared
            // and the margins reset, as a VT does on the switch.
            for y in 0..<Rows { screen[y] = Line(columns: Columns, fill: eraseCell) }
            top = 0
            bottom = Rows - 1
            left = 0
            right = Columns - 1
            moveTo(0, 0)
        case 5:
            ReverseVideo = on
            PaletteVersion += 1
        case 6:
            originMode = on
            moveTo(on ? left : 0, on ? top : 0)
        case 7: autowrap = on
        case 8: autorepeat = on
        case 12: CursorBlink = on
        case 25: CursorVisible = on
        case 40: allowColumnMode = on
        case 47, 1047: setAltScreen(on, clear: m == 1047 && !on, cursor: false)
        case 66: AppKeypad = on
        case 67: BackspaceSendsBS = on
        case 69:
            lrMarginMode = on
            if !on {
                left = 0
                right = Columns - 1
            }
        case 1048: if on { saveCursor() } else { restoreCursor() }
        case 1049: setAltScreen(on, clear: true, cursor: true)
        case 9, 1000: Mouse = on ? .clicks : .off
        case 1002: Mouse = on ? .drag : .off
        case 1003: Mouse = on ? .motion : .off
        case 1004: FocusReporting = on
        case 1005: setMouseFormat(.utf8, on)
        case 1006: setMouseFormat(.sgr, on)
        case 1007: AlternateScroll = on
        case 1015: setMouseFormat(.urxvt, on)
        case 1016: setMouseFormat(.sgrPixels, on)
        case 2004: BracketedPaste = on
        case 2026: SynchronizedOutput = on
        case 2031: ThemeReports = on
        default: break
        }
    }

    func setMouseFormat(_ f: MouseEncoding, _ on: bool) {
        if on {
            MouseFormat = f
        } else if MouseFormat == f {
            MouseFormat = .x10
        }
    }

    func reportMode(_ m: int, dec: bool) {
        // 1 set, 2 reset, 3 permanently set, 4 permanently reset, 0 not
        // recognized.
        var v = 0
        func b(_ on: bool) -> int { return on ? 1 : 2 }
        if dec {
            switch m {
            case 1: v = b(AppCursorKeys)
            case 3: v = 2
            case 5: v = b(ReverseVideo)
            case 6: v = b(originMode)
            case 7: v = b(autowrap)
            case 8: v = b(autorepeat)
            case 12: v = b(CursorBlink)
            case 25: v = b(CursorVisible)
            case 40: v = b(allowColumnMode)
            case 47, 1047, 1049: v = b(AltScreen)
            case 66: v = b(AppKeypad)
            case 67: v = b(BackspaceSendsBS)
            case 69: v = b(lrMarginMode)
            case 9, 1000: v = b(Mouse == .clicks)
            case 1002: v = b(Mouse == .drag)
            case 1003: v = b(Mouse == .motion)
            case 1004: v = b(FocusReporting)
            case 1005: v = b(MouseFormat == .utf8)
            case 1006: v = b(MouseFormat == .sgr)
            case 1007: v = b(AlternateScroll)
            case 1015: v = b(MouseFormat == .urxvt)
            case 1016: v = b(MouseFormat == .sgrPixels)
            case 2004: v = b(BracketedPaste)
            case 2026: v = b(SynchronizedOutput)
            case 2027: v = 3  // grapheme clusters: always
            case 2031: v = b(ThemeReports)
            default: v = 0
            }
            respond("\u{1b}[?\(m);\(v)$y")
        } else {
            switch m {
            case 4: v = b(insertMode)
            case 20: v = b(newlineMode)
            default: v = 0
            }
            respond("\u{1b}[\(m);\(v)$y")
        }
    }

    /// Tells a program that asked (mode 2031) that the color scheme
    /// changed: 1 dark, 2 light.
    public func ColorSchemeChanged(dark: bool) {
        DarkMode = dark
        if ThemeReports { respond("\u{1b}[?997;\(dark ? 1 : 2)n") }
    }

    // MARK: - SGR

    func sgr() {
        if params.isEmpty {
            let link = pen.Link
            let protected = pen.Attrs & Attr.protected
            pen = Cell.blank
            pen.Link = link
            pen.Attrs = protected
            return
        }
        var i = 0
        while i < params.count {
            let p = params[i] < 0 ? 0 : params[i]
            switch p {
            case 0:
                pen.Fg = .default
                pen.Bg = .default
                pen.Ul = .default
                pen.Attrs &= Attr.protected
            case 1: pen.Attrs |= Attr.bold
            case 2: pen.Attrs |= Attr.dim
            case 3: pen.Attrs |= Attr.italic
            case 4:
                pen.Attrs &= ~Attr.anyUnderline
                // 4:0 none, 4:1 single, 4:2 double, 4:3 curly, 4:4
                // dotted, 4:5 dashed.
                if i + 1 < params.count && colons[i + 1] {
                    let style = params[i + 1]
                    i += 1
                    switch style {
                    case 0: break
                    case 2: pen.Attrs |= Attr.doubleUnderline
                    case 3: pen.Attrs |= Attr.curlyUnderline
                    case 4: pen.Attrs |= Attr.dottedUnderline
                    case 5: pen.Attrs |= Attr.dashedUnderline
                    default: pen.Attrs |= Attr.underline
                    }
                } else {
                    pen.Attrs |= Attr.underline
                }
            case 5, 6: pen.Attrs |= Attr.blink
            case 7: pen.Attrs |= Attr.inverse
            case 8: pen.Attrs |= Attr.hidden
            case 9: pen.Attrs |= Attr.strike
            case 21:
                pen.Attrs &= ~Attr.anyUnderline
                pen.Attrs |= Attr.doubleUnderline
            case 22: pen.Attrs &= ~(Attr.bold | Attr.dim)
            case 23: pen.Attrs &= ~Attr.italic
            case 24: pen.Attrs &= ~Attr.anyUnderline
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
                if let (c, used) = extendedColor(i) {
                    pen.Ul = c
                    i += used
                }
            case 59: pen.Ul = .default
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
