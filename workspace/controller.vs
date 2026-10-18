package workspace

import (
    "fs"
    "image/draw"
    "os/env"
    "os/process"
    "os/user"
    "terminal/view"
    "terminal/vt"
    "time"
    "ui/app"
    "ui/component"
    "ui/viewport"
    "ui/window"
)

/// What the window holds: the tabs and their panes, the settings, what
/// is over the terminal, and what keys, the pointer and the wheel do.
/// The panes of the tab in front are drawn into one surface, side by
/// side as they are split.
@MainActor
public final class Controller {
    let ws = Workspace()
    let ui = UI()
    var settings: Settings
    var settingsFile: string
    var settingsStamp: int64 = -1
    var handle: viewport.Handle? = nil
    var surfaceNode: component.Ref = nil
    var focused = false
    var blinkOn = true
    var textBlinkOn = true
    var blinkEpoch = 0
    /// The next text event is a key already sent (Option as Meta, or a
    /// key the kitty protocol sent as an escape).
    var swallowText = false
    let optionAsMeta = (env.Get("TERMINAL_OPTION_AS_META") ?? "") == "1"
    // The pointer.
    var selecting = false
    var selectingPane = 0
    var anchorColumn = 0
    var anchorLine = 0
    var blockSelect = false
    var mouseButton = -1
    /// The press in progress is the program's (mouse reporting), not a
    /// selection.
    var mouseReported = false
    var wheel: float32 = 0
    var draggingDivider: PaneNode? = nil
    var draggingScrollbar = 0
    var hoverLink: uint32 = 0
    var hoverURL: view.Selection? = nil
    var hoverText = ""
    var pointerX: float32 = 0
    var pointerY: float32 = 0
    // The last frame.
    var scale: float32 = 2
    var surfaceW = 0
    var surfaceH = 0
    var frame: [uint8] = []
    var frameAll = true
    var layoutKey: [int] = []
    var dark = true
    var gridColumns = 80
    var gridRows = 24
    // What menus, the palette and dialogs run, by item ID.
    var paletteRun: [() -> void] = []
    var paletteStack: [string] = []
    var menuRun: [() -> void] = []
    var dialogRun: [() -> void] = []
    // Find.
    var matches: [view.Selection] = []
    var matchIndex = -1
    // Mark mode: a cursor the keyboard moves to select.
    var markMode = false
    var markColumn = 0
    var markLine = 0
    var markAnchorColumn = 0
    var markAnchorLine = 0
    var markSelecting = false
    // Closed tabs, to restore: profile, directory, title.
    var closed: [(Profile, string?, string)] = []
    var opacity = 100
    /// ⌃ was held at the last key: ⌃Tab's switcher stays open while it is.
    var lastKeyControl = false
    var alwaysOnTop = false
    var quitConfirmed = false
    let started = time.Instant.Now()
    /// For tests: settings given rather than read from the file.
    let fixedSettings: bool
    /// The settings' text, for a controller given its settings: what the
    /// settings tab edits in place of the file.
    var settingsText = ""
    /// Each tab's element, to measure while one is dragged.
    var tabNodes: [int: component.Ref] = [:]
    /// The tab pressed, where the pointer was then (less what a move
    /// across a neighbour has taken up), and whether it has moved enough
    /// to be a drag.
    var dragPress = 0
    var dragStartX: float32 = 0
    var dragMoved = false

    public init() {
        settingsFile = settingsPath()
        settings = LoadSettings(path: settingsFile)
        settingsStamp = settingsModified(settingsFile)
        fixedSettings = false
        ui.InTitlebar = settings.ShowTabsInTitlebar
    }

    /// A controller with settings from text (Windows Terminal's JSON),
    /// for tests: the user's file is neither read nor written.
    public init(settingsJSON: string) {
        settingsFile = ""
        settings = SettingsFrom(settingsJSON)
        settingsText = settingsJSON
        fixedSettings = true
    }

    var currentPane: Pane? { return ws.Current?.FocusedPane }
    var current: Shell? { return currentPane?.shell }

    // MARK: - Reading it (for a host, or a test)

    /// How many tabs are open.
    public var TabCount: int { return ws.Tabs.count }
    /// The settings tab: open, and in front.
    public var SettingsTabOpen: bool { return ui.SettingsOpen }
    public var SettingsTabShown: bool { return ui.SettingsShown }
    /// What the settings tab has written, for a controller given its
    /// settings.
    public var WrittenSettings: string { return settingsText }

    /// The titles of the tabs, in order, and which is in front.
    public var TabTitles: [string] { return ws.Tabs.map { $0.Shown } }
    public var ActiveIndex: int { return ws.Index(of: ws.Active) ?? -1 }

    /// How many panes the tab in front has.
    public var PaneCount: int { return ws.Current?.Panes.count ?? 0 }

    /// The index of the focused pane in the tab in front, in layout order.
    public var FocusedPaneIndex: int {
        guard let t = ws.Current else { return -1 }
        return t.Panes.firstIndex(where: { $0.ID == t.Focused }) ?? -1
    }

    /// The text of the screen of the focused pane.
    public func ScreenText() -> string {
        return current?.term.ScreenText() ?? ""
    }

    /// The text of the screen of every pane of the tab in front.
    public func PaneTexts() -> [string] {
        return ws.Current?.Panes.map { $0.shell.term.ScreenText() } ?? []
    }

    /// The text selected in the focused pane, or "".
    public func SelectedText() -> string {
        guard let shell = current, let sel = shell.selection, !sel.IsEmpty else { return "" }
        return selectionText(shell, sel)
    }

    /// The size of the focused terminal, in cells.
    public var GridSize: (Columns: int, Rows: int) {
        guard let t = current?.term else { return (Columns: 0, Rows: 0) }
        return (Columns: t.Columns, Rows: t.Rows)
    }

    /// The search's matches in the focused pane, and which is current.
    public var SearchMatches: (Count: int, Index: int) { return (Count: matches.count, Index: matchIndex) }

    /// What the overlays show, for tests.
    public var PaletteOpen: bool { return ui.Palette }
    public var PaletteLabels: [string] { return ui.PaletteItems.filter { !$0.Separator }.map { $0.Label } }
    public var SearchOpen: bool { return ui.Search }
    public var DialogOpen: bool { return ui.Dialog }
    /// Where the open menu is, and how wide the window is (CSS pixels).
    public var MenuX: float32 { return ui.MenuX }
    public var WindowWidth: float32 { return (handle?.Origin.X ?? 0) + (handle?.Size.Width ?? 0) }
    public var MenuLabels: [string] { return ui.Menu ? ui.MenuItems.filter { !$0.Separator }.map { $0.Label } : [] }
    public var Toast: string { return ui.Toast }
    public var TabColors: [string] { return ws.Tabs.map { $0.Color } }
    public var Broadcasting: bool { return ws.Current?.Broadcast ?? false }
    public var ReadOnly: bool { return currentPane?.ReadOnly ?? false }
    public var Zoomed: bool { return ws.Current?.IsZoomed ?? false }
    public var FocusMode: bool { return ui.FocusMode }
    public var InMarkMode: bool { return markMode }
    public var FontSize: float32 { return currentPane?.renderer.FontSize ?? 0 }
    public var ProfileNames: [string] { return settings.VisibleProfiles.map { $0.Name } }
    public var ThemeName: string { return currentPane?.renderer.Theme.Name ?? "" }

    func redraw() {
        handle?.Invalidate()
    }

    /// Gives the terminal surface the keyboard.
    func focusSurface() {
        // Not behind the settings tab: typing there would reach a shell
        // that can't be seen.
        if ui.SettingsShown { return }
        if let n = surfaceNode { component.Focus(n) }
    }

    func now() -> float64 {
        return started.Elapsed().AsSeconds()
    }

    /// A line at the bottom for a moment.
    func toast(_ text: string) {
        ui.Toast = text
        ui.toastEpoch += 1
        let epoch = ui.toastEpoch
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.ui.toastEpoch == epoch {
                self.ui.Toast = ""
                app.RequestFrame()
            }
        }
    }

    // MARK: - Panes

    /// A pane running a profile, in dir (or where the profile says).
    func makePane(_ p: Profile, dir: string?, commandline: string? = nil) -> Pane {
        let id = ws.nextPane
        ws.nextPane += 1
        let shell = Shell(columns: gridColumns, rows: gridRows)
        let r = view.Renderer(theme: settings.ThemeFor(p, dark: dark),
                              families: p.FontFace.isEmpty ? ["SF Mono", "Menlo", "Monaco", "monospace"] : p.FontFace,
                              size: p.FontSize)
        let pane = Pane(id: id, shell: shell, renderer: r, profile: p)
        pane.baseFontSize = p.FontSize
        configure(pane)
        shell.owner = self
        shell.paneID = id
        return pane
    }

    /// The directory a new pane starts in: the profile's, else the
    /// focused pane's (as a Mac terminal does), else home.
    func startDir(_ p: Profile, inherit: string?) -> string? {
        if !p.StartingDirectory.isEmpty && p.StartingDirectory != "." { return expandHome(p.StartingDirectory) }
        return inherit
    }

    /// Starts a pane's program once it has its size: at the next frame,
    /// which lays it out (so the shell's first prompt is drawn for the
    /// size it will have), or in a moment where no frame comes.
    func start(_ pane: Pane, dir: string?, commandline: string? = nil) {
        pane.pendingDir = dir
        pane.pendingCommand = commandline ?? pane.profile.Commandline
        pane.pending = true
        redraw()
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.startNow(pane)
        }
    }

    func startNow(_ pane: Pane) {
        if !pane.pending { return }
        pane.pending = false
        var e = pane.profile.Environment
        e["VERTEX_TERMINAL_PROFILE"] = pane.profile.Name
        pane.shell.Start(commandline: pane.pendingCommand, dir: pane.pendingDir, env: e)
    }

    /// Lays out the panes of tabs behind that haven't started, so they
    /// start at their size too.
    func startPending(_ w: int, _ h: int, divider: int) {
        for tab in ws.Tabs where tab.ID != ws.Active {
            let waiting = tab.Panes.filter { $0.pending }
            if waiting.isEmpty { continue }
            tab.root.Layout(0, 0, w, h, divider: divider)
            for p in waiting {
                let grid = p.renderer.GridSize(width: p.W, height: p.H, scale: scale)
                p.shell.Resize(columns: grid.Columns, rows: grid.Rows, width: p.W, height: p.H)
                startNow(p)
            }
        }
    }

    /// A pane's renderer and terminal set as its profile says.
    func configure(_ pane: Pane) {
        let p = pane.profile
        let r = pane.renderer
        let t = pane.shell.term
        r.Padding = p.Padding
        r.LineSpacing = max(0.5, p.CellHeight)
        r.CellWidthScale = max(0.5, p.CellWidth)
        r.CursorStyle = p.CursorShape
        r.CursorHeight = p.CursorHeight
        r.CursorColor = p.CursorColor
        r.IntenseBold = p.IntenseTextStyle == "bold" || p.IntenseTextStyle == "all"
        r.IntenseBright = p.IntenseTextStyle == "bright" || p.IntenseTextStyle == "all"
        r.AdjustIndistinguishable = p.AdjustIndistinguishableColors != "never"
        r.ScrollbarWidth = p.ScrollbarState == "hidden" ? 0 : 10
        r.SetFont(families: p.FontFace.isEmpty ? ["SF Mono", "Menlo", "Monaco", "monospace"] : p.FontFace,
                  size: pane.renderer.FontSize == pane.baseFontSize ? p.FontSize : pane.renderer.FontSize, weight: p.FontWeight)
        pane.baseFontSize = p.FontSize
        r.SetTheme(settings.ThemeFor(p, dark: dark))
        t.ScrollbackLimit = p.HistorySize
        t.Answerback = p.AnswerbackMessage
        t.KittyKeyboard = p.KittyKeyboard
        pane.dirty = true
    }

    // MARK: - Tabs

    func NewTab() {
        NewTab(profile: nil, dir: nil)
    }

    /// Opens a tab running a profile (a name, a guid, or the default).
    func NewTab(profile name: string?, dir: string?, commandline: string? = nil, title: string? = nil, color: string? = nil) {
        let p = settings.ProfileNamed(name)
        let d = dir ?? startDir(p, inherit: currentPane?.Directory)
        let pane = makePane(p, dir: d)
        let tab = Tab(id: ws.next, pane: pane)
        ws.next += 1
        tab.Icon = p.Icon
        if let c = p.TabColor { tab.Color = view.ColorHex(c) }
        if let c = color { tab.Color = c }
        if let t = title { tab.CustomTitle = t }
        if !p.TabTitle.isEmpty && title == nil { tab.CustomTitle = p.TabTitle }
        if settings.NewTabPosition == "afterCurrentTab", let i = ws.Index(of: ws.Active) {
            ws.Tabs.insert(tab, at: i + 1)
        } else {
            ws.Tabs.append(tab)
        }
        Select(tab.ID)
        start(pane, dir: d, commandline: commandline)
        UpdateTitle(tab)
    }

    func NewTab(dir: string?) {
        NewTab(profile: nil, dir: dir)
    }

    /// Splits the focused pane: a new pane right, left, down, up, or
    /// ("auto") along the longer side.
    func SplitPane(direction dIn: string, profile: string? = nil, duplicate: bool = false, size: float32 = 0.5, dir: string? = nil, commandline: string? = nil) {
        guard let tab = ws.Current, let cur = tab.FocusedPane else { return }
        var d = dIn
        if d == "auto" || d.isEmpty { d = cur.W >= cur.H ? "right" : "down" }
        if d == "vertical" { d = "right" }
        if d == "horizontal" { d = "down" }
        let p = duplicate ? cur.profile : settings.ProfileNamed(profile)
        let where_ = dir ?? (duplicate ? cur.Directory : startDir(p, inherit: cur.Directory))
        let pane = makePane(p, dir: where_)
        pane.renderer.SetFont(size: duplicate ? cur.renderer.FontSize : p.FontSize)
        tab.Split(pane, direction: d, size: size)
        frameAll = true
        start(pane, dir: where_, commandline: commandline)
        UpdateTitle(tab)
        redraw()
        focusSurface()
    }

    /// A shell wrote something.
    func ShellOutput(_ paneID: int) {
        guard let tab = ws.TabOf(pane: paneID), let pane = ws.PaneByID(paneID) else { return }
        let t = pane.shell.term
        pane.dirty = true
        let bells = t.Bells
        let seen = tab.seenBells[paneID] ?? 0
        if bells != seen {
            tab.seenBells[paneID] = bells
            ring(tab, pane)
        }
        if let text = t.TakeClipboard(), pane.profile.AllowOSC52 { window.SetClipboardText(text) }
        for n in t.TakeNotifications() {
            toast(n.Title.isEmpty ? n.Body : (n.Body.isEmpty ? n.Title : "\(n.Title): \(n.Body)"))
        }
        // Progress: the focused pane's, else any pane's.
        var progress = ""
        var value = 0
        for p in tab.Panes where p.shell.term.Progress != .none {
            if progress.isEmpty || p.ID == tab.Focused {
                progress = progressName(p.shell.term.Progress)
                value = p.shell.term.ProgressValue
            }
        }
        if tab.Progress != progress { tab.Progress = progress }
        if tab.ProgressValue != value { tab.ProgressValue = value }
        if paneID == tab.Focused { UpdateTitle(tab) }
        if ws.Active == tab.ID { redraw() }
    }

    /// The bell: a sound, a flash, the tab's dot, as the profile says.
    func ring(_ tab: Tab, _ pane: Pane) {
        let style = pane.profile.BellStyle
        if style.contains("audible") { app.Beep() }
        if style.contains("visual") && ws.Active == tab.ID {
            pane.flashUntil = now() + 0.12
            pane.dirty = true
            redraw()
            Task {
                try? await Task.sleep(nanoseconds: 140_000_000)
                pane.dirty = true
                self.redraw()
            }
        }
        if (style.contains("window") || style.contains("taskbar")) && (ws.Active != tab.ID || !focused) { tab.Bell = true }
    }

    /// A shell ended: its pane closes, or stays with a note, as the
    /// profile's closeOnExit says.
    func ShellExited(_ paneID: int) {
        guard let pane = ws.PaneByID(paneID) else { return }
        let code = pane.shell.ExitCode
        let mode = pane.profile.CloseOnExit
        let close = mode == "always" || ((mode == "graceful" || mode == "automatic") && code == 0)
        if close && pane.shell.failure == nil {
            ClosePane(paneID, remember: false)
            return
        }
        let hex = String(uint32(bitPattern: int32(truncatingIfNeeded: code)), radix: 16, uppercase: true)
        pane.shell.term.Feed("\r\n\u{1b}[0m\u{1b}[90m[process exited with code \(code) (0x\(hex))]\u{1b}[0m\r\n")
        pane.shell.term.Feed("You can now close this terminal with ⌘W, or press Enter to restart.\r\n")
        pane.dirty = true
        if let tab = ws.TabOf(pane: paneID) { UpdateTitle(tab) }
        redraw()
    }

    func Select(_ id: int) {
        ui.SettingsShown = false
        if ws.Active != id {
            ws.Active = id
            ws.recent = [id] + ws.recent.filter { $0 != id }
            if let i = ws.Index(of: id) { ws.Tabs[i].Bell = false }
            frameAll = true
            if let t = ws.Current { UpdateTitle(t) }
            closeSearch(keepOpen: ui.Search)
            applyOpacity()
        }
        blinkOn = true
        redraw()
        if !ui.Overlay || ui.Search { focusSurface() }
    }

    /// Closes a pane; the tab goes with its last.
    func ClosePane(_ paneID: int, remember: bool = true) {
        guard let tab = ws.TabOf(pane: paneID), let pane = ws.PaneByID(paneID) else { return }
        if tab.Panes.count <= 1 {
            Close(tab.ID, remember: remember)
            return
        }
        if remember { closed.append((pane.profile, pane.shell.Directory, tab.Shown)) }
        pane.shell.Close()
        _ = tab.Remove(paneID)
        frameAll = true
        UpdateTitle(tab)
        redraw()
    }

    func Close(_ id: int) {
        Close(id, remember: true)
    }

    func Close(_ id: int, remember: bool) {
        guard let i = ws.Index(of: id) else { return }
        let tab = ws.Tabs[i]
        for p in tab.Panes {
            if remember { closed.append((p.profile, p.shell.Directory, tab.Shown)) }
            p.shell.Close()
        }
        if closed.count > 20 { closed.removeFirst(closed.count - 20) }
        ws.Tabs.remove(at: i)
        ws.recent = ws.recent.filter { $0 != id }
        if ui.Renaming == id { ui.Renaming = 0 }
        if ws.Tabs.isEmpty {
            quitConfirmed = true
            app.Quit()
            app.RequestFrame()
            return
        }
        if ws.Active == id {
            Select(ws.Tabs[min(i, ws.Tabs.count - 1)].ID)
        }
    }

    func Step(_ by: int) {
        guard let i = ws.Index(of: ws.Active), ws.Tabs.count > 1 else { return }
        let n = ws.Tabs.count
        Select(ws.Tabs[((i + by) % n + n) % n].ID)
    }

    /// Focuses a pane of the tab in front.
    func FocusPane(_ id: int) {
        guard let tab = ws.Current, tab.Focused != id else { return }
        if let old = tab.FocusedPane, let report = old.shell.term.EncodeFocus(false) { old.shell.Send(report) }
        tab.Focus(id)
        if let p = tab.FocusedPane {
            if let report = p.shell.term.EncodeFocus(true) { p.shell.Send(report) }
            p.dirty = true
        }
        for p in tab.Panes { p.dirty = true }
        if tab.Zoomed != 0 { tab.Zoomed = id }
        frameAll = true
        UpdateTitle(tab)
        if ui.Search { searchChanged() }
        applyOpacity()
        redraw()
    }

    /// The tab's title from its focused pane: the profile's tabTitle,
    /// what the program set (OSC 0 or 2) unless the profile suppresses
    /// it, or what is running and where.
    func UpdateTitle(_ tab: Tab) {
        guard let pane = tab.FocusedPane else { return }
        let shell = pane.shell
        var t = ""
        if !pane.profile.TabTitle.isEmpty {
            t = pane.profile.TabTitle
        } else if !pane.profile.SuppressApplicationTitle && !shell.term.Title.isEmpty {
            t = shell.term.Title
        }
        if t.isEmpty {
            let name = shell.ProcessName ?? pane.profile.Name
            if let d = shell.Directory {
                t = "\(name) — \(shortPath(d))"
            } else {
                t = name
            }
        }
        if shell.Exited { t += " (exited)" }
        if t != tab.Title { tab.Title = t }
        if tab.PaneCount != tab.Panes.count { tab.changed() }
        if tab.ReadOnly != pane.ReadOnly { tab.ReadOnly = pane.ReadOnly }
        if ws.Active == tab.ID {
            let name = ui.WindowName.isEmpty ? "" : ui.WindowName + " — "
            app.SetTitle(settings.ShowTerminalTitleInTitlebar ? name + tab.Shown : (ui.WindowName.isEmpty ? "Terminal" : ui.WindowName))
        }
    }

    // MARK: - Settings

    /// Reads the settings again where the file changed: every pane takes
    /// its profile's new settings.
    func checkSettings() {
        if fixedSettings { return }
        let stamp = settingsModified(settingsFile)
        if stamp == settingsStamp { return }
        settingsStamp = stamp
        ReloadSettings()
    }

    func ReloadSettings() {
        if !fixedSettings { settings = LoadSettings(path: settingsFile, writeIfMissing: false) }
        applySettings()
        if let w = settings.Warnings.first { toast(w) } else { toast("Settings reloaded") }
    }

    func applySettings() {
        for tab in ws.Tabs {
            for pane in tab.Panes {
                // The profile by guid, then by name.
                var next = pane.profile
                var found = false
                for p in settings.Profiles where p.Guid.lowercased() == pane.profile.Guid.lowercased() {
                    next = p
                    found = true
                }
                if !found {
                    for p in settings.Profiles where p.Name == pane.profile.Name { next = p }
                }
                pane.profile = next
                configure(pane)
            }
            UpdateTitle(tab)
        }
        if alwaysOnTop != settings.AlwaysOnTop {
            alwaysOnTop = settings.AlwaysOnTop
            app.SetAlwaysOnTop(alwaysOnTop)
        }
        applyOpacity()
        frameAll = true
        redraw()
        ui.SettingsRev += 1
    }

    func applyOpacity() {
        let want = currentPane?.profile.Opacity ?? 100
        if want != opacity {
            opacity = want
            app.SetOpacity(float32(opacity) / 100)
        }
    }

    /// Watches the settings file, and blinks.
    func tick() async {
        var n = 0
        while true {
            try? await Task.sleep(nanoseconds: 530_000_000)
            n += 1
            if focused, let t = current?.term, t.CursorBlink, t.CursorVisible, !ui.Overlay || ui.Search {
                blinkOn = !blinkOn
                redraw()
            }
            // Blinking text, at the same pace.
            textBlinkOn = !textBlinkOn
            if let tab = ws.Current {
                for p in tab.Panes where hasBlinkingText(p.shell.term) {
                    p.dirty = true
                    redraw()
                }
            }
            if n % 2 == 0 { checkSettings() }
            // Titles follow what runs in the foreground.
            if n % 4 == 0, let tab = ws.Current { UpdateTitle(tab) }
        }
    }

    // MARK: - Drawing

    /// The viewport's frame: the panes of the tab in front, laid out in
    /// the box, each drawn by its renderer and put in place.
    func Draw(_ w: int, _ h: int, _ t: float64) -> [uint8] {
        if let css = handle?.Size, css.Width > 0 { scale = float32(w) / css.Width }
        let isDark = settings.Theme == "dark" ? true : (settings.Theme == "light" ? false : app.IsDark())
        if isDark != dark {
            dark = isDark
            for tab in ws.Tabs {
                for p in tab.Panes {
                    p.renderer.SetTheme(settings.ThemeFor(p.profile, dark: dark))
                    p.shell.term.ColorSchemeChanged(dark: dark)
                    p.dirty = true
                }
            }
            frameAll = true
        }
        if w != surfaceW || h != surfaceH || frame.count != w * h * 4 {
            surfaceW = w
            surfaceH = h
            frame = [uint8](repeating: 0, count: max(0, w * h * 4))
            frameAll = true
        }
        guard let tab = ws.Current, w > 0, h > 0 else {
            return [uint8](repeating: 0, count: max(0, w * h * 4))
        }
        let divider = max(1, int(scale.rounded()))
        let shown: [Pane]
        if tab.Zoomed != 0, let z = tab.root.Find(tab.Zoomed)?.pane {
            z.X = 0
            z.Y = 0
            z.W = w
            z.H = h
            shown = [z]
        } else {
            tab.root.Layout(0, 0, w, h, divider: divider)
            shown = tab.Panes
        }
        var key: [int] = [tab.ID, tab.Focused]
        for p in shown { key.append(contentsOf: [p.ID, p.X, p.Y, p.W, p.H]) }
        if key != layoutKey {
            layoutKey = key
            frameAll = true
        }
        let all = frameAll
        frameAll = false
        let multi = shown.count > 1
        let tm = now()
        for pane in shown {
            let term = pane.shell.term
            let r = pane.renderer
            let theme = r.Theme
            term.ForegroundRGB = (R: theme.Foreground.R, G: theme.Foreground.G, B: theme.Foreground.B)
            term.BackgroundRGB = (R: theme.Background.R, G: theme.Background.G, B: theme.Background.B)
            term.CursorRGB = (R: theme.Cursor.R, G: theme.Cursor.G, B: theme.Cursor.B)
            if term.ThemePalette.count != 16 || term.ThemePalette != theme.Palette { term.ThemePalette = theme.Palette }
            let grid = r.GridSize(width: pane.W, height: pane.H, scale: scale)
            let cell = r.CellPixels(scale: scale)
            term.CellPixelWidth = cell.Width
            term.CellPixelHeight = cell.Height
            pane.shell.Resize(columns: grid.Columns, rows: grid.Rows, width: pane.W, height: pane.H)
            if pane.pending { startNow(pane) }
            if pane.ID == tab.Focused {
                gridColumns = grid.Columns
                gridRows = grid.Rows
            }
            let isFocused = pane.ID == tab.Focused
            let visible = !isFocused || !term.CursorBlink || !focused || blinkOn
            var overlay = view.Overlay(blinkOn: textBlinkOn)
            if isFocused && ui.Search {
                overlay.Highlights = matches
                if matchIndex >= 0 && matchIndex < matches.count { overlay.Current = matches[matchIndex] }
            }
            if isFocused {
                overlay.HoverLink = hoverLink
                overlay.HoverURL = hoverURL
            }
            var sel = pane.shell.selection
            if isFocused && markMode && (sel == nil || sel!.IsEmpty) {
                // Mark mode's cursor: a one-cell selection.
                sel = view.Selection(startColumn: markColumn, startLine: markLine, endColumn: markColumn, endLine: markLine)
            }
            let px = r.Draw(term, width: pane.W, height: pane.H, scale: scale,
                            cursor: view.CursorState(visible: visible && !markMode, focused: focused && isFocused),
                            selection: sel, overlay: overlay)
            let flashing = pane.flashUntil > tm
            if all || r.Drew || pane.dirty || flashing {
                blit(px, pane, flash: flashing)
                pane.dirty = flashing
            }
        }
        startPending(w, h, divider: divider)
        let full = app.IsFullscreen()
        if full != ui.Fullscreen { ui.Fullscreen = full }
        if let f = tab.FocusedPane {
            let bgHex = view.ColorHex(f.renderer.Theme.Background)
            if ui.SurfaceColor != bgHex {
                ui.SurfaceColor = bgHex
                ui.SurfaceText = view.ColorHex(f.renderer.Theme.Foreground)
            }
        }
        if multi {
            // The dividers, and a line around the focused pane.
            let bg = currentPane?.renderer.Theme.Background ?? view.hex(0x1E1E1E)
            let line = dark ? view.hex(0x3C3C3C) : view.hex(0xC8C8C8)
            let accent = currentPane?.renderer.Theme.Cursor ?? view.hex(0x3B8EEA)
            _ = bg
            draw.WithCanvas(&frame, width: int32(w), height: int32(h)) { c in
                for n in tab.root.Splits {
                    c.Fill(draw.IRect(int32(n.divX), int32(n.divY), int32(n.divW), int32(n.divH)), line)
                }
                if let f = tab.FocusedPane {
                    let b = int32(divider)
                    let x = int32(f.X)
                    let y = int32(f.Y)
                    let fw = int32(f.W)
                    let fh = int32(f.H)
                    c.Fill(draw.IRect(x, y, fw, b), accent)
                    c.Fill(draw.IRect(x, y + fh - b, fw, b), accent)
                    c.Fill(draw.IRect(x, y, b, fh), accent)
                    c.Fill(draw.IRect(x + fw - b, y, b, fh), accent)
                }
            }
            // The next frame puts back what the line covered.
            for p in shown { p.dirty = true }
        }
        return frame
    }

    /// Puts a pane's pixels in the frame at its place; a flash lightens
    /// them.
    func blit(_ px: [uint8], _ pane: Pane, flash: bool) {
        let rowBytes = pane.W * 4
        if px.count < pane.W * pane.H * 4 { return }
        for y in 0..<pane.H {
            let fy = pane.Y + y
            if fy < 0 || fy >= surfaceH { continue }
            let dst = (fy * surfaceW + pane.X) * 4
            let src = y * rowBytes
            let n = min(rowBytes, (surfaceW - pane.X) * 4)
            if n <= 0 { continue }
            frame.withUnsafeMutableBytes { d in
                px.withUnsafeBytes { s in
                    (d.baseAddress! + dst).copyMemory(from: s.baseAddress! + src, byteCount: n)
                }
            }
            if flash {
                var i = dst
                while i < dst + n {
                    frame[i] = uint8((int(frame[i]) + 255) / 2)
                    frame[i + 1] = uint8((int(frame[i + 1]) + 255) / 2)
                    frame[i + 2] = uint8((int(frame[i + 2]) + 255) / 2)
                    i += 4
                }
            }
        }
    }

    // MARK: - Opening things

    /// Opens a URL or a path with the system (the browser, Finder, the
    /// text editor): only schemes that are safe to hand on.
    func openExternal(_ target: string, textEditor: bool = false) {
        let lower = target.lowercased()
        let safe = lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://") ||
            lower.hasPrefix("mailto:") || target.hasPrefix("/")
        if !safe {
            toast("Not opened: \(target) (only http, https, file and mailto links are)")
            return
        }
        var cmd = process.Command("/usr/bin/open", textEditor ? ["-t", target] : [target])
        cmd.Stdin = .null
        cmd.Stdout = .null
        cmd.Stderr = .null
        _ = try? cmd.Spawn()
    }

    /// Writes the focused pane's text, scrollback included, to a file in
    /// Downloads.
    func exportBuffer() {
        guard let shell = current else { return }
        let t = shell.term
        let text = t.Text(fromColumn: 0, line: 0, toColumn: t.Columns - 1, line: t.ScrollbackCount + t.Rows - 1)
        let dir = (user.Home() ?? "/tmp") + "/Downloads"
        let stamp = fs.Timestamp.Now().UnixSeconds
        let name = safeFileName(ws.Current?.Shown ?? "Terminal")
        let path = "\(dir)/\(name) \(stamp).txt"
        do {
            try fs.WriteText(fs.Path(path), text + "\n", atomic: true)
            toast("Exported to \(shortPath(path))")
        } catch {
            toast("Couldn't export: \(error)")
        }
    }
}

func safeFileName(_ s: string) -> string {
    var out: [uint8] = []
    for b in s.utf8 {
        if b == 0x2F || b == 0x3A || b == 0x5C || b < 0x20 { out.append(0x2D) } else { out.append(b) }
    }
    if out.count > 60 { out.removeLast(out.count - 60) }
    return string(decoding: out, as: UTF8.self)
}

func progressName(_ p: vt.ProgressState) -> string {
    switch p {
    case .none: return ""
    case .normal: return "normal"
    case .error: return "error"
    case .indeterminate: return "indeterminate"
    case .paused: return "paused"
    }
}

func hasBlinkingText(_ t: vt.Terminal) -> bool {
    for y in 0..<t.Rows {
        for c in t.ViewRow(y).Cells where c.Has(vt.Attr.blink) { return true }
    }
    return false
}

/// Whether the tabs go in the window's title bar (showTabsInTitlebar), as
/// a browser's do: the app is run with a unified title bar.
public func TabsInTitlebar() -> bool {
    return LoadSettings(writeIfMissing: false).ShowTabsInTitlebar
}

/// The window's size for the settings' initialCols and initialRows, in
/// points: the default profile's font and padding, and the tab bar.
public func InitialWindowSize() -> (Width: float32, Height: float32) {
    let s = LoadSettings(writeIfMissing: false)
    let p = s.ProfileNamed(nil)
    let r = view.Renderer(families: p.FontFace.isEmpty ? ["SF Mono", "Menlo", "Monaco", "monospace"] : p.FontFace, size: p.FontSize)
    r.LineSpacing = max(0.5, p.CellHeight)
    r.CellWidthScale = max(0.5, p.CellWidth)
    let cell = r.CellSize(scale: 2)
    let bar: float32 = p.ScrollbarState == "hidden" ? 0 : 10
    let w = cell.Width * float32(s.InitialCols) + p.Padding * 2 + bar + 1
    let h = cell.Height * float32(s.InitialRows) + p.Padding * 2 + 41
    return (Width: max(320, min(2400, w)), Height: max(200, min(1600, h)))
}
