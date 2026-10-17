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
- **`Cell`**, **`Line`**, **`Color`**, **`Attr`**: what a cell shows: a code point, foreground and background (default, indexed, 24-bit), and attribute bits (bold, dim, italic, underline and its double and curly forms, blink, inverse, hidden, strike, overline, wide and its spacer).
- **`Modifiers`**, **`CursorShape`**, **`MouseTracking`**.

## Functions

- `func Terminal.EncodeKey(key:code:_:altSendsEscape:) -> [uint8]?`: what a key sends, by its W3C names, or nil where its text arrives as text.
- `func Terminal.EncodeText(_:)`, `EncodePaste(_:)`, `EncodeFocus(_:)`, `EncodeMouse(button:column:row:kind:_:)`.
- `func CellWidth(_ cp: uint32) -> int`: 0, 1 or 2 cells.
- `func PaletteRGB(_ index: int)`: the 256-color palette.

## Sequences

C0 controls; ESC 7 8 D E H M c = > ( ) #8; CSI @ A–G H I J K L M P S T X Z
` a b c d e f g h l m n r s t u, with `?` (DECSET/DECRST, DECRQM, DECDSR) and
`>` (DA2, XTVERSION), SP q (DECSCUSR), ! p (DECSTR), $ p (DECRQM); OSC 0 2 7
10 11 52; DCS, SOS, PM and APC read and skipped. Modes: IRM, LNM, DECCKM,
DECSCNM, DECOM, DECAWM, cursor blink, DECTCEM, 47/1047/1048/1049, mouse
9/1000/1002/1003/1006, focus 1004, alternate scroll 1007, bracketed paste
2004.

Part of the [`terminal`](https://github.com/vertex-language/terminal) repository.
