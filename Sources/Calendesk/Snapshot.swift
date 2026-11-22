import SwiftUI
import AppKit

/// Developer aid: `Calendesk --snapshot <dir>` renders every style to PNG and exits.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { selfTest() }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        EventStore.shared.loadDemo(around: DayClock.shared.today)
        let settings = CalendarSettings.shared
        let saved = settings.config
        let combos: [(String, CalendarStyle, String, FontStyle, ColorScheme)] = [
            ("month-classic-light", .month, "classic", .rounded, .light),
            ("month-classic-dark", .month, "classic", .rounded, .dark),
            ("month-midnight-weeknums", .month, "midnight", .avenir, .dark),
            ("agenda-sunset-light", .agenda, "sunset", .futura, .light),
            ("agenda-neon-dark", .agenda, "neon", .din, .dark),
            ("day-rose-light", .day, "rose", .didot, .light),
            ("day-lcd-dark", .day, "lcd", .menlo, .dark),
            ("week-forest-light", .week, "forest", .sfPro, .light),
            ("week-lavender-dark", .week, "lavender", .serif, .dark),
        ]
        var c = settings.config
        c.showEvents = true
        for (name, style, preset, font, scheme) in combos {
            c.face = style
            c.presetID = preset
            c.font = font
            c.showWeekNumbers = name.contains("weeknums")
            let view = CalendarFace(size: 16, showsBackground: true)
                .padding(24)
                .environment(settings)
                .environment(\.previewConfig, c)
                .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        // Widget while browsing months: the footprint must stay identical.
        c.face = .month
        c.presetID = "classic"
        c.font = .rounded
        var sizes = Set<String>()
        for offset in [0, 1, 2, 3, 6, 9, 10, 12, 13, -1, -2] {
            let today = DayClock.shared.today
            let m = Calendar.current.date(byAdding: .month, value: offset, to: today)!
            let sel = offset == 0 ? Calendar.current.date(byAdding: .day, value: 2, to: today)! : m
            let view = CalendarFace(size: 14, showsBackground: true, month: m,
                                    selected: .constant(sel), onNavigate: { _ in },
                                    showsDayFooter: true, hoverScope: "widget")
                .padding(16)
                .fixedSize()
                .environment(settings)
                .environment(\.previewConfig, c)
                .environment(\.colorScheme, offset % 2 == 0 ? .light : .dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                sizes.insert("\(Int(img.size.width))x\(Int(img.size.height))")
                try? png.write(to: dir.appendingPathComponent("widget-month\(offset >= 0 ? "+" : "")\(offset).png"))
            }
        }
        print("widget sizes while browsing:", sizes.sorted(), sizes.count == 1 ? "PASS stable" : "FAIL changes size")

        for scheme in [ColorScheme.light, .dark] {
            let main = MainView().environment(settings).environment(\.colorScheme, scheme)
                .frame(width: 940, height: 660)
            let r = ImageRenderer(content: main)
            r.scale = 1
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("main-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        settings.config = saved
        exit(0)
    }

    /// Checks that Settings edits stay a draft until saved, and the month grid maths.
    private static func selfTest() {
        let s = CalendarSettings.shared
        let saved = s.config
        func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg) }
        s.draft.font = s.config.font == .futura ? .didot : .futura
        check(s.hasUnsavedChanges, "editing the draft marks unsaved changes")
        check(s.config.font == saved.font, "the live calendar is unchanged before Save")
        s.revertDraft()
        check(!s.hasUnsavedChanges && s.draft == s.config, "Revert discards the draft")
        s.draft.showWeekNumbers.toggle()
        s.saveDraft()
        check(s.config.showWeekNumbers != saved.showWeekNumbers && !s.hasUnsavedChanges, "Save applies the draft")
        s.config.highlightWeekends.toggle()
        check(s.draft.highlightWeekends == s.config.highlightWeekends, "quick toggles keep a clean draft in sync")
        s.draft.presetID = "neon"
        s.config.showEvents.toggle()
        check(s.draft.presetID == "neon", "quick toggles don't wipe unsaved edits")
        s.config = saved
        s.draft = saved

        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let nov = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let g = MonthGrid(month: nov, cal: cal)
        check(g.days.count == 42, "month grid has 6 full weeks")
        check(cal.component(.day, from: g.days[0]) == 26 && cal.component(.month, from: g.days[0]) == 10,
              "Monday-first Nov 2026 grid starts on Mon Oct 26")
        check(g.weekdaySymbols.first == cal.veryShortStandaloneWeekdaySymbols[1], "header starts on Monday")
        cal.firstWeekday = 1
        let g2 = MonthGrid(month: nov, cal: cal)
        check(cal.component(.day, from: g2.days[0]) == 1 && cal.component(.month, from: g2.days[0]) == 11,
              "Sunday-first Nov 2026 grid starts on Sun Nov 1")

        let old = #"{"appearance":"dark","presetID":"neon"}"#.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(CalendarConfig.self, from: old)
        check(decoded?.appearance == .dark && decoded?.widgetVisible == true, "partial saved config decodes with defaults")
        exit(0)
    }
}
