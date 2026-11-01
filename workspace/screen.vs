package workspace

import "ui/viewport"

/// The terminal's screen: the panes, drawn into the window's viewport.
/// Input reaches the surface around it, which routes it to the panes.
@MainActor
final class Screen: viewport.Source {
    unowned let c: Controller

    init(_ c: Controller) {
        self.c = c
        super.init()
    }

    override func Attached(_ handle: viewport.Handle) {
        c.handle = handle
    }

    override func Detached() {
        c.handle = nil
    }

    override func Draw(_ f: viewport.Frame) -> [uint8] {
        return c.Draw(f.Width, f.Height, f.Time)
    }
}
