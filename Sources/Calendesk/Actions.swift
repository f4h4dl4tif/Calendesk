import SwiftUI
import AppKit

/// Bridges AppKit code (widget menu) to SwiftUI window opening.
@MainActor
final class AppActions {
    static let shared = AppActions()
    var openWindow: OpenWindowAction?

    func open(_ id: String) {
        DockPresence.shared.showInDock()
        NSApp.activate(ignoringOtherApps: true)
        openWindow?(id: id)
    }

    static func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
