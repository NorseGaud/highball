import SwiftUI
import AppKit

/// Hands a SwiftUI view's hosting NSWindow to a callback once it exists. Used to mark the
/// Settings window non-restorable (issue #58): macOS window restoration otherwise brings a
/// Settings window that was open at quit back at the next launch, and SwiftUI then skips
/// opening the default main window because a window was already restored.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let window = nsView.window { configure(window) } }
    }
}

/// The main (library) window must exist whenever the app is in front of the user. SwiftUI opens
/// it at launch on its own, except when window restoration restored something else first; and a
/// dock click with only Settings visible does not reopen it either. Views that can appear without
/// a main window register an opener here, and the delegate and Settings ask for one when needed.
@MainActor
enum MainWindow {
    /// Set from a view's onAppear: `{ openWindow(id: "main") }`.
    static var opener: (() -> Void)?

    static func isMain(_ window: NSWindow) -> Bool {
        (window.identifier?.rawValue.hasPrefix("main") ?? false) || window.title == "Highball"
    }

    static var isOpen: Bool {
        NSApp.windows.contains { isMain($0) && ($0.isVisible || $0.isMiniaturized) }
    }

    /// Opens the main window if none is open; a no-op when one already is.
    ///
    /// With no view on screen there is no opener: a session saved with only Settings open
    /// ("Quit and Keep Windows", or any quit with "Close windows when quitting an application"
    /// turned off) restores zero windows, SwiftUI then opens none either, and every later launch
    /// came back with no window at all (2026-10-06, three gate runs). The main window group's
    /// own File > New Window command opens it then, found by its ⌘N shortcut so the menu's
    /// language does not matter.
    static func ensureOpen() {
        guard !isOpen else { return }
        if let opener { opener(); return }
        for menu in (NSApp.mainMenu?.items ?? []).compactMap(\.submenu) {
            if let index = menu.items.firstIndex(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }) {
                menu.performActionForItem(at: index)
                return
            }
        }
    }
}
