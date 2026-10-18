package workspace

import (
    "encoding/json"
    "terminal/view"
    "terminal/vt"
    "ui/app"
    "ui/window"
)

/// The colors the tab color picker offers, as Windows Terminal's does.
let tabColors: [(string, string)] = [
    ("Crimson", "#C50E1F"), ("Steel Blue", "#0078D4"), ("Sea Green", "#10893E"), ("Dark Orange", "#CA5010"),
    ("Dark Violet", "#8764B8"), ("Dark Slate Gray", "#486860"), ("Lime", "#7FBA00"), ("Yellow", "#FFB900"),
]

extension Controller {
    /// Runs an action; false where it didn't apply (copy with nothing
    /// selected), so its key goes on to the terminal.
    @discardableResult
    func Run(_ a: Action) -> bool {
        let tab = ws.Current
        let pane = currentPane
        switch a.Command {
        // Tabs.
        case "newTab":
            if a.Args["index"] != nil {
                let vis = settings.VisibleProfiles
                let i = a.Int("index")
                if i < 0 || i >= vis.count { return false }
                NewTab(profile: vis[i].Guid, dir: a.Args["startingDirectory"]?.String, commandline: a.Args["commandline"]?.String,
                       title: a.Args["tabTitle"]?.String, color: a.Args["tabColor"]?.String)
            } else {
                NewTab(profile: a.Args["profile"]?.String, dir: a.Args["startingDirectory"]?.String, commandline: a.Args["commandline"]?.String,
                       title: a.Args["tabTitle"]?.String, color: a.Args["tabColor"]?.String)
            }
        case "newWindow":
            // One window: a new tab is the nearest thing.
            NewTab()
            toast("New windows open as tabs: Vertex Terminal has one window")
        case "duplicateTab":
            guard let p = pane else { return false }
            NewTab(profile: p.profile.Guid, dir: p.shell.Directory)
        case "closeTab":
            if let i = a.Args["index"]?.Int, int(i) < ws.Tabs.count {
                Close(ws.Tabs[int(i)].ID)
            } else if let t = tab {
                Close(t.ID)
            }
        case "closeOtherTabs":
            guard let t = tab else { return false }
            for other in ws.Tabs where other.ID != t.ID { Close(other.ID) }
        case "closeTabsAfter":
            guard let t = tab, let i = ws.Index(of: t.ID) else { return false }
            let after = ws.Tabs.dropFirst(i + 1).map { $0.ID }
            for id in after { Close(id) }
        case "nextTab":
            if settings.UseTabSwitcher && ws.Tabs.count > 1 && a.Str("tabSwitcherMode") != "disabled" && switcherKeyHeld {
                openSwitcher(1)
            } else {
                Step(1)
            }
        case "prevTab":
            if settings.UseTabSwitcher && ws.Tabs.count > 1 && a.Str("tabSwitcherMode") != "disabled" && switcherKeyHeld {
                openSwitcher(-1)
            } else {
                Step(-1)
            }
        case "switchToTab":
            let i = a.Int("index")
            let idx = i >= ws.Tabs.count || i < 0 ? ws.Tabs.count - 1 : i
            if idx >= 0 && idx < ws.Tabs.count { Select(ws.Tabs[idx].ID) }
        case "moveTab":
            guard let t = tab, let i = ws.Index(of: t.ID) else { return false }
            let j = a.Str("direction") == "backward" ? i - 1 : i + 1
            if j < 0 || j >= ws.Tabs.count { return true }
            let moved = ws.Tabs.remove(at: i)
            ws.Tabs.insert(moved, at: j)
        case "restoreLastClosed":
            guard let last = closed.popLast() else {
                toast("Nothing to restore")
                return true
            }
            NewTab(profile: last.0.Guid, dir: last.1)
        case "renameTab":
            guard let t = tab else { return false }
            t.CustomTitle = a.Str("title")
            UpdateTitle(t)
        case "openTabRenamer":
            guard let t = tab else { return false }
            startRename(t.ID)
        case "setTabColor":
            guard let t = tab else { return false }
            t.Color = a.Str("color")
        case "openTabColorPicker":
            guard let t = tab else { return false }
            openColorPicker(t.ID, x: 40, y: 34)
        case "tabSearch":
            openPalette(mode: "tabs")

        // Panes.
        case "splitPane":
            if a.Str("splitMode") == "duplicate" {
                SplitPane(direction: a.Str("split", "auto"), duplicate: true, size: float32(a.Args["size"]?.Double ?? 0.5))
            } else {
                SplitPane(direction: a.Str("split", "auto"), profile: a.Args["profile"]?.String, size: float32(a.Args["size"]?.Double ?? 0.5),
                          dir: a.Args["startingDirectory"]?.String, commandline: a.Args["commandline"]?.String)
            }
        case "closePane":
            guard let p = pane else { return false }
            ClosePane(p.ID)
        case "closeOtherPanes":
            guard let t = tab, let p = pane else { return false }
            for other in t.Panes where other.ID != p.ID { ClosePane(other.ID) }
        case "moveFocus":
            guard let t = tab, let n = t.Neighbor(a.Str("direction")) else { return true }
            FocusPane(n.ID)
        case "swapPane":
            guard let t = tab else { return false }
            t.Swap(a.Str("direction"))
            frameAll = true
            redraw()
        case "resizePane":
            guard let t = tab else { return false }
            t.Resize(a.Str("direction"))
            frameAll = true
            redraw()
        case "togglePaneZoom":
            guard let t = tab else { return false }
            t.ToggleZoom()
            frameAll = true
            redraw()
        case "toggleSplitOrientation":
            guard let t = tab else { return false }
            t.ToggleOrientation()
            frameAll = true
            redraw()
        case "toggleBroadcastInput":
            guard let t = tab else { return false }
            t.Broadcast = !t.Broadcast
            toast(t.Broadcast ? "Broadcasting input to all panes" : "Broadcast input off")
        case "toggleReadOnlyMode", "enableReadOnlyMode", "disableReadOnlyMode":
            guard let p = pane, let t = tab else { return false }
            p.ReadOnly = a.Command == "toggleReadOnlyMode" ? !p.ReadOnly : a.Command == "enableReadOnlyMode"
            t.ReadOnly = p.ReadOnly
            toast(p.ReadOnly ? "Pane is read-only" : "Pane is writable")
        case "movePane":
            guard let t = tab, let p = pane else { return false }
            let i = a.Int("index")
            if i < 0 || i >= ws.Tabs.count || ws.Tabs[i].ID == t.ID { return true }
            let target = ws.Tabs[i]
            if t.Panes.count <= 1 { return true }
            _ = t.Remove(p.ID)
            if let leaf = target.root.Find(target.Focused) {
                _ = leaf
                target.Split(p, direction: "right")
            }
            Select(target.ID)
        case "restartConnection":
            guard let p = pane else { return false }
            p.shell.Restart()
        // Clipboard and selection.
        case "copy":
            guard let s = current, let sel = s.selection, !sel.IsEmpty else { return false }
            var text = selectionText(s, sel)
            if a.Bool("singleLine") {
                text = text.split(separator: "\n").map { trimmed(String($0)) }.joined(separator: " ")
            }
            window.SetClipboardText(text)
            if a.Bool("dismissSelection", true) {
                s.selection = nil
                redraw()
            }
        case "paste":
            guard let p = pane else { return false }
            paste(p, window.ClipboardText())
        case "selectAll":
            guard let s = current else { return false }
            let t = s.term
            s.selection = view.Selection(startColumn: 0, startLine: 0, endColumn: t.Columns - 1, endLine: t.ScrollbackCount + t.Rows - 1)
            redraw()
        case "markMode":
            toggleMarkMode()
        case "toggleBlockSelection":
            guard let s = current, var sel = s.selection else { return false }
            sel.Block = !sel.Block
            s.selection = sel
            redraw()
        case "switchSelectionEndpoint":
            guard let s = current, let sel = s.selection else { return false }
            s.selection = view.Selection(startColumn: sel.EndColumn, startLine: sel.EndLine, endColumn: sel.StartColumn, endLine: sel.StartLine, block: sel.Block)
            markColumn = sel.StartColumn
            markLine = sel.StartLine
            redraw()
        case "expandSelectionToWord":
            guard let s = current, let sel = s.selection?.Ordered else { return false }
            let a0 = wordAt(s.term, sel.StartColumn, sel.StartLine, settings.WordDelimiters)
            let b0 = wordAt(s.term, sel.EndColumn, sel.EndLine, settings.WordDelimiters)
            s.selection = view.Selection(startColumn: a0.0, startLine: sel.StartLine, endColumn: b0.1, endLine: sel.EndLine)
            redraw()
        case "selectCommand", "selectOutput":
            selectCommand(output: a.Command == "selectOutput", next: a.Str("direction") == "next")
        case "showContextMenu":
            openContextMenu(x: pointerX, y: pointerY)
        case "searchWeb":
            let q = SelectedText()
            if q.isEmpty { return false }
            let url = a.Str("queryUrl", settings.SearchWebDefaultQueryUrl)
            let url2 = replaceAll(url, "%s", percentEncode(q))
            openExternal(url2)

        // Scrolling and marks.
        case "scrollUp", "scrollDown":
            guard let t = current?.term else { return false }
            let n = a.Int("rowsToScroll", 1)
            t.ScrollView(by: a.Command == "scrollUp" ? n : -n)
            redraw()
        case "scrollUpPage", "scrollDownPage":
            guard let t = current?.term else { return false }
            t.ScrollView(by: a.Command == "scrollUpPage" ? t.Rows - 1 : -(t.Rows - 1))
            redraw()
        case "scrollToTop":
            guard let t = current?.term else { return false }
            t.ScrollView(by: t.ScrollbackCount)
            redraw()
        case "scrollToBottom":
            guard let t = current?.term else { return false }
            t.ScrollToBottom()
            redraw()
        case "scrollToMark":
            scrollToMark(a.Str("direction", "previous"))
        case "addMark":
            guard let t = current?.term else { return false }
            t.AddMark()
            redraw()
        case "clearMark", "clearAllMarks":
            guard let t = current?.term else { return false }
            t.ClearMarks()
            redraw()
        case "clearBuffer":
            guard let s = current else { return false }
            let what = a.Str("clear", "all")
            if what == "scrollback" || what == "all" { s.term.ClearScrollback() }
            if what == "screen" || what == "all" {
                // ^L: the shell clears the screen and draws its prompt again.
                s.Send([12])
            }
            s.selection = nil
            redraw()
        case "exportBuffer":
            exportBuffer()

        // Find.
        case "find":
            openSearch()
        case "findMatch":
            if !ui.Search { openSearch() }
            stepMatch(a.Str("direction") == "prev" ? -1 : 1)

        // Font, colors, opacity.
        case "adjustFontSize":
            guard let p = pane else { return false }
            p.renderer.SetFont(size: p.renderer.FontSize + float32(a.Int("delta", 1)))
            p.dirty = true
            frameAll = true
            redraw()
        case "resetFontSize":
            guard let p = pane else { return false }
            p.renderer.SetFont(size: p.baseFontSize)
            p.dirty = true
            frameAll = true
            redraw()
        case "setColorScheme":
            guard let p = pane else { return false }
            let name = a.Str("colorScheme")
            if settings.Scheme(name) == nil {
                toast("No color scheme named \(name)")
                return true
            }
            p.profile.ColorScheme = name
            p.profile.ColorSchemeDark = ""
            p.profile.ColorSchemeLight = ""
            p.renderer.SetTheme(settings.ThemeFor(p.profile, dark: dark))
            p.dirty = true
            redraw()
        case "adjustOpacity":
            guard let p = pane else { return false }
            let v = a.Int("opacity", 100)
            p.profile.Opacity = max(5, min(100, a.Bool("relative") ? p.profile.Opacity + v : v))
            applyOpacity()

        // The window.
        case "toggleFullscreen", "setFullScreen":
            let on = a.Command == "setFullScreen" ? a.Bool("isFullScreen", true) : !app.IsFullscreen()
            app.SetFullscreen(on)
        case "toggleFocusMode", "setFocusMode":
            ui.FocusMode = a.Command == "setFocusMode" ? a.Bool("isFocusMode", true) : !ui.FocusMode
            redraw()
        case "toggleAlwaysOnTop":
            alwaysOnTop = !alwaysOnTop
            app.SetAlwaysOnTop(alwaysOnTop)
            toast(alwaysOnTop ? "Always on top" : "Not always on top")
        case "minimize", "quakeMode", "globalSummon":
            app.Minimize()
        case "closeWindow", "quit":
            requestQuit()
        case "identifyWindow", "identifyWindows":
            toast(ui.WindowName.isEmpty ? "Window 1" : "Window 1: \(ui.WindowName)")
        case "renameWindow":
            ui.WindowName = a.Str("name")
            if let t = tab { UpdateTitle(t) }
        case "openWindowRenamer":
            ui.RenamingWindow = true
            ui.RenameText = ui.WindowName
        case "openSystemMenu":
            openContextMenu(x: 8, y: 8)

        // Palette, menus, settings.
        case "commandPalette":
            if ui.Palette { closePalette() } else { openPalette(mode: a.Str("launchMode") == "commandLine" ? "commandline" : "commands") }
        case "openNewTabDropdown":
            openNewTabMenu(x: 8, y: 34)
        case "openSettings":
            switch a.Str("target", "settingsFile") {
            case "settingsUI":
                OpenSettingsTab()
            case "directory":
                openExternal(parentDir(settingsFile))
            case "defaultsFile":
                toast("The defaults are built in: settings.json overrides them")
                openExternal(settingsFile, textEditor: true)
            default:
                if settingsFile.isEmpty { return true }
                openExternal(settingsFile, textEditor: true)
            }
        case "openAbout":
            openDialog(title: "Vertex Terminal", body: "Version 0.2 — a terminal written in Vertex, with Windows Terminal's settings, actions and keys.\n\nSettings: \(settingsFile.isEmpty ? "(built in)" : shortPath(settingsFile))",
                       buttons: [("OK", {})])
        case "openCWD":
            guard let d = current?.Directory else { return false }
            openExternal(d)
        case "sendInput":
            guard let p = pane else { return false }
            typed(p, [uint8](a.Str("input").utf8))
        case "multipleActions":
            if let list = a.Args["actions"]?.Array {
                for v in list {
                    var sub = Action()
                    if let s = v.String {
                        sub.Command = s
                    } else if let o = v.Object {
                        sub.Command = o["action"]?.String ?? ""
                        sub.Args = o
                    }
                    Run(sub)
                }
            }
        case "wt":
            runCommandline(a.Str("commandline"))
        case "toggleShaderEffects", "experimental.colorSelection", "showSuggestions", "quickFix", "experimental.openTasks", "workspaces", "openWorkspace":
            toast("\(actionName(a)) isn't available in Vertex Terminal")
        case "unbound", "":
            return false
        default:
            toast("Unknown action: \(a.Command)")
        }
        return true
    }

    /// Runs an action by its command and arguments, written as settings
    /// write them.
    func RunCommand(_ command: string, _ args: [string: json.Value] = [:]) {
        var a = Action()
        a.Command = command
        var o = json.Object()
        o["action"] = .string(command)
        for (k, v) in args { o[k] = v }
        a.Args = o
        Run(a)
    }

    /// Runs the action with an id ("Terminal.SplitPaneRight").
    public func RunAction(_ id: string) {
        if let a = settings.Actions[id] { Run(a) }
    }

    // MARK: - Quitting

    func requestQuit() {
        if tryQuit() {
            app.Quit()
            app.RequestFrame()
        }
    }

    /// Whether the window may close now: where there are several tabs or
    /// panes and the settings ask, a dialog asks first.
    func tryQuit() -> bool {
        if quitConfirmed { return true }
        var panes = 0
        var busy = 0
        for t in ws.Tabs {
            panes += t.Panes.count
            for p in t.Panes where p.shell.Busy { busy += 1 }
        }
        if !settings.ConfirmOnClose || (ws.Tabs.count <= 1 && panes <= 1 && busy == 0) {
            saveSession()
            return true
        }
        let what = ws.Tabs.count > 1 ? "\(ws.Tabs.count) tabs" : "\(panes) panes"
        openDialog(title: "Close all tabs?", body: "This window has \(what) open\(busy > 0 ? ", \(busy) running a program" : "").",
                   buttons: [("Close all", {
                       self.saveSession()
                       self.quitConfirmed = true
                       app.Quit()
                       app.RequestFrame()
                   }), ("Cancel", {})])
        return false
    }

    // MARK: - Find

    func openSearch() {
        ui.Search = true
        if ui.SearchText.isEmpty, let s = current, let sel = s.selection, !sel.IsEmpty {
            let text = selectionText(s, sel)
            if !text.contains("\n") { ui.SearchText = text }
        }
        searchChanged()
    }

    func closeSearch(keepOpen: bool = false) {
        if !keepOpen {
            ui.Search = false
            matches = []
            matchIndex = -1
            ui.SearchStatus = ""
        } else {
            searchChanged()
        }
        redraw()
        if !keepOpen { focusSurface() }
    }

    /// The search text changed: every match found again, the current one
    /// the nearest above the bottom of the view (searching goes up, as
    /// Windows Terminal's does).
    func searchChanged() {
        guard let t = current?.term else { return }
        matches = []
        matchIndex = -1
        if ui.SearchText.isEmpty {
            ui.SearchStatus = ""
            redraw()
            return
        }
        for m in t.Find(ui.SearchText, caseSensitive: ui.SearchCase) {
            matches.append(view.Selection(startColumn: m.StartColumn, startLine: m.StartLine, endColumn: m.EndColumn, endLine: m.EndLine))
        }
        if matches.isEmpty {
            ui.SearchStatus = "No results"
        } else {
            let bottom = t.ViewTop + t.Rows - 1
            matchIndex = matches.count - 1
            var i = matches.count - 1
            while i >= 0 {
                if matches[i].StartLine <= bottom {
                    matchIndex = i
                    break
                }
                i -= 1
            }
            showMatch()
        }
        redraw()
    }

    func stepMatch(_ by: int) {
        if matches.isEmpty { return }
        // Next goes up the buffer (older), as Enter in the search box does.
        matchIndex = ((matchIndex - by) % matches.count + matches.count) % matches.count
        showMatch()
        redraw()
    }

    func showMatch() {
        guard let t = current?.term, matchIndex >= 0 && matchIndex < matches.count else { return }
        let m = matches[matchIndex]
        ui.SearchStatus = "\(matchIndex + 1)/\(matches.count)"
        let top = t.ViewTop
        if m.StartLine < top || m.StartLine >= top + t.Rows {
            // In the middle of the view.
            let wantTop = max(0, min(t.ScrollbackCount, m.StartLine - t.Rows / 2))
            t.ScrollView(by: t.ViewTop - wantTop)
        }
    }

    // MARK: - Marks and commands

    func scrollToMark(_ direction: string) {
        guard let t = current?.term else { return }
        let top = t.ViewTop
        var target: int? = nil
        switch direction {
        case "next": target = t.NextPrompt(after: top)
        case "first": target = t.NextPrompt(after: -1)
        case "last": target = t.PreviousPrompt(before: t.ScrollbackCount + t.Rows)
        default: target = t.PreviousPrompt(before: top)
        }
        guard let line = target else {
            if direction == "next" { t.ScrollToBottom() }
            redraw()
            return
        }
        let wantTop = max(0, min(t.ScrollbackCount, line))
        t.ScrollView(by: t.ViewTop - wantTop)
        redraw()
    }

    /// Selects the command typed at a prompt, or its output, before (or
    /// after) the selection or the view: the shell's marks (OSC 133).
    func selectCommand(output: bool, next: bool) {
        guard let s = current else { return }
        let t = s.term
        let from = s.selection?.Ordered.StartLine ?? (t.ViewTop + t.Rows)
        guard let prompt = next ? t.NextPrompt(after: from) : t.PreviousPrompt(before: from) else {
            toast("No commands marked: the shell needs its integration (OSC 133)")
            return
        }
        if output {
            guard let out = t.CommandOutput(at: prompt) else { return }
            s.selection = view.Selection(startColumn: 0, startLine: out.From, endColumn: t.Columns - 1, endLine: out.To)
        } else {
            // The command: from the prompt line to just before the output.
            let end = t.CommandOutput(at: prompt).map { $0.From - 1 } ?? prompt
            s.selection = view.Selection(startColumn: 0, startLine: prompt, endColumn: t.Columns - 1, endLine: max(prompt, end))
        }
        let line = s.selection!.StartLine
        if line < t.ViewTop || line >= t.ViewTop + t.Rows {
            t.ScrollView(by: t.ViewTop - max(0, min(t.ScrollbackCount, line)))
        }
        redraw()
    }

    // MARK: - The command palette

    /// Opens the palette: "commands" (every action), "tabs" (the open
    /// tabs), "commandline" (a wt command line to run).
    func openPalette(mode: string) {
        ui.Palette = true
        ui.Menu = false
        ui.PaletteMode = mode
        ui.PaletteText = ""
        ui.PaletteIndex = 0
        paletteStack = []
        ui.PaletteTitle = mode == "tabs" ? "Search for a tab" : (mode == "commandline" ? "Run a command line (new-tab, split-pane…)" : "Type a command")
        filterPalette()
    }

    func closePalette() {
        ui.Palette = false
        ui.PaletteText = ""
        paletteStack = []
        redraw()
        focusSurface()
    }

    /// The palette's items for its mode and text, best matches first.
    func filterPalette() {
        var items: [Item] = []
        var runs: [() -> void] = []
        func add(_ label: string, _ detail: string = "", nested: bool = false, swatch: string = "", _ run: () -> void) {
            items.append(Item(ID: runs.count, Label: label, Detail: detail, Nested: nested, Swatch: swatch))
            runs.append(run)
        }
        let mode = paletteStack.last ?? ui.PaletteMode
        switch mode {
        case "tabs", "switcher":
            let order = mode == "switcher" ? ws.recent.filter { id in ws.Index(of: id) != nil } + ws.Tabs.map { $0.ID }.filter { !ws.recent.contains($0) } : ws.Tabs.map { $0.ID }
            for id in order {
                guard let i = ws.Index(of: id) else { continue }
                let t = ws.Tabs[i]
                add(t.Shown, "Tab \(i + 1)", swatch: t.Color) { self.Select(id) }
            }
        case "commandline":
            let line = ui.PaletteText
            add(line.isEmpty ? "Type a command line, as wt takes it" : "Run: \(line)") { self.runCommandline(line) }
        case "newTab":
            for p in settings.VisibleProfiles {
                let g = p.Guid
                add(p.Name, p.Icon) { self.NewTab(profile: g, dir: nil) }
            }
        case "splitPane":
            for p in settings.VisibleProfiles {
                let g = p.Guid
                for d in ["right", "down"] {
                    add("\(p.Name), split \(d)") { self.SplitPane(direction: d, profile: g) }
                }
            }
        case "colorScheme":
            for name in settings.SchemeNames {
                add(name, swatch: settings.Scheme(name).map { view.ColorHex($0.Background) } ?? "") { self.RunCommand("setColorScheme", ["colorScheme": .string(name)]) }
            }
        case "tabColor":
            for c in tabColors {
                let hex = c.1
                add(c.0, swatch: hex) { self.RunCommand("setTabColor", ["color": .string(hex)]) }
            }
            add("Reset tab color") { self.RunCommand("setTabColor") }
        case "opacity":
            for v in [100, 90, 80, 70, 60, 50] {
                add("\(v)%") { self.RunCommand("adjustOpacity", ["opacity": .number("\(v)"), "relative": .bool(false)]) }
            }
        default:
            for id in settings.ActionOrder {
                guard let a = settings.Actions[id] else { continue }
                if a.Command == "unbound" || a.Command.isEmpty { continue }
                let action = a
                add(a.Name, settings.KeysFor(id)) { _ = self.Run(action) }
            }
            add("New tab…", nested: true) { self.nestPalette("newTab") }
            add("Split pane…", nested: true) { self.nestPalette("splitPane") }
            add("Select color scheme…", nested: true) { self.nestPalette("colorScheme") }
            add("Set tab color…", nested: true) { self.nestPalette("tabColor") }
            add("Set opacity…", nested: true) { self.nestPalette("opacity") }
            add("Search for tab…", settings.KeysFor("Terminal.TabSearch")) { self.openPalette(mode: "tabs") }
            add("Run command line…") { self.openPalette(mode: "commandline") }
        }
        // Filtered and ranked by the text typed.
        let q = ui.PaletteText
        var ranked: [(int, Item)] = []
        if mode == "commandline" || q.isEmpty {
            for it in items { ranked.append((0, it)) }
        } else {
            for it in items {
                if let score = fuzzyScore(q, it.Label) { ranked.append((score, it)) }
            }
            ranked.sort { $0.0 > $1.0 }
        }
        paletteRun = runs
        ui.PaletteItems = ranked.map { $0.1 }
        ui.PaletteIndex = min(ui.PaletteIndex, max(0, ui.PaletteItems.count - 1))
        syncPalette()
    }

    /// The window of items shown follows the selected one.
    func syncPalette() {
        let n = ui.PaletteItems.count
        let rows = 12
        var first = 0
        if n > rows {
            first = max(0, min(n - rows, ui.PaletteIndex - rows / 2))
        }
        ui.PaletteShown = n == 0 ? [] : [Item](ui.PaletteItems[first..<min(n, first + rows)])
    }

    func nestPalette(_ mode: string) {
        paletteStack.append(mode)
        ui.PaletteText = ""
        ui.PaletteIndex = 0
        ui.Palette = true
        filterPalette()
    }

    /// Runs the palette's item i (by its place in the list).
    func runPalette(_ index: int) {
        if index < 0 || index >= ui.PaletteItems.count { return }
        let item = ui.PaletteItems[index]
        if item.ID < 0 || item.ID >= paletteRun.count { return }
        let run = paletteRun[item.ID]
        if !item.Nested {
            ui.Palette = false
            ui.PaletteText = ""
            paletteStack = []
            focusSurface()
        }
        run()
        redraw()
    }

    /// Keys in the palette: up and down to choose, Enter to run, Escape
    /// (or Backspace in an empty nested list) to go back.
    func PaletteKey(_ key: string, control: bool, shift: bool) -> bool {
        let n = ui.PaletteItems.count
        switch key {
        case "ArrowDown":
            if n > 0 { ui.PaletteIndex = (ui.PaletteIndex + 1) % n }
        case "ArrowUp":
            if n > 0 { ui.PaletteIndex = (ui.PaletteIndex - 1 + n) % n }
        case "PageDown":
            if n > 0 { ui.PaletteIndex = min(n - 1, ui.PaletteIndex + 8) }
        case "PageUp":
            ui.PaletteIndex = max(0, ui.PaletteIndex - 8)
        case "Tab":
            if ui.PaletteMode == "switcher" && n > 0 {
                ui.PaletteIndex = (ui.PaletteIndex + (shift ? -1 : 1) + n) % n
            } else {
                return false
            }
        case "Enter":
            runPalette(ui.PaletteIndex)
        case "Escape":
            if !paletteStack.isEmpty {
                paletteStack.removeLast()
                ui.PaletteText = ""
                ui.PaletteIndex = 0
                filterPalette()
            } else {
                closePalette()
            }
        case "Backspace":
            if ui.PaletteText.isEmpty && !paletteStack.isEmpty {
                paletteStack.removeLast()
                ui.PaletteIndex = 0
                filterPalette()
                return true
            }
            return false
        default:
            return false
        }
        syncPalette()
        return true
    }

    // MARK: - The tab switcher

    /// Whether ⌃ is held for ⌃Tab: the switcher stays while it is.
    var switcherKeyHeld: bool { return lastKeyControl }

    func openSwitcher(_ by: int) {
        if ui.Palette && ui.PaletteMode == "switcher" {
            let n = ui.PaletteItems.count
            if n > 0 { ui.PaletteIndex = (ui.PaletteIndex + by + n) % n }
            syncPalette()
            return
        }
        openPalette(mode: "switcher")
        ui.PaletteTitle = "Switch tabs (release ⌃)"
        let n = ui.PaletteItems.count
        ui.PaletteIndex = n > 1 ? (by > 0 ? 1 : n - 1) : 0
        syncPalette()
    }

    /// ⌃ let go: the switcher goes to the tab chosen.
    func SwitcherRelease() {
        if ui.Palette && ui.PaletteMode == "switcher" { runPalette(ui.PaletteIndex) }
    }

    // MARK: - Menus

    func openMenu(x: float32, y: float32, _ items: [(string, string, () -> void)]) {
        var list: [Item] = []
        var runs: [() -> void] = []
        for it in items {
            if it.0 == "-" {
                list.append(Item(ID: -1, Label: "", Separator: true))
                continue
            }
            list.append(Item(ID: runs.count, Label: it.0, Detail: it.1))
            runs.append(it.2)
        }
        menuRun = runs
        ui.MenuItems = list
        // Inside the window: a menu near the right or bottom edge opens
        // to the left of, or above, where it was asked.
        let o = handle?.Origin ?? (X: 0, Y: 0)
        let size = handle?.Size ?? (Width: 800, Height: 600)
        let winW = o.X + size.Width
        let winH = o.Y + size.Height
        let menuW: float32 = 250
        var menuH: float32 = 10
        for it in list { menuH += it.Separator ? 9 : 24 }
        ui.MenuX = max(4, min(x, winW - menuW - 4))
        ui.MenuY = y + menuH > winH - 4 ? max(4, min(y, winH - 4) - menuH) : y
        ui.Menu = true
        ui.Palette = false
    }

    func runMenu(_ id: int) {
        ui.Menu = false
        focusSurface()
        if id >= 0 && id < menuRun.count { menuRun[id]() }
        redraw()
    }

    func closeMenu() {
        ui.Menu = false
        focusSurface()
    }

    func keys(_ id: string) -> string { return settings.KeysFor(id) }

    /// The ⌄ menu: a tab per profile, then settings and the palette.
    func openNewTabMenu(x: float32, y: float32) {
        var items: [(string, string, () -> void)] = []
        let vis = settings.VisibleProfiles
        for i in 0..<vis.count {
            let g = vis[i].Guid
            items.append(((vis[i].Icon.isEmpty ? "" : vis[i].Icon + "  ") + vis[i].Name, i < 9 ? keys("Terminal.OpenNewTabProfile\(i)") : "", { self.NewTab(profile: g, dir: nil) }))
        }
        items.append(("-", "", {}))
        items.append(("Settings", keys("Terminal.OpenSettingsUI"), { self.OpenSettingsTab() }))
        items.append(("Command palette", keys("Terminal.ToggleCommandPalette"), { self.openPalette(mode: "commands") }))
        items.append(("About", keys("Terminal.OpenAboutDialog"), { self.RunCommand("openAbout") }))
        openMenu(x: x, y: y, items)
    }

    /// A tab's menu (right-click on it), as Windows Terminal's.
    func openTabMenu(_ id: int, x: float32, y: float32) {
        Select(id)
        openMenu(x: x, y: y, [
            ("Change tab color…", "", { self.openColorPicker(id, x: x, y: y) }),
            ("Rename tab", keys("Terminal.OpenTabRenamer"), { self.startRename(id) }),
            ("Duplicate tab", keys("Terminal.DuplicateTab"), { self.RunCommand("duplicateTab") }),
            ("Split tab", "", { self.SplitPane(direction: "auto", duplicate: true) }),
            ("Move tab left", "", { self.RunCommand("moveTab", ["direction": .string("backward")]) }),
            ("Move tab right", "", { self.RunCommand("moveTab", ["direction": .string("forward")]) }),
            ("Export text", keys("Terminal.ExportBuffer"), { self.exportBuffer() }),
            ("Find", keys("Terminal.FindText"), { self.openSearch() }),
            ("-", "", {}),
            ("Close tabs to the right", "", { self.RunCommand("closeTabsAfter") }),
            ("Close other tabs", "", { self.RunCommand("closeOtherTabs") }),
            ("Close tab", "", { self.Close(id) }),
        ])
    }

    func openColorPicker(_ id: int, x: float32, y: float32) {
        var items: [(string, string, () -> void)] = []
        for c in tabColors {
            let hex = c.1
            items.append(("●  " + c.0, hex, {
                if let i = self.ws.Index(of: id) { self.ws.Tabs[i].Color = hex }
            }))
        }
        items.append(("-", "", {}))
        items.append(("Reset", "", {
            if let i = self.ws.Index(of: id) { self.ws.Tabs[i].Color = "" }
        }))
        openMenu(x: x, y: y, items)
    }

    /// The terminal's menu (right-click), as Windows Terminal's.
    func openContextMenu(x: float32, y: float32) {
        let hasSel = !SelectedText().isEmpty
        var items: [(string, string, () -> void)] = []
        if hasSel {
            items.append(("Copy", keys("Terminal.CopyToClipboard"), { self.RunCommand("copy") }))
            items.append(("Search web", "", { self.RunCommand("searchWeb") }))
        }
        items.append(("Paste", keys("Terminal.PasteFromClipboard"), { self.RunCommand("paste") }))
        items.append(("Find…", keys("Terminal.FindText"), { self.openSearch() }))
        items.append(("Select all", keys("Terminal.SelectAll"), { self.RunCommand("selectAll") }))
        items.append(("-", "", {}))
        items.append(("Split pane right", keys("Terminal.SplitPaneRight"), { self.SplitPane(direction: "right") }))
        items.append(("Split pane down", keys("Terminal.SplitPaneDown"), { self.SplitPane(direction: "down") }))
        items.append(("Duplicate pane", "", { self.SplitPane(direction: "auto", duplicate: true) }))
        if (ws.Current?.Panes.count ?? 0) > 1 {
            items.append(("Toggle pane zoom", keys("Terminal.TogglePaneZoom"), { self.RunCommand("togglePaneZoom") }))
            items.append(("Swap pane…", "", { self.openPalette(mode: "commands"); self.ui.PaletteText = "swap pane"; self.filterPalette() }))
            items.append(("Toggle broadcast input", keys("Terminal.ToggleBroadcastInput"), { self.RunCommand("toggleBroadcastInput") }))
        }
        items.append(("Toggle read-only mode", keys("Terminal.ToggleReadOnlyMode"), { self.RunCommand("toggleReadOnlyMode") }))
        items.append(("Select command", "", { self.selectCommand(output: false, next: false) }))
        items.append(("Select output", "", { self.selectCommand(output: true, next: false) }))
        items.append(("-", "", {}))
        items.append(("Export text", keys("Terminal.ExportBuffer"), { self.exportBuffer() }))
        items.append(("Clear buffer", keys("Terminal.ClearBuffer"), { self.RunCommand("clearBuffer") }))
        items.append(("Restart connection", "", { self.RunCommand("restartConnection") }))
        items.append(("Close pane", keys("Terminal.ClosePane"), { self.RunCommand("closePane") }))
        openMenu(x: x, y: y, items)
    }

    // MARK: - Dialogs

    func openDialog(title: string, body: string, buttons: [(string, () -> void)]) {
        var list: [Item] = []
        var runs: [() -> void] = []
        for b in buttons {
            list.append(Item(ID: runs.count, Label: b.0))
            runs.append(b.1)
        }
        dialogRun = runs
        ui.DialogTitle = title
        ui.DialogBody = body
        ui.DialogButtons = list
        ui.Dialog = true
        ui.Menu = false
        ui.Palette = false
        app.RequestFrame()
    }

    func runDialog(_ id: int) {
        ui.Dialog = false
        focusSurface()
        if id >= 0 && id < dialogRun.count { dialogRun[id]() }
        redraw()
    }

    // MARK: - Renaming

    func startRename(_ id: int) {
        guard let i = ws.Index(of: id) else { return }
        ui.Renaming = id
        ui.RenameText = ws.Tabs[i].Shown
    }

    func commitRename() {
        if ui.RenamingWindow {
            ui.WindowName = ui.RenameText
            ui.RenamingWindow = false
            if let t = ws.Current { UpdateTitle(t) }
        } else if let i = ws.Index(of: ui.Renaming) {
            let t = ws.Tabs[i]
            // An empty name gives the title back to the program.
            t.CustomTitle = ui.RenameText == t.Title ? "" : ui.RenameText
            UpdateTitle(t)
        }
        ui.Renaming = 0
        focusSurface()
    }

    func cancelRename() {
        ui.Renaming = 0
        ui.RenamingWindow = false
        focusSurface()
    }

    // MARK: - Command lines

    /// Runs a command line as wt.exe takes it: subcommands separated by
    /// ";" -- new-tab (nt), split-pane (sp), focus-tab (ft), move-focus
    /// (mf), swap-pane, focus-pane (fp) -- with -p profile, -d dir,
    /// --title, --tabColor, -H/-V, -s size, and a command after them.
    func runCommandline(_ line: string) {
        let words = splitCommandline(line)
        var groups: [[string]] = [[]]
        for w in words {
            if w == ";" {
                groups.append([])
            } else if w.hasSuffix(";") && w.count > 1 {
                groups[groups.count - 1].append(String(w.dropLast()))
                groups.append([])
            } else {
                groups[groups.count - 1].append(w)
            }
        }
        var first = true
        for g in groups where !g.isEmpty {
            runSubcommand(g, first: first)
            first = false
        }
    }

    func runSubcommand(_ g: [string], first: bool) {
        var args = g
        if args.first == "wt" || args.first == "wt.exe" { args.removeFirst() }
        var cmd = "new-tab"
        if let a = args.first, !a.hasPrefix("-") {
            switch a {
            case "new-tab", "nt", "split-pane", "sp", "focus-tab", "ft", "move-focus", "mf", "swap-pane", "focus-pane", "fp", "move-pane", "mp":
                cmd = a
                args.removeFirst()
            default: break
            }
        }
        var profile: string? = nil
        var dir: string? = nil
        var title: string? = nil
        var color: string? = nil
        var split = "auto"
        var size: float32 = 0.5
        var target = -1
        var rest: [string] = []
        var dupe = false
        var i = 0
        while i < args.count {
            let a = args[i]
            func value() -> string? {
                if i + 1 < args.count {
                    i += 1
                    return args[i]
                }
                return nil
            }
            if !rest.isEmpty || (!a.hasPrefix("-") && cmd != "move-focus" && cmd != "mf" && cmd != "swap-pane") {
                rest.append(a)
                i += 1
                continue
            }
            switch a {
            case "-p", "--profile": profile = value()
            case "-d", "--startingDirectory": dir = value()
            case "--title": title = value()
            case "--tabColor": color = value()
            case "-H", "--horizontal": split = "down"
            case "-V", "--vertical": split = "right"
            case "-D", "--duplicate": dupe = true
            case "-s", "--size": size = float32(value() ?? "0.5") ?? 0.5
            case "-t", "--target": target = int(value() ?? "") ?? -1
            case "-n", "--next": target = -2
            case "--previous": target = -3
            case "--": break
            default:
                if cmd == "move-focus" || cmd == "mf" || cmd == "swap-pane" { rest.append(a) }
            }
            i += 1
        }
        let commandline: string? = rest.isEmpty ? nil : rest.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        switch cmd {
        case "split-pane", "sp":
            SplitPane(direction: split, profile: profile, duplicate: dupe, size: size, dir: dir, commandline: commandline)
        case "focus-tab", "ft":
            if target >= 0 && target < ws.Tabs.count { Select(ws.Tabs[target].ID) }
            if target == -2 { Step(1) }
            if target == -3 { Step(-1) }
        case "move-focus", "mf":
            if let d = rest.first { RunCommand("moveFocus", ["direction": .string(d)]) }
        case "swap-pane":
            if let d = rest.first { RunCommand("swapPane", ["direction": .string(d)]) }
        case "focus-pane", "fp":
            if let t = ws.Current, target >= 0 && target < t.Panes.count { FocusPane(t.Panes[target].ID) }
        default:
            NewTab(profile: profile, dir: dir, commandline: commandline, title: title, color: color)
        }
    }
}

/// How well a query matches a label: its characters in order, scored
/// higher for runs, word starts and an early start; nil where they
/// aren't all there.
func fuzzyScore(_ query: string, _ label: string) -> int? {
    let q = [uint8](query.lowercased().utf8).filter { $0 != 0x20 }
    let l = [uint8](label.lowercased().utf8)
    if q.isEmpty { return 0 }
    var score = 0
    var qi = 0
    var prev = -2
    var i = 0
    while i < l.count && qi < q.count {
        if l[i] == q[qi] {
            score += 1
            if prev == i - 1 { score += 5 }
            if i == 0 || l[i - 1] == 0x20 || l[i - 1] == 0x2C { score += 8 }
            prev = i
            qi += 1
        }
        i += 1
    }
    if qi < q.count { return nil }
    // A label that contains the query as typed comes first.
    if containsText(label.lowercased(), query.lowercased()) { score += 40 }
    return score * 100 - l.count
}

/// Whether needle appears in s.
func containsText(_ s: string, _ needle: string) -> bool {
    let a = [uint8](s.utf8)
    let b = [uint8](needle.utf8)
    if b.isEmpty { return true }
    if b.count > a.count { return false }
    for i in 0...(a.count - b.count) {
        var j = 0
        while j < b.count && a[i + j] == b[j] { j += 1 }
        if j == b.count { return true }
    }
    return false
}

/// s with every from as to.
func replaceAll(_ s: string, _ from: string, _ to: string) -> string {
    let a = [uint8](s.utf8)
    let f = [uint8](from.utf8)
    let t = [uint8](to.utf8)
    var out: [uint8] = []
    var i = 0
    while i < a.count {
        if i + f.count <= a.count && !f.isEmpty {
            var j = 0
            while j < f.count && a[i + j] == f[j] { j += 1 }
            if j == f.count {
                out.append(contentsOf: t)
                i += f.count
                continue
            }
        }
        out.append(a[i])
        i += 1
    }
    return string(decoding: out, as: UTF8.self)
}

/// Text for a URL's query: what isn't a letter or digit as %XX.
func percentEncode(_ s: string) -> string {
    let digits: [string] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    var out = ""
    for b in s.utf8 {
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x5F || b == 0x2E {
            out += string(decoding: [b], as: UTF8.self)
        } else {
            out += "%" + digits[int(b >> 4)] + digits[int(b & 15)]
        }
    }
    return out
}
