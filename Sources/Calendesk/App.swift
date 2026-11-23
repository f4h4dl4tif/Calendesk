import SwiftUI
import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set only by "Quit Calendesk" in the menu bar icon (or logout/shutdown).
    static var allowTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            #if DEBUG
            if CommandLine.arguments.contains("--glass-snapshot") { GlassSnapshot.runIfRequested(); return }
            #endif
            Snapshot.runIfRequested()
            let settings = CalendarSettings.shared
            settings.applyAppearance()
            _ = DayClock.shared
            EventStore.shared.start()
            settings.startTickdeskSync()
            DesktopWidgetController.shared.sync()
            DockPresence.shared.start()
        }
        // Never block a logout, restart or shutdown.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            AppDelegate.allowTermination = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.allowTermination || Self.isSystemQuit() { return .terminateNow }
        // ⌘Q / Dock "Quit": close the app's windows but keep the widget and menu bar icon.
        MainActor.assumeIsolated { DockPresence.shared.closeAppWindows() }
        return .terminateCancel
    }

    /// True when macOS itself is quitting apps (logout, restart, shutdown).
    private static func isSystemQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
              let reason = event.attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue
        else { return false }
        return [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog,
                kAERestart, kAEShutDown].contains(reason)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppActions.shared.open("main") } }
        return true
    }
}

/// Shows the Dock icon only while a Calendesk window is open; the widget and the
/// menu bar icon keep running without it.
@MainActor
final class DockPresence {
    static let shared = DockPresence()

    func start() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let w = note.object as? NSWindow, Self.isAppWindow(w) { self.showInDock() }
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let closing = note.object as? NSWindow else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.updateAfterClosing(closing) }
            }
        }
    }

    private static func isAppWindow(_ w: NSWindow) -> Bool {
        !(w is NSPanel) && w.canBecomeMain
    }

    func showInDock() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    private func updateAfterClosing(_ closing: NSWindow) {
        let stillOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && Self.isAppWindow($0) }
        if !stillOpen {
            NSApp.setActivationPolicy(.accessory)
            Self.releaseFreedMemory()
        }
    }

    func closeAppWindows() {
        for w in NSApp.windows where Self.isAppWindow(w) && w.isVisible { w.close() }
        NSApp.setActivationPolicy(.accessory)
        DesktopWidgetController.shared.sync()
        Self.releaseFreedMemory()
    }

    /// Once only the widget is left, hand the pages freed by the closed windows back to macOS
    /// (malloc otherwise keeps them reserved for the process).
    static func releaseFreedMemory() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }
}

@main
struct CalendeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let settings = CalendarSettings.shared

    var body: some Scene {
        Window("Calendesk", id: "main") {
            MainView()
                .environment(settings)
        }
        .defaultSize(width: 920, height: 680)
        .commands { AppCommands() }

        Window("Calendesk Settings", id: "settings") {
            SettingsView()
                .environment(settings)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContent()
                .environment(settings)
        } label: {
            MenuBarLabel()
                .environment(settings)
        }
    }
}

private struct MenuBarLabel: View {
    @Environment(CalendarSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let today = DayClock.shared.today
        Group {
            switch settings.config.menuBar {
            case .icon: Image(systemName: "calendar")
            case .day: Text("\(Image(systemName: "calendar")) \(Fmt.dayNumber(today))")
            case .short: Text(Fmt.string(today, template: "EEEMMMd"))
            }
        }
        .onAppear { AppActions.shared.openWindow = openWindow }
    }
}

private struct MenuContent: View {
    @Environment(CalendarSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings
        let today = DayClock.shared.today
        let store = EventStore.shared
        Text(Fmt.string(today, template: "EEEEMMMMdyyyy"))
        if settings.config.showEvents && store.hasAccess {
            let events = store.events(on: today, config: settings.config)
                .filter { $0.isAllDay || $0.end > DayClock.shared.now }
            if events.isEmpty {
                Text("No more events today")
            } else {
                ForEach(events.prefix(6)) { e in
                    Text("\(e.timeLabel(use24h: settings.config.use24h, on: today))  \(e.title)")
                }
            }
        }
        Divider()
        Button("Open Calendesk") { open("main") }
        Toggle("Show Desktop Widget", isOn: $settings.config.widgetVisible)
        Toggle("Show Events", isOn: $settings.config.showEvents)
        Picker("Appearance", selection: $settings.config.appearance) {
            ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
        }
        Picker("Calendar Style", selection: $settings.config.face) {
            ForEach(CalendarStyle.allCases) { Text($0.title).tag($0) }
        }
        Picker("Colors", selection: $settings.config.presetID) {
            ForEach(ColorPreset.all) { Text($0.name).tag($0.id) }
            Text("Custom").tag("custom")
        }
        Divider()
        Button("Open Calendar App") { AppActions.openCalendarApp() }
        Button("Settings…") { open("settings") }.keyboardShortcut(",")
        Button("Quit Calendesk") {
            AppDelegate.allowTermination = true
            NSApp.terminate(nil)
        }
    }

    private func open(_ id: String) {
        DockPresence.shared.showInDock()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

private struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) { OpenWindowButton(title: "Settings…", id: "settings", key: ",") }
        CommandGroup(replacing: .appTermination) {
            Button("Close Calendesk (Widget Stays)") { DockPresence.shared.closeAppWindows() }
                .keyboardShortcut("q")
        }
        CommandGroup(after: .windowArrangement) {
            Button("Toggle Desktop Widget") { DesktopWidgetController.shared.toggle() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}

private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    let title: String
    let id: String
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    var body: some View {
        Button(title) { openWindow(id: id) }.keyboardShortcut(key, modifiers: modifiers)
    }
}
