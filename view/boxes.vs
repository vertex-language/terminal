package view

import "image/draw"

// Box drawing (U+2500-257F) and block elements (U+2580-259F) are drawn
// as shapes rather than from the font, so lines meet across cells with
// no gaps whatever the font's line height.

// The lines of U+2500 onwards: four digits, up right down left, each 0
// none, 1 light, 2 heavy, 3 double. Dashed forms are drawn solid.
let boxLines: [string] = [
    "0101", "0202", "1010", "2020", "0101", "0202", "1010", "2020", "0101", "0202", "1010", "2020",
    "0110", "0210", "0120", "0220", "0011", "0012", "0021", "0022", "1100", "1200", "2100", "2200",
    "1001", "1002", "2001", "2002", "1110", "1210", "2110", "1120", "2120", "2210", "1220", "2220",
    "1011", "1012", "2011", "1021", "2021", "2012", "1022", "2022", "0111", "0112", "0211", "0212",
    "0121", "0122", "0221", "0222", "1101", "1102", "1201", "1202", "2101", "2102", "2201", "2202",
    "1111", "1112", "1211", "1212", "2111", "1121", "2121", "2112", "2211", "1122", "1221", "2212",
    "1222", "2122", "2221", "2222", "0101", "0202", "1010", "2020", "0303", "3030", "0310", "0130",
    "0330", "0013", "0031", "0033", "1300", "3100", "3300", "1003", "3001", "3003", "1310", "3130",
    "3330", "1013", "3031", "3033", "0313", "0131", "0333", "1303", "3101", "3303", "1313", "3131",
    "3333", "0110", "0011", "1001", "1100", "", "", "", "0001", "1000", "0100", "0010",
    "0002", "2000", "0200", "0020", "0201", "1020", "0102", "2010",
]

/// Whether a code point is drawn here rather than from the font.
func isDrawnShape(_ cp: uint32) -> bool {
    if cp >= 0x2500 && cp <= 0x257F { return !boxLines[int(cp - 0x2500)].isEmpty }
    return cp >= 0x2580 && cp <= 0x259F
}

/// Draws a box or block character into the cell at (x, y), w × h device
/// pixels, in color.
func drawShape(_ c: draw.Canvas, _ cp: uint32, _ x: int32, _ y: int32, _ w: int32, _ h: int32, _ color: draw.Color, scale: float32) {
    if cp >= 0x2580 {
        drawBlock(c, cp, x, y, w, h, color)
        return
    }
    let spec = [uint8](boxLines[int(cp - 0x2500)].utf8)
    let light = max(int32(1), int32((scale + 0.5)))
    let heavy = light * 2 + (light == 1 ? 0 : 0) + 1
    let cx = x + w / 2
    let cy = y + h / 2
    let up = int(spec[0] - 0x30), right = int(spec[1] - 0x30), down = int(spec[2] - 0x30), left = int(spec[3] - 0x30)
    func thick(_ k: int) -> int32 { return k == 2 ? heavy : light }
    // How far a horizontal line reaches past the centre to meet the
    // vertical one, and the other way.
    let vReach = max(thick(up), thick(down)) / 2 + 1
    let hReach = max(thick(left), thick(right)) / 2 + 1
    func hline(_ x0: int32, _ x1: int32, _ k: int) {
        if k == 3 {
            c.Fill(draw.IRect(x0, cy - light - light / 2 - 0, x1 - x0, light), color)
            c.Fill(draw.IRect(x0, cy + light - light / 2, x1 - x0, light), color)
        } else {
            let t = thick(k)
            c.Fill(draw.IRect(x0, cy - t / 2, x1 - x0, t), color)
        }
    }
    func vline(_ y0: int32, _ y1: int32, _ k: int) {
        if k == 3 {
            c.Fill(draw.IRect(cx - light - light / 2, y0, light, y1 - y0), color)
            c.Fill(draw.IRect(cx + light - light / 2, y0, light, y1 - y0), color)
        } else {
            let t = thick(k)
            c.Fill(draw.IRect(cx - t / 2, y0, t, y1 - y0), color)
        }
    }
    if left > 0 { hline(x, cx + (up > 0 || down > 0 ? vReach : 0), left) }
    if right > 0 { hline(cx - (up > 0 || down > 0 ? vReach - 1 : 0), x + w, right) }
    if up > 0 { vline(y, cy + (left > 0 || right > 0 ? hReach : 0), up) }
    if down > 0 { vline(cy - (left > 0 || right > 0 ? hReach - 1 : 0), y + h, down) }
}

func drawBlock(_ c: draw.Canvas, _ cp: uint32, _ x: int32, _ y: int32, _ w: int32, _ h: int32, _ color: draw.Color) {
    func eighthsH(_ n: int32) -> int32 { return (h * n + 4) / 8 }
    func eighthsW(_ n: int32) -> int32 { return (w * n + 4) / 8 }
    let hw = w / 2, hh = h / 2
    switch cp {
    case 0x2580: c.Fill(draw.IRect(x, y, w, hh), color)
    case 0x2581, 0x2582, 0x2583, 0x2584, 0x2585, 0x2586, 0x2587:
        let n = eighthsH(int32(cp - 0x2580))
        c.Fill(draw.IRect(x, y + h - n, w, n), color)
    case 0x2588: c.Fill(draw.IRect(x, y, w, h), color)
    case 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F:
        c.Fill(draw.IRect(x, y, eighthsW(int32(0x2590 - cp)), h), color)
    case 0x2590: c.Fill(draw.IRect(x + hw, y, w - hw, h), color)
    case 0x2591: c.Fill(draw.IRect(x, y, w, h), color.Faded(0.25))
    case 0x2592: c.Fill(draw.IRect(x, y, w, h), color.Faded(0.5))
    case 0x2593: c.Fill(draw.IRect(x, y, w, h), color.Faded(0.75))
    case 0x2594: c.Fill(draw.IRect(x, y, w, eighthsH(1)), color)
    case 0x2595:
        let n = eighthsW(1)
        c.Fill(draw.IRect(x + w - n, y, n, h), color)
    default:
        // Quadrants: bits upper-left 1, upper-right 2, lower-left 4,
        // lower-right 8.
        let quads: [int] = [4, 8, 1, 1 | 4 | 8, 1 | 8, 1 | 2 | 4, 1 | 2 | 8, 2, 2 | 4, 2 | 4 | 8]
        let i = int(cp) - 0x2596
        if i < 0 || i >= quads.count { return }
        let q = quads[i]
        if q & 1 != 0 { c.Fill(draw.IRect(x, y, hw, hh), color) }
        if q & 2 != 0 { c.Fill(draw.IRect(x + hw, y, w - hw, hh), color) }
        if q & 4 != 0 { c.Fill(draw.IRect(x, y + hh, hw, h - hh), color) }
        if q & 8 != 0 { c.Fill(draw.IRect(x + hw, y + hh, w - hw, h - hh), color) }
    }
}
