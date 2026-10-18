# Windows Terminal parity

What [Windows Terminal](https://github.com/microsoft/terminal) does (from
its settings schema, `defaults.json` and its VT dispatcher, at commit
`9fd41b2`), and where this terminal stands.

✅ done · ◐ partly · ✗ not yet · — Windows-only, nothing to match on macOS

## Tabs

| Feature | | Notes |
| :--- | :-: | :--- |
| New tab, close, next/previous, switch to tab 1–9/last | ✅ | ⌘T, ⌘W (pane, then tab), ⌃Tab, ⌘⇧[ ], ⌘1–⌘9 |
| New tab with a profile, new-tab dropdown (⌄) | ✅ | ⌘⇧1–⌘⇧9, ⌘⇧Space |
| Duplicate tab, restore last closed | ✅ | ⌘⇧O, ⌘⇧T (profile and directory; not the buffer) |
| Rename tab (double-click, menu, action), reset title | ✅ | `renameTab`, `openTabRenamer` |
| Tab color (picker, `setTabColor`, profile `tabColor`) | ✅ | |
| Move tab (forward/backward, drag to reorder) | ✅ | |
| Close other tabs, close tabs after | ✅ | tab menu, palette |
| Tab context menu | ✅ | right-click a tab |
| Bell indicator, progress indicator (OSC 9;4) | ✅ | dot; bar along the tab (normal, error, paused, indeterminate) |
| Tab search, tab switcher (MRU, ⌃Tab) | ✅ | `useTabSwitcher` |
| Tab width modes (equal, titleLength, compact) | ✅ | |
| Middle-click closes | ✅ | |
| Profile icon on the tab | ◐ | text/emoji icons; image paths aren't loaded |
| Tear a tab out into a new window, move tab to window | ✗ | one window (see Window) |

## Panes

| Feature | | Notes |
| :--- | :-: | :--- |
| Split right/left/down/up/auto, with a profile or duplicated | ✅ | ⌘D, ⌘⇧D, ⌥⇧+, ⌥⇧- |
| Move focus by direction, previous, in order, first | ✅ | ⌘⌥arrows, ⌘[ ⌘] |
| Resize (keys, dragging the divider) | ✅ | ⌘⌃arrows |
| Swap panes, toggle split orientation, zoom | ✅ | ⌘⇧↩ zooms |
| Close pane, close other panes | ✅ | |
| Broadcast input to every pane | ✅ | `toggleBroadcastInput` |
| Read-only pane | ✅ | |
| Move pane to another tab | ✅ | `movePane` |
| Restart connection | ✅ | also Enter after the program ends |
| `focusFollowMouse` | ✅ | |
| Focus parent/child pane (multi-pane selection) | ✗ | |
| Snippets pane, tasks, markdown pane | ✗ | |

## Command palette and search

| Feature | | Notes |
| :--- | :-: | :--- |
| Command palette: every action, with its keys, fuzzy filtered | ✅ | ⌘⇧P |
| Nested commands (new tab…, split…, color scheme…, tab color…, opacity…) | ✅ | |
| Command-line mode (`wt` subcommands) | ✅ | "Run command line…" |
| Find: incremental, match case, next/previous, all matches highlighted, scrollbar ticks | ✅ | ⌘F, ⌘G, ⌘⇧G |
| Find with regular expressions | ✗ | no regex package yet |
| Suggestions / shell completion menu, quick fix | ✗ | |

## Selection, clipboard, input

| Feature | | Notes |
| :--- | :-: | :--- |
| Drag, double-click word (`wordDelimiters`), triple-click line, shift-click extends | ✅ | |
| Block selection (⌥-drag, `toggleBlockSelection`), `trimBlockSelection` | ✅ | |
| Mark mode (keyboard selection) | ✅ | ⌘⇧M |
| Expand to word, switch endpoint, select all | ✅ | |
| Select command / output (shell integration) | ✅ | ⌘⇧← ⌘⇧→ |
| `copyOnSelect`, copy as single line | ✅ | |
| Copy as HTML/RTF (`copyFormatting`) | ✗ | the clipboard API takes text only |
| Paste, bracketed paste, `trimPaste`, large and multi-line paste warnings | ✅ | |
| Right-click: context menu, or copy/paste (`rightClickContextMenu`) | ✅ | |
| Clickable OSC 8 hyperlinks, detected URLs (⌘-click), link preview | ✅ | `experimental.detectURLs` |
| Search the web for the selection | ✅ | `searchWebDefaultQueryUrl` |
| `sendInput` actions, `multipleActions` | ✅ | |
| Kitty keyboard protocol | ✅ | disambiguate, all keys as escapes, associated text; per profile |
| Key release events (kitty flag 2), win32-input-mode | ✗ / — | |
| Drag and drop files to paste their paths | ✗ | the window has no file-drop events yet |

## Scrolling and marks

| Feature | | Notes |
| :--- | :-: | :--- |
| Scrollbar (visible/hidden), draggable | ✅ | `scrollbarState` |
| Scroll line/page/top/bottom actions, `rowsToScroll` | ✅ | |
| Shell integration marks (OSC 133, also 633 and 1337 SetMark) | ✅ | prompts on the scrollbar, red/green by exit code |
| Scroll to previous/next mark, add/clear marks, `autoMarkPrompts` | ✅ | ⌘↑ ⌘↓ |
| Clear buffer (all, screen, scrollback), export buffer | ✅ | ⌘K; export to ~/Downloads |

## Rendering and appearance

| Feature | | Notes |
| :--- | :-: | :--- |
| 16/256/24-bit color, the 16 built-in schemes, custom `schemes` | ✅ | Campbell, One Half, Solarized, Tango, Vintage, Dark+, CGA… |
| Scheme per light/dark appearance, `theme` dark/light/system | ✅ | |
| Per-profile foreground/background/cursor/selection colors | ✅ | |
| Font face (fallback list), size, weight, cell height/width | ✅ | |
| Zoom font (keys, ⌘-wheel), reset | ✅ | |
| Cursor shapes: bar, underscore, double underscore, filled box, empty box, vintage (height %), cursor color | ✅ | DECSCUSR overrides |
| Bold, dim, italic, blink, inverse, invisible, strikethrough, overline | ✅ | |
| Underline: single, double, curly, dotted, dashed, colored (SGR 58) | ✅ | |
| `intenseTextStyle`, `adjustIndistinguishableColors` | ✅ | |
| Combining marks, ZWJ emoji, flags, VS16 (grapheme clusters, mode 2027) | ✅ | |
| Double-width and double-height lines | ✅ | |
| Sixel images | ✅ | scroll with the text |
| Box drawing and block elements drawn as shapes | ✅ | |
| Reflow on resize | ✅ | main screen and scrollback |
| Window opacity (`opacity`, `adjustOpacity`, ⌘⇧-wheel) | ◐ | the whole window's alpha, not the background's alone |
| Acrylic, Mica, background images, retro effect, pixel shaders | ✗ | |
| Ligatures, font features and axes | ✗ | glyphs are shaped per cell |
| Unfocused appearance (a scheme for unfocused panes) | ◐ | unfocused panes get a hollow cursor and no accent border |

## Window

| Feature | | Notes |
| :--- | :-: | :--- |
| Fullscreen, focus mode (no tab bar), always on top, minimize | ✅ | ⌃⌘F |
| `launchMode`, `initialCols`/`initialRows`, `alwaysShowTabs` | ✅ | |
| Tabs in the title bar (`showTabsInTitlebar`), dragging the window by the bar, double-click to zoom | ✅ | Chrome-style tabs beside the window buttons |
| Title from the program, `showTerminalTitleInTitlebar`, rename window | ✅ | |
| Confirm closing several tabs (`warning.confirmOnClose`) | ✅ | |
| Restore the last session (`firstWindowPreference: persistedWindowLayout`), with the buffer's text | ✅ | |
| Several windows, quake mode, `globalSummon`, tray icon, identify windows | ✗ | `ui/app` runs one window |
| Default terminal, elevation/admin, ConPTY, WSL/Azure profiles, `wt.exe` aliases | — | macOS: profiles come from `/etc/shells` |

## Settings

| Feature | | Notes |
| :--- | :-: | :--- |
| `settings.json` in Windows Terminal's format, comments and trailing commas | ✅ | `~/Library/Application Support/vertex-terminal/` |
| Profiles with `defaults`, merged by guid or name; hidden; dynamic profiles | ✅ | |
| `actions` and `keybindings` by id, all of Windows Terminal's action ids | ✅ | ⌘ is `cmd` |
| Reload when the file is saved | ✅ | |
| `startupActions` and `wt` command lines (new-tab, split-pane, focus-tab, move-focus, swap-pane, focus-pane) | ✅ | also on the command line |
| `closeOnExit` (graceful, always, never), `bellStyle` (audible, visual, window) | ✅ | |
| `environment`, `startingDirectory`, `commandline`, `tabTitle`, `suppressApplicationTitle`, `historySize`, `padding`, `snapOnInput`, `answerbackMessage`, `compatibility.allowOSC52` | ✅ | |
| Graphical settings editor | ✅ | a Settings tab (⌘,): startup, interaction, appearance, color schemes, actions, the profiles' defaults and each profile; changes are written to `settings.json` at once. ⌘⇧, opens the JSON |

## VT

| Feature | | Notes |
| :--- | :-: | :--- |
| Cursor movement, erase, insert/delete chars and lines, scroll regions, tabs, REP | ✅ | |
| Left/right margins (DECLRMM, DECSLRM), DECIC/DECDC, SL/SR, DECBI/DECFI | ✅ | |
| Rectangular editing: DECCRA, DECFRA, DECERA, DECSERA, DECCARA, DECRARA, DECSACE, DECRQCRA | ✅ | |
| Selective erase: DECSCA, DECSED, DECSEL | ✅ | |
| Charsets: G0–G3, SO/SI, LS2/LS3, SS2/SS3, DEC line drawing, UK | ◐ | no NRCS, DRCS soft fonts, or DEC supplemental |
| Modes: DECCKM, DECSCNM, DECOM, DECAWM, DECTCEM, DECNKM, DECBKM, DECCOLM, 47/1047/1048/1049, mouse 9/1000/1002/1003, encodings 1005/1006/1015/1016, focus 1004, alternate scroll 1007, bracketed paste 2004, synchronized output 2026, graphemes 2027, theme reports 2031 | ✅ | |
| Reports: DA1/DA2/DA3, DSR/DECDSR, DECRQM, DECRQSS, DECRQPSR (tab stops), XTVERSION, XTWINOPS 14/16/18/19/22/23, ENQ | ✅ | |
| OSC 0/1/2 titles, 4/104 palette, 7 and 9;9 directory, 8 hyperlinks, 9;4 progress, 9 and 777 notifications, 10/11/12 and 110/111/112 colors, 52 clipboard, 133/633 marks, 1337 | ✅ | notifications show as toasts |
| Macros (DECDMAC/DECINVM), DECPS sounds, presentation/terminal state reports (DECRQPSR cursor, DECRQTSR), pages | ✗ | |
