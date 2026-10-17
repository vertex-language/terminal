package vt

/// A cell's color: the terminal's default, one of the 256 indexed colors
/// (0-15 the theme's ANSI colors), or a 24-bit color.
public struct Color: Equatable {
    /// 0 the default; 1 << 24 | index; 2 << 24 | 0xRRGGBB.
    public let Raw: uint32

    public init(raw: uint32) {
        Raw = raw
    }

    /// The default foreground or background, whichever the color is for.
    public static let `default` = Color(raw: 0)

    /// One of the 256 indexed colors.
    public static func Indexed(_ i: int) -> Color {
        return Color(raw: (1 << 24) | uint32(i & 0xFF))
    }

    /// A 24-bit color.
    public static func RGB(_ r: uint8, _ g: uint8, _ b: uint8) -> Color {
        return Color(raw: (2 << 24) | (uint32(r) << 16) | (uint32(g) << 8) | uint32(b))
    }

    public var IsDefault: bool { return Raw == 0 }
    public var IsIndexed: bool { return Raw >> 24 == 1 }
    public var IsRGB: bool { return Raw >> 24 == 2 }
    /// The index, for an indexed color.
    public var Index: int { return int(Raw & 0xFF) }
    public var R: uint8 { return uint8((Raw >> 16) & 0xFF) }
    public var G: uint8 { return uint8((Raw >> 8) & 0xFF) }
    public var B: uint8 { return uint8(Raw & 0xFF) }
}

/// The attributes a cell can have, as bits of `Cell.Attrs`.
public enum Attr {
    public static let bold: uint16 = 1
    public static let dim: uint16 = 2
    public static let italic: uint16 = 4
    public static let underline: uint16 = 8
    public static let blink: uint16 = 16
    public static let inverse: uint16 = 32
    public static let hidden: uint16 = 64
    public static let strike: uint16 = 128
    public static let doubleUnderline: uint16 = 256
    public static let curlyUnderline: uint16 = 512
    public static let overline: uint16 = 1024
    /// The cell holds a character two cells wide; the cell after it is its
    /// spacer.
    public static let wide: uint16 = 2048
    /// The right half of a wide character: nothing of its own to draw.
    public static let spacer: uint16 = 4096
}

/// One character cell: what it shows and how.
public struct Cell: Equatable {
    /// The code point shown, or 0 for a cell nothing was written to (drawn
    /// as a space).
    public var Rune: uint32
    public var Fg: Color
    public var Bg: Color
    public var Attrs: uint16

    public init(rune: uint32 = 0, fg: Color = .default, bg: Color = .default, attrs: uint16 = 0) {
        Rune = rune
        Fg = fg
        Bg = bg
        Attrs = attrs
    }

    public static let blank = Cell()

    public func Has(_ attr: uint16) -> bool {
        return Attrs & attr != 0
    }
}

/// A row of cells. `Wrapped` is set where the text ran on past the
/// right margin onto the next row, so copying joins them again.
public struct Line {
    public var Cells: [Cell]
    public var Wrapped: bool

    public init(columns: int, fill: Cell = .blank) {
        Cells = [Cell](repeating: fill, count: columns)
        Wrapped = false
    }

    /// The row's text, trailing blanks dropped.
    public func Text() -> string {
        var end = Cells.count
        while end > 0 && (Cells[end - 1].Rune == 0 || Cells[end - 1].Rune == 32) { end -= 1 }
        var out: [uint8] = []
        var i = 0
        while i < end {
            let c = Cells[i]
            if !c.Has(Attr.spacer) { appendUTF8(&out, c.Rune == 0 ? 32 : c.Rune) }
            i += 1
        }
        return textOf(out)
    }
}

/// The 256-color palette's colors 16-255: a 6×6×6 cube and a ramp of
/// grays, as xterm has them. 0-15 are the theme's.
public func PaletteRGB(_ index: int) -> (R: uint8, G: uint8, B: uint8) {
    if index >= 232 {
        let v = uint8(8 + (index - 232) * 10)
        return (R: v, G: v, B: v)
    }
    if index >= 16 {
        let i = index - 16
        let steps: [int] = [0, 95, 135, 175, 215, 255]
        return (R: uint8(steps[(i / 36) % 6]), G: uint8(steps[(i / 6) % 6]), B: uint8(steps[i % 6]))
    }
    // The standard 16, for a host with no theme.
    let ansi: [uint32] = [0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
                          0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff]
    let v = ansi[index & 15]
    return (R: uint8((v >> 16) & 0xFF), G: uint8((v >> 8) & 0xFF), B: uint8(v & 0xFF))
}

// appendUTF8 appends a code point's UTF-8.
func appendUTF8(_ out: inout [uint8], _ cp: uint32) {
    if cp < 0x80 {
        out.append(uint8(cp))
    } else if cp < 0x800 {
        out.append(uint8(0xC0 | (cp >> 6)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    } else if cp < 0x10000 {
        out.append(uint8(0xE0 | (cp >> 12)))
        out.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    } else {
        out.append(uint8(0xF0 | (cp >> 18)))
        out.append(uint8(0x80 | ((cp >> 12) & 0x3F)))
        out.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        out.append(uint8(0x80 | (cp & 0x3F)))
    }
}

func textOf(_ b: [uint8]) -> string {
    return string(decoding: b, as: UTF8.self)
}
