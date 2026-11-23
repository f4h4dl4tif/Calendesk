import SwiftUI

struct MainView: View {
    @Environment(CalendarSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    private let vm = MainViewModel.shared

    var body: some View {
        @Bindable var settings = settings
        @Bindable var vm = vm
        let p = settings.palette(for: scheme)
        let store = EventStore.shared

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                // One calendar, sized to the space (ViewThatFits kept all six candidates alive).
                GeometryReader { geo in
                    calendar(size: fittedSize(geo.size, weekNumbers: settings.config.showWeekNumbers))
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                DayDetail(day: vm.selected, newEvent: { vm.beginNewEvent() })
                    .frame(width: 250)
            }
            .padding(24)

            if !store.hasAccess && settings.config.showEvents {
                AccessBanner(p: p, glass: settings.config.usesGlass).padding(.horizontal, 24).padding(.bottom, 12)
            }

            StyleGallery()
                .padding(.bottom, 18)
        }
        .background {
            if settings.config.usesGlass { GlassBackdrop(p: p).ignoresSafeArea() } else { p.background.ignoresSafeArea() }
        }
        .animation(.easeInOut(duration: 0.25), value: settings.config)
        .onAppear { AppActions.shared.openWindow = openWindow }
        .sheet(isPresented: $vm.showingNewEvent) {
            NewEventSheet()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { shift(-1) } label: { Label("Previous Month", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Previous month (⌘←)")
                Button("Today") { goToday() }
                    .keyboardShortcut("t", modifiers: .command)
                    .help("Go to today (⌘T)")
                Button { shift(1) } label: { Label("Next Month", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .help("Next month (⌘→)")
            }
            ToolbarItemGroup {
                Picker("Appearance", selection: $settings.config.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Image(systemName: mode.symbol).help(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Appearance: Light, Dark or follow System")

                Toggle(isOn: $settings.config.showEvents) {
                    Label("Events", systemImage: "list.bullet.circle")
                }
                .help("Show calendar events")

                Toggle(isOn: $settings.config.widgetVisible) {
                    Label("Desktop Widget", systemImage: "macwindow.on.rectangle")
                }
                .help("Show the calendar on your desktop")

                Button { vm.beginNewEvent() } label: {
                    Label("New Event", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!store.hasAccess || store.demoMode)
                .help("New event on the selected day (⌘N)")

                Button { openWindow(id: "settings") } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Fonts, colors and more")
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    /// Largest base size whose month grid fits the space (dimensions are in units of the base size).
    private func fittedSize(_ space: CGSize, weekNumbers: Bool) -> CGFloat {
        let widthUnits: CGFloat = 2.25 * 7 + 1.6 + (weekNumbers ? 1.6 : 0) + 0.2
        let heightUnits: CGFloat = 18.6
        let fit = min(space.width / widthUnits, space.height / heightUnits)
        return max(9, min(30, fit.rounded(.down)))
    }

    private func calendar(size: CGFloat) -> some View {
        CalendarFace(style: .month, size: size, month: vm.month, selected: Bindable(vm).selected,
                     onNavigate: { d in d == 0 ? goToday() : shift(d) },
                     navEdge: vm.lastDelta < 0 ? .leading : .trailing,
                     hoverScope: "main")
    }

    private func shift(_ delta: Int) { vm.shift(delta) }
    private func goToday() { vm.goToday() }
}

/// Events for the selected day.
private struct DayDetail: View {
    @Environment(CalendarSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    let day: Date
    let newEvent: () -> Void

    var body: some View {
        let cfg = settings.config
        let p = cfg.palette(for: scheme)
        let ctx = FaceContext(cfg: cfg, p: p, size: 15, today: DayClock.shared.today, compact: false)
        let store = EventStore.shared
        let events = store.events(on: day, config: cfg)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.relativeDay(day, today: ctx.today) == "Today" ? "TODAY" : Fmt.weekday(day).uppercased())
                    .font(cfg.typeface(12, weight: .bold)).tracking(1)
                    .foregroundStyle(p.accent)
                Text(Fmt.dayNumber(day))
                    .font(cfg.typeface(64))
                    .monospacedDigit()
                    .foregroundStyle(p.digit)
                Text(Fmt.string(day, template: "EEEEdMMMMyyyy"))
                    .font(cfg.typeface(13, weight: .medium))
                    .foregroundStyle(p.digit.opacity(0.6))
            }

            Rectangle().fill(p.digit.opacity(0.12)).frame(height: 1)

            if !cfg.showEvents {
                note("Events are hidden.", p)
            } else if !store.hasAccess {
                note("Allow calendar access to see your events here.", p)
            } else if events.isEmpty {
                note("No events.", p)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(events) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                EventRow(ctx: ctx, event: e, day: day)
                                if let loc = e.location, !loc.isEmpty {
                                    Label(loc, systemImage: "mappin.and.ellipse")
                                        .font(cfg.typeface(11, weight: .regular))
                                        .foregroundStyle(p.digit.opacity(0.5))
                                        .lineLimit(1)
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            HStack {
                if store.hasAccess && !store.demoMode {
                    Button { newEvent() } label: { Label("New Event", systemImage: "plus") }
                        .glassButton(cfg.usesGlass)
                }
                Spacer()
                Button("Open in Calendar") { AppActions.openCalendarApp() }
                    .glassButton(cfg.usesGlass)
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .surface(RoundedRectangle(cornerRadius: 16, style: .continuous), fill: p.card,
                 glass: cfg.usesGlass, palette: p, shadow: 6, shadowY: 2, shadowOpacity: 0.1)
    }

    private func note(_ s: String, _ p: Palette) -> some View {
        Text(s).font(settings.config.typeface(13, weight: .regular)).foregroundStyle(p.digit.opacity(0.55))
    }
}

private struct AccessBanner: View {
    let p: Palette
    var glass = false
    var body: some View {
        let store = EventStore.shared
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark").font(.title2).foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Show your events").font(.headline).foregroundStyle(p.digit)
                Text("Calendesk reads the calendars you already use in the Calendar app (iCloud, Google, Exchange). Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(p.digit.opacity(0.65))
            }
            Spacer()
            Button(store.canAsk ? "Allow Access" : "Open Privacy Settings") { store.requestAccess() }
                .glassButton(glass, prominent: true)
        }
        .padding(12)
        .modifier(BannerBackground(p: p, glass: glass))
    }
}

private struct BannerBackground: ViewModifier {
    let p: Palette
    let glass: Bool
    func body(content: Content) -> some View {
        if glass {
            content.surface(RoundedRectangle(cornerRadius: 12, style: .continuous), fill: p.card, glass: true, palette: p)
        } else {
            content.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.card))
        }
    }
}

/// Clickable thumbnails of every style, plus a row of color swatches.
struct StyleGallery: View {
    @Environment(CalendarSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = settings.palette(for: scheme)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(CalendarStyle.allCases) { style in
                    let selected = settings.config.face == style
                    Button {
                        settings.config.face = style
                    } label: {
                        VStack(spacing: 6) {
                            // Live but non-interactive: no hover tracking, gestures or tooltips per cell.
                            CalendarFace(style: style, size: thumbSize(style), compact: true)
                                .frame(width: 150, height: 84)
                                .clipped()
                                .allowsHitTesting(false)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(p.digit.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(selected ? p.accent : p.digit.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                                )
                            Text(style.title)
                                .font(.caption.weight(selected ? .semibold : .regular))
                                .foregroundStyle(p.digit.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Use \(style.title) for the widget and menu")
                }
            }
            SwatchRow(config: Bindable(settings).config)
        }
    }

    private func thumbSize(_ s: CalendarStyle) -> CGFloat {
        switch s {
        case .month: 3.6
        case .agenda: 4.6
        case .day: 5.0
        case .week: 6.2
        }
    }
}

struct SwatchRow: View {
    @Binding var config: CalendarConfig
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = config.palette(for: scheme)
        HStack(spacing: 10) {
            ForEach(ColorPreset.all) { preset in
                let c = (scheme == .dark ? preset.dark : preset.light).palette
                swatch(card: c.card, digit: c.digit, accent: c.accent, bg: c.background,
                       selected: config.presetID == preset.id, ring: p.accent)
                    .help(preset.name)
                    .onTapGesture { config.presetID = preset.id }
            }
            let custom = (scheme == .dark ? config.customDark : config.customLight).palette
            swatch(card: custom.card, digit: custom.digit, accent: custom.accent, bg: custom.background,
                   selected: config.presetID == "custom", ring: p.accent)
                .overlay(Image(systemName: "paintpalette.fill").font(.system(size: 9)).foregroundStyle(custom.digit).offset(x: 9, y: 9))
                .help("Custom colors (edit in Settings)")
                .onTapGesture { config.presetID = "custom" }
        }
    }

    private func swatch(card: Color, digit: Color, accent: Color, bg: Color, selected: Bool, ring: Color) -> some View {
        ZStack {
            Circle().fill(bg)
            Circle().fill(card).padding(4)
            Text("20").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(digit)
            Circle().fill(accent).frame(width: 5, height: 5).offset(y: 8)
        }
        .frame(width: 28, height: 28)
        .overlay(Circle().strokeBorder(selected ? ring : .gray.opacity(0.35), lineWidth: selected ? 2.5 : 1))
        .contentShape(Circle())
    }
}

/// State for the main window (this toolchain has no @State macro, so it lives here).
@Observable
@MainActor
final class MainViewModel {
    static let shared = MainViewModel()
    var month = Date()
    var selected = Date()
    var showingNewEvent = false
    var draft = NewEventDraft()
    /// Direction of the last month change, for the slide animation.
    var lastDelta = 1

    func shift(_ delta: Int) {
        withAnimation(.snappy(duration: 0.34)) {
            lastDelta = delta
            month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
        }
    }

    func goToday() {
        let today = DayClock.shared.today
        withAnimation(.snappy(duration: 0.34)) {
            lastDelta = month > today ? -1 : 1
            month = today
            selected = today
        }
    }

    func beginNewEvent() {
        let store = EventStore.shared
        guard store.hasAccess, !store.demoMode else { return }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date()) + 1
        var d = NewEventDraft()
        d.start = cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: selected) ?? selected
        d.end = d.start.addingTimeInterval(3600)
        d.calendarID = store.defaultCalendarID ?? store.writableCalendars.first?.id ?? ""
        draft = d
        showingNewEvent = true
    }
}

struct NewEventDraft {
    var title = ""
    var location = ""
    var allDay = false
    var start = Date()
    var end = Date().addingTimeInterval(3600)
    var calendarID = ""
    var error: String?
}

/// Adds an event to one of the user's calendars.
private struct NewEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let vm = MainViewModel.shared

    var body: some View {
        @Bindable var vm = vm
        let store = EventStore.shared
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Title", text: $vm.draft.title)
                TextField("Location", text: $vm.draft.location)
                Toggle("All day", isOn: $vm.draft.allDay)
                DatePicker("Starts", selection: $vm.draft.start,
                           displayedComponents: vm.draft.allDay ? .date : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $vm.draft.end, in: vm.draft.start...,
                           displayedComponents: vm.draft.allDay ? .date : [.date, .hourAndMinute])
                Picker("Calendar", selection: $vm.draft.calendarID) {
                    ForEach(store.writableCalendars) { c in
                        Text("\(c.title) — \(c.source)").tag(c.id)
                    }
                }
                if let error = vm.draft.error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Event") {
                    let d = vm.draft
                    vm.draft.error = store.addEvent(title: d.title, start: d.start, end: d.end, allDay: d.allDay,
                                                    calendarID: d.calendarID.isEmpty ? nil : d.calendarID,
                                                    location: d.location)
                    if vm.draft.error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 440)
        .onChange(of: vm.draft.start) { old, new in
            // Keep the duration when the start moves.
            vm.draft.end = new.addingTimeInterval(max(0, vm.draft.end.timeIntervalSince(old)))
        }
    }
}
