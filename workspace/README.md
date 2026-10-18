# terminal/workspace

The terminal app's window, as `.vsx` and `.vss`, with Windows Terminal's
features: a tab bar over a terminal surface; each tab's panes, split side
by side or one above another, each running a profile's program under a
pseudo-terminal; a command palette, find, menus and dialogs; and Windows
Terminal's `settings.json`.

```vsx
import "terminal/workspace"

app.Run(title: "Terminal") { <workspace.TerminalWindow /> }
```

## Types

- **`Controller`** (class): the tabs and their panes, the settings, and what keys, the pointer and the wheel do. `Controller()` reads the user's settings; `Controller(settingsJSON:)` takes them as text (tests). Given to `TerminalWindow(controller:)` to drive and read it from outside: `RunAction(_:)` (any action id), `TabCount`, `TabTitles`, `ActiveIndex`, `PaneCount`, `FocusedPaneIndex`, `ScreenText()`, `PaneTexts()`, `SelectedText()`, `GridSize`, `SearchMatches`, `PaletteOpen`, `PaletteLabels`, and more.

## Functions

- `func TerminalWindow(controller: Controller? = nil) -> component.Node`: the window.
- `func InitialWindowSize() -> (Width: float32, Height: float32)`: the window's size for the settings' `initialCols` and `initialRows`.

## Files

| File | What it is |
| :--- | :--- |
| `workspace.vsx` | The markup: the tab bar, the surface, and what goes over it; launching (command line, `startupActions`, the last session). |
| `controller.vs` | Tabs, panes, the shells' output and exits, bells, titles, settings reloads, and drawing the panes into one surface. |
| `actions.vs` | Every Windows Terminal action, the command palette, menus, dialogs, find, marks, and `wt` command lines. |
| `input.vs` | Keys (bindings first, then the terminal), typing, paste, mark mode, the pointer (panes, dividers, the scrollbar, links, selection), the wheel. |
| `panes.vs` | `Pane`, the split tree (`PaneNode`), `Tab` (split, close, focus by direction, resize, swap, zoom) and `Workspace`. |
| `settings.vs` | `settings.json`: profiles, schemes, actions and keybindings, and the defaults, written the same way. |
| `schemes.vs` | Windows Terminal's built-in color schemes. |
| `session.vs` | The layout and text kept across launches (`persistedWindowLayout`). |
| `shell.vs` | A program under a pseudo-terminal: start, restart, write, resize, exit. |
| `settingspage.vsx` | The settings tab: its tab in the bar, and its page -- a sidebar of pages and a search box beside cards of settings, with icons from `icons/lucide`. |
| `settingsui.vs` | The settings tab's pages as rows (switches, choices, fields, numbers, schemes, keys), and writing a change to `settings.json`. |
| `ui.vs` | What the markup shows over the terminal. |

The surface is a `div` with a `tabindex`: it takes the keyboard when
pressed, keys arrive as `onKeyDown` (with modifiers) and typed text as
`onBeforeInput`, and the screen is one `ui/viewport` into which each
pane's `terminal/view` renderer is copied at its place. Each pane's
`Shell` reads its pseudo-terminal in a task on the main actor and
invalidates the viewport as output arrives; a shell starts once its pane
is laid out, so its first prompt is drawn for its real size.

The page's own rules (`html, body { height: 100% }`) are the program's to
write in its `.vss`: a library's sheet may not style the document. The
program's sheet reaches the page through the component call itself.

Part of the [`terminal`](https://github.com/vertex-language/terminal) repository.
