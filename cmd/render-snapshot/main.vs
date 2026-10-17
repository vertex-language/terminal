// render-snapshot: draws a terminal with sample output -- colors, styles,
// box drawing, wide characters, a selection and the cursor -- into a PNG,
// headless, to look at what view draws.
//
//     vsc run render-snapshot -- out.png [light]
package main

import (
    "fs"
    "image"
    "image/png"
    "terminal/view"
    "terminal/vt"
)

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "render.png"
let light = args.count > 2 && args[2] == "light"

let t = vt.Terminal(columns: 72, rows: 22)
t.Feed("\u{1b}[1;32muser@host\u{1b}[0m:\u{1b}[1;34m~/vertex\u{1b}[0m$ ls --color\r\n")
t.Feed("\u{1b}[1;34mcmd\u{1b}[0m  \u{1b}[1;34mvt\u{1b}[0m  \u{1b}[1;34mview\u{1b}[0m  vs.mod  \u{1b}[1;32mbuild.sh\u{1b}[0m  README.md\r\n")
var colors = ""
for i in 0..<16 { colors += "\u{1b}[48;5;\(i)m  " }
t.Feed(colors + "\u{1b}[0m\r\n")
var cube = ""
for i in 0..<64 { cube += "\u{1b}[48;5;\(16 + i * 3)m " }
t.Feed(cube + "\u{1b}[0m\r\n")
var grad = ""
for i in 0..<64 { grad += "\u{1b}[48;2;\(i * 4);\(100 + i);\(255 - i * 4)m " }
t.Feed(grad + "\u{1b}[0m\r\n")
t.Feed("\u{1b}[1mbold\u{1b}[0m \u{1b}[2mdim\u{1b}[0m \u{1b}[3mitalic\u{1b}[0m \u{1b}[4munderline\u{1b}[0m \u{1b}[9mstrike\u{1b}[0m \u{1b}[7minverse\u{1b}[0m \u{1b}[21mdouble\u{1b}[0m \u{1b}[53mover\u{1b}[0m\r\n")
for i in 0..<8 { t.Feed("\u{1b}[3\(i)mcolor\(i) ") }
t.Feed("\u{1b}[0m\r\n")
for i in 0..<8 { t.Feed("\u{1b}[9\(i)mbright\(i) ") }
t.Feed("\u{1b}[0m\r\n")
t.Feed("┌──────┬──────┐ ╔══════╗ ╭──────╮ ▁▂▃▄▅▆▇█ ░▒▓ ▖▗▘▙▚▛▜▝▞▟\r\n")
t.Feed("│ box  │ ┃━┃  │ ║ dbl  ║ │ round│ ▏▎▍▌▋▊▉█ ▀▄▐▌\r\n")
t.Feed("├──────┼──────┤ ╠══════╣ ╰──────╯ ┏━━┳━━┓\r\n")
t.Feed("└──────┴──────┘ ╚══════╝          ┗━━┻━━┛\r\n")
t.Feed("\u{1b}(0lqqqqwqqqqk\u{1b}(B  DEC line drawing  \u{1b}(0x\u{1b}(B  ~ \u{1b}(0`afgjklmnopqrstuvwxyz{|}~\u{1b}(B\r\n")
t.Feed("wide: 日本語のテキスト 한국어 中文 emoji: 😀 🚀 ✨ — accents: é ñ ü ø\r\n")
t.Feed("selected text here: the quick brown fox\r\n")
t.Feed("\u{1b}[38;2;255;128;0morange truecolor\u{1b}[0m \u{1b}[48;5;236m on 236 \u{1b}[0m \u{1b}[4:3mcurly\u{1b}[0m\r\n")
t.Feed("\u{1b}[1;32muser@host\u{1b}[0m:\u{1b}[1;34m~/vertex\u{1b}[0m$ echo cursor")

let r = view.Renderer(theme: light ? .light : .dark)
let scale: float32 = 2
let cell = r.CellSize(scale: scale)
let w = int((cell.Width * 72 + 12) * scale)
let h = int((cell.Height * 22 + 12) * scale)
let sel = view.Selection(startColumn: 0, startLine: t.ViewTop + 17, endColumn: 17, endLine: t.ViewTop + 17)
let px = r.Draw(t, width: w, height: h, scale: scale, cursor: view.CursorState(visible: true, focused: true), selection: sel)
// A second frame after one more character: only its row is drawn.
t.Feed("!")
let px2 = r.Draw(t, width: w, height: h, scale: scale, cursor: view.CursorState(visible: true, focused: true), selection: sel)
try! fs.WriteFile(fs.Path(out), png.Encode(image.RGBA(width: w, height: h, pixels: px2)))
print("wrote \(out) \(w)x\(h), \(px.count == px2.count ? "same size" : "resized")")
