package workspace

import (
    "terminal/view"
    "ui/state"
)

/// A pane: a shell, the renderer that draws it, the profile it was made
/// from, and where it was last laid out (device pixels in the surface).
@MainActor
final class Pane {
    let ID: int
    let shell: Shell
    let renderer: view.Renderer
    var profile: Profile
    var X = 0
    var Y = 0
    var W = 0
    var H = 0
    /// Input is refused (toggleReadOnlyMode).
    var ReadOnly = false
    /// The font size the profile asked for, before zooming.
    var baseFontSize: float32 = 13
    /// The bell's visual flash: until when it shows.
    var flashUntil: float64 = 0
    /// Its pixels have changed since they were put in the frame.
    var dirty = true
    /// Its program starts once it is laid out: where, and what.
    var pending = false
    var pendingDir: string? = nil
    var pendingCommand = ""

    init(id: int, shell: Shell, renderer: view.Renderer, profile: Profile) {
        ID = id
        self.shell = shell
        self.renderer = renderer
        self.profile = profile
    }

    /// Where its program is, or will start.
    var Directory: string? { return pending ? pendingDir : shell.Directory }

    func Contains(_ x: int, _ y: int) -> bool {
        return x >= X && x < X + W && y >= Y && y < Y + H
    }
}

/// A node of a tab's layout: a pane, or two nodes side by side
/// (vertical: a line between them runs top to bottom) or one above the
/// other, sharing the space by ratio.
@MainActor
final class PaneNode {
    var pane: Pane? = nil
    var first: PaneNode? = nil
    var second: PaneNode? = nil
    var vertical = true
    var ratio: float32 = 0.5
    weak var parent: PaneNode? = nil
    // Where the divider was laid out, for dragging it.
    var divX = 0
    var divY = 0
    var divW = 0
    var divH = 0
    var spanX = 0
    var spanY = 0
    var spanW = 0
    var spanH = 0

    init(pane: Pane) {
        self.pane = pane
    }

    init(first: PaneNode, second: PaneNode, vertical: bool, ratio: float32) {
        self.first = first
        self.second = second
        self.vertical = vertical
        self.ratio = ratio
        first.parent = self
        second.parent = self
    }

    var IsLeaf: bool { return pane != nil }

    /// The panes under it, left to right and top to bottom.
    var Leaves: [Pane] {
        if let p = pane { return [p] }
        var out: [Pane] = []
        if let f = first { out.append(contentsOf: f.Leaves) }
        if let s = second { out.append(contentsOf: s.Leaves) }
        return out
    }

    /// The leaf node holding a pane.
    func Find(_ id: int) -> PaneNode? {
        if let p = pane { return p.ID == id ? self : nil }
        if let n = first?.Find(id) { return n }
        return second?.Find(id)
    }

    /// The split nodes under it, for their dividers.
    var Splits: [PaneNode] {
        if pane != nil { return [] }
        var out: [PaneNode] = [self]
        if let f = first { out.append(contentsOf: f.Splits) }
        if let s = second { out.append(contentsOf: s.Splits) }
        return out
    }

    /// Lays its panes out in x, y, w × h, a divider of d pixels between
    /// two.
    func Layout(_ x: int, _ y: int, _ w: int, _ h: int, divider d: int) {
        if let p = pane {
            p.X = x
            p.Y = y
            p.W = max(1, w)
            p.H = max(1, h)
            return
        }
        guard let f = first, let s = second else { return }
        spanX = x
        spanY = y
        spanW = w
        spanH = h
        if vertical {
            let fw = max(1, min(w - d - 1, int(float32(w - d) * ratio)))
            divX = x + fw
            divY = y
            divW = d
            divH = h
            f.Layout(x, y, fw, h, divider: d)
            s.Layout(x + fw + d, y, w - fw - d, h, divider: d)
        } else {
            let fh = max(1, min(h - d - 1, int(float32(h - d) * ratio)))
            divX = x
            divY = y + fh
            divW = w
            divH = d
            f.Layout(x, y, w, fh, divider: d)
            s.Layout(x, y + fh + d, w, h - fh - d, divider: d)
        }
    }
}

/// A tab: its panes' layout, which pane has focus, and what its tab
/// shows.
@Observable @MainActor
final class Tab {
    let ID: int
    var root: PaneNode
    var Focused: int
    /// The pane shown alone (togglePaneZoom), or 0.
    var Zoomed = 0
    /// Panes by when they last had focus, latest first.
    var recent: [int] = []
    var Title = "Terminal"
    /// A title the user gave it (renameTab); "" follows the program.
    var CustomTitle = ""
    var Color = ""
    var Icon = ""
    /// The bell rang while the tab was behind another.
    var Bell = false
    var seenBells: [int: int] = [:]
    /// What a program said of its progress (OSC 9;4): "", "normal",
    /// "error", "indeterminate", "paused"; and the percentage.
    var Progress = ""
    var ProgressValue = 0
    /// Typing goes to every pane (toggleBroadcastInput).
    var Broadcast = false
    var ReadOnly = false
    var PaneCount = 1
    var IsZoomed = false

    init(id: int, pane: Pane) {
        ID = id
        root = PaneNode(pane: pane)
        Focused = pane.ID
        recent = [pane.ID]
    }

    var Panes: [Pane] { return root.Leaves }

    var FocusedPane: Pane? {
        for p in Panes where p.ID == Focused { return p }
        return Panes.first
    }

    /// Gives a pane focus, remembering the order.
    func Focus(_ id: int) {
        Focused = id
        recent = [id] + recent.filter { $0 != id }
        ReadOnly = FocusedPane?.ReadOnly ?? false
    }

    /// Splits the focused pane: the new one goes right, left, down or up
    /// of it, taking size of the space.
    func Split(_ pane: Pane, direction: string, size: float32 = 0.5) {
        guard let node = root.Find(Focused), let old = node.pane else { return }
        let a = PaneNode(pane: old)
        let b = PaneNode(pane: pane)
        let vertical = direction == "right" || direction == "left"
        let newFirst = direction == "left" || direction == "up"
        let r = max(0.05, min(0.95, newFirst ? size : 1 - size))
        node.pane = nil
        node.first = newFirst ? b : a
        node.second = newFirst ? a : b
        node.vertical = vertical
        node.ratio = r
        node.first!.parent = node
        node.second!.parent = node
        Zoomed = 0
        Focus(pane.ID)
        changed()
    }

    /// Takes a pane out of the layout; its sibling takes its place. False
    /// where it was the last.
    func Remove(_ id: int) -> bool {
        guard let node = root.Find(id) else { return false }
        recent = recent.filter { $0 != id }
        guard let parent = node.parent else { return false }
        let sibling = parent.first === node ? parent.second! : parent.first!
        parent.pane = sibling.pane
        parent.first = sibling.first
        parent.second = sibling.second
        parent.vertical = sibling.vertical
        parent.ratio = sibling.ratio
        parent.first?.parent = parent
        parent.second?.parent = parent
        if Zoomed == id { Zoomed = 0 }
        if Focused == id {
            let ids = Panes.map { $0.ID }
            let next = recent.first(where: { ids.contains($0) }) ?? ids.first ?? 0
            Focus(next)
        }
        changed()
        return true
    }

    /// The pane next to the focused one in a direction: the one whose
    /// edge touches it and that overlaps it most.
    func Neighbor(_ direction: string) -> Pane? {
        guard let me = FocusedPane else { return nil }
        let all = Panes
        switch direction {
        case "previous":
            for r in recent.dropFirst() {
                for p in all where p.ID == r { return p }
            }
            return nil
        case "nextInOrder", "previousInOrder":
            guard let i = all.firstIndex(where: { $0.ID == me.ID }), all.count > 1 else { return nil }
            let n = all.count
            return all[(i + (direction == "nextInOrder" ? 1 : -1) + n) % n]
        case "first":
            return all.first
        default:
            break
        }
        var best: Pane? = nil
        var bestScore = -1
        for p in all where p.ID != me.ID {
            var touches = false
            var overlap = 0
            switch direction {
            case "left":
                touches = p.X + p.W <= me.X && p.X + p.W >= me.X - 8
                overlap = min(p.Y + p.H, me.Y + me.H) - max(p.Y, me.Y)
            case "right":
                touches = p.X >= me.X + me.W && p.X <= me.X + me.W + 8
                overlap = min(p.Y + p.H, me.Y + me.H) - max(p.Y, me.Y)
            case "up":
                touches = p.Y + p.H <= me.Y && p.Y + p.H >= me.Y - 8
                overlap = min(p.X + p.W, me.X + me.W) - max(p.X, me.X)
            case "down":
                touches = p.Y >= me.Y + me.H && p.Y <= me.Y + me.H + 8
                overlap = min(p.X + p.W, me.X + me.W) - max(p.X, me.X)
            default:
                break
            }
            if !touches || overlap <= 0 { continue }
            // The most recently focused of those that touch, then the one
            // that overlaps most.
            let recency = recent.firstIndex(of: p.ID).map { 100000 - $0 } ?? 0
            let score = recency * 10000 + overlap
            if score > bestScore {
                bestScore = score
                best = p
            }
        }
        return best
    }

    /// Moves the divider nearest the focused pane that runs across the
    /// direction, by amount of its space.
    func Resize(_ direction: string, amount: float32 = 0.05) {
        let wantVertical = direction == "left" || direction == "right"
        var node = root.Find(Focused)
        while let n = node {
            if let p = n.parent, p.vertical == wantVertical {
                let grow = direction == "right" || direction == "down"
                p.ratio = max(0.05, min(0.95, p.ratio + (grow ? amount : -amount)))
                changed()
                return
            }
            node = n.parent
        }
    }

    /// Swaps the focused pane with its neighbor; focus stays with it.
    func Swap(_ direction: string) {
        guard let other = Neighbor(direction), let a = root.Find(Focused), let b = root.Find(other.ID) else { return }
        let pa = a.pane
        a.pane = b.pane
        b.pane = pa
        changed()
    }

    /// Turns the split the focused pane is in: side by side becomes one
    /// above the other.
    func ToggleOrientation() {
        if let p = root.Find(Focused)?.parent {
            p.vertical = !p.vertical
            changed()
        }
    }

    func ToggleZoom() {
        Zoomed = Zoomed == 0 && Panes.count > 1 ? Focused : 0
        changed()
    }

    /// Something about the layout changed: what the tab bar shows of it.
    func changed() {
        PaneCount = Panes.count
        IsZoomed = Zoomed != 0
    }

    /// The title shown: the user's, or the focused pane's.
    var Shown: string {
        return CustomTitle.isEmpty ? Title : CustomTitle
    }
}

/// Every tab, and which is in front.
@Observable @MainActor
final class Workspace {
    var Tabs: [Tab] = []
    var Active = 0
    var next = 1
    var nextPane = 1
    /// Tabs by when they were last in front, latest first: the tab
    /// switcher's order.
    var recent: [int] = []

    init() {}

    var Current: Tab? {
        for t in Tabs where t.ID == Active { return t }
        return Tabs.first
    }

    func Index(of id: int) -> int? {
        for i in 0..<Tabs.count where Tabs[i].ID == id { return i }
        return nil
    }

    /// The tab a pane is in.
    func TabOf(pane id: int) -> Tab? {
        for t in Tabs where t.root.Find(id) != nil { return t }
        return nil
    }

    func PaneByID(_ id: int) -> Pane? {
        for t in Tabs {
            if let n = t.root.Find(id) { return n.pane }
        }
        return nil
    }
}
