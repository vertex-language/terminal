package workspace

import "ui/state"

/// One line of the command palette, a menu, or the tab switcher.
struct Item: Equatable {
    var ID: int
    var Label: string
    /// The keys bound to it, or a profile's or a tab's detail.
    var Detail: string = ""
    /// A line between groups, not an item.
    var Separator: bool = false
    var Disabled: bool = false
    /// Opens a submenu (palette: a nested list) rather than running.
    var Nested: bool = false
    var Swatch: string = ""
}

/// What the window shows over the terminal: the search box, the command
/// palette, a menu, a dialog, a toast. Read by the markup; written by
/// the controller.
@Observable @MainActor
final class UI {
    // Find.
    var Search = false
    var SearchText = ""
    var SearchCase = false
    var SearchStatus = ""
    // The command palette, and its other modes: "commands", "tabs" (tab
    // search), "switcher" (⌃Tab), a nested list's name.
    var Palette = false
    var PaletteMode = "commands"
    var PaletteText = ""
    var PaletteIndex = 0
    var PaletteItems: [Item] = []
    /// The items shown: a window of the list around the selected one.
    var PaletteShown: [Item] = []
    var PaletteTitle = ""
    // A menu: its items and where it is (CSS pixels in the window).
    var Menu = false
    var MenuX: float32 = 0
    var MenuY: float32 = 0
    var MenuItems: [Item] = []
    // A dialog: a title, a message, and buttons (the first the default).
    var Dialog = false
    var DialogTitle = ""
    var DialogBody = ""
    var DialogButtons: [Item] = []
    // A tab being renamed, and what is typed.
    var Renaming = 0
    var RenameText = ""
    // The window's title being renamed.
    var RenamingWindow = false
    // A toast at the bottom: a line that goes by itself.
    var Toast = ""
    var toastEpoch = 0
    // The link under the pointer, shown at the bottom left.
    var Hover = ""
    // The tab bar is hidden (focus mode).
    var FocusMode = false
    // The tab being dragged to a new place, or 0, and how far it is from
    // its place in the bar (CSS pixels).
    var Dragging = 0
    var DragShift: float32 = 0
    var WindowName = ""
    /// The terminal's background and text colors: the tab in front is
    /// drawn in them, so it joins the terminal under it.
    var SurfaceColor = ""
    /// The tabs are in the window's title bar, beside its buttons; not
    /// while it fills the screen.
    var InTitlebar = false
    var Fullscreen = false
    var SurfaceText = ""
    // The settings tab: open, in front of the terminals, its page, what
    // its search box says, and a count that moves when the settings
    // change (the page reads it to be drawn again).
    var SettingsOpen = false
    var SettingsShown = false
    var SettingsPage = "startup"
    var SettingsQuery = ""
    var SettingsRev = 0

    init() {}

    /// Whether anything over the terminal has the keyboard.
    var Overlay: bool { return Search || Palette || Menu || Dialog || Renaming != 0 || RenamingWindow }
}
