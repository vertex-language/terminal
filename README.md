# terminal

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![packages: vt | view | workspace](https://img.shields.io/badge/packages-vt%20%7C%20view%20%7C%20workspace-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/terminal)
[![status: macOS tested](https://img.shields.io/badge/status-macOS%20tested-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/terminal)

<p align="center">
  <img src="docs/screenshot.png" alt="Vertex Terminal: three color-striped tabs, the first split into three panes -- the 16, 256 and 24-bit colors, underline styles, CJK and emoji beside a colored git log and a directory listing" width="100%">
</p>

<p align="center">
  <b>A terminal with everything Windows Terminal has, on the Mac -- written in Vertex, from the pseudo-terminal to the pixels.</b>
</p>

---

- **Every color, every style.** 16, 256 and 24-bit color; bold, italic, dim,
  strike, inverse; curly, double, dotted and dashed underlines in their own
  colors; OSC 8 hyperlinks; sixel images; CJK and emoji at double width; Windows
  Terminal's color schemes, light and dark.
- **Tabs and panes.** Chrome-style tabs in the title bar -- drag one to reorder
  it, give it a color, rename it -- each split into panes in any direction, to
  resize, zoom, swap or type into all at once.
- **A settings page, and `settings.json`.** Windows Terminal's own format:
  profiles, schemes, actions and keys, reloaded the moment it's saved. Or press
  ⌘, and change them in a Settings tab that writes the file for you.
- **Everything at a keystroke.** ⌘⇧P lists every action with its keys; find
  with ⌘F; jump between prompts with ⌘↑ ⌘↓; select by mouse, by keyboard (mark
  mode) or by block.
- **Nothing but Vertex.** `vt` is the emulator, `view` the renderer and
  `workspace` the window -- about 11,600 lines of `.vs`, `.vsx` and `.vss`,
  built into one native executable of under 5 MB. No Electron, no system web view.

<p align="center">
  <img src="docs/settings.png" alt="The Settings tab: a sidebar of pages and profiles beside cards of settings with switches, choices and steppers" width="100%">
</p>

[FEATURES.md](FEATURES.md) goes through Windows Terminal's features one by one.
The screenshot is `docs/showcase.sh`, in the layout and settings
(`docs/showcase.json`, One Half Dark) its header describes.

## Quick Start

```bash
vsc run terminal                           # your $SHELL, in a window
vsc run terminal -- --light                # or --dark, whatever the system's
vsc run terminal -- new-tab -p bash -d ~/src \; split-pane -V   # wt's command line
vsc run terminal -- --tabs 3 --type "ls\n" # open tabs, type into the last

vsc run check                              # the emulator's checks (offline)
vsc run check-ui                           # the window, headless, with real shells
vsc run render-snapshot -- out.png         # what view draws, as a PNG
```

`--snapshot out.png --snapshot-after 2` (from `ui/app`) draws the window two
seconds in and quits; `--action <id>` runs an action at startup
(`--action Terminal.ToggleCommandPalette`), `--quit-after 3` quits as ⌘Q
does.

| Keys | Do |
| :--- | :--- |
| ⌘⇧P | the command palette: every action, with its keys |
| ⌘T, ⌘⇧1–⌘⇧9, ⌘⇧Space | new tab; with that profile; the profiles menu |
| ⌘W, ⌘⇧W | close the pane (the tab with its last), close the window |
| ⌘⇧T, ⌘⇧O | reopen the last closed tab, duplicate the tab |
| ⌘1–⌘8, ⌘9, ⌘⇧[ ⌘⇧], ⌃Tab | that tab, the last tab, previous/next (⌃Tab: the switcher) |
| ⌘D, ⌘⇧D, ⌥⇧+, ⌥⇧- | split right, down; duplicate right, down |
| ⌘⌥arrows, ⌘[ ⌘], ⌘⌃arrows, ⌘⇧↩ | focus a pane, the previous/next, resize, zoom |
| ⌘F, ⌘G ⌘⇧G | find, next/previous match |
| ⌘C ⌘V ⌘A, ⌘⇧M | copy, paste (with warnings), select all; mark mode |
| ⌘↑ ⌘↓, ⌘⇧← ⌘⇧→ | previous/next prompt (shell integration); select command/output |
| ⇧PageUp ⇧PageDown, ⌘Home ⌘End, the wheel, the scrollbar | scroll |
| ⌘K, ⌘S | clear the buffer, export it to ~/Downloads |
| ⌘+ ⌘- ⌘0, ⌘ wheel, ⌘⇧ wheel | font size; opacity |
| ⌃⌘F, ⌘, | fullscreen, settings |
| drag, double-, triple-click, ⇧-click, ⌥-drag | select characters, a word, a line, extend, a block |
| ⌘-click | open a hyperlink or URL |
| right-click | the menu (copy, paste, split, find, read-only, export…) |

Option is a composing key, as on a Mac; `TERMINAL_OPTION_AS_META=1` sends it
as Meta (ESC before the key) for shells' Alt bindings.

## Settings

`~/Library/Application Support/vertex-terminal/settings.json` (or
`$VERTEX_TERMINAL_SETTINGS`), in [Windows Terminal's
format](https://learn.microsoft.com/windows/terminal/customize-settings/):
global settings, `profiles` (a `defaults` object and a `list`), `schemes`,
and `actions`/`keybindings` by Windows Terminal's ids, with `cmd` for ⌘.
It is written the first time with a profile for each shell in
`/etc/shells`, and read again whenever it is saved.

```jsonc
{
    "defaultProfile": "zsh",
    "copyOnSelect": true,
    "firstWindowPreference": "persistedWindowLayout",
    "profiles": {
        "defaults": { "colorScheme": "One Half Dark", "font": { "face": "SF Mono", "size": 13 }, "cursorShape": "bar" },
        "list": [ { "name": "Logs", "commandline": "tail -f /var/log/system.log", "tabColor": "#C50E1F" } ]
    },
    "keybindings": [ { "keys": "cmd+shift+e", "id": "Terminal.ToggleBroadcastInput" } ]
}
```

---

## Packages

| Package | What it is |
| :--- | :--- |
| **`terminal/vt`** | The emulator: bytes in, a screen of cells out. A DEC/xterm parser (UTF-8, CSI, OSC, DCS), the main and alternate screens, a scrollback ring with reflow, scrolling regions and left/right margins, rectangular editing, selective erase, SGR with 16, 256 and 24-bit colors and underline styles and colors, grapheme clusters, double-width/height lines, hyperlinks, shell-integration marks, palette changes, sixel images, the kitty keyboard protocol, and the reports programs ask for. `EncodeKey`, `EncodeMouse`, `EncodePaste`, `EncodeFocus` are what the host sends back; `Find` searches. No I/O and no drawing. |
| **`terminal/view`** | The renderer: a `vt.Terminal` into RGBA pixels, in a monospaced font and a theme (a Windows Terminal color scheme), with Windows Terminal's cursor shapes, a selection (or block), search matches, hyperlinks, sixel images and a scrollbar with marks. Box drawing and block elements are drawn as shapes so lines meet. It redraws only the rows that changed. |
| **`terminal/workspace`** | The window, as `.vsx` and `.vss`: the tab bar, split panes drawn into one surface (a `ui/viewport`), the command palette, find, menus and dialogs, keys and their actions, the pointer, selection and the clipboard, each pane's shell (`os/pty` + `vt`), and `settings.json`. `workspace.TerminalWindow(controller:)`. |

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

[FEATURES.md](FEATURES.md) has the list; the larger pieces are several
windows (and quake mode), background images
and acrylic, ligatures, regex search, copying as HTML, and Windows (where
`os/pty` has no ConPTY yet).

The bugs and gaps found on the way, in vsc and the packages it uses, are in
`../vsc_TODO.md`.

---

## Layout

```
terminal/
  vs.mod
  FEATURES.md  Windows Terminal's features, and which are here
  vt/          cell.vs, terminal.vs, parser.vs, csi.vs, input.vs, width.vs, sixel.vs
  view/        view.vs, theme.vs, boxes.vs
  workspace/   workspace.vsx, controller.vs, actions.vs, input.vs, panes.vs,
               shell.vs, settings.vs, schemes.vs, session.vs, ui.vs, style.vss,
               settingspage.vsx, settingsui.vs (the Settings tab), tabdrag.vs
  docs/        screenshot.png, settings.png, and showcase.sh/.json that make them
  cmd/
    terminal/         the app
    check/            vt's checks
    check-ui/         the window mounted headless, typed into, with real shells
    render-snapshot/  a sample screen drawn to a PNG
```

## License

[MIT](LICENSE)
