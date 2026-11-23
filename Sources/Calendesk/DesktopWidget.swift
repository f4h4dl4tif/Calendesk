import SwiftUI
import AppKit

private final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var scrollAccum: CGFloat = 0
    private var lastFlip = Date.distantPast

    /// Scroll or swipe over the month grid to browse months.
    override func scrollWheel(with e: NSEvent) {
        let c = CalendarSettings.shared.config
        guard (c.widgetFace ?? c.face) == .month else { return }
        if e.momentumPhase != [] { return } // ignore inertia so one swipe = one month
        if e.phase == .began { scrollAccum = 0 }
        let raw = abs(e.scrollingDeltaY) >= abs(e.scrollingDeltaX) ? e.scrollingDeltaY : e.scrollingDeltaX
        scrollAccum += e.hasPreciseScrollingDeltas ? raw : raw * 12
        guard abs(scrollAccum) > 36, Date().timeIntervalSince(lastFlip) > 0.28 else { return }
        let delta = scrollAccum > 0 ? -1 : 1
        scrollAccum = 0
        lastFlip = Date()
        MainActor.assumeIsolated { DesktopWidgetController.shared.navigate(delta) }
    }
}

/// Clicks work on the first press even though the widget never becomes the key window.
private final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct WidgetSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// The borderless calendar that lives on the desktop.
@Observable
@MainActor
final class DesktopWidgetController {
    static let shared = DesktopWidgetController()
    private static let topLeftKey = "Calendesk.widget.topLeft"

    @ObservationIgnored private(set) var panel: NSPanel?
    @ObservationIgnored private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    /// Months browsed away from the current one.
    var monthOffset = 0
    /// Day picked on the grid; nil means today.
    var selectedDay: Date?
    /// Direction of the last month change, for the slide animation.
    var lastDelta = 1

    func sync() {
        let c = CalendarSettings.shared.config
        guard c.widgetVisible else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil { createPanel() }
        guard let panel else { return }
        panel.level = c.widgetLevel.windowLevel
        panel.alphaValue = c.widgetOpacity
        panel.orderFrontRegardless()
    }

    func toggle() {
        CalendarSettings.shared.config.widgetVisible.toggle()
    }

    /// -1 / +1 browse months, 0 returns to today.
    func navigate(_ delta: Int) {
        withAnimation(.snappy(duration: 0.34)) {
            if delta == 0 {
                lastDelta = monthOffset > 0 ? -1 : 1
                monthOffset = 0
                selectedDay = nil
            } else {
                lastDelta = delta
                monthOffset += delta
            }
        }
    }

    private func createPanel() {
        let panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        // The panel is sized from the measured SwiftUI content (see `fit`), never squeezed.
        let host = WidgetHostingView(rootView: WidgetRootView().environment(CalendarSettings.shared))
        host.sizingOptions = []
        panel.contentView = host

        let topLeft: NSPoint
        if let saved = UserDefaults.standard.string(forKey: Self.topLeftKey) {
            topLeft = NSPointFromString(saved)
        } else if let vf = NSScreen.main?.visibleFrame {
            topLeft = NSPoint(x: vf.maxX - 420, y: vf.maxY - 40)
        } else {
            topLeft = NSPoint(x: 200, y: 800)
        }
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - 420, width: 360, height: 420), display: false)
        self.panel = panel
    }

    /// Resizes the panel to the content, keeping the top-left corner where the user put it.
    func fit(_ size: CGSize) {
        guard let panel, size.width > 10, size.height > 10, dragStart == nil else { return }
        let w = ceil(size.width), h = ceil(size.height)
        guard abs(panel.frame.width - w) > 0.5 || abs(panel.frame.height - h) > 0.5 else { return }
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - h, width: w, height: h)
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame {
            // Keep it reachable if it grew past a screen edge.
            frame.origin.x = min(max(frame.minX, vf.minX - 16), vf.maxX - w + 16)
            frame.origin.y = min(max(frame.minY, vf.minY - 16), vf.maxY - h + 16)
        }
        panel.setFrame(frame, display: true)
    }

    // Manual dragging so it works at desktop level and respects the lock.
    func dragChanged() {
        guard let panel, !CalendarSettings.shared.config.widgetLocked else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    func dragEnded() {
        dragStart = nil
        if let panel {
            let tl = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            UserDefaults.standard.set(NSStringFromPoint(tl), forKey: Self.topLeftKey)
        }
    }
}

private struct WidgetRootView: View {
    @Environment(CalendarSettings.self) private var settings
    private var controller: DesktopWidgetController { .shared }

    var body: some View {
        @Bindable var settings = settings
        let today = DayClock.shared.today
        let month = Calendar.current.date(byAdding: .month, value: controller.monthOffset, to: today) ?? today
        let selection = Binding<Date>(
            get: { controller.selectedDay ?? today },
            set: { controller.selectedDay = Calendar.current.isDate($0, inSameDayAs: today) ? nil : $0 })

        CalendarFace(style: settings.config.widgetFace,
                     size: 14 * settings.config.widgetScale,
                     showsBackground: settings.config.widgetBackground,
                     month: month,
                     selected: selection,
                     onNavigate: { controller.navigate($0) },
                     navEdge: controller.lastDelta < 0 ? .leading : .trailing,
                     showsDayFooter: true,
                     hoverScope: "widget")
            .padding(16) // room for shadows
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { AppActions.shared.open("main") }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in controller.dragChanged() }
                    .onEnded { _ in controller.dragEnded() }
            )
            .fixedSize()
            .background(GeometryReader { g in
                Color.clear.preference(key: WidgetSizeKey.self, value: g.size)
            })
            .onPreferenceChange(WidgetSizeKey.self) { size in
                MainActor.assumeIsolated { controller.fit(size) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: today) {
                controller.monthOffset = 0
                controller.selectedDay = nil
            }
            .contextMenu {
                Picker("Widget Style", selection: $settings.config.widgetFace) {
                    Text("Same as Main Calendar").tag(CalendarStyle?.none)
                    Divider()
                    ForEach(CalendarStyle.allCases) { Text($0.title).tag(CalendarStyle?.some($0)) }
                }
                Picker("Appearance", selection: $settings.config.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Colors", selection: $settings.config.presetID) {
                    ForEach(ColorPreset.all) { Text($0.name).tag($0.id) }
                    Text("Custom").tag("custom")
                }
                Picker("Position", selection: $settings.config.widgetLevel) {
                    ForEach(WidgetLevel.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show Events", isOn: $settings.config.showEvents)
                Toggle("Show Week Numbers", isOn: $settings.config.showWeekNumbers)
                Toggle("Show Background", isOn: $settings.config.widgetBackground)
                if GlassSupport.isAvailable {
                    Toggle("Liquid Glass", isOn: $settings.config.glassTheme)
                }
                Toggle("Lock Position", isOn: $settings.config.widgetLocked)
                Divider()
                Button("Go to Today") { controller.navigate(0) }
                Button("Open Calendesk") { AppActions.shared.open("main") }
                Button("Settings…") { AppActions.shared.open("settings") }
                Button("Hide Widget") { settings.config.widgetVisible = false }
            }
    }
}
