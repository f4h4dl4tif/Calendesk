import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Options (same set as Tickdesk, so the two apps look alike)

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum CalendarStyle: String, CaseIterable, Identifiable, Codable {
    case month, agenda, day, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "Month Grid"
        case .agenda: "Agenda"
        case .day: "Day Page"
        case .week: "Week Strip"
        }
    }
    var symbol: String {
        switch self {
        case .month: "calendar"
        case .agenda: "list.bullet.rectangle"
        case .day: "doc.text.image"
        case .week: "rectangle.split.3x1"
        }
    }
}

enum FontStyle: String, CaseIterable, Identifiable, Codable {
    case rounded, sfPro, mono, serif, avenir, futura, din, helvetica, gillSans, didot, georgia, menlo, courier, typewriter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rounded: "SF Rounded"
        case .sfPro: "SF Pro"
        case .mono: "SF Mono"
        case .serif: "New York (Serif)"
        case .avenir: "Avenir Next"
        case .futura: "Futura"
        case .din: "DIN Alternate"
        case .helvetica: "Helvetica Neue"
        case .gillSans: "Gill Sans"
        case .didot: "Didot"
        case .georgia: "Georgia"
        case .menlo: "Menlo"
        case .courier: "Courier New"
        case .typewriter: "American Typewriter"
        }
    }
    private var familyName: String? {
        switch self {
        case .rounded, .sfPro, .mono, .serif: nil
        case .avenir: "Avenir Next"
        case .futura: "Futura"
        case .din: "DIN Alternate"
        case .helvetica: "Helvetica Neue"
        case .gillSans: "Gill Sans"
        case .didot: "Didot"
        case .georgia: "Georgia"
        case .menlo: "Menlo"
        case .courier: "Courier New"
        case .typewriter: "American Typewriter"
        }
    }
    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .sfPro: return .system(size: size, weight: weight, design: .default)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        default: return Font.custom(familyName ?? "Helvetica", size: size).weight(weight)
        }
    }
}

enum FontWeightOption: String, CaseIterable, Identifiable, Codable {
    case thin, light, regular, medium, semibold, bold, heavy, black
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var weight: Font.Weight {
        switch self {
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

enum FirstWeekday: String, CaseIterable, Identifiable, Codable {
    case system, sunday, monday, saturday
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System setting"
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .saturday: "Saturday"
        }
    }
    var value: Int? {
        switch self {
        case .system: nil
        case .sunday: 1
        case .monday: 2
        case .saturday: 7
        }
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable, Codable {
    case icon, day, short
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: "Icon only"
        case .day: "Icon + day (20)"
        case .short: "Date (Fri, Nov 20)"
        }
    }
}

enum WidgetLevel: String, CaseIterable, Identifiable, Codable {
    case desktop, normal, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: "On desktop (behind windows)"
        case .normal: "Normal window"
        case .floating: "Always on top"
        }
    }
    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .normal: .normal
        case .floating: .floating
        }
    }
}

// MARK: - Colors (identical presets to Tickdesk)

struct Palette: Equatable {
    var background: Color
    var card: Color
    /// Main text color (the "Digits" color in Tickdesk).
    var digit: Color
    /// Today highlight, event markers, selection.
    var accent: Color
}

struct CustomColors: Codable, Equatable {
    var background: String
    var card: String
    var digit: String
    var accent: String
    var palette: Palette {
        Palette(background: Color(hex: background), card: Color(hex: card), digit: Color(hex: digit), accent: Color(hex: accent))
    }
}

struct ColorPreset: Identifiable {
    let id: String
    let name: String
    let light: CustomColors
    let dark: CustomColors

    static let all: [ColorPreset] = [
        ColorPreset(id: "classic", name: "Classic",
                    light: .init(background: "#E9E9EC", card: "#FFFFFF", digit: "#1C1C1E", accent: "#FF3B30"),
                    dark: .init(background: "#101012", card: "#2A2A2D", digit: "#F5F5F7", accent: "#FF453A")),
        ColorPreset(id: "ink", name: "Ink",
                    light: .init(background: "#E4E6EB", card: "#1C1C1E", digit: "#FFFFFF", accent: "#FF9F0A"),
                    dark: .init(background: "#000000", card: "#151517", digit: "#EDEDED", accent: "#FF9F0A")),
        ColorPreset(id: "midnight", name: "Midnight",
                    light: .init(background: "#DCE3F2", card: "#24325A", digit: "#FFFFFF", accent: "#5AC8FA"),
                    dark: .init(background: "#0A0F1F", card: "#1A2444", digit: "#DCE6FF", accent: "#64D2FF")),
        ColorPreset(id: "lavender", name: "Lavender",
                    light: .init(background: "#E3E2F5", card: "#F7F6FF", digit: "#4B4A8C", accent: "#AF52DE"),
                    dark: .init(background: "#16152B", card: "#2B2950", digit: "#D9D7FF", accent: "#BF5AF2")),
        ColorPreset(id: "lcd", name: "Retro LCD",
                    light: .init(background: "#DCE3D2", card: "#B7C6A2", digit: "#1E2A17", accent: "#3C5A2A"),
                    dark: .init(background: "#0E120C", card: "#1C2418", digit: "#B9F27C", accent: "#7DD13F")),
        ColorPreset(id: "neon", name: "Neon",
                    light: .init(background: "#E7F7F4", card: "#0D1B1E", digit: "#3DFFD0", accent: "#FF2D95"),
                    dark: .init(background: "#05080A", card: "#0D1416", digit: "#3DFFD0", accent: "#FF2D95")),
        ColorPreset(id: "sunset", name: "Sunset",
                    light: .init(background: "#FBE6D8", card: "#FFF6EF", digit: "#C2410C", accent: "#F97316"),
                    dark: .init(background: "#1E0F0A", card: "#3A1D12", digit: "#FFB98A", accent: "#FB923C")),
        ColorPreset(id: "forest", name: "Forest",
                    light: .init(background: "#E1ECE3", card: "#FFFFFF", digit: "#1F5134", accent: "#34C759"),
                    dark: .init(background: "#0B1610", card: "#173323", digit: "#CDEFD8", accent: "#30D158")),
        ColorPreset(id: "rose", name: "Rose",
                    light: .init(background: "#F8E4E8", card: "#FFFFFF", digit: "#9F1D47", accent: "#FF375F"),
                    dark: .init(background: "#1A0B10", card: "#3A1422", digit: "#FFC9D7", accent: "#FF375F")),
        ColorPreset(id: "wood", name: "Walnut",
                    light: .init(background: "#EFE6DA", card: "#C9A57A", digit: "#3B2614", accent: "#8B5A2B"),
                    dark: .init(background: "#15100B", card: "#4A3320", digit: "#F2DEC4", accent: "#D19A5B")),
    ]
}

// MARK: - Config

struct CalendarConfig: Codable, Equatable {
    // Look (same fields and meaning as Tickdesk)
    var appearance: AppearanceMode = .system
    var face: CalendarStyle = .month
    var presetID: String = "classic"
    var font: FontStyle = .rounded
    var weight: FontWeightOption = .semibold
    var customLight = CustomColors(background: "#E9E9EC", card: "#FFFFFF", digit: "#1C1C1E", accent: "#FF3B30")
    var customDark = CustomColors(background: "#101012", card: "#2A2A2D", digit: "#F5F5F7", accent: "#FF453A")
    var followTickdesk = false
    /// Liquid Glass surfaces (macOS 26+). On by default.
    var glassTheme = true

    // Calendar
    var firstWeekday: FirstWeekday = .system
    var showWeekNumbers = false
    var highlightWeekends = true
    var showAdjacentDays = true
    var showEvents = true
    var agendaDays = 7
    var hiddenCalendarIDs: [String] = []
    var use24h = true
    var menuBar: MenuBarDisplay = .day

    // Desktop widget
    var widgetVisible = true
    var widgetFace: CalendarStyle? = nil
    var widgetLevel: WidgetLevel = .desktop
    var widgetScale: Double = 1.0
    var widgetOpacity: Double = 1.0
    var widgetBackground = true
    var widgetLocked = false

    init() {}

    // Tolerant decoding: a missing key keeps its default, so new options never reset a saved setup.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CalendarConfig()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? def }
        appearance = v(.appearance, d.appearance)
        face = v(.face, d.face)
        presetID = v(.presetID, d.presetID)
        font = v(.font, d.font)
        weight = v(.weight, d.weight)
        customLight = v(.customLight, d.customLight)
        customDark = v(.customDark, d.customDark)
        followTickdesk = v(.followTickdesk, d.followTickdesk)
        glassTheme = v(.glassTheme, d.glassTheme)
        firstWeekday = v(.firstWeekday, d.firstWeekday)
        showWeekNumbers = v(.showWeekNumbers, d.showWeekNumbers)
        highlightWeekends = v(.highlightWeekends, d.highlightWeekends)
        showAdjacentDays = v(.showAdjacentDays, d.showAdjacentDays)
        showEvents = v(.showEvents, d.showEvents)
        agendaDays = v(.agendaDays, d.agendaDays)
        hiddenCalendarIDs = v(.hiddenCalendarIDs, d.hiddenCalendarIDs)
        use24h = v(.use24h, d.use24h)
        menuBar = v(.menuBar, d.menuBar)
        widgetVisible = v(.widgetVisible, d.widgetVisible)
        widgetFace = try? c.decodeIfPresent(CalendarStyle.self, forKey: .widgetFace)
        widgetLevel = v(.widgetLevel, d.widgetLevel)
        widgetScale = v(.widgetScale, d.widgetScale)
        widgetOpacity = v(.widgetOpacity, d.widgetOpacity)
        widgetBackground = v(.widgetBackground, d.widgetBackground)
        widgetLocked = v(.widgetLocked, d.widgetLocked)
    }
}

@Observable
@MainActor
final class CalendarSettings {
    static let shared = CalendarSettings()
    private static let key = "Calendesk.config.v1"

    var config: CalendarConfig {
        didSet {
            guard config != oldValue else { return }
            // Quick toggles (toolbar, menu bar, widget menu) apply instantly; keep the
            // Settings draft in step with them unless the user has unsaved edits.
            if draft == oldValue { draft = config }
            save()
            if config.appearance != oldValue.appearance { applyAppearance() }
            if config.followTickdesk != oldValue.followTickdesk { startTickdeskSync() }
            DesktopWidgetController.shared.sync()
        }
    }

    /// Edits made in the Settings window. They only take effect when saved.
    var draft: CalendarConfig

    var hasUnsavedChanges: Bool { draft != config }

    func saveDraft() { config = draft }
    func revertDraft() { draft = config }

    private var tickdeskTimer: Timer?

    private init() {
        let loaded: CalendarConfig
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(CalendarConfig.self, from: data) {
            loaded = decoded
        } else {
            loaded = CalendarConfig()
        }
        config = loaded
        draft = loaded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func applyAppearance() {
        NSApp.appearance = config.appearance.nsAppearance
    }

    func palette(for scheme: ColorScheme) -> Palette { config.palette(for: scheme) }

    var effectiveScheme: ColorScheme {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Calendesk: launch at login change failed: \(error)")
            }
        }
    }

    // MARK: Tickdesk style sharing

    /// Polls Tickdesk's saved style while "Follow Tickdesk" is on.
    /// Polls Tickdesk's saved style only while "Follow Tickdesk" is on.
    func startTickdeskSync() {
        tickdeskTimer?.invalidate()
        tickdeskTimer = nil
        guard config.followTickdesk else { return }
        syncFromTickdesk()
        let t = Timer(timeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { CalendarSettings.shared.syncFromTickdesk() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        tickdeskTimer = t
    }

    func syncFromTickdesk() {
        guard config.followTickdesk, let style = TickdeskStyle.load() else { return }
        var c = config
        style.apply(to: &c)
        if c != config { config = c }
    }
}

/// The look-related part of Tickdesk's saved settings.
struct TickdeskStyle: Decodable {
    var appearance: AppearanceMode
    var presetID: String
    var font: FontStyle
    var weight: FontWeightOption
    var customLight: CustomColors
    var customDark: CustomColors
    var glassTheme: Bool?

    static let domain = "app.tickdesk.clock"

    private static let defaults = UserDefaults(suiteName: domain)
    nonisolated(unsafe) private static var lastData: Data?
    nonisolated(unsafe) private static var lastStyle: TickdeskStyle?

    /// Decodes only when Tickdesk's saved data actually changed.
    static func load() -> TickdeskStyle? {
        guard let data = defaults?.data(forKey: "Tickdesk.config.v1") else { return nil }
        if data == lastData { return lastStyle }
        lastData = data
        lastStyle = try? JSONDecoder().decode(TickdeskStyle.self, from: data)
        return lastStyle
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: domain) != nil || load() != nil
    }

    func apply(to c: inout CalendarConfig) {
        c.appearance = appearance
        c.presetID = presetID
        c.font = font
        c.weight = weight
        c.customLight = customLight
        c.customDark = customDark
        if let glassTheme { c.glassTheme = glassTheme }
    }
}

extension CalendarConfig {
    func colors(for scheme: ColorScheme) -> CustomColors {
        if presetID == "custom" {
            return scheme == .dark ? customDark : customLight
        }
        let preset = ColorPreset.all.first { $0.id == presetID } ?? ColorPreset.all[0]
        return scheme == .dark ? preset.dark : preset.light
    }

    func palette(for scheme: ColorScheme) -> Palette { colors(for: scheme).palette }

    /// Liquid Glass is drawn only when chosen and supported.
    var usesGlass: Bool { glassTheme && GlassSupport.isAvailable }

    func typeface(_ size: CGFloat, weight: Font.Weight? = nil) -> Font {
        font.font(size: size, weight: weight ?? self.weight.weight)
    }

    /// The Gregorian/locale calendar with the chosen first weekday.
    var calendar: Calendar {
        var cal = Calendar.autoupdatingCurrent
        if let f = firstWeekday.value { cal.firstWeekday = f }
        return cal
    }

    /// Copies the active preset into the custom slots so the user can tweak it.
    mutating func beginCustomizing() {
        guard presetID != "custom" else { return }
        customLight = colors(for: .light)
        customDark = colors(for: .dark)
        presetID = "custom"
    }
}

/// Lets a view (the Settings preview) render a config other than the saved one.
private struct PreviewConfigKey: EnvironmentKey {
    static let defaultValue: CalendarConfig? = nil
}

extension EnvironmentValues {
    var previewConfig: CalendarConfig? {
        get { self[PreviewConfigKey.self] }
        set { self[PreviewConfigKey.self] = newValue }
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 6 { s += "FF" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 24) & 0xFF) / 255,
                  green: Double((v >> 16) & 0xFF) / 255,
                  blue: Double((v >> 8) & 0xFF) / 255,
                  opacity: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
