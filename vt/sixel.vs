package vt

/// A picture a program drew into the terminal (sixel), placed over the
/// cells from its corner: it scrolls with the text.
public struct Image: Equatable {
    /// Unique to this image, for a host's caches.
    public let ID: int
    /// Its pixels: premultiplied RGBA, top row first.
    public let Pixels: [uint8]
    public let Width: int
    public let Height: int
    /// The cell its top left corner is in: a column, and a line counted
    /// as the terminal counts them all (`ImageLine`).
    public let Column: int
    let row: int
    /// Whether it was drawn on the alternate screen.
    public let OnAltScreen: bool
}

var nextImageID = 1

/// The VT340's 16 colors, sixel's palette until a program defines its own.
let sixelDefaults: [uint32] = [
    0x000000, 0x3333CC, 0xCC2121, 0x33CC33, 0xCC33CC, 0x33CCCC, 0xCCCC33, 0x878787,
    0x424242, 0x545499, 0x994242, 0x549954, 0x995499, 0x549999, 0x999954, 0xCCCCCC,
]

extension Terminal {
    /// The absolute line (as `Absolute` numbers them) of an image's top.
    public func ImageLine(_ img: Image) -> int {
        return img.row - dropped
    }

    /// Images over the lines from..<to of the screen in front, absolute.
    public func ImagesOver(from: int, to: int) -> [Image] {
        var out: [Image] = []
        for img in Images where img.OnAltScreen == AltScreen {
            let top = ImageLine(img)
            let rows = (img.Height + max(1, CellPixelHeight) - 1) / max(1, CellPixelHeight)
            if top < to && top + rows > from { out.append(img) }
        }
        return out
    }

    /// Takes images away whose lines are gone: off the scrollback's top,
    /// or (for the alternate screen) off its top.
    func pruneImages() {
        let before = Images.count
        Images = Images.filter { img in
            let rows = (img.Height + max(1, CellPixelHeight) - 1) / max(1, CellPixelHeight)
            return ImageLine(img) + rows > 0
        }
        if Images.count != before { ImagesVersion += 1 }
    }

    /// Takes the screen's images away (a clear).
    func clearScreenImages() {
        if Images.isEmpty { return }
        let first = ringCount
        Images = Images.filter { img in img.OnAltScreen != AltScreen || (!AltScreen && ImageLine(img) < first) }
        ImagesVersion += 1
    }

    /// Decodes a sixel image (the DCS's parameters, then its data after
    /// the q) and places it at the cursor; the cursor goes to the line
    /// below it, as xterm's sixel scrolling has it.
    func sixel(_ params: [int], _ data: [uint8]) {
        // P2: 1 leaves unset pixels clear; otherwise they are color 0.
        let clearBackground = params.count > 1 && params[1] == 1
        var palette = [uint32](repeating: 0, count: 256)
        for i in 0..<16 { palette[i] = sixelDefaults[i] }
        var color = 0
        let maxW = 4096
        let maxH = 4096
        var width = 0
        var height = 0
        // Indices into the palette, -1 unset; grown as drawing reaches
        // further.
        var pix: [int16] = []
        var stride = 0
        var x = 0
        var band = 0
        func grow(_ w: int, _ h: int) {
            let nw = min(maxW, max(stride, w))
            let nh = min(maxH, max(pix.count / max(1, stride), h))
            if nw == stride && nh * stride == pix.count { return }
            var next = [int16](repeating: -1, count: nw * nh)
            let oldH = stride == 0 ? 0 : pix.count / stride
            for y in 0..<oldH {
                for xx in 0..<stride { next[y * nw + xx] = pix[y * stride + xx] }
            }
            pix = next
            stride = nw
        }
        func draw(_ bits: int, _ count: int) {
            if bits == 0 {
                x += count
                width = max(width, min(maxW, x))
                return
            }
            let y0 = band * 6
            if y0 >= maxH { x += count; return }
            grow(x + count, y0 + 6)
            for b in 0..<6 where bits & (1 << b) != 0 {
                let y = y0 + b
                if y >= maxH { continue }
                height = max(height, y + 1)
                var i = 0
                while i < count && x + i < stride {
                    pix[y * stride + x + i] = int16(color)
                    i += 1
                }
            }
            x += count
            width = max(width, min(maxW, x))
        }
        var i = 0
        let n = data.count
        func number() -> int {
            var v = 0
            var any = false
            while i < n && data[i] >= 0x30 && data[i] <= 0x39 {
                v = min(v * 10 + int(data[i] - 0x30), 1_000_000)
                any = true
                i += 1
            }
            return any ? v : -1
        }
        func numbers() -> [int] {
            var out: [int] = [number()]
            while i < n && data[i] == 0x3B {
                i += 1
                out.append(number())
            }
            return out
        }
        while i < n {
            let b = data[i]
            if b >= 0x3F && b <= 0x7E {
                draw(int(b - 0x3F), 1)
                i += 1
            } else if b == 0x21 {  // ! repeat
                i += 1
                let count = max(1, number())
                if i < n && data[i] >= 0x3F && data[i] <= 0x7E {
                    draw(int(data[i] - 0x3F), min(count, maxW))
                    i += 1
                }
            } else if b == 0x23 {  // # color
                i += 1
                let p = numbers()
                let pc = max(0, p[0]) & 255
                if p.count >= 5 {
                    let r: uint32
                    let g: uint32
                    let bl: uint32
                    if p[1] == 1 {
                        let rgb = hlsToRGB(p[2], p[3], p[4])
                        r = rgb.0
                        g = rgb.1
                        bl = rgb.2
                    } else {
                        r = uint32(clamp255(max(0, p[2]) * 255 / 100))
                        g = uint32(clamp255(max(0, p[3]) * 255 / 100))
                        bl = uint32(clamp255(max(0, p[4]) * 255 / 100))
                    }
                    palette[pc] = (r << 16) | (g << 8) | bl
                }
                color = pc
            } else if b == 0x22 {  // " raster attributes: aspect, size
                i += 1
                let p = numbers()
                if p.count >= 4 && p[2] > 0 && p[3] > 0 {
                    width = max(width, min(maxW, p[2]))
                    height = max(height, min(maxH, p[3]))
                    grow(width, height)
                }
            } else if b == 0x24 {  // $ to the band's start
                x = 0
                i += 1
            } else if b == 0x2D {  // - the next band
                x = 0
                band += 1
                i += 1
            } else {
                i += 1
            }
        }
        if width <= 0 || height <= 0 { return }
        grow(width, height)
        var rgba = [uint8](repeating: 0, count: width * height * 4)
        let bg = palette[0]
        for y in 0..<height {
            for xx in 0..<width {
                let v = pix[y * stride + xx]
                let o = (y * width + xx) * 4
                if v < 0 {
                    if clearBackground { continue }
                    rgba[o] = uint8((bg >> 16) & 0xFF)
                    rgba[o + 1] = uint8((bg >> 8) & 0xFF)
                    rgba[o + 2] = uint8(bg & 0xFF)
                    rgba[o + 3] = 255
                    continue
                }
                let c = palette[int(v)]
                rgba[o] = uint8((c >> 16) & 0xFF)
                rgba[o + 1] = uint8((c >> 8) & 0xFF)
                rgba[o + 2] = uint8(c & 0xFF)
                rgba[o + 3] = 255
            }
        }
        let img = Image(ID: nextImageID, Pixels: rgba, Width: width, Height: height, Column: cx,
                        row: ringCount + cy + dropped, OnAltScreen: AltScreen)
        nextImageID += 1
        // An image over another's cells replaces it.
        let rows = (height + max(1, CellPixelHeight) - 1) / max(1, CellPixelHeight)
        let top = ringCount + cy
        Images = Images.filter { o in
            if o.OnAltScreen != AltScreen { return true }
            let ot = ImageLine(o)
            let orows = (o.Height + max(1, CellPixelHeight) - 1) / max(1, CellPixelHeight)
            let ocols = (o.Width + max(1, CellPixelWidth) - 1) / max(1, CellPixelWidth)
            let cols = (width + max(1, CellPixelWidth) - 1) / max(1, CellPixelWidth)
            let covered = ot >= top && ot + orows <= top + rows && o.Column >= cx && o.Column + ocols <= cx + cols
            return !covered
        }
        Images.append(img)
        if Images.count > 64 { Images.removeFirst(Images.count - 64) }
        ImagesVersion += 1
        // The cursor goes below it, in its column.
        let col = cx
        for _ in 0..<rows {
            lineFeed()
        }
        cx = col
        pendingWrap = false
        Version += 1
    }
}

/// Sixel's HLS (hue 0-360 from blue, lightness and saturation 0-100) as
/// RGB 0-255.
func hlsToRGB(_ hIn: int, _ lIn: int, _ sIn: int) -> (uint32, uint32, uint32) {
    // Sixel's hue starts at blue; the usual formula's, at red.
    let h = float32((hIn + 240) % 360) / 360
    let l = float32(max(0, min(100, lIn))) / 100
    let s = float32(max(0, min(100, sIn))) / 100
    if s == 0 {
        let v = uint32(l * 255 + 0.5)
        return (v, v, v)
    }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func hue(_ tIn: float32) -> float32 {
        var t = tIn
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6 { return p + (q - p) * 6 * t }
        if t < 0.5 { return q }
        if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
        return p
    }
    let r = hue(h + 1.0 / 3)
    let g = hue(h)
    let b = hue(h - 1.0 / 3)
    return (uint32(r * 255 + 0.5), uint32(g * 255 + 0.5), uint32(b * 255 + 0.5))
}
