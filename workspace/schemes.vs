package workspace

import (
    "image/draw"
    "terminal/view"
)

// The color schemes Windows Terminal ships with (its defaults.json),
// under their names there: a profile's "colorScheme" names one of these
// or one of the settings' own "schemes".

let builtinSchemes: [view.Theme] = [
    scheme("Dimidium", fg: view.hex(0xBAB7B6), bg: view.hex(0x141414), cursor: view.hex(0x37E57B), selection: view.hex(0x8DB8E5),
           ansi: [view.hex(0x000000), view.hex(0xCF494C), view.hex(0x60B442), view.hex(0xDB9C11), view.hex(0x0575D8), view.hex(0xAF5ED2), view.hex(0x1DB6BB), view.hex(0xBAB7B6), view.hex(0x817E7E), view.hex(0xFF643B), view.hex(0x37E57B), view.hex(0xFCCD1A), view.hex(0x688DFD), view.hex(0xED6FE9), view.hex(0x32E0FB), view.hex(0xDEE3E4)]),
    scheme("Ottosson", fg: view.hex(0xBEBEBE), bg: view.hex(0x000000), cursor: view.hex(0xFFFFFF), selection: view.hex(0x92A4FD),
           ansi: [view.hex(0x000000), view.hex(0xBE2C21), view.hex(0x3FAE3A), view.hex(0xBE9A4A), view.hex(0x204DBE), view.hex(0xBB54BE), view.hex(0x00A7B2), view.hex(0xBEBEBE), view.hex(0x808080), view.hex(0xFF3E30), view.hex(0x58EA51), view.hex(0xFFC944), view.hex(0x2F6AFF), view.hex(0xFC74FF), view.hex(0x00E1F0), view.hex(0xFFFFFF)]),
    scheme("Campbell", fg: view.hex(0xCCCCCC), bg: view.hex(0x0C0C0C), cursor: view.hex(0xFFFFFF), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x0C0C0C), view.hex(0xC50F1F), view.hex(0x13A10E), view.hex(0xC19C00), view.hex(0x0037DA), view.hex(0x881798), view.hex(0x3A96DD), view.hex(0xCCCCCC), view.hex(0x767676), view.hex(0xE74856), view.hex(0x16C60C), view.hex(0xF9F1A5), view.hex(0x3B78FF), view.hex(0xB4009E), view.hex(0x61D6D6), view.hex(0xF2F2F2)]),
    scheme("Campbell Powershell", fg: view.hex(0xCCCCCC), bg: view.hex(0x012456), cursor: view.hex(0xFFFFFF), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x0C0C0C), view.hex(0xC50F1F), view.hex(0x13A10E), view.hex(0xC19C00), view.hex(0x0037DA), view.hex(0x881798), view.hex(0x3A96DD), view.hex(0xCCCCCC), view.hex(0x767676), view.hex(0xE74856), view.hex(0x16C60C), view.hex(0xF9F1A5), view.hex(0x3B78FF), view.hex(0xB4009E), view.hex(0x61D6D6), view.hex(0xF2F2F2)]),
    scheme("Vintage", fg: view.hex(0xC0C0C0), bg: view.hex(0x000000), cursor: view.hex(0xFFFFFF), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x000000), view.hex(0x800000), view.hex(0x008000), view.hex(0x808000), view.hex(0x000080), view.hex(0x800080), view.hex(0x008080), view.hex(0xC0C0C0), view.hex(0x808080), view.hex(0xFF0000), view.hex(0x00FF00), view.hex(0xFFFF00), view.hex(0x0000FF), view.hex(0xFF00FF), view.hex(0x00FFFF), view.hex(0xFFFFFF)]),
    scheme("One Half Dark", fg: view.hex(0xDCDFE4), bg: view.hex(0x282C34), cursor: view.hex(0xFFFFFF), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x282C34), view.hex(0xE06C75), view.hex(0x98C379), view.hex(0xE5C07B), view.hex(0x61AFEF), view.hex(0xC678DD), view.hex(0x56B6C2), view.hex(0xDCDFE4), view.hex(0x5A6374), view.hex(0xE06C75), view.hex(0x98C379), view.hex(0xE5C07B), view.hex(0x61AFEF), view.hex(0xC678DD), view.hex(0x56B6C2), view.hex(0xDCDFE4)]),
    scheme("One Half Light", fg: view.hex(0x383A42), bg: view.hex(0xFAFAFA), cursor: view.hex(0x4F525D), selection: view.hex(0x383A42),
           ansi: [view.hex(0x383A42), view.hex(0xE45649), view.hex(0x50A14F), view.hex(0xC18301), view.hex(0x0184BC), view.hex(0xA626A4), view.hex(0x0997B3), view.hex(0xFAFAFA), view.hex(0x4F525D), view.hex(0xDF6C75), view.hex(0x98C379), view.hex(0xE4C07A), view.hex(0x61AFEF), view.hex(0xC577DD), view.hex(0x56B5C1), view.hex(0xFFFFFF)]),
    scheme("Solarized Dark", fg: view.hex(0x839496), bg: view.hex(0x002B36), cursor: view.hex(0xFFFFFF), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x002B36), view.hex(0xDC322F), view.hex(0x859900), view.hex(0xB58900), view.hex(0x268BD2), view.hex(0xD33682), view.hex(0x2AA198), view.hex(0xEEE8D5), view.hex(0x073642), view.hex(0xCB4B16), view.hex(0x586E75), view.hex(0x657B83), view.hex(0x839496), view.hex(0x6C71C4), view.hex(0x93A1A1), view.hex(0xFDF6E3)]),
    scheme("Solarized Light", fg: view.hex(0x657B83), bg: view.hex(0xFDF6E3), cursor: view.hex(0x002B36), selection: view.hex(0x2C4D57),
           ansi: [view.hex(0x002B36), view.hex(0xDC322F), view.hex(0x859900), view.hex(0xB58900), view.hex(0x268BD2), view.hex(0xD33682), view.hex(0x2AA198), view.hex(0xEEE8D5), view.hex(0x073642), view.hex(0xCB4B16), view.hex(0x586E75), view.hex(0x657B83), view.hex(0x839496), view.hex(0x6C71C4), view.hex(0x93A1A1), view.hex(0xFDF6E3)]),
    scheme("Tango Dark", fg: view.hex(0xD3D7CF), bg: view.hex(0x000000), cursor: view.hex(0xFFFFFF), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x000000), view.hex(0xCC0000), view.hex(0x4E9A06), view.hex(0xC4A000), view.hex(0x3465A4), view.hex(0x75507B), view.hex(0x06989A), view.hex(0xD3D7CF), view.hex(0x555753), view.hex(0xEF2929), view.hex(0x8AE234), view.hex(0xFCE94F), view.hex(0x729FCF), view.hex(0xAD7FA8), view.hex(0x34E2E2), view.hex(0xEEEEEC)]),
    scheme("Tango Light", fg: view.hex(0x555753), bg: view.hex(0xFFFFFF), cursor: view.hex(0x000000), selection: view.hex(0x141414),
           ansi: [view.hex(0x000000), view.hex(0xCC0000), view.hex(0x4E9A06), view.hex(0xC4A000), view.hex(0x3465A4), view.hex(0x75507B), view.hex(0x06989A), view.hex(0xD3D7CF), view.hex(0x555753), view.hex(0xEF2929), view.hex(0x8AE234), view.hex(0xFCE94F), view.hex(0x729FCF), view.hex(0xAD7FA8), view.hex(0x34E2E2), view.hex(0xEEEEEC)]),
    scheme("Dark+", fg: view.hex(0xCCCCCC), bg: view.hex(0x1E1E1E), cursor: view.hex(0x808080), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x000000), view.hex(0xCD3131), view.hex(0x0DBC79), view.hex(0xE5E510), view.hex(0x2472C8), view.hex(0xBC3FBC), view.hex(0x11A8CD), view.hex(0xE5E5E5), view.hex(0x666666), view.hex(0xF14C4C), view.hex(0x23D18B), view.hex(0xF5F543), view.hex(0x3B8EEA), view.hex(0xD670D6), view.hex(0x29B8DB), view.hex(0xE5E5E5)]),
    scheme("VSCode Dark Modern", fg: view.hex(0xCCCCCC), bg: view.hex(0x1F1F1F), cursor: view.hex(0xFFFFFF), selection: view.hex(0x264F78),
           ansi: [view.hex(0x000000), view.hex(0xCD3131), view.hex(0x0DBC79), view.hex(0xE5E510), view.hex(0x2472C8), view.hex(0xBC3FBC), view.hex(0x11A8CD), view.hex(0xE5E5E5), view.hex(0x666666), view.hex(0xF14C4C), view.hex(0x23D18B), view.hex(0xF5F543), view.hex(0x3B8EEA), view.hex(0xD670D6), view.hex(0x29B8DB), view.hex(0xE5E5E5)]),
    scheme("VSCode Light Modern", fg: view.hex(0x3B3B3B), bg: view.hex(0xFFFFFF), cursor: view.hex(0x000000), selection: view.hex(0xADD6FF),
           ansi: [view.hex(0x000000), view.hex(0xCD3131), view.hex(0x00BC00), view.hex(0x949800), view.hex(0x0451A5), view.hex(0xBC05BC), view.hex(0x0598BC), view.hex(0x555555), view.hex(0x666666), view.hex(0xCD3131), view.hex(0x14CE14), view.hex(0xB5BA00), view.hex(0x0451A5), view.hex(0xBC05BC), view.hex(0x0598BC), view.hex(0xA5A5A5)]),
    scheme("CGA", fg: view.hex(0xAAAAAA), bg: view.hex(0x000000), cursor: view.hex(0x00AA00), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x000000), view.hex(0xAA0000), view.hex(0x00AA00), view.hex(0xAA5500), view.hex(0x0000AA), view.hex(0xAA00AA), view.hex(0x00AAAA), view.hex(0xAAAAAA), view.hex(0x555555), view.hex(0xFF5555), view.hex(0x55FF55), view.hex(0xFFFF55), view.hex(0x5555FF), view.hex(0xFF55FF), view.hex(0x55FFFF), view.hex(0xFFFFFF)]),
    scheme("IBM 5153", fg: view.hex(0xAAAAAA), bg: view.hex(0x000000), cursor: view.hex(0x00AA00), selection: view.hex(0xFFFFFF),
           ansi: [view.hex(0x000000), view.hex(0xAA0000), view.hex(0x00AA00), view.hex(0xC47E00), view.hex(0x0000AA), view.hex(0xAA00AA), view.hex(0x00AAAA), view.hex(0xAAAAAA), view.hex(0x555555), view.hex(0xFF5555), view.hex(0x55FF55), view.hex(0xFFFF55), view.hex(0x5555FF), view.hex(0xFF55FF), view.hex(0x55FFFF), view.hex(0xFFFFFF)]),
]

/// A scheme as Windows Terminal writes one: the selection is drawn
/// translucent over the background, as it draws it.
func scheme(_ name: string, fg: draw.Color, bg: draw.Color, cursor: draw.Color, selection: draw.Color, ansi: [draw.Color]) -> view.Theme {
    let dark = (0.2126 * float32(bg.R) + 0.7152 * float32(bg.G) + 0.0722 * float32(bg.B)) / 255 < 0.5
    return view.Theme(name: name, foreground: fg, background: bg, cursor: cursor, cursorText: bg,
                      selection: blend(bg, selection, 0.35), ansi: ansi,
                      searchMatch: dark ? view.hex(0x8A6D00) : view.hex(0xF8E08E),
                      searchCurrent: dark ? view.hex(0xE8A317) : view.hex(0xF2B33D))
}

/// a and b mixed: t of b.
func blend(_ a: draw.Color, _ b: draw.Color, _ t: float32) -> draw.Color {
    func m(_ x: uint8, _ y: uint8) -> uint8 { return uint8(float32(x) * (1 - t) + float32(y) * t + 0.5) }
    return draw.Color(m(a.R, b.R), m(a.G, b.G), m(a.B, b.B))
}
