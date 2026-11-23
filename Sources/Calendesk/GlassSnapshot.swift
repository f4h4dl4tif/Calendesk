#if DEBUG
import SwiftUI
import AppKit
import Darwin

/// Developer aid: `Calendesk --glass-snapshot <dir>` opens the widget, main window and
/// Settings with Liquid Glass off and on, in light and dark, captures each real on-screen
/// window (ImageRenderer can't draw glass), writes PNGs and quits. Saved settings are restored.
@MainActor
enum GlassSnapshot {
    private typealias CapFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static var jobs: [(@escaping () -> Void) -> Void] = []
    private static var dir = URL(fileURLWithPath: ".")
    private static var keepAlive: [NSWindow] = []

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--glass-snapshot"), i + 1 < args.count else { return }
        dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let defaults = UserDefaults.standard
        let savedData = defaults.data(forKey: "Calendesk.config.v1")
        let savedTopLeft = defaults.string(forKey: "Calendesk.widget.topLeft")
        let settings = CalendarSettings.shared
        EventStore.shared.loadDemo(around: DayClock.shared.today)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let wallpaper = desktopPicture()
        let bright = Image(nsImage: brightBackdrop())
        var base = settings.config
        base.widgetVisible = false
        base.face = .month
        base.presetID = "classic"
        base.showEvents = true

        for glass in [false, true] {
            for scheme in [ColorScheme.light, .dark] {
                let tag = "\(glass ? "glass" : "plain")-\(scheme == .dark ? "dark" : "light")"
                var c = base
                c.glassTheme = glass
                c.appearance = scheme == .dark ? .dark : .light

                // Desktop widget (month, with background) over the real desktop picture.
                add("widget-\(tag)", scheme) {
                    widget(c, style: .month, background: true).padding(40)
                        .background(wallpaper.resizable().aspectRatio(contentMode: .fill))
                }
                // Every widget style over a colorful backdrop.
                add("faces-\(tag)", scheme) {
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(CalendarStyle.allCases) { s in widget(c, style: s, background: true) }
                    }
                    .padding(36)
                    .background(bright.resizable().aspectRatio(contentMode: .fill))
                }
                // Color presets.
                add("presets-\(tag)", scheme) {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(["ink", "midnight", "sunset", "lcd", "wood"], id: \.self) { id in
                            var pc = c
                            pc.presetID = id
                            return widget(pc, style: .month, background: true, scale: 0.8)
                        }
                    }
                    .padding(32)
                    .background(wallpaper.resizable().aspectRatio(contentMode: .fill))
                }
                // Widget without the background panel: cards float on the desktop.
                add("nobg-\(tag)", scheme) {
                    HStack(alignment: .top, spacing: 28) {
                        widget(c, style: .month, background: false)
                        VStack(spacing: 28) {
                            widget(c, style: .week, background: false)
                            widget(c, style: .agenda, background: false)
                        }
                    }
                    .padding(36)
                    .background(bright.resizable().aspectRatio(contentMode: .fill))
                }
                // Main window and Settings use the live config.
                jobs.append { done in settings.config = c; done() }
                addWindow("main-\(tag)", scheme, size: NSSize(width: 940, height: 660), titled: true) {
                    AnyView(MainView().environment(settings))
                }
                addWindow("settings-\(tag)", scheme, size: nil, titled: true) {
                    AnyView(SettingsView().environment(settings))
                }
            }
        }
        jobs.append { _ in
            if let savedData { defaults.set(savedData, forKey: "Calendesk.config.v1") } else { defaults.removeObject(forKey: "Calendesk.config.v1") }
            if let savedTopLeft { defaults.set(savedTopLeft, forKey: "Calendesk.widget.topLeft") } else { defaults.removeObject(forKey: "Calendesk.widget.topLeft") }
            defaults.synchronize()
            exit(0)
        }
        // Hide the window SwiftUI opens at launch, then start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            MainActor.assumeIsolated {
                for w in NSApp.windows where !keepAlive.contains(w) { w.orderOut(nil) }
                next()
            }
        }
    }

    private static func widget(_ c: CalendarConfig, style: CalendarStyle, background: Bool, scale: CGFloat = 1) -> some View {
        var cc = c
        cc.widgetBackground = background
        let today = DayClock.shared.today
        return CalendarFace(style: style, size: 14 * scale, showsBackground: background, month: today,
                            selected: .constant(today), onNavigate: { _ in },
                            showsDayFooter: true, hoverScope: "snap")
            .fixedSize()
            .environment(CalendarSettings.shared)
            .environment(\.previewConfig, cc)
    }

    private static func add<V: View>(_ name: String, _ scheme: ColorScheme, @ViewBuilder _ content: @escaping () -> V) {
        addWindow(name, scheme, size: nil, titled: false) {
            AnyView(content().environment(\.colorScheme, scheme))
        }
    }

    private static func addWindow(_ name: String, _ scheme: ColorScheme, size: NSSize?, titled: Bool,
                                  _ content: @escaping () -> AnyView) {
        jobs.append { done in
            let host = NSHostingController(rootView: content())
            host.sceneBridgingOptions = [.toolbars, .title]
            let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
            let win = NSWindow(contentViewController: host)
            win.styleMask = style
            win.title = titled ? "Calendesk" : ""
            win.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            win.isReleasedWhenClosed = false
            let s = size ?? host.view.fittingSize
            win.setContentSize(s)
            win.setFrameOrigin(NSPoint(x: 80, y: 80))
            win.level = .floating
            win.orderFrontRegardless()
            win.makeKey()
            keepAlive.append(win)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                MainActor.assumeIsolated {
                    capture(win, name)
                    win.orderOut(nil)
                    done()
                }
            }
        }
    }

    private static func next() {
        guard !jobs.isEmpty else { return }
        let job = jobs.removeFirst()
        job { DispatchQueue.main.async { MainActor.assumeIsolated { next() } } }
    }

    private static func capture(_ win: NSWindow, _ name: String) {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return }
        let f = unsafeBitCast(sym, to: CapFn.self)
        guard let img = f(.null, 8, UInt32(win.windowNumber), 1 | 8)?.takeRetainedValue(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
            print("capture failed:", name)
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        print("wrote", name, win.frame, win.isVisible, win.occlusionState.contains(.visible), img.width, img.height, win.windowNumber)
    }

    private static func desktopPicture() -> Image {
        if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let img = NSImage(contentsOf: url) {
            return Image(nsImage: img)
        }
        return Image(nsImage: brightBackdrop())
    }

    /// A busy, colorful stand-in wallpaper so glass refraction is visible.
    private static func brightBackdrop() -> NSImage {
        NSImage(size: NSSize(width: 1600, height: 1000), flipped: false) { r in
            NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.35, alpha: 1),
                                NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.55, alpha: 1),
                                NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.95, alpha: 1)])?
                .draw(in: r, angle: -30)
            let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
                (0.15, 0.7, 260, .systemYellow), (0.5, 0.3, 320, .systemTeal),
                (0.8, 0.75, 280, .white), (0.35, 0.15, 200, .systemPurple), (0.65, 0.55, 160, .black),
            ]
            for (x, y, d, c) in blobs {
                c.withAlphaComponent(0.75).setFill()
                NSBezierPath(ovalIn: NSRect(x: r.width * x - d / 2, y: r.height * y - d / 2, width: d, height: d)).fill()
            }
            return true
        }
    }
}
#endif
