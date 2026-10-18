package workspace

import "ui/component"

// Dragging a tab, as a browser's: pressed and moved a few pixels, it
// leaves its place and follows the pointer; past the middle of the tab
// beside it, the two trade places; let go, it settles where it is.

extension Controller {
    func tabPressed(_ id: int, x: float32) {
        dragPress = id
        dragStartX = x
        dragMoved = false
    }

    func tabDragMove(x: float32) {
        guard dragPress != 0 else { return }
        if !dragMoved {
            if abs(x - dragStartX) < 4 { return }
            dragMoved = true
            ui.Dragging = dragPress
        }
        guard let i = ws.Index(of: dragPress), let me = boundsOf(dragPress) else {
            ui.DragShift = x - dragStartX
            return
        }
        var shift = x - dragStartX
        let center = me.X + me.Width / 2 + shift
        if i + 1 < ws.Tabs.count, let next = boundsOf(ws.Tabs[i + 1].ID), center > next.X + next.Width / 2 {
            // Past the middle of the tab on the right: it takes this one's
            // place, and this one's place moves right by its width.
            let moved = ws.Tabs.remove(at: i)
            ws.Tabs.insert(moved, at: i + 1)
            dragStartX += next.Width
            shift -= next.Width
        } else if i > 0, let prev = boundsOf(ws.Tabs[i - 1].ID), center < prev.X + prev.Width / 2 {
            let moved = ws.Tabs.remove(at: i)
            ws.Tabs.insert(moved, at: i - 1)
            dragStartX -= prev.Width
            shift += prev.Width
        }
        // Not beyond the first tab's place or the last's.
        if let idx = ws.Index(of: dragPress) {
            if idx == 0 { shift = max(0, shift) }
            if idx == ws.Tabs.count - 1 { shift = min(0, shift) }
        }
        ui.DragShift = shift
    }

    func tabDragEnd() {
        dragPress = 0
        dragMoved = false
        ui.Dragging = 0
        ui.DragShift = 0
    }

    /// A tab's place in the bar: where it is drawn, less the shift of the
    /// one being dragged (its place in the flow).
    func boundsOf(_ id: int) -> (X: float32, Width: float32)? {
        guard let n = tabNodes[id], let r = component.Bounds(of: n) else { return nil }
        let shift: float32 = ui.Dragging == id ? ui.DragShift : 0
        return (X: r.X - shift, Width: r.Width)
    }
}
