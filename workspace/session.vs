package workspace

import (
    "encoding/json"
    "fs"
)

// The window's layout kept across launches, as Windows Terminal's
// "firstWindowPreference": "persistedWindowLayout" keeps it: the tabs,
// how their panes are split, each pane's profile and directory, and the
// text it showed (drawn again, plain, before its shell starts).

/// Where the layout is kept: beside settings.json.
func sessionPath(_ settingsFile: string) -> string {
    return parentDir(settingsFile) + "/state.json"
}

extension Controller {
    /// Writes the layout, for the next launch.
    func saveSession() {
        if fixedSettings || settings.FirstWindowPreference != "persistedWindowLayout" { return }
        var tabs: [json.Value] = []
        for t in ws.Tabs {
            var o = json.Object()
            o["title"] = .string(t.CustomTitle)
            o["color"] = .string(t.Color)
            o["focused"] = .number("\(t.Panes.firstIndex(where: { $0.ID == t.Focused }) ?? 0)")
            o["layout"] = nodeJSON(t.root)
            tabs.append(.object(o))
        }
        var root = json.Object()
        root["tabs"] = .array(tabs)
        root["active"] = .number("\(ws.Index(of: ws.Active) ?? 0)")
        try? fs.WriteText(fs.Path(sessionPath(settingsFile)), json.Encode(.object(root), indent: "  "), atomic: true)
    }

    func nodeJSON(_ n: PaneNode) -> json.Value {
        var o = json.Object()
        if let p = n.pane {
            o["profile"] = .string(p.profile.Guid)
            if let d = p.shell.Directory { o["dir"] = .string(d) }
            // The last screenful or so of text, to draw again.
            let t = p.shell.term
            let last = t.ScrollbackCount + t.CursorY
            let first = max(0, last - 500)
            o["text"] = .string(t.Text(fromColumn: 0, line: first, toColumn: t.Columns - 1, line: max(first, last - 1)))
            return .object(o)
        }
        o["split"] = .string(n.vertical ? "vertical" : "horizontal")
        o["ratio"] = .number("\(n.ratio)")
        if let f = n.first { o["first"] = nodeJSON(f) }
        if let s = n.second { o["second"] = nodeJSON(s) }
        return .object(o)
    }

    /// Opens the tabs the last session had; false where there was none.
    func restoreSession() -> bool {
        if fixedSettings || settings.FirstWindowPreference != "persistedWindowLayout" { return false }
        let path = sessionPath(settingsFile)
        guard let text = try? fs.ReadText(fs.Path(path)), let v = try? json.Parse(text), let tabs = v["tabs"]?.Array, !tabs.isEmpty else {
            return false
        }
        var starts: [(Pane, string?)] = []
        for tv in tabs {
            guard let layout = tv["layout"] else { continue }
            guard let root = buildNode(layout, &starts) else { continue }
            let leaves = root.Leaves
            guard let first = leaves.first else { continue }
            let tab = Tab(id: ws.next, pane: first)
            ws.next += 1
            tab.root = root
            root.parent = nil
            let fi = int(tv["focused"]?.Int ?? 0)
            tab.Focus(fi < leaves.count ? leaves[fi].ID : first.ID)
            tab.CustomTitle = tv["title"]?.String ?? ""
            tab.Color = tv["color"]?.String ?? ""
            tab.Icon = first.profile.Icon
            tab.changed()
            ws.Tabs.append(tab)
        }
        if ws.Tabs.isEmpty { return false }
        let active = int(v["active"]?.Int ?? 0)
        Select(ws.Tabs[min(max(0, active), ws.Tabs.count - 1)].ID)
        for (p, d) in starts { start(p, dir: d) }
        for t in ws.Tabs { UpdateTitle(t) }
        // Used once: a crash later shouldn't bring back old tabs.
        try? fs.Remove(fs.Path(path))
        return true
    }

    func buildNode(_ v: json.Value, _ starts: inout [(Pane, string?)]) -> PaneNode? {
        if let split = v["split"]?.String {
            guard let fv = v["first"], let sv = v["second"], let f = buildNode(fv, &starts), let s = buildNode(sv, &starts) else { return nil }
            let ratio = float32(v["ratio"]?.Double ?? 0.5)
            return PaneNode(first: f, second: s, vertical: split == "vertical", ratio: max(0.05, min(0.95, ratio)))
        }
        let p = settings.ProfileNamed(v["profile"]?.String)
        let dir = v["dir"]?.String
        let pane = makePane(p, dir: dir)
        if let text = v["text"]?.String, !text.isEmpty {
            // The old text, then a note, then the new shell's prompt.
            var lines: [string] = []
            for l in text.split(separator: "\n", omittingEmptySubsequences: false) { lines.append(String(l)) }
            while let l = lines.last, trimRight(l).isEmpty { lines.removeLast() }
            if !lines.isEmpty {
                pane.shell.term.Feed(lines.joined(separator: "\r\n") + "\r\n\u{1b}[90m[restored]\u{1b}[0m\r\n")
            }
        }
        starts.append((pane, dir))
        return PaneNode(pane: pane)
    }
}
