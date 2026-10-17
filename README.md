# terminal

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![packages: vt | view | workspace](https://img.shields.io/badge/packages-vt%20%7C%20view%20%7C%20workspace-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/terminal)
[![status: macOS tested](https://img.shields.io/badge/status-macOS%20tested-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/terminal)

A general-purpose terminal with tabs, written in Vertex from the ground up:
the emulator, the renderer and the window are `.vs`, `.vsx` and `.vss`. Each
tab runs your shell under a pseudo-terminal (`os/pty`); `vt` keeps the
screen it draws; `view` paints it into a viewport under a tab bar of `.vsx`
markup.

---

## Quick Start

```bash
vsc run terminal                           # your $SHELL, in a window
vsc run terminal -- --light                # or --dark, whatever the system's
vsc run terminal -- --tabs 3 --type "ls\n" # open tabs, type into the last

vsc run check                              # the emulator's checks (offline)
vsc run check-ui                           # the window, headless, with real shells
vsc run render-snapshot -- out.png         # what view draws, as a PNG
```

`--snapshot out.png --snapshot-after 2` (from `ui/app`) draws the window two
seconds in and quits.

| Keys | Do |
| :--- | :--- |
| ⌘T | new tab, in the current tab's directory |
| ⌘W, or the tab's × | close the tab (the window closes with the last) |
| ⌘1–⌘8, ⌘9 | that tab, the last tab |
| ⌘⇧[ ⌘⇧], ⌃Tab ⌃⇧Tab | previous, next tab |
| ⌘C ⌘V ⌘A | copy the selection, paste (bracketed where the program asked), select all |
| ⌘K | clear the scrollback and the screen |
| ⌘+ ⌘- ⌘0 | font size |
| ⇧PageUp ⇧PageDown, the wheel | scroll the scrollback |
| drag, double-click, triple-click | select characters, a word, a line (⇧ while a program has the mouse) |

Option is a composing key, as on a Mac; `TERMINAL_OPTION_AS_META=1` sends it
as Meta (ESC before the key) for shells' Alt bindings.

---

## Packages

| Package | What it is |
| :--- | :--- |
| **`terminal/vt`** | The emulator: bytes in, a screen of cells out. A DEC/xterm parser (UTF-8, CSI, OSC, DCS skipped), the main and alternate screens, a scrollback ring, scrolling regions, insert/delete, SGR with 16, 256 and 24-bit colors, DEC line drawing, wide characters, tab stops, modes, and the reports programs ask for. `EncodeKey`, `EncodeMouse`, `EncodePaste`, `EncodeFocus` are what the host sends back. No I/O and no drawing. |
| **`terminal/view`** | The renderer: a `vt.Terminal` into RGBA pixels, in a monospaced font (`text/font`) and a theme, with the cursor (block, underline, bar; hollow unfocused) and a selection. Box drawing and block elements are drawn as shapes so lines meet. It redraws only the rows that changed. |
| **`terminal/workspace`** | The window, as `.vsx` and `.vss`: the tab bar, the terminal surface (a `ui/viewport`), keys, the pointer, selection and the clipboard, and each tab's shell (`os/pty` + `vt`). `workspace.TerminalWindow(controller:)`. |

```
cmd/terminal   app.Run { <workspace.TerminalWindow /> }
      │
workspace      tab bar (.vsx/.vss) · Controller · Shell ──► os/pty (the shell's terminal)
      │                                   │
      ├──── view (pixels) ◄──── vt (screen, scrollback, modes) ◄── bytes
      │
ui/viewport ── ui/app ── web (page, events) ── ui/window
```

Output arrives in a task on the main actor: the shell's bytes go to
`vt.Feed`, the replies it wants (cursor reports, device attributes) go back
to the shell, and the viewport is invalidated; the next frame draws the
rows that changed. 200,000 lines of `seq` reach the screen in about a
quarter of a second (`check-ui`).

`TERM` is `xterm-256color`, with `COLORTERM=truecolor` and
`TERM_PROGRAM=vertex-terminal`.

---

## What it does not do yet

- **Reflow on resize.** Lines are cut or padded, not re-wrapped; rows move
  between the screen and the scrollback so the cursor keeps its row.
- **Combining marks** take no cell and are dropped; precomposed text is
  fine.
- **Windows**: `os/pty` has no ConPTY yet.
- Splits, a scrollbar, search, settings, hyperlinks (OSC 8), images (sixel,
  kitty).

The bugs and gaps found on the way, in vsc and the packages it uses, are in
`../vsc_TODO.md`.

---

## Layout

```
terminal/
  vs.mod
  vt/          cell.vs, terminal.vs, parser.vs, csi.vs, input.vs, width.vs
  view/        view.vs, theme.vs, boxes.vs
  workspace/   workspace.vsx, shell.vs, style.vss
  cmd/
    terminal/         the app
    check/            vt's checks
    check-ui/         the window mounted headless, typed into, with real shells
    render-snapshot/  a sample screen drawn to a PNG
```

## License

[MIT](LICENSE)
