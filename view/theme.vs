package view

import "image/draw"

/// The colors a terminal is drawn in: the default foreground and
/// background, the cursor, the selection, and the 16 ANSI colors that
/// indexed colors 0-15 name. A Windows Terminal color scheme is one
/// (`workspace` reads them from the settings).
public struct Theme {
    public var Name: string
    public var Foreground: draw.Color
    public var Background: draw.Color
    public var Cursor: draw.Color
    /// The text under a block cursor.
    public var CursorText: draw.Color
    public var Selection: draw.Color
    public var ANSI: [draw.Color]
    /// Bold text in colors 0-7 is shown in their bright forms, as most
    /// terminals do.
    public var BoldIsBright: bool
    /// Search matches, and the one the search is on.
    public var SearchMatch: draw.Color
    public var SearchCurrent: draw.Color

    public init(name: string, foreground: draw.Color, background: draw.Color, cursor: draw.Color, cursorText: draw.Color,
                selection: draw.Color, ansi: [draw.Color], boldIsBright: bool = true,
                searchMatch: draw.Color = hex(0x8A6D00), searchCurrent: draw.Color = hex(0xE8A317)) {
        Name = name
        Foreground = foreground
        Background = background
        Cursor = cursor
        CursorText = cursorText
        Selection = selection
        ANSI = ansi
        BoldIsBright = boldIsBright
        SearchMatch = searchMatch
        SearchCurrent = searchCurrent
    }

    public static let dark = Theme(
        name: "dark",
        foreground: hex(0xCCCCCC), background: hex(0x1E1E1E), cursor: hex(0xAEAFAD), cursorText: hex(0x1E1E1E),
        selection: hex(0x264F78),
        ansi: [hex(0x000000), hex(0xCD3131), hex(0x0DBC79), hex(0xE5E510), hex(0x2472C8), hex(0xBC3FBC), hex(0x11A8CD), hex(0xE5E5E5),
               hex(0x666666), hex(0xF14C4C), hex(0x23D18B), hex(0xF5F543), hex(0x3B8EEA), hex(0xD670D6), hex(0x29B8DB), hex(0xFFFFFF)])

    public static let light = Theme(
        name: "light",
        foreground: hex(0x333333), background: hex(0xFFFFFF), cursor: hex(0x333333), cursorText: hex(0xFFFFFF),
        selection: hex(0xADD6FF),
        ansi: [hex(0x000000), hex(0xCD3131), hex(0x00BC00), hex(0x949800), hex(0x0451A5), hex(0xBC05BC), hex(0x0598BC), hex(0x555555),
               hex(0x666666), hex(0xCD3131), hex(0x14CE14), hex(0xB5BA00), hex(0x0451A5), hex(0xBC05BC), hex(0x0598BC), hex(0xA5A5A5)],
        searchMatch: hex(0xF8E08E), searchCurrent: hex(0xF2B33D))

    /// Whether the background is dark: what the window's chrome follows.
    public var IsDark: bool {
        return luminance(Background) < 0.4
    }

    /// The 16 ANSI colors as 0xRRGGBB, for vt's color reports.
    public var Palette: [uint32] {
        return ANSI.map { (uint32($0.R) << 16) | (uint32($0.G) << 8) | uint32($0.B) }
    }
}

/// A color from 0xRRGGBB.
public func hex(_ v: uint32) -> draw.Color {
    return draw.Color(uint8((v >> 16) & 0xFF), uint8((v >> 8) & 0xFF), uint8(v & 0xFF))
}

/// A color from "#RRGGBB" or "#RGB"; nil for anything else.
public func ParseColor(_ s: string) -> draw.Color? {
    let b = [uint8](s.utf8)
    if b.isEmpty || b[0] != 0x23 { return nil }
    func h(_ c: uint8) -> uint32? {
        if c >= 0x30 && c <= 0x39 { return uint32(c - 0x30) }
        if c >= 0x61 && c <= 0x66 { return uint32(c - 0x61 + 10) }
        if c >= 0x41 && c <= 0x46 { return uint32(c - 0x41 + 10) }
        return nil
    }
    var v: uint32 = 0
    if b.count == 7 {
        for i in 1..<7 {
            guard let d = h(b[i]) else { return nil }
            v = v * 16 + d
        }
        return hex(v)
    }
    if b.count == 4 {
        for i in 1..<4 {
            guard let d = h(b[i]) else { return nil }
            v = v * 256 + d * 17
        }
        return hex(v)
    }
    return nil
}

/// "#RRGGBB" for a color.
public func ColorHex(_ c: draw.Color) -> string {
    let digits: [string] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    func two(_ v: uint8) -> string { return digits[int(v >> 4)] + digits[int(v & 15)] }
    return "#" + two(c.R) + two(c.G) + two(c.B)
}

/// a and b mixed: t of b, the rest a.
func mix(_ a: draw.Color, _ b: draw.Color, _ t: float32) -> draw.Color {
    func m(_ x: uint8, _ y: uint8) -> uint8 {
        return uint8(float32(x) * (1 - t) + float32(y) * t + 0.5)
    }
    return draw.Color(m(a.R, b.R), m(a.G, b.G), m(a.B, b.B), 255)
}

/// Relative luminance, 0 black to 1 white (WCAG's, without the gamma
/// curve: close enough to tell light from dark).
func luminance(_ c: draw.Color) -> float32 {
    return (0.2126 * float32(c.R) + 0.7152 * float32(c.G) + 0.0722 * float32(c.B)) / 255
}

/// fg moved away from bg where the two are too close to tell apart
/// (Windows Terminal's adjustIndistinguishableColors).
func distinguishable(_ fg: draw.Color, from bg: draw.Color) -> draw.Color {
    let lf = luminance(fg)
    let lb = luminance(bg)
    if abs(lf - lb) >= 0.12 { return fg }
    // Toward white on a dark background, black on a light one.
    return lb < 0.5 ? mix(fg, hex(0xFFFFFF), 0.55) : mix(fg, hex(0x000000), 0.55)
}
