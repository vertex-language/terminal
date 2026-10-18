package workspace

import (
    "encoding/json"
    "fs"
    "terminal/view"
    "ui/app"
    "web/dom"
)

// The settings tab: Windows Terminal's settings UI, as a tab beside the
// terminals. Its pages are groups of rows, each a setting and its control;
// a change is written to settings.json, as the settings UI writes it, and
// read back at once.

/// One setting on a page: what it is, its control, and what a change
/// writes. A class: the page's lists hold it by reference.
final class SettingRow {
    var ID: int = 0
    /// The first in its card: no line above it.
    var First = false
    var Title: string
    var Detail: string
    /// "toggle", "choice", "text", "number", "scheme", "keys".
    var Kind: string
    var On: bool
    /// The text shown: a choice's label, a field's text, a number.
    var Value: string
    /// A choice's options: label, then the value written.
    var Options: [(string, string)]
    /// A number's step and bounds.
    var Step: float64
    var Min: float64
    var Max: float64
    /// A scheme's colors: background, foreground, then its 16.
    var Colors: [string]
    /// Given the new value: "true"/"false" for a toggle, an option's value,
    /// a field's text, a number.
    var Set: (string) -> void

    init(Title: string, Detail: string = "", Kind: string, On: bool = false, Value: string = "", Options: [(string, string)] = [],
         Step: float64 = 1, Min: float64 = 0, Max: float64 = 1_000_000, Colors: [string] = [], Set: (string) -> void = { _ in }) {
        self.Title = Title
        self.Detail = Detail
        self.Kind = Kind
        self.On = On
        self.Value = Value
        self.Options = Options
        self.Step = Step
        self.Min = Min
        self.Max = Max
        self.Colors = Colors
        self.Set = Set
    }
}

/// Rows under a heading, drawn as one card.
final class SettingGroup {
    var ID: int = 0
    var Title: string
    var Rows: [SettingRow]

    init(Title: string, Rows: [SettingRow]) {
        self.Title = Title
        self.Rows = Rows
    }
}

/// A page of the sidebar: its id, its name, and its icon (a lucide name,
/// see SettingsIcon).
struct SettingsPageInfo: Equatable {
    var ID: string
    var Title: string
    var Icon: string
}

extension Controller {
    // MARK: - The tab

    /// Opens the settings tab and puts it in front.
    func OpenSettingsTab(page: string? = nil) {
        if let p = page { ui.SettingsPage = p }
        ui.SettingsOpen = true
        ui.SettingsShown = true
        ui.SettingsQuery = ""
        closeSearch(keepOpen: false)
        app.RequestFrame()
    }

    /// Back to the terminal in front, the settings tab staying open.
    func ShowTerminal() {
        ui.SettingsShown = false
        frameAll = true
        redraw()
        focusSurface()
    }

    func CloseSettingsTab() {
        ui.SettingsOpen = false
        ShowTerminal()
    }

    /// The settings, for markup: read through here, a part of the window
    /// is drawn again when they change.
    var liveSettings: Settings {
        if ui.SettingsRev < 0 { return Settings() }
        return settings
    }

    /// Whether a terminal tab is the one in front (not hidden behind the
    /// settings tab).
    func IsFront(_ id: int) -> bool {
        return ws.Active == id && !ui.SettingsShown
    }

    /// The pages of the sidebar: the settings, then one per profile.
    var SettingsPages: [SettingsPageInfo] {
        return [
            SettingsPageInfo(ID: "startup", Title: "Startup", Icon: "rocket"),
            SettingsPageInfo(ID: "interaction", Title: "Interaction", Icon: "pointer"),
            SettingsPageInfo(ID: "appearance", Title: "Appearance", Icon: "sun"),
            SettingsPageInfo(ID: "schemes", Title: "Color schemes", Icon: "palette"),
            SettingsPageInfo(ID: "actions", Title: "Actions", Icon: "keyboard"),
        ]
    }

    var ProfilePages: [SettingsPageInfo] {
        var out = [SettingsPageInfo(ID: "profile:", Title: "Defaults", Icon: "layers")]
        for p in settings.Profiles {
            out.append(SettingsPageInfo(ID: "profile:" + p.Guid, Title: p.Name, Icon: "terminal"))
        }
        return out
    }

    /// The profiles' pages, read again when the settings change.
    func LiveProfilePages() -> [SettingsPageInfo] {
        if ui.SettingsRev < 0 { return [] }
        return ProfilePages
    }

    /// A page's title.
    func SettingsTitle(_ page: string) -> string {
        for p in SettingsPages + ProfilePages where p.ID == page { return p.ID == "profile:" ? "Defaults" : p.Title }
        return "Settings"
    }

    /// What the page shows, or with a query, every row that matches it
    /// across the pages, under each page's name.
    func SettingsGroups(page: string, query: string) -> [SettingGroup] {
        var groups: [SettingGroup] = []
        if query.isEmpty {
            groups = groupsOf(page)
        } else {
            let q = query.lowercased()
            for p in SettingsPages + ProfilePages {
                var rows: [SettingRow] = []
                for g in groupsOf(p.ID) {
                    for r in g.Rows where r.Title.lowercased().contains(q) || r.Detail.lowercased().contains(q) {
                        rows.append(r)
                    }
                }
                if !rows.isEmpty { groups.append(SettingGroup(Title: p.ID == "profile:" ? "Defaults" : p.Title, Rows: rows)) }
            }
        }
        // Keys for the lists: unique across the page.
        var n = 0
        for gi in 0..<groups.count {
            groups[gi].ID = gi
            for ri in 0..<groups[gi].Rows.count {
                groups[gi].Rows[ri].ID = n
                groups[gi].Rows[ri].First = ri == 0
                n += 1
            }
        }
        return groups
    }

    func groupsOf(_ page: string) -> [SettingGroup] {
        switch page {
        case "startup": return startupGroups()
        case "interaction": return interactionGroups()
        case "appearance": return appearanceGroups()
        case "schemes": return schemeGroups()
        case "actions": return actionGroups()
        default:
            if page.hasPrefix("profile:") { return profileGroups(String(page.dropFirst(8))) }
            return []
        }
    }

    // MARK: - Rows

    func toggle(_ title: string, _ detail: string, _ on: bool, _ key: string) -> SettingRow {
        return SettingRow(Title: title, Detail: detail, Kind: "toggle", On: on, Set: { v in self.setGlobal(key, .bool(v == "true")) })
    }

    func choice(_ title: string, _ detail: string, _ value: string, _ options: [(string, string)], _ set: (string) -> void) -> SettingRow {
        var shown = value
        for (label, v) in options where v == value { shown = label }
        return SettingRow(Title: title, Detail: detail, Kind: "choice", Value: shown, Options: options, Set: set)
    }

    func field(_ title: string, _ detail: string, _ value: string, _ set: (string) -> void) -> SettingRow {
        return SettingRow(Title: title, Detail: detail, Kind: "text", Value: value, Set: set)
    }

    func number(_ title: string, _ detail: string, _ value: float64, step: float64 = 1, min: float64 = 0, max: float64 = 1_000_000, _ set: (string) -> void) -> SettingRow {
        return SettingRow(Title: title, Detail: detail, Kind: "number", Value: numberText(value), Step: step, Min: min, Max: max, Set: set)
    }

    func startupGroups() -> [SettingGroup] {
        let s = settings
        var profiles: [(string, string)] = []
        for p in s.Profiles where !p.Hidden { profiles.append((p.Name, p.Guid)) }
        let def = s.ProfileNamed(nil).Guid
        return [
            SettingGroup(Title: "Launch", Rows: [
                choice("Default profile", "The profile a new tab opens with", def, profiles, { v in self.setGlobal("defaultProfile", .string(v)) }),
                choice("When Terminal starts", "What the first window opens with", s.FirstWindowPreference,
                       [("Open a tab with the default profile", "defaultProfile"), ("Open tabs from the previous session", "persistedWindowLayout")],
                       { v in self.setGlobal("firstWindowPreference", .string(v)) }),
                choice("Launch mode", "How the window first appears", s.LaunchMode,
                       [("Default", "default"), ("Maximized", "maximized"), ("Full screen", "fullscreen"), ("Focus", "focus"), ("Maximized focus", "maximizedFocus")],
                       { v in self.setGlobal("launchMode", .string(v)) }),
                field("Startup actions", "Commands run in a new window, as wt's command line", s.StartupActions, { v in self.setGlobal("startupActions", v.isEmpty ? nil : .string(v)) }),
            ]),
            SettingGroup(Title: "Launch size", Rows: [
                number("Columns", "The width of a new window, in characters", float64(s.InitialCols), min: 10, max: 1000, { v in self.setGlobal("initialCols", .number(v)) }),
                number("Rows", "The height of a new window, in lines", float64(s.InitialRows), min: 4, max: 1000, { v in self.setGlobal("initialRows", .number(v)) }),
            ]),
            SettingGroup(Title: "Window", Rows: [
                toggle("Always on top", "Keep the window above other windows", s.AlwaysOnTop, "alwaysOnTop"),
            ]),
        ]
    }

    func interactionGroups() -> [SettingGroup] {
        let s = settings
        return [
            SettingGroup(Title: "Selection and clipboard", Rows: [
                toggle("Copy on select", "Selected text goes to the clipboard as it is selected", s.CopyOnSelect, "copyOnSelect"),
                toggle("Trim trailing spaces in block selection", "Spaces at the ends of a block selection's lines are left out", s.TrimBlockSelection, "trimBlockSelection"),
                toggle("Trim pasted text", "Spaces at the end of pasted text are removed", s.TrimPaste, "trimPaste"),
                field("Word delimiters", "Characters that end a word when double-clicking", s.WordDelimiters, { v in self.setGlobal("wordDelimiters", .string(v)) }),
            ]),
            SettingGroup(Title: "Tabs and panes", Rows: [
                toggle("Tab switcher", "⌃Tab switches tabs in the order they were used", s.UseTabSwitcher, "useTabSwitcher"),
                choice("New tab position", "Where a new tab opens", s.NewTabPosition,
                       [("After the last tab", "afterLastTab"), ("After the current tab", "afterCurrentTab")],
                       { v in self.setGlobal("newTabPosition", .string(v)) }),
                toggle("Focus follows mouse", "The pane under the pointer gets the keyboard", s.FocusFollowMouse, "focusFollowMouse"),
            ]),
            SettingGroup(Title: "Links and scrolling", Rows: [
                toggle("Detect URLs", "Links in the output can be opened with ⌘-click", s.DetectURLs, "experimental.detectURLs"),
                number("Rows to scroll", "Lines a wheel notch scrolls; 0 is the system's", float64(s.RowsToScroll), max: 100, { v in self.setGlobal("rowsToScroll", .number(v)) }),
                field("Search the web URL", "%s is replaced by the selected text", s.SearchWebDefaultQueryUrl, { v in self.setGlobal("searchWebDefaultQueryUrl", .string(v)) }),
            ]),
            SettingGroup(Title: "Warnings", Rows: [
                toggle("Confirm closing a window", "Ask before closing a window with more than one tab", s.ConfirmOnClose, "warning.confirmOnClose"),
                toggle("Confirm closing all tabs", "Ask before closing every tab at once", s.ConfirmCloseAllTabs, "warning.confirmCloseAllTabs"),
                toggle("Large paste", "Ask before pasting more than 5 KiB", s.LargePasteWarning, "warning.largePaste"),
                toggle("Multi-line paste", "Ask before pasting text of more than one line", s.MultiLinePasteWarning, "warning.multiLinePaste"),
            ]),
        ]
    }

    func appearanceGroups() -> [SettingGroup] {
        let s = settings
        return [
            SettingGroup(Title: "Theme", Rows: [
                choice("Application theme", "Light or dark, or as the system is", s.Theme,
                       [("Use system setting", "system"), ("Light", "light"), ("Dark", "dark")],
                       { v in self.setGlobal("theme", .string(v)) }),
                toggle("Disable pane animations", "Panes open and close without moving", s.DisableAnimations, "disableAnimations"),
            ]),
            SettingGroup(Title: "Tabs", Rows: [
                toggle("Always show tabs", "The tab bar stays with one tab", s.AlwaysShowTabs, "alwaysShowTabs"),
                toggle("Show tabs in the title bar", "Tabs sit beside the window's buttons", s.ShowTabsInTitlebar, "showTabsInTitlebar"),
                toggle("Use the active terminal's title", "The window is named after the tab in front", s.ShowTerminalTitleInTitlebar, "showTerminalTitleInTitlebar"),
                choice("Tab width", "How wide the tabs are", s.TabWidthMode,
                       [("Equal", "equal"), ("Size to the title", "titleLength"), ("Compact", "compact")],
                       { v in self.setGlobal("tabWidthMode", .string(v)) }),
            ]),
            SettingGroup(Title: "Scrolling", Rows: [
                toggle("Scroll to zoom", "⌘ and the wheel change the font size", s.ScrollToZoom, "experimental.scrollToZoom"),
                toggle("Scroll to change opacity", "⌘⇧ and the wheel change the background's opacity", s.ScrollToChangeOpacity, "experimental.scrollToChangeOpacity"),
            ]),
        ]
    }

    func schemeGroups() -> [SettingGroup] {
        let current = defaultsProfile().ColorScheme
        var own: [SettingRow] = []
        var builtin: [SettingRow] = []
        let names = Set(settings.Schemes.map { $0.Name })
        for name in settings.SchemeNames {
            guard let t = settings.Scheme(name) else { continue }
            var colors = [view.ColorHex(t.Background), view.ColorHex(t.Foreground)]
            for c in t.ANSI { colors.append(view.ColorHex(c)) }
            let row = SettingRow(Title: name, Detail: name == current ? "The defaults' scheme" : "", Kind: "scheme", On: name == current,
                                 Colors: colors, Set: { _ in self.setProfile("", ["colorScheme"], .string(name)) })
            if names.contains(name) { own.append(row) } else { builtin.append(row) }
        }
        var out: [SettingGroup] = []
        if !own.isEmpty { out.append(SettingGroup(Title: "Yours", Rows: own)) }
        out.append(SettingGroup(Title: "Built in", Rows: builtin))
        return out
    }

    func actionGroups() -> [SettingGroup] {
        var rows: [SettingRow] = []
        for id in settings.ActionOrder {
            guard let a = settings.Actions[id], a.Command != "unbound" else { continue }
            rows.append(SettingRow(Title: a.Name, Detail: id, Kind: "keys", Value: settings.KeysFor(id),
                                   Set: { _ in self.RunAction(id) }))
        }
        return [SettingGroup(Title: "Commands and their keys", Rows: rows)]
    }

    /// A profile's page; guid "" is the defaults every profile starts from.
    func profileGroups(_ guid: string) -> [SettingGroup] {
        let p = guid.isEmpty ? defaultsProfile() : settings.ProfileNamed(guid)
        func set(_ path: [string], _ v: json.Value?) { self.setProfile(guid, path, v) }
        func text(_ v: string) -> json.Value? { return v.isEmpty ? nil : .string(v) }
        var schemes: [(string, string)] = [("Default", "")]
        for n in settings.SchemeNames { schemes.append((n, n)) }
        var general: [SettingRow] = []
        if !guid.isEmpty {
            general.append(field("Name", "What the profile is called in menus", p.Name, { v in set(["name"], text(v)) }))
        }
        general += [
            field("Command line", "The program a tab runs; empty is your login shell", p.Commandline, { v in set(["commandline"], text(v)) }),
            field("Starting directory", "Where it starts; empty is the current tab's directory", p.StartingDirectory, { v in set(["startingDirectory"], text(v)) }),
            field("Tab title", "A title for its tabs instead of the program's", p.TabTitle, { v in set(["tabTitle"], text(v)) }),
            field("Icon", "An emoji or a character shown on its tabs", p.Icon, { v in set(["icon"], text(v)) }),
        ]
        if !guid.isEmpty {
            general.append(SettingRow(Title: "Hide from menus", Detail: "Leave it out of the new-tab menu and the palette", Kind: "toggle", On: p.Hidden,
                                      Set: { v in set(["hidden"], .bool(v == "true")) }))
        }
        let cursor: string
        switch p.CursorShape {
        case .bar: cursor = "bar"
        case .underscore: cursor = "underscore"
        case .doubleUnderscore: cursor = "doubleUnderscore"
        case .emptyBox: cursor = "emptyBox"
        case .vintage: cursor = "vintage"
        default: cursor = "filledBox"
        }
        var bell = "none"
        if p.BellStyle.contains("audible") { bell = "audible" }
        if p.BellStyle.contains("visual") { bell = p.BellStyle.contains("audible") ? "all" : "visual" }
        return [
            SettingGroup(Title: "General", Rows: general),
            SettingGroup(Title: "Text", Rows: [
                choice("Color scheme", "The colors its text and background are drawn in", p.ColorScheme, schemes, { v in set(["colorScheme"], text(v)) }),
                field("Font face", "A font, or several separated by commas", p.FontFace.joined(separator: ", "), { v in set(["font", "face"], text(v)) }),
                number("Font size", "In points", float64(p.FontSize), step: 1, min: 6, max: 72, { v in set(["font", "size"], .number(v)) }),
                choice("Font weight", "How heavy the text is", "\(p.FontWeight)",
                       [("Thin", "100"), ("Light", "300"), ("Normal", "400"), ("Medium", "500"), ("Semi-bold", "600"), ("Bold", "700")],
                       { v in set(["font", "weight"], .number(v)) }),
                number("Line height", "As a fraction of the font's", float64(p.CellHeight), step: 0.05, min: 0.8, max: 2, { v in set(["font", "cellHeight"], .number(v)) }),
                choice("Intense text", "How bold text is shown", p.IntenseTextStyle,
                       [("Bright colors", "bright"), ("Bold font", "bold"), ("Both", "all"), ("Neither", "none")],
                       { v in set(["intenseTextStyle"], .string(v)) }),
            ]),
            SettingGroup(Title: "Cursor and window", Rows: [
                choice("Cursor shape", "How the text cursor is drawn", cursor,
                       [("Bar ┃", "bar"), ("Underscore ▁", "underscore"), ("Double underscore ‗", "doubleUnderscore"), ("Filled box █", "filledBox"), ("Empty box ▯", "emptyBox"), ("Vintage ▃", "vintage")],
                       { v in set(["cursorShape"], .string(v)) }),
                number("Background opacity", "Percent; less shows what is behind the window", float64(p.Opacity), step: 5, min: 10, max: 100, { v in set(["opacity"], .number(v)) }),
                number("Padding", "Space around the text, in points", float64(p.Padding), min: 0, max: 64, { v in set(["padding"], .number(v)) }),
                choice("Scrollbar", "When the scrollbar shows", p.ScrollbarState,
                       [("Visible", "visible"), ("Hidden", "hidden"), ("Always", "always")],
                       { v in set(["scrollbarState"], .string(v)) }),
            ]),
            SettingGroup(Title: "Advanced", Rows: [
                number("History size", "Lines kept above the screen", float64(p.HistorySize), step: 1000, min: 0, max: 1_000_000, { v in set(["historySize"], .number(v)) }),
                choice("Bell", "What the bell does", bell,
                       [("Sound", "audible"), ("Flash", "visual"), ("Sound and flash", "all"), ("Nothing", "none")],
                       { v in
                           if v == "all" || v == "none" {
                               set(["bellStyle"], .string(v))
                           } else {
                               set(["bellStyle"], .array([.string(v), .string("window")]))
                           }
                       }),
                choice("When the program exits", "What happens to its pane", p.CloseOnExit,
                       [("Close if it succeeded", "graceful"), ("Always close", "always"), ("Never close", "never"), ("Automatic", "automatic")],
                       { v in set(["closeOnExit"], .string(v)) }),
                SettingRow(Title: "Scroll to the bottom on input", Detail: "Typing brings the prompt back into view", Kind: "toggle", On: p.SnapOnInput,
                           Set: { v in set(["snapOnInput"], .bool(v == "true")) }),
                SettingRow(Title: "Ignore the program's title", Detail: "Keep the tab's title when the program sets one", Kind: "toggle", On: p.SuppressApplicationTitle,
                           Set: { v in set(["suppressApplicationTitle"], .bool(v == "true")) }),
                SettingRow(Title: "Mark prompts", Detail: "Each Enter marks a prompt, to jump between", Kind: "toggle", On: p.AutoMarkPrompts,
                           Set: { v in set(["autoMarkPrompts"], .bool(v == "true")) }),
                SettingRow(Title: "Clipboard access", Detail: "Programs may write the clipboard (OSC 52)", Kind: "toggle", On: p.AllowOSC52,
                           Set: { v in set(["allowOSC52"], .bool(v == "true")) }),
                SettingRow(Title: "Kitty keyboard protocol", Detail: "Programs may ask for every key, unambiguously", Kind: "toggle", On: p.KittyKeyboard,
                           Set: { v in set(["kittyKeyboard"], .bool(v == "true")) }),
            ]),
        ]
    }

    /// The defaults every profile starts from: the built-in ones, and
    /// what settings.json's profiles.defaults says.
    func defaultsProfile() -> Profile {
        var p = Profile()
        if let root = settingsJSON(), let d = root["profiles"]?["defaults"]?.Object { applyProfile(d, to: &p) }
        return p
    }

    // MARK: - Writing

    /// settings.json as a document, or nil when it can't be read as one
    /// (a change then isn't written, rather than writing over it).
    func settingsJSON() -> json.Value? {
        var text = settingsText
        if !fixedSettings {
            text = (try? fs.ReadText(fs.Path(settingsFile))) ?? "{}"
        }
        return try? json.Parse(stripJSONC(text.isEmpty ? "{}" : text))
    }

    /// Sets a global setting; nil removes it, for the default.
    func setGlobal(_ key: string, _ value: json.Value?) {
        guard let root = settingsJSON() else {
            toast("settings.json can't be read, so the change wasn't written")
            return
        }
        var o = root.Object ?? json.Object()
        o[key] = value
        writeSettings(.object(o))
    }

    /// Sets a profile's setting (guid "" is profiles.defaults): a path
    /// into its object, as ["font", "size"].
    func setProfile(_ guid: string, _ path: [string], _ value: json.Value?) {
        guard let root = settingsJSON() else {
            toast("settings.json can't be read, so the change wasn't written")
            return
        }
        var o = root.Object ?? json.Object()
        var profiles = json.Object()
        if let po = o["profiles"]?.Object {
            profiles = po
        } else if let arr = o["profiles"]?.Array {
            profiles["list"] = .array(arr)
        }
        // The font's own keys win over the older flat ones.
        var drop: [string] = []
        if path.first == "font" && path.count == 2 {
            switch path[1] {
            case "face": drop = ["fontFace"]
            case "size": drop = ["fontSize"]
            case "weight": drop = ["fontWeight"]
            default: break
            }
        }
        if guid.isEmpty {
            var d = profiles["defaults"]?.Object ?? json.Object()
            for k in drop { d[k] = nil }
            profiles["defaults"] = setIn(.object(d), path, 0, value)
        } else {
            var list = profiles["list"]?.Array ?? []
            var found = -1
            for i in 0..<list.count where (list[i]["guid"]?.String ?? "").lowercased() == guid.lowercased() { found = i }
            if found < 0 {
                for i in 0..<list.count where list[i]["guid"] == nil && list[i]["name"]?.String == settings.ProfileNamed(guid).Name { found = i }
            }
            if found < 0 {
                var po = json.Object()
                po["guid"] = .string(guid)
                po["name"] = .string(settings.ProfileNamed(guid).Name)
                list.append(.object(po))
                found = list.count - 1
            }
            var po = list[found].Object ?? json.Object()
            for k in drop { po[k] = nil }
            list[found] = setIn(.object(po), path, 0, value)
            profiles["list"] = .array(list)
        }
        o["profiles"] = .object(profiles)
        writeSettings(.object(o))
    }

    /// Writes the document as settings.json and takes its settings now.
    func writeSettings(_ root: json.Value) {
        let text = "// Settings for Vertex Terminal, in Windows Terminal's format, as the\n// settings tab writes them. Changes apply as soon as the file is saved.\n" + json.Encode(root, indent: "    ") + "\n"
        if fixedSettings {
            settingsText = text
            settings = SettingsFrom(text)
        } else {
            do {
                try fs.WriteText(fs.Path(settingsFile), text, atomic: true)
            } catch {
                toast("settings.json couldn't be written: \(error)")
                return
            }
            settingsStamp = settingsModified(settingsFile)
            settings = LoadSettings(path: settingsFile, writeIfMissing: false)
        }
        if ui.InTitlebar != settings.ShowTabsInTitlebar && !ui.Fullscreen { ui.InTitlebar = settings.ShowTabsInTitlebar }
        applySettings()
    }

    // MARK: - Controls

    /// A choice's options, as a menu under the pointer.
    func openChoice(_ row: SettingRow, x: float32, y: float32) {
        var items: [(string, string, () -> void)] = []
        for (label, v) in row.Options {
            items.append((label, label == row.Value ? "✓" : "", { row.Set(v) }))
        }
        openMenu(x: x, y: y, items)
    }

    /// A number one step up or down, within its bounds.
    func stepNumber(_ row: SettingRow, _ dir: float64) {
        let v = (float64(row.Value) ?? row.Min) + dir * row.Step
        row.Set(numberText(min(row.Max, max(row.Min, v))))
    }

    /// A number typed: kept within its bounds, or left as it was.
    func typedNumber(_ row: SettingRow, _ text: string) {
        guard let v = float64(trimmed(text)) else {
            ui.SettingsRev += 1
            return
        }
        let clamped = min(row.Max, max(row.Min, v))
        if numberText(clamped) != row.Value { row.Set(numberText(clamped)) } else { ui.SettingsRev += 1 }
    }

    /// Keys pressed on the settings page: ⌘ shortcuts run their actions,
    /// as on a terminal.
    func SettingsKey(_ e: dom.KeyboardEvent) {
        if e.Key == "Escape" && !ui.Overlay {
            ShowTerminal()
            return
        }
        guard e.Meta || e.Control else { return }
        let chord = chordOf(code: e.Code, key: e.Key, shift: e.Shift, control: e.Control, alt: e.Alt, meta: e.Meta)
        if let a = settings.ActionFor(chord) {
            // Copying and pasting belong to the field being typed in.
            if a.Command == "copy" || a.Command == "paste" { return }
            e.PreventDefault()
            RunAction(a.ID)
        }
    }
}

/// A number as settings.json and the page write it: no ".0" for a whole
/// one, two places at most.
func numberText(_ v: float64) -> string {
    if v == float64(int64(v)) { return "\(int64(v))" }
    let r = float64(int64((v * 100).rounded())) / 100
    return "\(r)"
}

/// v with the member at path[i...] set (nil removes it), objects made as
/// they're needed.
func setIn(_ v: json.Value, _ path: [string], _ i: int, _ value: json.Value?) -> json.Value {
    var o = v.Object ?? json.Object()
    let k = path[i]
    if i == path.count - 1 {
        o[k] = value
    } else {
        o[k] = setIn(o[k] ?? .object(json.Object()), path, i + 1, value)
    }
    return .object(o)
}
