# terminal/vt

A terminal emulator's core: the bytes a program writes to a terminal in,
the screen they describe out. No I/O and no drawing.

```vertex
import "terminal/vt"

let term = vt.Terminal(columns: 80, rows: 24)
term.Feed(bytes)                          // what the program wrote, in any pieces
let row = term.ViewRow(0)                 // a row of cells, as the view shows it
shell.Write(term.TakeResponses())         // what the program asked to be told
term.Resize(columns: 120, rows: 40)

let keys = term.EncodeKey(key: "ArrowUp", code: "ArrowUp", vt.Modifiers())  // ESC [ A, or ESC O A
```

## Types

- **`Terminal`** (class): the screen, scrollback, cursor and modes. `Feed`, `Resize`, `Row`, `ViewRow`, `Absolute`, `Text(fromColumn:line:toColumn:line:)`, `ScreenText`, `ScrollView(by:)`, `ScrollToBottom`, `ClearScrollback`, `TakeResponses`, `TakeClipboard`; `Title`, `WorkingDirectory`, `Bells`, `AltScreen`, `CursorX`, `CursorY`, `CursorVisible`, `Shape`, `Mouse`, `BracketedPaste`, `Version`.
- **`Cell`**, **`Line`**, **`Color`**, **`Attr`**: what a cell shows: a code point or cluster, foreground, background and underline colors (default, indexed, 24-bit), a hyperlink, and attribute bits (bold, dim, italic, underline and its double, curly, dotted and dashed forms, blink, inverse, hidden, strike, overline, protected, wide and its spacer); a line's mark (OSC 133) and rendition (double width or height).
- **`Image`**, **`Notification`**, **`ProgressState`**, **`MouseEncoding`**, **`Mark`**, **`Rendition`**.
- **`Modifiers`**, **`CursorShape`**, **`MouseTracking`**.

## Functions

- `func Terminal.EncodeKey(key:code:_:altSendsEscape:) -> [uint8]?`: what a key sends, by its W3C names, or nil where its text arrives as text.
- `func Terminal.EncodeText(_:)`, `EncodePaste(_:)`, `EncodeFocus(_:)`, `EncodeMouse(button:column:row:kind:_:)`.
- `func CellWidth(_ cp: uint32) -> int`: 0, 1 or 2 cells.
- `func PaletteRGB(_ index: int)`: the 256-color palette.

## Sequences

C0 controls (ENQ answers `Answerback`); ESC 6 7 8 9 D E H M N O c n o = > \
( ) * + (G0–G3: ASCII, DEC line drawing, UK) #3 #4 #5 #6 #8; CSI @ A–G H I
J K L M P S T X Z ` a b c d e f g h l m n r s t u x, with `?` (DECSET/DECRST,
DECRQM, DECDSR, DECSED, DECSEL, DECST8C, kitty query), `>` (DA2, XTVERSION,
kitty push), `<` (kitty pop), `=` (DA3, kitty set), SP q @ A (DECSCUSR, SL,
SR), ! p (DECSTR), " q (DECSCA), $ p v z { x r t w (DECRQM, DECCRA, DECERA,
DECSERA, DECFRA, DECCARA, DECRARA, DECRQPSR), * x y (DECSACE, DECRQCRA),
' } ~ (DECIC, DECDC), s as DECSLRM in DECLRMM; DCS $ q (DECRQSS) and q
(sixel); OSC 0 1 2 4 7 8 9 (progress, directory, notification) 10 11 12 52
104 110 111 112 133 633 777 1337. Modes: IRM, LNM, DECCKM, DECCOLM,
DECSCNM, DECOM, DECAWM, autorepeat, cursor blink, DECTCEM, 40, DECNKM,
DECBKM, DECLRMM, 47/1047/1048/1049, mouse 9/1000/1002/1003 with encodings
1005/1006/1015/1016, focus 1004, alternate scroll 1007, bracketed paste
2004, synchronized output 2026, graphemes 2027, theme reports 2031.

Lines are rewrapped when the width changes (`Reflow`); combining marks,
ZWJ sequences, flags and VS16 join the character before them as a cluster
(`Cluster`, `RuneText`). Hyperlinks (`LinkURI`), shell marks (`Marks`,
`PreviousPrompt`, `NextPrompt`, `CommandOutput`), palette changes
(`PaletteColor`, `ForegroundOverride`…), progress, notifications
(`TakeNotifications`) and sixel `Images` are kept for the host to show.
`Find` searches the screen and the scrollback.

Part of the [`terminal`](https://github.com/vertex-language/terminal) repository.
