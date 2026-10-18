package workspace

import (
    "encoding/json"
    "fs"
    "image/draw"
    "os/env"
    "os/user"
    "terminal/view"
)

// Settings are Windows Terminal's: a settings.json of global settings,
// profiles (with "defaults" under every one), color schemes, and actions
// bound to keys, read with comments and trailing commas allowed. What
// isn't set comes from defaultSettings below, which is written the same
// way, with macOS's keys (⌘ is "cmd") where Windows Terminal uses Ctrl+Shift.

/// What a tab runs and how it looks.
struct Profile {
    var Name = ""
    var Guid = ""
    /// The program and its arguments; "" is the user's shell, as a login
    /// shell.
    var Commandline = ""
    /// Where it starts; "" is the directory of the tab it was opened
    /// from (or home), "~" home.
    var StartingDirectory = ""
    var ColorScheme = ""
    var ColorSchemeLight = ""
    var ColorSchemeDark = ""
    var FontFace: [string] = []
    var FontSize: float32 = 13
    var FontWeight = 400
    /// Line height and cell width, as fractions of the font's.
    var CellHeight: float32 = 1.15
    var CellWidth: float32 = 1
    var CursorShape: view.CursorStyle = .filledBox
    var CursorHeight = 25
    var CursorColor: draw.Color? = nil
    var Foreground: draw.Color? = nil
    var Background: draw.Color? = nil
    var SelectionBackground: draw.Color? = nil
    var Padding: float32 = 6
    var HistorySize = 10000
    /// "audible", "visual", "window" (the tab's dot), "taskbar".
    var BellStyle: [string] = ["audible", "window"]
    /// "graceful" (close on success), "always", "never"; "automatic" is
    /// graceful.
    var CloseOnExit = "automatic"
    var TabTitle = ""
    var SuppressApplicationTitle = false
    var TabColor: draw.Color? = nil
    var Environment: [string: string] = [:]
    var Hidden = false
    /// "bright", "bold", "all", "none".
    var IntenseTextStyle = "bright"
    /// "never", "indexed", "always".
    var AdjustIndistinguishableColors = "indexed"
    var SnapOnInput = true
    /// "visible", "hidden", "always".
    var ScrollbarState = "visible"
    var AnswerbackMessage = ""
    var AutoMarkPrompts = false
    var ShowMarksOnScrollbar = true
    var RightClickContextMenu = true
    var Opacity = 100
    var Icon = ""
    var AllowOSC52 = true
    var KittyKeyboard = true
    var Source = ""
}

/// A key and its modifiers, as a binding names it ("cmd+shift+t").
struct KeyChord: Equatable {
    var Key = ""
    var Ctrl = false
    var Alt = false
    var Shift = false
    var Cmd = false
}

/// An action: a command and its arguments, as settings write them
/// ("newTab", or {"action": "splitPane", "split": "right"}).
struct Action {
    var ID = ""
    var Name = ""
    var Command = ""
    var Args: json.Object = json.Object()

    func Str(_ key: string, _ def: string = "") -> string {
        return Args[key]?.String ?? def
    }

    func Int(_ key: string, _ def: int = 0) -> int {
        if let v = Args[key]?.Int { return int(v) }
        if let d = Args[key]?.Double { return int(d) }
        return def
    }

    func Bool(_ key: string, _ def: bool = false) -> bool {
        return Args[key]?.Bool ?? def
    }
}

/// A binding: a chord, and the action it runs.
struct Binding {
    var Chord: KeyChord
    var ActionID: string
}

/// Everything settings.json says.
final class Settings {
    var DefaultProfile = ""
    var InitialCols = 120
    var InitialRows = 30
    var CopyOnSelect = false
    var TrimBlockSelection = true
    var TrimPaste = true
    var WordDelimiters = " /\\()\"'-.,:;<>~!@#$%^&*|+=[]{}~?\u{2502}"
    var AlwaysShowTabs = true
    var ShowTerminalTitleInTitlebar = true
    /// The tabs sit in the title bar, beside the window's buttons.
    var ShowTabsInTitlebar = true
    /// "equal", "titleLength", "compact".
    var TabWidthMode = "equal"
    var ConfirmOnClose = true
    var ConfirmCloseAllTabs = true
    var LargePasteWarning = true
    var MultiLinePasteWarning = true
    var FocusFollowMouse = false
    var DetectURLs = true
    /// "afterLastTab", "afterCurrentTab".
    var NewTabPosition = "afterLastTab"
    /// Lines a wheel notch scrolls; 0 is the system's.
    var RowsToScroll = 0
    /// "system", "dark", "light".
    var Theme = "system"
    /// "default", "maximized", "fullscreen", "focus", "maximizedFocus".
    var LaunchMode = "default"
    var AlwaysOnTop = false
    var StartupActions = ""
    var SearchWebDefaultQueryUrl = "https://www.bing.com/search?q=%22%s%22"
    var DisableAnimations = false
    var ScrollToZoom = true
    var ScrollToChangeOpacity = true
    var UseTabSwitcher = true
    /// "defaultProfile", or "persistedWindowLayout": the last session's
    /// tabs and panes come back.
    var FirstWindowPreference = "defaultProfile"

    var Profiles: [Profile] = []
    var Schemes: [view.Theme] = []
    var Actions: [string: Action] = [:]
    /// Actions in the order they were defined: what the command palette
    /// lists.
    var ActionOrder: [string] = []
    var Bindings: [Binding] = []
    /// What went wrong reading the user's file, to show once.
    var Warnings: [string] = []

    init() {}

    /// The profile a name or guid names, or the default one.
    func ProfileNamed(_ key: string?) -> Profile {
        if let k = key, !k.isEmpty {
            for p in Profiles where p.Name == k || p.Guid.lowercased() == k.lowercased() { return p }
        }
        for p in Profiles where p.Guid.lowercased() == DefaultProfile.lowercased() || p.Name == DefaultProfile { return p }
        return Profiles.first ?? Profile()
    }

    /// The profiles shown in menus: not hidden.
    var VisibleProfiles: [Profile] { return Profiles.filter { !$0.Hidden } }

    /// A scheme by name: the settings' own, then the built-in ones.
    func Scheme(_ name: string) -> view.Theme? {
        for s in Schemes where s.Name == name { return s }
        for s in builtinSchemes where s.Name == name { return s }
        return nil
    }

    /// Every scheme's name, the settings' own first.
    var SchemeNames: [string] {
        var names: [string] = Schemes.map { $0.Name }
        for s in builtinSchemes where !names.contains(s.Name) { names.append(s.Name) }
        return names
    }

    /// The theme a profile is drawn in, for a dark or light appearance:
    /// its scheme, with its own colors over it.
    func ThemeFor(_ p: Profile, dark: bool) -> view.Theme {
        var name = p.ColorScheme
        if dark && !p.ColorSchemeDark.isEmpty { name = p.ColorSchemeDark }
        if !dark && !p.ColorSchemeLight.isEmpty { name = p.ColorSchemeLight }
        var t = name.isEmpty ? (dark ? view.Theme.dark : view.Theme.light) : (Scheme(name) ?? (dark ? view.Theme.dark : view.Theme.light))
        var tag = ""
        if let c = p.Foreground {
            t.Foreground = c
            tag += "f" + view.ColorHex(c)
        }
        if let c = p.Background {
            t.Background = c
            t.CursorText = c
            tag += "b" + view.ColorHex(c)
        }
        if let c = p.SelectionBackground {
            t.Selection = blend(t.Background, c, 0.4)
            tag += "s" + view.ColorHex(c)
        }
        if let c = p.CursorColor {
            t.Cursor = c
            tag += "c" + view.ColorHex(c)
        }
        if p.IntenseTextStyle == "bold" || p.IntenseTextStyle == "none" { t.BoldIsBright = false }
        if !tag.isEmpty { t.Name += "+" + tag }
        return t
    }

    /// The action bound to a chord, if any.
    func ActionFor(_ chord: KeyChord) -> Action? {
        // The last binding of a chord wins: the user's come after the
        // defaults.
        var i = Bindings.count - 1
        while i >= 0 {
            if Bindings[i].Chord == chord {
                let id = Bindings[i].ActionID
                if id.isEmpty || id == "unbound" { return nil }
                return Actions[id]
            }
            i -= 1
        }
        return nil
    }

    /// The chord an action is bound to, written for a menu ("⌘⇧T").
    func KeysFor(_ id: string) -> string {
        var i = Bindings.count - 1
        while i >= 0 {
            if Bindings[i].ActionID == id {
                // Unless the chord was taken by another binding later.
                let c = Bindings[i].Chord
                var taken = false
                var j = i + 1
                while j < Bindings.count {
                    if Bindings[j].Chord == c { taken = true }
                    j += 1
                }
                if !taken { return chordLabel(c) }
            }
            i -= 1
        }
        return ""
    }
}

// MARK: - Where it is

/// The settings file: settings.json in the app's folder under the
/// user's configuration directory, or $VERTEX_TERMINAL_SETTINGS.
func settingsPath() -> string {
    if let p = env.Get("VERTEX_TERMINAL_SETTINGS"), !p.isEmpty { return p }
    let base = user.ConfigDir() ?? ((user.Home() ?? "/tmp") + "/.config")
    return base + "/vertex-terminal/settings.json"
}

/// When the file last changed, to notice an edit.
func settingsModified(_ path: string) -> int64 {
    if let m = try? fs.Metadata(fs.Path(path)) { return m.Modified.UnixSeconds * 1000 + int64(m.Modified.Nanoseconds / 1_000_000) }
    return -1
}

// MARK: - Reading

/// Reads the settings: the defaults, the shells the system lists as
/// profiles, then the user's file over them. A file that isn't there is
/// written, with the profiles found, for the user to edit.
func LoadSettings(path: string? = nil, writeIfMissing: bool = true) -> Settings {
    let s = Settings()
    if let d = try? json.Parse(stripJSONC(defaultSettings)) { apply(d, to: s, user: false) }
    s.Profiles = detectedProfiles()
    let p = path ?? settingsPath()
    if let text = try? fs.ReadText(fs.Path(p)) {
        do {
            let v = try json.Parse(stripJSONC(text))
            apply(v, to: s, user: true)
        } catch {
            s.Warnings.append("settings.json couldn't be read: \(error). The defaults are used until it is fixed.")
        }
    } else if writeIfMissing {
        writeStarter(p, s)
    }
    if s.Profiles.isEmpty { s.Profiles.append(Profile(Name: "Shell", Guid: guidFor("Shell"))) }
    if s.DefaultProfile.isEmpty { s.DefaultProfile = s.Profiles[0].Guid }
    return s
}

/// Parses settings JSON text over the defaults (for tests).
func SettingsFrom(_ text: string) -> Settings {
    let s = Settings()
    if let d = try? json.Parse(stripJSONC(defaultSettings)) { apply(d, to: s, user: false) }
    s.Profiles = detectedProfiles()
    do {
        let v = try json.Parse(stripJSONC(text))
        apply(v, to: s, user: true)
    } catch {
        s.Warnings.append("\(error)")
    }
    if s.Profiles.isEmpty { s.Profiles.append(Profile(Name: "Shell", Guid: guidFor("Shell"))) }
    if s.DefaultProfile.isEmpty { s.DefaultProfile = s.Profiles[0].Guid }
    return s
}

func apply(_ v: json.Value, to s: Settings, user: bool) {
    guard let o = v.Object else { return }
    func str(_ k: string) -> string? { return o[k]?.String }
    func bool(_ k: string) -> bool? { return o[k]?.Bool }
    func num(_ k: string) -> int? {
        if let i = o[k]?.Int { return int(i) }
        if let d = o[k]?.Double { return int(d) }
        return nil
    }
    if let x = str("defaultProfile") { s.DefaultProfile = x }
    if let x = num("initialCols") { s.InitialCols = max(10, x) }
    if let x = num("initialRows") { s.InitialRows = max(4, x) }
    if let x = bool("copyOnSelect") { s.CopyOnSelect = x }
    if let x = bool("trimBlockSelection") { s.TrimBlockSelection = x }
    if let x = bool("trimPaste") { s.TrimPaste = x }
    if let x = str("wordDelimiters") { s.WordDelimiters = x }
    if let x = bool("alwaysShowTabs") { s.AlwaysShowTabs = x }
    if let x = bool("showTerminalTitleInTitlebar") { s.ShowTerminalTitleInTitlebar = x }
    if let x = bool("showTabsInTitlebar") { s.ShowTabsInTitlebar = x }
    if let x = str("tabWidthMode") { s.TabWidthMode = x }
    if let x = bool("warning.confirmOnClose") ?? bool("confirmCloseAllTabs") { s.ConfirmOnClose = x }
    if let x = bool("warning.confirmCloseAllTabs") { s.ConfirmCloseAllTabs = x }
    if let x = bool("warning.largePaste") ?? bool("largePasteWarning") { s.LargePasteWarning = x }
    if let x = bool("warning.multiLinePaste") ?? bool("multiLinePasteWarning") { s.MultiLinePasteWarning = x }
    if let x = bool("focusFollowMouse") { s.FocusFollowMouse = x }
    if let x = bool("experimental.detectURLs") { s.DetectURLs = x }
    if let x = str("newTabPosition") { s.NewTabPosition = x }
    if let x = num("rowsToScroll") { s.RowsToScroll = max(0, x) }
    if let x = o["rowsToScroll"]?.String, x == "system" { s.RowsToScroll = 0 }
    if let x = str("theme") { s.Theme = x }
    if let x = str("launchMode") { s.LaunchMode = x }
    if let x = bool("alwaysOnTop") { s.AlwaysOnTop = x }
    if let x = str("startupActions") { s.StartupActions = x }
    if let x = str("searchWebDefaultQueryUrl") { s.SearchWebDefaultQueryUrl = x }
    if let x = bool("disableAnimations") { s.DisableAnimations = x }
    if let x = bool("experimental.scrollToZoom") { s.ScrollToZoom = x }
    if let x = bool("experimental.scrollToChangeOpacity") { s.ScrollToChangeOpacity = x }
    if let x = bool("useTabSwitcher") { s.UseTabSwitcher = x }
    if let x = o["useTabSwitcher"]?.String { s.UseTabSwitcher = x != "disabled" }
    if let x = str("firstWindowPreference") { s.FirstWindowPreference = x }
    // Schemes: added, or replacing one of the same name.
    if let list = o["schemes"]?.Array {
        for sv in list {
            if let t = parseScheme(sv) {
                s.Schemes = s.Schemes.filter { $0.Name != t.Name }
                s.Schemes.append(t)
            }
        }
    }
    // Profiles: "defaults" under each, "list" merged by guid or name.
    var defaults = json.Object()
    var list: [json.Value] = []
    if let pv = o["profiles"] {
        if let arr = pv.Array {
            list = arr
        } else if let po = pv.Object {
            defaults = po["defaults"]?.Object ?? json.Object()
            list = po["list"]?.Array ?? []
        }
    }
    if user {
        // The defaults apply to the profiles found as well.
        for i in 0..<s.Profiles.count { applyProfile(defaults, to: &s.Profiles[i]) }
        for pv in list {
            guard let po = pv.Object else { continue }
            let guid = po["guid"]?.String ?? ""
            let name = po["name"]?.String ?? ""
            var found = -1
            for i in 0..<s.Profiles.count where (!guid.isEmpty && s.Profiles[i].Guid.lowercased() == guid.lowercased()) || (guid.isEmpty && !name.isEmpty && s.Profiles[i].Name == name) {
                found = i
            }
            if found >= 0 {
                applyProfile(po, to: &s.Profiles[found])
            } else {
                var p = Profile()
                applyProfile(defaults, to: &p)
                applyProfile(po, to: &p)
                if p.Guid.isEmpty { p.Guid = guidFor(p.Name) }
                if p.Name.isEmpty { p.Name = "Profile \(s.Profiles.count + 1)" }
                s.Profiles.append(p)
            }
        }
    }
    // Actions, and the keys bound to them.
    for key in ["actions", "keybindings"] {
        guard let arr = o[key]?.Array else { continue }
        for av in arr {
            guard let ao = av.Object else { continue }
            var id = ao["id"]?.String ?? ""
            if let cmd = ao["command"] {
                var a = Action()
                if let c = cmd.String {
                    a.Command = c
                } else if let co = cmd.Object {
                    a.Command = co["action"]?.String ?? ""
                    a.Args = co
                } else if cmd.IsNull {
                    a.Command = "unbound"
                }
                if let n = ao["name"]?.String { a.Name = n }
                if id.isEmpty { id = "User." + actionKey(a) }
                a.ID = id
                if a.Name.isEmpty { a.Name = actionName(a) }
                if s.Actions[id] == nil { s.ActionOrder.append(id) }
                s.Actions[id] = a
            }
            var keys: [string] = []
            if let k = ao["keys"]?.String { keys = [k] }
            if let ks = ao["keys"]?.Array { keys = ks.compactMap { $0.String } }
            for k in keys {
                if let chord = parseChord(k) { s.Bindings.append(Binding(Chord: chord, ActionID: id)) }
            }
        }
    }
}

func applyProfile(_ o: json.Object, to p: inout Profile) {
    func str(_ k: string) -> string? { return o[k]?.String }
    func bool(_ k: string) -> bool? { return o[k]?.Bool }
    func num(_ k: string) -> float32? {
        if let d = o[k]?.Double { return float32(d) }
        return nil
    }
    if let x = str("name") { p.Name = x }
    if let x = str("guid") { p.Guid = x }
    if let x = str("commandline") { p.Commandline = x }
    if o["startingDirectory"] != nil {
        p.StartingDirectory = o["startingDirectory"]?.String ?? ""
    }
    if let cs = o["colorScheme"] {
        if let n = cs.String {
            p.ColorScheme = n
            p.ColorSchemeLight = ""
            p.ColorSchemeDark = ""
        } else if let pair = cs.Object {
            p.ColorSchemeLight = pair["light"]?.String ?? ""
            p.ColorSchemeDark = pair["dark"]?.String ?? ""
        }
    }
    if let f = o["font"]?.Object {
        if let face = f["face"]?.String { p.FontFace = fontList(face) }
        if let size = f["size"]?.Double { p.FontSize = float32(size) }
        if let w = f["weight"] { p.FontWeight = fontWeight(w) }
        if let h = f["cellHeight"]?.String, let v = float32(h) { p.CellHeight = v }
        if let h = f["cellHeight"]?.Double { p.CellHeight = float32(h) }
        if let w = f["cellWidth"]?.String, let v = float32(w) { p.CellWidth = v }
        if let w = f["cellWidth"]?.Double { p.CellWidth = float32(w) }
    }
    if let face = str("fontFace") { p.FontFace = fontList(face) }
    if let size = num("fontSize") { p.FontSize = size }
    if let w = o["fontWeight"] { p.FontWeight = fontWeight(w) }
    if let x = str("cursorShape") {
        switch x {
        case "bar": p.CursorShape = .bar
        case "underscore": p.CursorShape = .underscore
        case "doubleUnderscore": p.CursorShape = .doubleUnderscore
        case "emptyBox": p.CursorShape = .emptyBox
        case "vintage": p.CursorShape = .vintage
        default: p.CursorShape = .filledBox
        }
    }
    if let x = num("cursorHeight") { p.CursorHeight = int(x) }
    if let x = str("cursorColor") { p.CursorColor = view.ParseColor(x) }
    if let x = str("foreground") { p.Foreground = view.ParseColor(x) }
    if let x = str("background") { p.Background = view.ParseColor(x) }
    if let x = str("selectionBackground") { p.SelectionBackground = view.ParseColor(x) }
    if let x = str("padding") {
        let parts = x.split(separator: ",")
        let first = parts.isEmpty ? x : trimmed(String(parts[0]))
        if let v = float32(first) { p.Padding = v }
    }
    if let x = num("padding") { p.Padding = x }
    if let x = num("historySize") { p.HistorySize = max(0, int(x)) }
    if let x = str("bellStyle") { p.BellStyle = x == "all" ? ["audible", "visual", "window", "taskbar"] : (x == "none" ? [] : [x]) }
    if let x = o["bellStyle"]?.Array { p.BellStyle = x.compactMap { $0.String } }
    if let x = str("closeOnExit") { p.CloseOnExit = x }
    if let x = bool("closeOnExit") { p.CloseOnExit = x ? "graceful" : "never" }
    if let x = str("tabTitle") { p.TabTitle = x }
    if let x = bool("suppressApplicationTitle") { p.SuppressApplicationTitle = x }
    if let x = str("tabColor") { p.TabColor = view.ParseColor(x) }
    if let e = o["environment"]?.Object {
        for (k, v) in e.Members { if let sv = v.String { p.Environment[k] = sv } }
    }
    if let x = bool("hidden") { p.Hidden = x }
    if let x = str("intenseTextStyle") { p.IntenseTextStyle = x }
    if let x = str("adjustIndistinguishableColors") { p.AdjustIndistinguishableColors = x }
    if let x = bool("snapOnInput") { p.SnapOnInput = x }
    if let x = str("scrollbarState") { p.ScrollbarState = x }
    if let x = str("answerbackMessage") { p.AnswerbackMessage = x }
    if let x = bool("autoMarkPrompts") ?? bool("experimental.autoMarkPrompts") { p.AutoMarkPrompts = x }
    if let x = bool("showMarksOnScrollbar") ?? bool("experimental.showMarksOnScrollbar") { p.ShowMarksOnScrollbar = x }
    if let x = bool("rightClickContextMenu") ?? bool("experimental.rightClickContextMenu") { p.RightClickContextMenu = x }
    if let x = num("opacity") { p.Opacity = max(5, min(100, int(x))) }
    if let x = str("icon") { p.Icon = x }
    if let x = bool("compatibility.allowOSC52") { p.AllowOSC52 = x }
    if let x = bool("compatibility.kittyKeyboardMode") { p.KittyKeyboard = x }
    if let x = str("source") { p.Source = x }
}

func fontList(_ face: string) -> [string] {
    var out: [string] = []
    for part in face.split(separator: ",") {
        let f = trimmed(String(part))
        if !f.isEmpty { out.append(f) }
    }
    out.append(contentsOf: ["SF Mono", "Menlo", "Monaco", "monospace"])
    return out
}

func fontWeight(_ v: json.Value) -> int {
    if let n = v.Int { return int(n) }
    switch v.String ?? "" {
    case "thin": return 100
    case "extra-light": return 200
    case "light", "semi-light": return 300
    case "medium": return 500
    case "semi-bold": return 600
    case "bold": return 700
    case "extra-bold": return 800
    case "black", "extra-black": return 900
    default: return 400
    }
}

func parseScheme(_ v: json.Value) -> view.Theme? {
    guard let o = v.Object, let name = o["name"]?.String else { return nil }
    let keys = ["black", "red", "green", "yellow", "blue", "purple", "cyan", "white",
                "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue", "brightPurple", "brightCyan", "brightWhite"]
    let base = view.Theme.dark
    var ansi: [draw.Color] = []
    for i in 0..<16 {
        ansi.append(view.ParseColor(o[keys[i]]?.String ?? "") ?? base.ANSI[i])
    }
    let fg = view.ParseColor(o["foreground"]?.String ?? "") ?? base.Foreground
    let bg = view.ParseColor(o["background"]?.String ?? "") ?? base.Background
    let cur = view.ParseColor(o["cursorColor"]?.String ?? "") ?? fg
    let sel = view.ParseColor(o["selectionBackground"]?.String ?? "") ?? fg
    return scheme(name, fg: fg, bg: bg, cursor: cur, selection: sel, ansi: ansi)
}

/// "cmd+shift+t" as a chord; nil for what can't be one.
func parseChord(_ text: string) -> KeyChord? {
    var c = KeyChord()
    let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { String($0) }
    var i = 0
    while i < parts.count {
        var p = parts[i]
        // "ctrl++" is ctrl and plus.
        if p.isEmpty && i + 1 < parts.count && parts[i + 1].isEmpty {
            p = "plus"
            i += 1
        }
        switch p {
        case "ctrl", "control": c.Ctrl = true
        case "alt", "option", "opt": c.Alt = true
        case "shift": c.Shift = true
        case "cmd", "command", "win", "super", "meta": c.Cmd = true
        default:
            if p.isEmpty { return nil }
            c.Key = normalizeKey(p)
        }
        i += 1
    }
    if c.Key.isEmpty { return nil }
    return c
}

/// A key's name as bindings write it, from the many ways to say it.
func normalizeKey(_ k: string) -> string {
    switch k {
    case "plus", "=", "numpad_plus": return "="
    case "minus", "-", "numpad_minus": return "-"
    case "return": return "enter"
    case "escape": return "esc"
    case "pageup", "page_up": return "pgup"
    case "pagedown", "page_down": return "pgdn"
    case "del": return "delete"
    case "comma": return ","
    case "period": return "."
    case "slash": return "/"
    case "backslash": return "\\"
    case "semicolon": return ";"
    case "quote", "apostrophe": return "'"
    case "backtick", "grave", "sc(41)": return "`"
    case "numpad_0": return "0"
    case "arrowup": return "up"
    case "arrowdown": return "down"
    case "arrowleft": return "left"
    case "arrowright": return "right"
    default: return k
    }
}

/// A key event's chord, by where the key is (its code), so bindings work
/// whatever the layout and whatever Option makes of the character.
func chordOf(code: string, key: string, shift: bool, control: bool, alt: bool, meta: bool) -> KeyChord {
    var c = KeyChord(Key: "", Ctrl: control, Alt: alt, Shift: shift, Cmd: meta)
    let b = [uint8](code.utf8)
    if b.count == 4 && code.hasPrefix("Key") {
        c.Key = string(decoding: [b[3] + 0x20], as: UTF8.self)
        return c
    }
    if b.count == 6 && code.hasPrefix("Digit") {
        c.Key = string(decoding: [b[5]], as: UTF8.self)
        return c
    }
    if code.hasPrefix("Numpad") && b.count == 7 {
        c.Key = string(decoding: [b[6]], as: UTF8.self)
        return c
    }
    switch code {
    case "Equal", "NumpadAdd": c.Key = "="
    case "Minus", "NumpadSubtract": c.Key = "-"
    case "BracketLeft": c.Key = "["
    case "BracketRight": c.Key = "]"
    case "Comma": c.Key = ","
    case "Period": c.Key = "."
    case "Slash": c.Key = "/"
    case "Backslash": c.Key = "\\"
    case "Semicolon": c.Key = ";"
    case "Quote": c.Key = "'"
    case "Backquote": c.Key = "`"
    case "Enter", "NumpadEnter": c.Key = "enter"
    case "Tab": c.Key = "tab"
    case "Space": c.Key = "space"
    case "Escape": c.Key = "esc"
    case "Backspace": c.Key = "backspace"
    case "Delete": c.Key = "delete"
    case "Insert": c.Key = "insert"
    case "Home": c.Key = "home"
    case "End": c.Key = "end"
    case "PageUp": c.Key = "pgup"
    case "PageDown": c.Key = "pgdn"
    case "ArrowUp": c.Key = "up"
    case "ArrowDown": c.Key = "down"
    case "ArrowLeft": c.Key = "left"
    case "ArrowRight": c.Key = "right"
    case "ContextMenu": c.Key = "menu"
    default:
        if code.hasPrefix("F") && b.count <= 3 {
            c.Key = code.lowercased()
        } else {
            c.Key = normalizeKey(key.lowercased())
        }
    }
    return c
}

/// A chord as macOS menus write it: ⌃⌥⇧⌘ then the key.
func chordLabel(_ c: KeyChord) -> string {
    var s = ""
    if c.Ctrl { s += "⌃" }
    if c.Alt { s += "⌥" }
    if c.Shift { s += "⇧" }
    if c.Cmd { s += "⌘" }
    switch c.Key {
    case "up": s += "↑"
    case "down": s += "↓"
    case "left": s += "←"
    case "right": s += "→"
    case "enter": s += "↩"
    case "tab": s += "⇥"
    case "esc": s += "⎋"
    case "space": s += "Space"
    case "backspace": s += "⌫"
    case "delete": s += "⌦"
    case "pgup": s += "⇞"
    case "pgdn": s += "⇟"
    case "home": s += "↖"
    case "end": s += "↘"
    default: s += c.Key.uppercased()
    }
    return s
}

// MARK: - Profiles the system has

/// A profile for each shell /etc/shells lists that exists, the user's
/// $SHELL first: what Windows Terminal's dynamic profiles are on a Mac.
func detectedProfiles() -> [Profile] {
    var out: [Profile] = []
    var seen: [string] = []
    let mine = env.Get("SHELL") ?? "/bin/zsh"
    var shells = [mine]
    if let text = try? fs.ReadText(fs.Path("/etc/shells")) {
        for line in text.split(separator: "\n") {
            let l = trimmed(String(line))
            if l.isEmpty || l.hasPrefix("#") { continue }
            shells.append(l)
        }
    }
    for path in shells {
        let name = String(path.split(separator: "/").last ?? "shell")
        if seen.contains(name) || !fs.Exists(fs.Path(path), followSymlinks: true) { continue }
        seen.append(name)
        var p = Profile()
        p.Name = name
        p.Guid = guidFor(name)
        p.Commandline = path == mine ? "" : path + " -l"
        p.Source = "Vertex.Shells"
        // sh and csh: rarely wanted, there if asked for.
        p.Hidden = name == "sh" || name == "csh" || name == "tcsh" || name == "dash" || name == "ksh"
        out.append(p)
    }
    return out
}

/// A stable guid for a name: what a generated profile is known by.
func guidFor(_ name: string) -> string {
    var h1: uint64 = 0xcbf29ce484222325
    var h2: uint64 = 0x84222325cbf29ce4
    for b in name.utf8 {
        h1 = (h1 ^ uint64(b)) &* 0x100000001b3
        h2 = (h2 ^ uint64(b)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15
    }
    func hex(_ v: uint64, _ n: int) -> string {
        let digits: [string] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
        var s = ""
        var x = v
        for _ in 0..<n {
            s = digits[int(x & 15)] + s
            x >>= 4
        }
        return s
    }
    return "{" + hex(h1 >> 32, 8) + "-" + hex(h1 >> 16, 4) + "-" + hex(h1, 4) + "-" + hex(h2 >> 48, 4) + "-" + hex(h2, 12) + "}"
}

/// The file written the first time: the profiles found, and room for the
/// user's own settings.
func writeStarter(_ path: string, _ s: Settings) {
    var list: [string] = []
    for p in s.Profiles {
        list.append("            {\n                \"guid\": \(json.Quote(p.Guid)),\n                \"name\": \(json.Quote(p.Name)),\n                \"hidden\": \(p.Hidden ? "true" : "false"),\n                \"source\": \(json.Quote(p.Source))\n            }")
    }
    let text = """
    // Settings for Vertex Terminal, in Windows Terminal's format:
    // https://learn.microsoft.com/windows/terminal/customize-settings/
    // Changes apply as soon as the file is saved.
    {
        "$schema": "https://aka.ms/terminal-profiles-schema",
        "defaultProfile": \(json.Quote(s.Profiles.first?.Guid ?? "")),
        "copyOnSelect": false,
        "profiles": {
            "defaults": {
                // "colorScheme": "Campbell",
                // "font": { "face": "SF Mono", "size": 13 },
                // "cursorShape": "bar"
            },
            "list": [
    \(list.joined(separator: ",\n"))
            ]
        },
        "schemes": [],
        "actions": [],
        "keybindings": [
            // { "keys": "cmd+shift+e", "id": "Terminal.ToggleBroadcastInput" }
        ]
    }

    """
    let dir = parentDir(path)
    try? fs.CreateDir(fs.Path(dir), all: true)
    try? fs.WriteText(fs.Path(path), text, atomic: true)
}

/// s without the spaces and tabs around it.
func trimmed(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var a = 0
    var e = b.count
    while a < e && (b[a] == 0x20 || b[a] == 0x09 || b[a] == 0x0D) { a += 1 }
    while e > a && (b[e - 1] == 0x20 || b[e - 1] == 0x09 || b[e - 1] == 0x0D) { e -= 1 }
    return string(decoding: [uint8](b[a..<e]), as: UTF8.self)
}

/// The directory a path is in.
func parentDir(_ path: string) -> string {
    let b = [uint8](path.utf8)
    var i = b.count - 1
    while i > 0 && b[i] != 0x2F { i -= 1 }
    if i <= 0 { return "/" }
    return string(decoding: [uint8](b[0..<i]), as: UTF8.self)
}

/// JSON with comments (// and /* */) and trailing commas, as settings.json
/// may be written, made plain JSON.
func stripJSONC(_ text: string) -> string {
    let b = [uint8](text.utf8)
    var out: [uint8] = []
    var i = 0
    var inString = false
    while i < b.count {
        let c = b[i]
        if inString {
            out.append(c)
            if c == 0x5C && i + 1 < b.count {
                out.append(b[i + 1])
                i += 2
                continue
            }
            if c == 0x22 { inString = false }
            i += 1
            continue
        }
        if c == 0x22 {
            inString = true
            out.append(c)
            i += 1
            continue
        }
        if c == 0x2F && i + 1 < b.count && b[i + 1] == 0x2F {
            while i < b.count && b[i] != 0x0A { i += 1 }
            continue
        }
        if c == 0x2F && i + 1 < b.count && b[i + 1] == 0x2A {
            i += 2
            while i + 1 < b.count && !(b[i] == 0x2A && b[i + 1] == 0x2F) { i += 1 }
            i += 2
            continue
        }
        if c == 0x2C {
            // A comma before a closing bracket goes.
            var j = i + 1
            while j < b.count {
                let d = b[j]
                if d == 0x20 || d == 0x09 || d == 0x0A || d == 0x0D {
                    j += 1
                } else if d == 0x2F && j + 1 < b.count && b[j + 1] == 0x2F {
                    while j < b.count && b[j] != 0x0A { j += 1 }
                } else if d == 0x2F && j + 1 < b.count && b[j + 1] == 0x2A {
                    j += 2
                    while j + 1 < b.count && !(b[j] == 0x2A && b[j + 1] == 0x2F) { j += 1 }
                    j += 2
                } else {
                    break
                }
            }
            if j < b.count && (b[j] == 0x7D || b[j] == 0x5D) {
                i += 1
                continue
            }
        }
        out.append(c)
        i += 1
    }
    return string(decoding: out, as: UTF8.self)
}

// MARK: - Action names

/// A key for an action the user wrote without an id: its command and
/// arguments.
func actionKey(_ a: Action) -> string {
    var s = a.Command
    for (k, v) in a.Args.Members where k != "action" {
        s += "." + k + "=" + (v.String ?? json.Encode(v))
    }
    return s
}

/// What the command palette calls an action, as Windows Terminal does.
func actionName(_ a: Action) -> string {
    func dir(_ d: string) -> string {
        switch d {
        case "up": return "up"
        case "down": return "down"
        case "left": return "left"
        case "right": return "right"
        case "previous": return "to the last used pane"
        case "previousInOrder": return "to the previous pane"
        case "nextInOrder": return "to the next pane"
        case "first": return "to the first pane"
        case "parent": return "to the parent pane"
        case "child": return "to the child pane"
        default: return d
        }
    }
    switch a.Command {
    case "closeWindow": return "Close window"
    case "toggleFullscreen": return "Toggle fullscreen"
    case "toggleFocusMode": return "Toggle focus mode"
    case "toggleAlwaysOnTop": return "Toggle always on top mode"
    case "openNewTabDropdown": return "Open new tab dropdown"
    case "openSettings":
        switch a.Str("target") {
        case "defaultsFile": return "Open default settings file (JSON)"
        case "directory": return "Open settings folder"
        case "settingsUI": return "Open settings"
        default: return "Open settings file (JSON)"
        }
    case "find": return "Find"
    case "findMatch": return a.Str("direction") == "prev" ? "Find previous search match" : "Find next search match"
    case "openTabColorPicker": return "Change tab color..."
    case "renameTab": return a.Args["title"] != nil ? "Rename tab to \"\(a.Str("title"))\"" : "Reset tab title"
    case "openTabRenamer": return "Rename tab..."
    case "commandPalette": return "Toggle command palette"
    case "quit": return "Quit"
    case "restoreLastClosed": return "Restore the last closed tab or pane"
    case "openAbout": return "About"
    case "openCWD": return "Open current working directory"
    case "closeOtherTabs": return "Close all other tabs"
    case "closeTabsAfter": return "Close tabs after current tab"
    case "closeTab": return "Close tab"
    case "moveTab": return a.Str("direction") == "backward" ? "Move tab backward" : "Move tab forward"
    case "newTab":
        if a.Args["index"] != nil { return "New tab, profile index: \(a.Int("index"))" }
        if let p = a.Args["profile"]?.String { return "New tab, profile: \(p)" }
        return "New tab"
    case "newWindow": return "New window"
    case "duplicateTab": return "Duplicate tab"
    case "nextTab": return "Next tab"
    case "prevTab": return "Previous tab"
    case "switchToTab":
        let i = a.Int("index")
        return i >= 1000 || i < 0 ? "Switch to the last tab" : "Switch to tab \(i + 1)"
    case "closeOtherPanes": return "Close all other panes"
    case "closePane": return "Close pane"
    case "splitPane":
        let dup = a.Str("splitMode") == "duplicate"
        let d = a.Str("split", "auto")
        let where_ = d == "auto" ? "" : (d == "vertical" || d == "right" ? ", split: right" : (d == "horizontal" || d == "down" ? ", split: down" : ", split: \(d)"))
        return (dup ? "Duplicate pane" : "Split pane") + where_
    case "resizePane": return "Resize pane \(a.Str("direction"))"
    case "moveFocus": return "Move focus \(dir(a.Str("direction")))"
    case "swapPane": return "Swap pane \(dir(a.Str("direction")))"
    case "toggleBroadcastInput": return "Toggle broadcast input to all panes"
    case "togglePaneZoom": return "Toggle pane zoom"
    case "toggleSplitOrientation": return "Toggle split orientation"
    case "toggleReadOnlyMode": return "Toggle pane read-only mode"
    case "enableReadOnlyMode": return "Enable pane read-only mode"
    case "disableReadOnlyMode": return "Disable pane read-only mode"
    case "movePane": return "Move pane to tab \(a.Int("index") + 1)"
    case "restartConnection": return "Restart connection"
    case "copy": return "Copy text"
    case "paste": return "Paste"
    case "selectAll": return "Select all"
    case "markMode": return "Toggle mark mode"
    case "toggleBlockSelection": return "Toggle block selection"
    case "switchSelectionEndpoint": return "Switch selection endpoint"
    case "expandSelectionToWord": return "Expand selection to word"
    case "showContextMenu": return "Show context menu"
    case "searchWeb": return "Search the web for selected text"
    case "scrollDown": return "Scroll down"
    case "scrollDownPage": return "Scroll down one page"
    case "scrollUp": return "Scroll up"
    case "scrollUpPage": return "Scroll up one page"
    case "scrollToTop": return "Scroll to the top of history"
    case "scrollToBottom": return "Scroll to the bottom of history"
    case "scrollToMark":
        switch a.Str("direction") {
        case "next": return "Scroll to the next mark"
        case "first": return "Scroll to the first mark"
        case "last": return "Scroll to the last mark"
        default: return "Scroll to the previous mark"
        }
    case "addMark": return "Add a scroll mark"
    case "clearMark": return "Clear mark"
    case "clearAllMarks": return "Clear all marks"
    case "clearBuffer":
        switch a.Str("clear", "all") {
        case "screen": return "Clear the screen"
        case "scrollback": return "Clear the scrollback"
        default: return "Clear buffer"
        }
    case "exportBuffer": return "Export text"
    case "adjustFontSize": return a.Int("delta", 1) > 0 ? "Increase font size" : "Decrease font size"
    case "resetFontSize": return "Reset font size"
    case "setColorScheme": return "Select color scheme: \(a.Str("colorScheme"))"
    case "setTabColor": return a.Args["color"] != nil ? "Set tab color to \(a.Str("color"))" : "Reset tab color"
    case "sendInput": return "Send input: \(a.Str("input").debugDescription)"
    case "adjustOpacity": return a.Bool("relative") ? "Adjust opacity by \(a.Int("opacity"))%" : "Set opacity to \(a.Int("opacity"))%"
    case "tabSearch": return "Search for tab..."
    case "minimize": return "Minimize"
    case "identifyWindow": return "Identify window"
    case "openWindowRenamer": return "Rename window..."
    case "renameWindow": return "Rename window"
    case "toggleShaderEffects": return "Toggle terminal visual effects"
    case "selectCommand": return a.Str("direction") == "next" ? "Select next command" : "Select previous command"
    case "selectOutput": return a.Str("direction") == "next" ? "Select next command output" : "Select previous command output"
    case "multipleActions": return "Run multiple actions"
    case "openSystemMenu": return "Open window menu"
    default: return a.Command
    }
}

// The defaults, in Windows Terminal's format. Every action Windows
// Terminal has by id, and the keys bound to them on a Mac.
let defaultSettings = """
{
    "initialCols": 120,
    "initialRows": 30,
    "copyOnSelect": false,
    "trimBlockSelection": true,
    "trimPaste": true,
    "alwaysShowTabs": true,
    "tabWidthMode": "equal",
    "warning.confirmOnClose": true,
    "warning.largePaste": true,
    "warning.multiLinePaste": true,
    "theme": "system",
    "actions": [
        { "command": "closeWindow", "id": "Terminal.CloseWindow" },
        { "command": "toggleFullscreen", "id": "Terminal.ToggleFullscreen" },
        { "command": "toggleFocusMode", "id": "Terminal.ToggleFocusMode" },
        { "command": "toggleAlwaysOnTop", "id": "Terminal.ToggleAlwaysOnTop" },
        { "command": "openNewTabDropdown", "id": "Terminal.OpenNewTabDropdown" },
        { "command": { "action": "openSettings", "target": "settingsFile" }, "id": "Terminal.OpenSettingsFile" },
        { "command": { "action": "openSettings", "target": "settingsUI" }, "id": "Terminal.OpenSettingsUI" },
        { "command": { "action": "openSettings", "target": "directory" }, "id": "Terminal.OpenSettingsDirectory" },
        { "command": "find", "id": "Terminal.FindText" },
        { "command": { "action": "findMatch", "direction": "next" }, "id": "Terminal.FindNextMatch" },
        { "command": { "action": "findMatch", "direction": "prev" }, "id": "Terminal.FindPrevMatch" },
        { "command": "openTabColorPicker", "id": "Terminal.OpenTabColorPicker" },
        { "command": "renameTab", "id": "Terminal.RenameTab" },
        { "command": "openTabRenamer", "id": "Terminal.OpenTabRenamer" },
        { "command": "commandPalette", "id": "Terminal.ToggleCommandPalette" },
        { "command": "tabSearch", "id": "Terminal.TabSearch" },
        { "command": "quit", "id": "Terminal.Quit" },
        { "command": "minimize", "id": "Terminal.Minimize" },
        { "command": "restoreLastClosed", "id": "Terminal.RestoreLastClosed" },
        { "command": "openAbout", "id": "Terminal.OpenAboutDialog" },
        { "command": "openCWD", "id": "Terminal.OpenCWD" },
        { "command": "closeOtherTabs", "id": "Terminal.CloseOtherTabs" },
        { "command": "closeTabsAfter", "id": "Terminal.CloseTabsAfter" },
        { "command": "closeTab", "id": "Terminal.CloseTab" },
        { "command": { "action": "moveTab", "direction": "forward" }, "id": "Terminal.MoveTabForward" },
        { "command": { "action": "moveTab", "direction": "backward" }, "id": "Terminal.MoveTabBackward" },
        { "command": "newTab", "id": "Terminal.OpenNewTab" },
        { "command": "newWindow", "id": "Terminal.OpenNewWindow" },
        { "command": { "action": "newTab", "index": 0 }, "id": "Terminal.OpenNewTabProfile0" },
        { "command": { "action": "newTab", "index": 1 }, "id": "Terminal.OpenNewTabProfile1" },
        { "command": { "action": "newTab", "index": 2 }, "id": "Terminal.OpenNewTabProfile2" },
        { "command": { "action": "newTab", "index": 3 }, "id": "Terminal.OpenNewTabProfile3" },
        { "command": { "action": "newTab", "index": 4 }, "id": "Terminal.OpenNewTabProfile4" },
        { "command": { "action": "newTab", "index": 5 }, "id": "Terminal.OpenNewTabProfile5" },
        { "command": { "action": "newTab", "index": 6 }, "id": "Terminal.OpenNewTabProfile6" },
        { "command": { "action": "newTab", "index": 7 }, "id": "Terminal.OpenNewTabProfile7" },
        { "command": { "action": "newTab", "index": 8 }, "id": "Terminal.OpenNewTabProfile8" },
        { "command": "duplicateTab", "id": "Terminal.DuplicateTab" },
        { "command": "nextTab", "id": "Terminal.NextTab" },
        { "command": "prevTab", "id": "Terminal.PrevTab" },
        { "command": { "action": "switchToTab", "index": 0 }, "id": "Terminal.SwitchToTab0" },
        { "command": { "action": "switchToTab", "index": 1 }, "id": "Terminal.SwitchToTab1" },
        { "command": { "action": "switchToTab", "index": 2 }, "id": "Terminal.SwitchToTab2" },
        { "command": { "action": "switchToTab", "index": 3 }, "id": "Terminal.SwitchToTab3" },
        { "command": { "action": "switchToTab", "index": 4 }, "id": "Terminal.SwitchToTab4" },
        { "command": { "action": "switchToTab", "index": 5 }, "id": "Terminal.SwitchToTab5" },
        { "command": { "action": "switchToTab", "index": 6 }, "id": "Terminal.SwitchToTab6" },
        { "command": { "action": "switchToTab", "index": 7 }, "id": "Terminal.SwitchToTab7" },
        { "command": { "action": "switchToTab", "index": 4294967295 }, "id": "Terminal.SwitchToLastTab" },
        { "command": "closeOtherPanes", "id": "Terminal.CloseOtherPanes" },
        { "command": "closePane", "id": "Terminal.ClosePane" },
        { "command": { "action": "splitPane", "split": "up" }, "id": "Terminal.SplitPaneUp" },
        { "command": { "action": "splitPane", "split": "down" }, "id": "Terminal.SplitPaneDown" },
        { "command": { "action": "splitPane", "split": "left" }, "id": "Terminal.SplitPaneLeft" },
        { "command": { "action": "splitPane", "split": "right" }, "id": "Terminal.SplitPaneRight" },
        { "command": { "action": "splitPane", "splitMode": "duplicate", "split": "down" }, "id": "Terminal.DuplicatePaneDown" },
        { "command": { "action": "splitPane", "splitMode": "duplicate", "split": "right" }, "id": "Terminal.DuplicatePaneRight" },
        { "command": { "action": "splitPane", "splitMode": "duplicate", "split": "auto" }, "id": "Terminal.DuplicatePaneAuto" },
        { "command": { "action": "resizePane", "direction": "down" }, "id": "Terminal.ResizePaneDown" },
        { "command": { "action": "resizePane", "direction": "left" }, "id": "Terminal.ResizePaneLeft" },
        { "command": { "action": "resizePane", "direction": "right" }, "id": "Terminal.ResizePaneRight" },
        { "command": { "action": "resizePane", "direction": "up" }, "id": "Terminal.ResizePaneUp" },
        { "command": { "action": "moveFocus", "direction": "down" }, "id": "Terminal.MoveFocusDown" },
        { "command": { "action": "moveFocus", "direction": "left" }, "id": "Terminal.MoveFocusLeft" },
        { "command": { "action": "moveFocus", "direction": "right" }, "id": "Terminal.MoveFocusRight" },
        { "command": { "action": "moveFocus", "direction": "up" }, "id": "Terminal.MoveFocusUp" },
        { "command": { "action": "moveFocus", "direction": "previous" }, "id": "Terminal.MoveFocusPrevious" },
        { "command": { "action": "moveFocus", "direction": "previousInOrder" }, "id": "Terminal.MoveFocusPreviousInOrder" },
        { "command": { "action": "moveFocus", "direction": "nextInOrder" }, "id": "Terminal.MoveFocusNextInOrder" },
        { "command": { "action": "moveFocus", "direction": "first" }, "id": "Terminal.MoveFocusFirst" },
        { "command": { "action": "moveFocus", "direction": "parent" }, "id": "Terminal.MoveFocusParent" },
        { "command": { "action": "moveFocus", "direction": "child" }, "id": "Terminal.MoveFocusChild" },
        { "command": { "action": "swapPane", "direction": "down" }, "id": "Terminal.SwapPaneDown" },
        { "command": { "action": "swapPane", "direction": "left" }, "id": "Terminal.SwapPaneLeft" },
        { "command": { "action": "swapPane", "direction": "right" }, "id": "Terminal.SwapPaneRight" },
        { "command": { "action": "swapPane", "direction": "up" }, "id": "Terminal.SwapPaneUp" },
        { "command": { "action": "swapPane", "direction": "previous" }, "id": "Terminal.SwapPanePrevious" },
        { "command": { "action": "swapPane", "direction": "previousInOrder" }, "id": "Terminal.SwapPanePreviousInOrder" },
        { "command": { "action": "swapPane", "direction": "nextInOrder" }, "id": "Terminal.SwapPaneNextInOrder" },
        { "command": { "action": "swapPane", "direction": "first" }, "id": "Terminal.SwapPaneFirst" },
        { "command": "toggleBroadcastInput", "id": "Terminal.ToggleBroadcastInput" },
        { "command": "togglePaneZoom", "id": "Terminal.TogglePaneZoom" },
        { "command": "toggleSplitOrientation", "id": "Terminal.ToggleSplitOrientation" },
        { "command": "toggleReadOnlyMode", "id": "Terminal.ToggleReadOnlyMode" },
        { "command": "enableReadOnlyMode", "id": "Terminal.EnableReadOnlyMode" },
        { "command": "disableReadOnlyMode", "id": "Terminal.DisableReadOnlyMode" },
        { "command": { "action": "movePane", "index": 0 }, "id": "Terminal.MovePaneToTab0" },
        { "command": { "action": "movePane", "index": 1 }, "id": "Terminal.MovePaneToTab1" },
        { "command": { "action": "movePane", "index": 2 }, "id": "Terminal.MovePaneToTab2" },
        { "command": { "action": "movePane", "index": 3 }, "id": "Terminal.MovePaneToTab3" },
        { "command": "restartConnection", "id": "Terminal.RestartConnection" },
        { "command": { "action": "copy", "singleLine": false }, "id": "Terminal.CopyToClipboard" },
        { "command": "paste", "id": "Terminal.PasteFromClipboard" },
        { "command": "selectAll", "id": "Terminal.SelectAll" },
        { "command": "markMode", "id": "Terminal.ToggleMarkMode" },
        { "command": "toggleBlockSelection", "id": "Terminal.ToggleBlockSelection" },
        { "command": "switchSelectionEndpoint", "id": "Terminal.SwitchSelectionEndpoint" },
        { "command": "expandSelectionToWord", "id": "Terminal.ExpandSelectionToWord" },
        { "command": "showContextMenu", "id": "Terminal.ShowContextMenu" },
        { "command": { "action": "searchWeb" }, "id": "Terminal.SearchWeb" },
        { "command": "scrollDown", "id": "Terminal.ScrollDown" },
        { "command": "scrollDownPage", "id": "Terminal.ScrollDownPage" },
        { "command": "scrollUp", "id": "Terminal.ScrollUp" },
        { "command": "scrollUpPage", "id": "Terminal.ScrollUpPage" },
        { "command": "scrollToTop", "id": "Terminal.ScrollToTop" },
        { "command": "scrollToBottom", "id": "Terminal.ScrollToBottom" },
        { "command": { "action": "scrollToMark", "direction": "previous" }, "id": "Terminal.ScrollToPreviousMark" },
        { "command": { "action": "scrollToMark", "direction": "next" }, "id": "Terminal.ScrollToNextMark" },
        { "command": { "action": "selectCommand", "direction": "prev" }, "id": "Terminal.SelectPreviousCommand" },
        { "command": { "action": "selectOutput", "direction": "prev" }, "id": "Terminal.SelectPreviousOutput" },
        { "command": "addMark", "id": "Terminal.AddMark" },
        { "command": "clearAllMarks", "id": "Terminal.ClearAllMarks" },
        { "command": { "action": "clearBuffer", "clear": "all" }, "id": "Terminal.ClearBuffer" },
        { "command": { "action": "clearBuffer", "clear": "scrollback" }, "id": "Terminal.ClearScrollback" },
        { "command": { "action": "clearBuffer", "clear": "screen" }, "id": "Terminal.ClearScreen" },
        { "command": "exportBuffer", "id": "Terminal.ExportBuffer" },
        { "command": { "action": "adjustFontSize", "delta": 1 }, "id": "Terminal.IncreaseFontSize" },
        { "command": { "action": "adjustFontSize", "delta": -1 }, "id": "Terminal.DecreaseFontSize" },
        { "command": "resetFontSize", "id": "Terminal.ResetFontSize" },
        { "command": { "action": "adjustOpacity", "opacity": 10, "relative": true }, "id": "Terminal.IncreaseOpacity" },
        { "command": { "action": "adjustOpacity", "opacity": -10, "relative": true }, "id": "Terminal.DecreaseOpacity" },
        { "command": { "action": "adjustOpacity", "opacity": 100, "relative": false }, "id": "Terminal.ResetOpacity" },
        { "command": { "action": "setTabColor" }, "id": "Terminal.ResetTabColor" }
    ],
    "keybindings": [
        { "id": "Terminal.CloseWindow", "keys": "cmd+shift+w" },
        { "id": "Terminal.ToggleFullscreen", "keys": "cmd+ctrl+f" },
        { "id": "Terminal.ToggleFullscreen", "keys": "f11" },
        { "id": "Terminal.OpenNewTabDropdown", "keys": "cmd+shift+space" },
        { "id": "Terminal.OpenSettingsUI", "keys": "cmd+," },
        { "id": "Terminal.OpenSettingsFile", "keys": "cmd+shift+," },
        { "id": "Terminal.FindText", "keys": "cmd+f" },
        { "id": "Terminal.FindNextMatch", "keys": "cmd+g" },
        { "id": "Terminal.FindPrevMatch", "keys": "cmd+shift+g" },
        { "id": "Terminal.ToggleCommandPalette", "keys": "cmd+shift+p" },
        { "id": "Terminal.Quit", "keys": "cmd+q" },
        { "id": "Terminal.Minimize", "keys": "cmd+m" },
        { "id": "Terminal.RestoreLastClosed", "keys": "cmd+shift+t" },
        { "id": "Terminal.OpenNewTab", "keys": "cmd+t" },
        { "id": "Terminal.OpenNewTabProfile0", "keys": "cmd+shift+1" },
        { "id": "Terminal.OpenNewTabProfile1", "keys": "cmd+shift+2" },
        { "id": "Terminal.OpenNewTabProfile2", "keys": "cmd+shift+3" },
        { "id": "Terminal.OpenNewTabProfile3", "keys": "cmd+shift+4" },
        { "id": "Terminal.OpenNewTabProfile4", "keys": "cmd+shift+5" },
        { "id": "Terminal.OpenNewTabProfile5", "keys": "cmd+shift+6" },
        { "id": "Terminal.OpenNewTabProfile6", "keys": "cmd+shift+7" },
        { "id": "Terminal.OpenNewTabProfile7", "keys": "cmd+shift+8" },
        { "id": "Terminal.OpenNewTabProfile8", "keys": "cmd+shift+9" },
        { "id": "Terminal.DuplicateTab", "keys": "cmd+shift+o" },
        { "id": "Terminal.NextTab", "keys": "ctrl+tab" },
        { "id": "Terminal.PrevTab", "keys": "ctrl+shift+tab" },
        { "id": "Terminal.NextTab", "keys": "cmd+shift+]" },
        { "id": "Terminal.PrevTab", "keys": "cmd+shift+[" },
        { "id": "Terminal.SwitchToTab0", "keys": "cmd+1" },
        { "id": "Terminal.SwitchToTab1", "keys": "cmd+2" },
        { "id": "Terminal.SwitchToTab2", "keys": "cmd+3" },
        { "id": "Terminal.SwitchToTab3", "keys": "cmd+4" },
        { "id": "Terminal.SwitchToTab4", "keys": "cmd+5" },
        { "id": "Terminal.SwitchToTab5", "keys": "cmd+6" },
        { "id": "Terminal.SwitchToTab6", "keys": "cmd+7" },
        { "id": "Terminal.SwitchToTab7", "keys": "cmd+8" },
        { "id": "Terminal.SwitchToLastTab", "keys": "cmd+9" },
        { "id": "Terminal.ClosePane", "keys": "cmd+w" },
        { "id": "Terminal.SplitPaneRight", "keys": "cmd+d" },
        { "id": "Terminal.SplitPaneDown", "keys": "cmd+shift+d" },
        { "id": "Terminal.DuplicatePaneDown", "keys": "alt+shift+-" },
        { "id": "Terminal.DuplicatePaneRight", "keys": "alt+shift+plus" },
        { "id": "Terminal.ResizePaneDown", "keys": "cmd+ctrl+down" },
        { "id": "Terminal.ResizePaneLeft", "keys": "cmd+ctrl+left" },
        { "id": "Terminal.ResizePaneRight", "keys": "cmd+ctrl+right" },
        { "id": "Terminal.ResizePaneUp", "keys": "cmd+ctrl+up" },
        { "id": "Terminal.MoveFocusDown", "keys": "cmd+alt+down" },
        { "id": "Terminal.MoveFocusLeft", "keys": "cmd+alt+left" },
        { "id": "Terminal.MoveFocusRight", "keys": "cmd+alt+right" },
        { "id": "Terminal.MoveFocusUp", "keys": "cmd+alt+up" },
        { "id": "Terminal.MoveFocusPreviousInOrder", "keys": "cmd+[" },
        { "id": "Terminal.MoveFocusNextInOrder", "keys": "cmd+]" },
        { "id": "Terminal.TogglePaneZoom", "keys": "cmd+shift+enter" },
        { "id": "Terminal.CopyToClipboard", "keys": "cmd+c" },
        { "id": "Terminal.PasteFromClipboard", "keys": "cmd+v" },
        { "id": "Terminal.SelectAll", "keys": "cmd+a" },
        { "id": "Terminal.ToggleMarkMode", "keys": "cmd+shift+m" },
        { "id": "Terminal.ShowContextMenu", "keys": "menu" },
        { "id": "Terminal.ScrollDown", "keys": "cmd+shift+down" },
        { "id": "Terminal.ScrollUp", "keys": "cmd+shift+up" },
        { "id": "Terminal.ScrollDownPage", "keys": "shift+pgdn" },
        { "id": "Terminal.ScrollUpPage", "keys": "shift+pgup" },
        { "id": "Terminal.ScrollToTop", "keys": "cmd+home" },
        { "id": "Terminal.ScrollToBottom", "keys": "cmd+end" },
        { "id": "Terminal.ScrollToTop", "keys": "shift+home" },
        { "id": "Terminal.ScrollToBottom", "keys": "shift+end" },
        { "id": "Terminal.ScrollToPreviousMark", "keys": "cmd+up" },
        { "id": "Terminal.ScrollToNextMark", "keys": "cmd+down" },
        { "id": "Terminal.SelectPreviousCommand", "keys": "cmd+shift+left" },
        { "id": "Terminal.SelectPreviousOutput", "keys": "cmd+shift+right" },
        { "id": "Terminal.ClearBuffer", "keys": "cmd+k" },
        { "id": "Terminal.ExportBuffer", "keys": "cmd+s" },
        { "id": "Terminal.IncreaseFontSize", "keys": "cmd+plus" },
        { "id": "Terminal.DecreaseFontSize", "keys": "cmd+minus" },
        { "id": "Terminal.ResetFontSize", "keys": "cmd+0" },
        { "id": "Terminal.OpenTabRenamer", "keys": "cmd+shift+i" },
        { "id": "Terminal.OpenAboutDialog", "keys": "cmd+shift+/" }
    ]
}
"""
