# terminal/workspace

The terminal app's window, as `.vsx` and `.vss`: a tab bar over a terminal
surface, each tab a shell under a pseudo-terminal.

```vsx
import "terminal/workspace"

app.Run(title: "Terminal") { <workspace.TerminalWindow /> }
```

## Types

- **`Controller`** (class): the tabs, the one view showing the tab in front, and what keys, the pointer and the wheel do. Given to `TerminalWindow(controller:)` to read it from outside: `TabCount`, `TabTitles`, `ActiveIndex`, `ScreenText()`, `SelectedText()`, `GridSize`.

## Functions

- `func TerminalWindow(controller: Controller? = nil) -> component.Node`: the window.

The surface is a `div` with a `tabindex`: it takes the keyboard when
pressed, keys arrive as `onKeyDown` (with modifiers) and typed text as
`onBeforeInput`, and the screen is a `ui/viewport` that `terminal/view`
draws. Each tab's `Shell` reads its pseudo-terminal in a task on the main
actor and invalidates the viewport as output arrives.

The page's own rules (`html, body { height: 100% }`) are the program's to
write in its `.vss`: a library's sheet may not style the document. The
program's sheet reaches the page through the component call itself.

Part of the [`terminal`](https://github.com/vertex-language/terminal) repository.
