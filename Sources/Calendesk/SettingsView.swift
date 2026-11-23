import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            SaveBar()
        }
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tabs: some View {
        TabView {
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            CalendarSettingsTab().tabItem { Label("Calendar", systemImage: "calendar") }
            WidgetSettings().tabItem { Label("Widget", systemImage: "macwindow.on.rectangle") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
    }
}

/// Changes in Settings are a draft; nothing reaches the calendar or widget until Save.
private struct SaveBar: View {
    @Environment(CalendarSettings.self) private var settings

    var body: some View {
        let dirty = settings.hasUnsavedChanges
        HStack(spacing: 10) {
            if dirty {
                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.orange)
                Text("Unsaved changes. The preview shows them; click Save to apply them.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("All changes saved").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revert") { settings.revertDraft() }
                .disabled(!dirty)
                .keyboardShortcut(.cancelAction)
                .glassButton(settings.config.usesGlass)
            Button("Save") { settings.saveDraft() }
                .disabled(!dirty)
                .keyboardShortcut("s", modifiers: .command)
                .glassButton(settings.config.usesGlass, prominent: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: dirty)
    }
}

private struct PreviewHeader: View {
    @Environment(CalendarSettings.self) private var settings
    var style: CalendarStyle? = nil

    /// The preview follows the unsaved Light/Dark/System choice too.
    private var previewScheme: ColorScheme {
        switch settings.draft.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system:
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
        }
    }

    var body: some View {
        let s = style ?? settings.draft.face
        let glass = settings.draft.usesGlass
        CalendarFace(style: s, size: s == .month ? 8.5 : 10, showsBackground: true)
            .environment(\.previewConfig, settings.draft)
            .environment(\.colorScheme, previewScheme)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .padding(.vertical, 4)
            .background {
                // Glass needs something behind it to show; plain keeps the form background.
                if glass {
                    GlassBackdrop(p: settings.draft.palette(for: previewScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(-6)
                }
            }
    }
}

private struct AppearanceSettings: View {
    @Environment(CalendarSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            PreviewHeader()

            Section("Theme") {
                Picker("Appearance", selection: $settings.draft.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows macOS Light/Dark mode automatically, including Auto at sunset.")
                    .font(.caption).foregroundStyle(.secondary)

                GlassThemeToggle(isOn: $settings.draft.glassTheme)

                Picker("Calendar style", selection: $settings.draft.face) {
                    ForEach(CalendarStyle.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }

            Section("Font") {
                Picker("Font style", selection: $settings.draft.font) {
                    ForEach(FontStyle.allCases) { f in
                        Text("Nov 20  \(f.title)").font(f.font(size: 13, weight: .medium)).tag(f)
                    }
                }
                Picker("Weight", selection: $settings.draft.weight) {
                    ForEach(FontWeightOption.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Colors") {
                LabeledContent("Combination") { SwatchRow(config: $settings.draft) }
                Picker("Preset", selection: $settings.draft.presetID) {
                    ForEach(ColorPreset.all) { Text($0.name).tag($0.id) }
                    Divider()
                    Text("Custom").tag("custom")
                }
                if settings.draft.presetID == "custom" {
                    CustomColorEditor(title: "Light mode colors", colors: $settings.draft.customLight)
                    CustomColorEditor(title: "Dark mode colors", colors: $settings.draft.customDark)
                } else {
                    Button("Customize These Colors…") { settings.draft.beginCustomizing() }
                }
            }

            Section("Match Tickdesk") {
                Toggle("Follow Tickdesk's style automatically", isOn: $settings.draft.followTickdesk)
                HStack {
                    Button("Copy Style from Tickdesk Now") {
                        if let s = TickdeskStyle.load() { s.apply(to: &settings.draft) }
                    }
                    .disabled(TickdeskStyle.load() == nil)
                    Spacer()
                    Text(TickdeskStyle.load() == nil ? "Tickdesk settings not found" : "Theme, font, colors and glass")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Uses the same Light/Dark/System choice, font, colors and Liquid Glass setting as your Tickdesk clock so both widgets match.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CustomColorEditor: View {
    let title: String
    @Binding var colors: CustomColors

    private func binding(_ kp: WritableKeyPath<CustomColors, String>) -> Binding<Color> {
        Binding(get: { Color(hex: colors[keyPath: kp]) },
                set: { colors[keyPath: kp] = $0.hexString })
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 14) {
                ColorPicker("Background", selection: binding(\.background), supportsOpacity: false)
                ColorPicker("Card", selection: binding(\.card), supportsOpacity: false)
                ColorPicker("Text", selection: binding(\.digit), supportsOpacity: false)
                ColorPicker("Accent", selection: binding(\.accent), supportsOpacity: false)
            }
            .labelsHidden()
        }
        .help("Background · Card · Text · Accent (today & highlights)")
        HStack {
            Spacer()
            Text("Background · Card · Text · Accent").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CalendarSettingsTab: View {
    @Environment(CalendarSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let store = EventStore.shared
        Form {
            PreviewHeader(style: .month)
            Section("Layout") {
                Picker("Week starts on", selection: $settings.draft.firstWeekday) {
                    ForEach(FirstWeekday.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show week numbers", isOn: $settings.draft.showWeekNumbers)
                Toggle("Highlight weekends", isOn: $settings.draft.highlightWeekends)
                Toggle("Show days from adjacent months", isOn: $settings.draft.showAdjacentDays)
            }
            Section("Events") {
                Toggle("Show events from Calendar", isOn: $settings.draft.showEvents)
                Picker("Time format", selection: $settings.draft.use24h) {
                    Text("24-hour").tag(true)
                    Text("12-hour (AM/PM)").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(!settings.draft.showEvents)
                Stepper("Agenda shows the next \(settings.draft.agendaDays) day\(settings.draft.agendaDays == 1 ? "" : "s")",
                        value: $settings.draft.agendaDays, in: 1...30)
                    .disabled(!settings.draft.showEvents)
                if !store.hasAccess {
                    LabeledContent("Calendar access") {
                        Button(store.canAsk ? "Allow Access…" : "Open Privacy Settings…") { store.requestAccess() }
                    }
                }
            }
            if store.hasAccess && !store.calendars.isEmpty {
                Section("Calendars") {
                    ForEach(store.calendars) { c in
                        Toggle(isOn: Binding(
                            get: { !settings.draft.hiddenCalendarIDs.contains(c.id) },
                            set: { on in
                                settings.draft.hiddenCalendarIDs.removeAll { $0 == c.id }
                                if !on { settings.draft.hiddenCalendarIDs.append(c.id) }
                            })) {
                            HStack(spacing: 8) {
                                Circle().fill(c.color).frame(width: 10, height: 10)
                                Text(c.title)
                                Text(c.source).foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }
                .disabled(!settings.draft.showEvents)
            }
        }
        .formStyle(.grouped)
        .frame(maxHeight: 640)
    }
}

private struct WidgetSettings: View {
    @Environment(CalendarSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Desktop widget") {
                Toggle("Show calendar on desktop", isOn: $settings.draft.widgetVisible)
                Picker("Style", selection: $settings.draft.widgetFace) {
                    Text("Same as main calendar").tag(CalendarStyle?.none)
                    ForEach(CalendarStyle.allCases) { Text($0.title).tag(CalendarStyle?.some($0)) }
                }
                Picker("Position", selection: $settings.draft.widgetLevel) {
                    ForEach(WidgetLevel.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Size") {
                    Slider(value: $settings.draft.widgetScale, in: 0.6...2.2) {
                        EmptyView()
                    } minimumValueLabel: { Image(systemName: "textformat.size.smaller") }
                      maximumValueLabel: { Image(systemName: "textformat.size.larger") }
                }
                LabeledContent("Opacity") {
                    Slider(value: $settings.draft.widgetOpacity, in: 0.2...1)
                }
                Toggle("Show background panel", isOn: $settings.draft.widgetBackground)
                Toggle("Lock position", isOn: $settings.draft.widgetLocked)
            }
            Text("Drag the widget to move it, use its arrows to browse months, double-click to open Calendesk, right-click for quick options.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @Environment(CalendarSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Startup") {
                Toggle("Open Calendesk at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }))
            }
            Section("Menu bar") {
                Picker("Menu bar shows", selection: $settings.draft.menuBar) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Quick actions") {
                LabeledContent("Calendar app") {
                    Button("Open Calendar") { AppActions.openCalendarApp() }
                }
                LabeledContent("Privacy") {
                    Button("Calendar Privacy Settings…") { EventStore.shared.openPrivacySettings() }
                }
            }
            Section {
                Button("Reset All Settings to Defaults", role: .destructive) { settings.draft = CalendarConfig() }
            }
        }
        .formStyle(.grouped)
    }
}
