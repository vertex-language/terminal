package view

import "image/draw"

/// The colors a terminal is drawn in: the default foreground and
/// background, the cursor, the selection, and the 16 ANSI colors that
/// indexed colors 0-15 name.
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

    public init(name: string, foreground: draw.Color, background: draw.Color, cursor: draw.Color, cursorText: draw.Color,
                selection: draw.Color, ansi: [draw.Color], boldIsBright: bool = true) {
        Name = name
        Foreground = foreground
        Background = background
        Cursor = cursor
        CursorText = cursorText
        Selection = selection
        ANSI = ansi
        BoldIsBright = boldIsBright
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
               hex(0x666666), hex(0xCD3131), hex(0x14CE14), hex(0xB5BA00), hex(0x0451A5), hex(0xBC05BC), hex(0x0598BC), hex(0xA5A5A5)])
}

/// A color from 0xRRGGBB.
public func hex(_ v: uint32) -> draw.Color {
    return draw.Color(uint8((v >> 16) & 0xFF), uint8((v >> 8) & 0xFF), uint8(v & 0xFF))
}

/// a and b mixed: t of b, the rest a.
func mix(_ a: draw.Color, _ b: draw.Color, _ t: float32) -> draw.Color {
    func m(_ x: uint8, _ y: uint8) -> uint8 {
        return uint8(float32(x) * (1 - t) + float32(y) * t + 0.5)
    }
    return draw.Color(m(a.R, b.R), m(a.G, b.G), m(a.B, b.B), 255)
}
