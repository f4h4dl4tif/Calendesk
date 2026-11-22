import SwiftUI

// MARK: - Formatting helpers

@MainActor
enum Fmt {
    private static var cache: [String: DateFormatter] = [:]
    static func string(_ date: Date, template: String) -> String {
        if let f = cache[template] { return f.string(from: date) }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        cache[template] = f
        return f.string(from: date)
    }
    static func monthName(_ d: Date) -> String { string(d, template: "LLLL") }
    static func year(_ d: Date) -> String { string(d, template: "y") }
    static func weekday(_ d: Date) -> String { string(d, template: "EEEE") }
    static func shortWeekday(_ d: Date) -> String { string(d, template: "EEE") }
    static func dayNumber(_ d: Date) -> String { string(d, template: "d") }

    static func relativeDay(_ day: Date, today: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: today) { return "Today" }
        if let t = cal.date(byAdding: .day, value: 1, to: today), cal.isDate(day, inSameDayAs: t) { return "Tomorrow" }
        return string(day, template: "EEEMMMd")
    }
}

/// The days needed to draw a month grid (always whole weeks).
struct MonthGrid {
    let monthStart: Date
    let days: [Date]
    let weekdaySymbols: [String]
    let weekendColumns: Set<Int>

    init(month: Date, cal: Calendar, fixedSixRows: Bool = true) {
        monthStart = cal.dateInterval(of: .month, for: month)?.start ?? cal.startOfDay(for: month)
        let lead = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let rows = fixedSixRows ? 6 : Int(ceil(Double(lead + count) / 7))
        let gridStart = cal.date(byAdding: .day, value: -lead, to: monthStart)!
        days = (0..<(rows * 7)).map { cal.date(byAdding: .day, value: $0, to: gridStart)! }
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        weekdaySymbols = (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
        weekendColumns = Set((0..<7).filter { col in
            let weekday = (cal.firstWeekday - 1 + col) % 7 + 1
            return cal.weekdaySymbols.indices.contains(weekday - 1) && Self.isWeekend(weekday: weekday, cal: cal)
        })
    }

    private static func isWeekend(weekday: Int, cal: Calendar) -> Bool {
        // Find a date with this weekday and ask the calendar (respects regional weekends).
        let ref = cal.date(from: DateComponents(year: 2024, month: 1, day: 7))! // a Sunday
        let d = cal.date(byAdding: .day, value: weekday - 1, to: ref)!
        return cal.isDateInWeekend(d)
    }
}

// MARK: - Calendar face

/// Renders the calendar in the chosen style, palette and font.
struct CalendarFace: View {
    @Environment(CalendarSettings.self) private var settings
    @Environment(\.previewConfig) private var preview
    @Environment(\.colorScheme) private var scheme
    private var cfg: CalendarConfig { preview ?? settings.config }

    var style: CalendarStyle? = nil
    /// Base text size in points; every style scales from it.
    var size: CGFloat
    var showsBackground = false
    /// Month to show (month style). Defaults to the current month.
    var month: Date? = nil
    var selected: Binding<Date>? = nil
    /// Called with -1 / +1 to change month, 0 to jump back to today.
    var onNavigate: ((Int) -> Void)? = nil
    /// Thumbnails skip event text.
    var compact = false
    /// Side the next month slides in from.
    var navEdge: Edge = .trailing
    /// Month style: list the selected day's events under the grid (desktop widget).
    var showsDayFooter = false
    /// Keeps hover highlights of the widget and the main window apart.
    var hoverScope = "main"

    var body: some View {
        let today = DayClock.shared.today
        let p = cfg.palette(for: scheme)
        let shown = month ?? today
        face(today: today, shown: shown, p: p)
            .padding(showsBackground ? size * 1.1 : 0)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: size * 1.2, style: .continuous)
                        .fill(p.background)
                        .shadow(color: .black.opacity(0.18), radius: size * 0.5, y: size * 0.15)
                }
            }
            .task(id: Calendar.current.dateInterval(of: .month, for: shown)?.start) {
                EventStore.shared.ensureLoaded(around: shown)
            }
    }

    @ViewBuilder
    private func face(today: Date, shown: Date, p: Palette) -> some View {
        let ctx = FaceContext(cfg: cfg, p: p, size: size, today: today, compact: compact, hoverScope: hoverScope)
        switch style ?? cfg.face {
        case .month: MonthFace(ctx: ctx, month: shown, selected: selected, onNavigate: onNavigate,
                               navEdge: navEdge, showsDayFooter: showsDayFooter)
        case .agenda: AgendaFace(ctx: ctx)
        case .day: DayPageFace(ctx: ctx)
        case .week: WeekFace(ctx: ctx, selected: selected)
        }
    }
}

struct FaceContext {
    let cfg: CalendarConfig
    let p: Palette
    let size: CGFloat
    let today: Date
    let compact: Bool
    let hoverScope: String
    /// Built once per render instead of on every lookup.
    let cal: Calendar
    private let hidden: Set<String>

    init(cfg: CalendarConfig, p: Palette, size: CGFloat, today: Date, compact: Bool, hoverScope: String = "main") {
        self.cfg = cfg
        self.p = p
        self.size = size
        self.today = today
        self.compact = compact
        self.hoverScope = hoverScope
        self.cal = cfg.calendar
        self.hidden = Set(cfg.hiddenCalendarIDs)
    }

    func font(_ scale: CGFloat, _ weight: Font.Weight? = nil) -> Font { cfg.typeface(size * scale, weight: weight) }
    @MainActor func events(_ day: Date) -> [EventItem] {
        EventStore.shared.events(on: day, show: cfg.showEvents, hidden: hidden)
    }
}

private struct Card<Content: View>: View {
    let ctx: FaceContext
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(ctx.size * 0.8)
            .background(
                RoundedRectangle(cornerRadius: ctx.size * 0.9, style: .continuous)
                    .fill(ctx.p.card)
                    .shadow(color: .black.opacity(0.14), radius: ctx.size * 0.3, y: ctx.size * 0.1)
            )
    }
}

// MARK: - Shared controls

/// Tracks which control the pointer is over (this toolchain has no @State macro).
@Observable
@MainActor
final class HoverState {
    static let shared = HoverState()
    private(set) var key: String?
    /// Hovered day per surface ("widget", "main"). Only the hover ring reads it,
    /// so moving the pointer never re-renders the 42 day cells.
    private(set) var day: [String: Date] = [:]

    func update(_ k: String, _ inside: Bool) {
        let new: String? = inside ? k : (key == k ? nil : key)
        if new != key { key = new }
    }

    func setDay(_ scope: String, _ d: Date?) {
        if day[scope] != d { day[scope] = d }
    }
}

/// Gentle press feedback for the calendar's own buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct NavButton: View {
    let ctx: FaceContext
    let symbol: String
    let help: String
    var small = false
    var dimmed = false
    let action: () -> Void

    var body: some View {
        let key = "\(ctx.hoverScope)-nav-\(symbol)"
        let hovered = HoverState.shared.key == key && !dimmed
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: ctx.size * (small ? 0.4 : 0.78), weight: .bold))
                .foregroundStyle(dimmed ? ctx.p.digit.opacity(0.28) : (hovered ? ctx.p.accent : ctx.p.digit.opacity(0.72)))
                .frame(width: ctx.size * 1.6, height: ctx.size * 1.6)
                .background(Circle().fill(hovered ? ctx.p.digit.opacity(0.1) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .onHover { HoverState.shared.update(key, $0) }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// The single hover highlight of a month grid. It alone observes the pointer.
private struct HoverRing: View {
    let ctx: FaceContext
    let grid: MonthGrid
    let selected: Date?
    let origin: CGPoint
    let cellW: CGFloat
    let cellH: CGFloat

    var body: some View {
        let s = ctx.size
        if let d = HoverState.shared.day[ctx.hoverScope],
           let i = grid.days.firstIndex(where: { ctx.cal.isDate($0, inSameDayAs: d) }),
           !ctx.cal.isDate(d, inSameDayAs: ctx.today),
           !(selected.map { ctx.cal.isDate($0, inSameDayAs: d) } ?? false) {
            let ring = s * 1.75
            Circle()
                .fill(ctx.p.digit.opacity(0.08))
                .frame(width: ring, height: ring)
                .offset(x: origin.x + CGFloat(i % 7) * cellW + (cellW - ring) / 2,
                        y: origin.y + CGFloat(i / 7) * cellH + (cellH - s * 2.13) / 2)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Month grid

private struct MonthFace: View {
    let ctx: FaceContext
    let month: Date
    var selected: Binding<Date>?
    var onNavigate: ((Int) -> Void)?
    var navEdge: Edge = .trailing
    var showsDayFooter = false

    // Every dimension is fixed from the base size, so nothing (month name length,
    // the Today control, events) can change the widget's footprint while browsing.
    private var s: CGFloat { ctx.size }
    private var cellW: CGFloat { s * 2.25 }
    private var cellH: CGFloat { s * 2.15 }
    private var weekColW: CGFloat { ctx.cfg.showWeekNumbers ? s * 1.6 : 0 }
    private var gridW: CGFloat { weekColW + cellW * 7 }
    private var totalW: CGFloat { gridW + s * 1.6 } // + Card padding
    private var footerH: CGFloat { s * 9.4 }

    var body: some View {
        let grid = MonthGrid(month: month, cal: ctx.cal)
        let rows = grid.days.count / 7
        VStack(alignment: .leading, spacing: s * 0.6) {
            header(grid)
                .frame(width: totalW)
            Card(ctx: ctx) {
                VStack(spacing: 0) {
                    weekdayRow(grid)
                    ZStack(alignment: .top) {
                        days(grid)
                            .id(grid.monthStart)
                            .transition(.asymmetric(
                                insertion: .move(edge: navEdge).combined(with: .opacity),
                                removal: .move(edge: navEdge == .trailing ? .leading : .trailing).combined(with: .opacity)))
                    }
                    .frame(width: gridW, height: cellH * CGFloat(rows), alignment: .top)
                    .clipped()
                    if showsDayFooter { footer }
                }
            }
        }
        .fixedSize()
    }

    private func header(_ grid: MonthGrid) -> some View {
        let isCurrent = ctx.cal.isDate(grid.monthStart, equalTo: ctx.today, toGranularity: .month)
        return HStack(alignment: .center, spacing: s * 0.5) {
            HStack(alignment: .firstTextBaseline, spacing: s * 0.35) {
                Text(Fmt.monthName(grid.monthStart))
                    .font(ctx.font(1.45))
                    .foregroundStyle(ctx.p.digit)
                Text(Fmt.year(grid.monthStart))
                    .font(ctx.font(1.45, .regular))
                    .foregroundStyle(ctx.p.accent)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(countsDown: navEdge == .leading))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if !isCurrent { onNavigate?(0) } }

            if let onNavigate {
                HStack(spacing: s * 0.1) {
                    NavButton(ctx: ctx, symbol: "chevron.left", help: "Previous month") { onNavigate(-1) }
                    NavButton(ctx: ctx, symbol: "circle.fill", help: "Today", small: true,
                              dimmed: isCurrent && isTodaySelected) { onNavigate(0) }
                    NavButton(ctx: ctx, symbol: "chevron.right", help: "Next month") { onNavigate(1) }
                }
                .padding(s * 0.12)
                .background(Capsule().fill(ctx.p.digit.opacity(0.06)))
                .fixedSize()
            }
        }
        .padding(.horizontal, s * 0.3)
    }

    private var isTodaySelected: Bool {
        selected.map { ctx.cal.isDate($0.wrappedValue, inSameDayAs: ctx.today) } ?? true
    }

    private func weekdayRow(_ grid: MonthGrid) -> some View {
        HStack(spacing: 0) {
            if ctx.cfg.showWeekNumbers {
                Text("W")
                    .font(ctx.font(0.6, .semibold))
                    .foregroundStyle(ctx.p.digit.opacity(0.3))
                    .frame(width: weekColW)
            }
            ForEach(0..<7, id: \.self) { col in
                Text(grid.weekdaySymbols[col])
                    .font(ctx.font(0.72, .semibold))
                    .lineLimit(1)
                    .foregroundStyle(weekendTint(col, grid) ?? ctx.p.digit.opacity(0.55))
                    .frame(width: cellW)
            }
        }
        .padding(.bottom, s * 0.35)
    }

    private func days(_ grid: MonthGrid) -> some View {
        let interactive = selected != nil
        return VStack(spacing: 0) {
            ForEach(0..<(grid.days.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    if ctx.cfg.showWeekNumbers {
                        Text("\(ctx.cal.component(.weekOfYear, from: grid.days[row * 7]))")
                            .font(ctx.font(0.6, .medium))
                            .monospacedDigit()
                            .foregroundStyle(ctx.p.digit.opacity(0.35))
                            .frame(width: weekColW, height: cellH)
                    }
                    ForEach(0..<7, id: \.self) { col in
                        cell(grid.days[row * 7 + col], col: col, grid: grid)
                            .frame(width: cellW, height: cellH)
                    }
                }
            }
        }
        .background(alignment: .topLeading) {
            if interactive {
                HoverRing(ctx: ctx, grid: grid, selected: selected?.wrappedValue,
                          origin: CGPoint(x: weekColW, y: 0), cellW: cellW, cellH: cellH)
            }
        }
        .contentShape(Rectangle())
        // One hover tracker and one tap recognizer for the whole grid, instead of 42 of each.
        .onContinuousHover { phase in
            guard interactive else { return }
            switch phase {
            case .active(let pt): HoverState.shared.setDay(ctx.hoverScope, day(at: pt, grid))
            case .ended: HoverState.shared.setDay(ctx.hoverScope, nil)
            }
        }
        .gesture(SpatialTapGesture().onEnded { v in
            guard let selected, let d = day(at: v.location, grid) else { return }
            withAnimation(.easeOut(duration: 0.15)) { selected.wrappedValue = d }
        }, including: interactive ? .all : .subviews)
    }

    /// The day under a point in the grid, if it's one that's drawn.
    private func day(at pt: CGPoint, _ grid: MonthGrid) -> Date? {
        let x = pt.x - weekColW
        guard x >= 0, pt.y >= 0 else { return nil }
        let col = Int(x / cellW), row = Int(pt.y / cellH)
        guard col < 7, row < grid.days.count / 7 else { return nil }
        let d = grid.days[row * 7 + col]
        if !ctx.cfg.showAdjacentDays && !ctx.cal.isDate(d, equalTo: grid.monthStart, toGranularity: .month) { return nil }
        return d
    }

    private func weekendTint(_ col: Int, _ grid: MonthGrid) -> Color? {
        ctx.cfg.highlightWeekends && grid.weekendColumns.contains(col) ? ctx.p.accent.opacity(0.85) : nil
    }

    @ViewBuilder
    private func cell(_ day: Date, col: Int, grid: MonthGrid) -> some View {
        let inMonth = ctx.cal.isDate(day, equalTo: grid.monthStart, toGranularity: .month)
        if !inMonth && !ctx.cfg.showAdjacentDays {
            Color.clear
        } else {
            let isToday = ctx.cal.isDate(day, inSameDayAs: ctx.today)
            let isSelected = selected.map { ctx.cal.isDate(day, inSameDayAs: $0.wrappedValue) } ?? false
            let events = ctx.events(day)
            let base: Color = weekendTint(col, grid) ?? ctx.p.digit
            VStack(spacing: s * 0.12) {
                Text(Fmt.dayNumber(day))
                    .font(ctx.font(0.95, isToday ? .bold : nil))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isToday ? Color.white : base.opacity(inMonth ? 1 : 0.3))
                    .frame(width: s * 1.75, height: s * 1.75)
                    .background {
                        if isToday {
                            Circle().fill(ctx.p.accent)
                        } else if isSelected {
                            Circle().fill(ctx.p.accent.opacity(0.14))
                                .overlay(Circle().strokeBorder(ctx.p.accent, lineWidth: max(1, s * 0.09)))
                        }
                    }
                    .overlay {
                        if isToday && isSelected {
                            Circle().strokeBorder(ctx.p.card, lineWidth: max(1, s * 0.08)).padding(s * 0.1)
                        }
                    }
                if events.isEmpty {
                    Color.clear.frame(height: s * 0.26)
                } else {
                    HStack(spacing: s * 0.12) {
                        ForEach(0..<min(3, events.count), id: \.self) { i in
                            Circle().fill(events[i].color).frame(width: s * 0.26, height: s * 0.26)
                        }
                    }
                    .frame(height: s * 0.26)
                    .opacity(inMonth ? 1 : 0.4)
                }
            }
        }
    }

    /// Events of the selected day (today by default), at a fixed height so the widget never jumps.
    private var footer: some View {
        let day = selected?.wrappedValue ?? ctx.today
        let store = EventStore.shared
        let events = ctx.events(day)
        return VStack(alignment: .leading, spacing: s * 0.42) {
            Rectangle().fill(ctx.p.digit.opacity(0.1)).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.relativeDay(day, today: ctx.today))
                    .font(ctx.font(0.8, .semibold))
                    .foregroundStyle(ctx.p.accent)
                Spacer(minLength: s)
                if !events.isEmpty {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(ctx.font(0.68, .medium))
                        .foregroundStyle(ctx.p.digit.opacity(0.45))
                }
            }
            .lineLimit(1)
            if !ctx.cfg.showEvents {
                note("Events are turned off")
            } else if !store.hasAccess {
                note("Open Calendesk to connect your calendars")
            } else if events.isEmpty {
                note("No events")
            } else {
                ForEach(events.prefix(3)) { e in EventRow(ctx: ctx, event: e, day: day) }
                if events.count > 3 {
                    Text("+\(events.count - 3) more")
                        .font(ctx.font(0.66, .medium))
                        .foregroundStyle(ctx.p.digit.opacity(0.45))
                }
            }
        }
        .padding(.top, s * 0.5)
        .padding(.horizontal, s * 0.2)
        .frame(width: gridW, height: footerH, alignment: .topLeading)
        .clipped()
        .id(ctx.cal.startOfDay(for: day))
        .transition(.opacity)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(ctx.font(0.75, .regular))
            .foregroundStyle(ctx.p.digit.opacity(0.5))
            .lineLimit(1)
    }
}

// MARK: - Agenda

private struct AgendaFace: View {
    let ctx: FaceContext

    var body: some View {
        let s = ctx.size
        HStack(alignment: .top, spacing: s * 0.8) {
            Card(ctx: ctx) {
                VStack(spacing: s * 0.1) {
                    Text(Fmt.weekday(ctx.today).uppercased())
                        .font(ctx.font(0.75, .bold))
                        .tracking(s * 0.06)
                        .foregroundStyle(ctx.p.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(Fmt.dayNumber(ctx.today))
                        .font(ctx.font(4.2))
                        .monospacedDigit()
                        .foregroundStyle(ctx.p.digit)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(Fmt.monthName(ctx.today)) \(Fmt.year(ctx.today))")
                        .font(ctx.font(0.8, .medium))
                        .foregroundStyle(ctx.p.digit.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: s * 7)
            }
            list
                .frame(width: s * 15, alignment: .leading)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var list: some View {
        let s = ctx.size
        let store = EventStore.shared
        VStack(alignment: .leading, spacing: s * 0.45) {
            Text("Up next")
                .font(ctx.font(0.75, .bold))
                .tracking(s * 0.04)
                .foregroundStyle(ctx.p.digit.opacity(0.5))
            if !ctx.cfg.showEvents {
                emptyLine("Events are turned off", "Enable them in Settings › Calendar")
            } else if !store.hasAccess {
                emptyLine("Connect your calendars", "Open Calendesk to allow access")
            } else {
                let groups = store.agenda(from: ctx.today, config: ctx.cfg)
                if groups.isEmpty {
                    emptyLine("Nothing scheduled", "Next \(ctx.cfg.agendaDays) days are free")
                } else {
                    let limit = ctx.compact ? 3 : 7
                    let flat = groups.flatMap { g in g.events.map { (g.day, $0) } }
                    ForEach(Array(groups.enumerated()), id: \.offset) { gi, g in
                        let before = groups.prefix(gi).reduce(0) { $0 + $1.events.count }
                        if before < limit {
                            Text(Fmt.relativeDay(g.day, today: ctx.today))
                                .font(ctx.font(0.72, .semibold))
                                .foregroundStyle(ctx.p.accent)
                                .padding(.top, gi == 0 ? 0 : s * 0.15)
                            ForEach(Array(g.events.prefix(limit - before).enumerated()), id: \.offset) { _, e in
                                EventRow(ctx: ctx, event: e, day: g.day)
                            }
                        }
                    }
                    if flat.count > limit {
                        Text("+\(flat.count - limit) more")
                            .font(ctx.font(0.7, .medium))
                            .foregroundStyle(ctx.p.digit.opacity(0.45))
                    }
                }
            }
        }
    }

    private func emptyLine(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: ctx.size * 0.15) {
            Text(title).font(ctx.font(0.95)).foregroundStyle(ctx.p.digit)
            Text(sub).font(ctx.font(0.72, .regular)).foregroundStyle(ctx.p.digit.opacity(0.55))
        }
    }
}

struct EventRow: View {
    let ctx: FaceContext
    let event: EventItem
    let day: Date

    var body: some View {
        let s = ctx.size
        HStack(alignment: .center, spacing: s * 0.45) {
            RoundedRectangle(cornerRadius: s * 0.1)
                .fill(event.color)
                .frame(width: s * 0.22, height: s * 1.25)
            VStack(alignment: .leading, spacing: s * 0.02) {
                Text(event.title)
                    .font(ctx.font(0.85, .medium))
                    .foregroundStyle(ctx.p.digit)
                    .lineLimit(1)
                Text(event.timeLabel(use24h: ctx.cfg.use24h, on: day))
                    .font(ctx.font(0.68, .regular))
                    .monospacedDigit()
                    .foregroundStyle(ctx.p.digit.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Day page (tear-off)

private struct DayPageFace: View {
    let ctx: FaceContext

    var body: some View {
        let s = ctx.size
        let events = ctx.events(ctx.today)
        let upcoming = events.filter { $0.isAllDay || $0.end > DayClock.shared.now }
        let w = s * 11
        VStack(spacing: 0) {
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: s * 0.9, topTrailingRadius: s * 0.9, style: .continuous)
                    .fill(ctx.p.accent)
                Text(Fmt.monthName(ctx.today).uppercased())
                    .font(ctx.font(1.0, .bold))
                    .tracking(s * 0.12)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, s * 0.8)
            }
            .frame(width: w, height: s * 2.4)
            .overlay(alignment: .top) {
                // Binder rings
                HStack(spacing: s * 4) {
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule()
                            .fill(ctx.p.background)
                            .frame(width: s * 0.45, height: s * 1.2)
                            .overlay(Capsule().strokeBorder(ctx.p.digit.opacity(0.25), lineWidth: max(0.5, s * 0.05)))
                    }
                }
                .offset(y: -s * 0.5)
            }

            VStack(spacing: s * 0.1) {
                Text(Fmt.dayNumber(ctx.today))
                    .font(ctx.font(5.6))
                    .monospacedDigit()
                    .foregroundStyle(ctx.p.digit)
                    .lineLimit(1)
                    .fixedSize()
                Text(Fmt.weekday(ctx.today))
                    .font(ctx.font(1.1, .medium))
                    .foregroundStyle(ctx.p.digit.opacity(0.75))
                    .lineLimit(1)
                Text(dayOfYear)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .font(ctx.font(0.65, .regular))
                    .foregroundStyle(ctx.p.digit.opacity(0.45))
                if !ctx.compact && ctx.cfg.showEvents && EventStore.shared.hasAccess {
                    Rectangle().fill(ctx.p.digit.opacity(0.12)).frame(height: 1).padding(.vertical, s * 0.4)
                    if let next = upcoming.first {
                        EventRow(ctx: ctx, event: next, day: ctx.today)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if upcoming.count > 1 {
                            Text("+\(upcoming.count - 1) more today")
                                .font(ctx.font(0.65, .medium))
                                .foregroundStyle(ctx.p.digit.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, s * 0.15)
                        }
                    } else {
                        Text(events.isEmpty ? "No events today" : "All done for today")
                            .font(ctx.font(0.75, .medium))
                            .foregroundStyle(ctx.p.digit.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, s * 0.9)
            .padding(.top, s * 0.5)
            .padding(.bottom, s * 0.9)
            .frame(width: w)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: s * 0.9, bottomTrailingRadius: s * 0.9, style: .continuous)
                    .fill(ctx.p.card)
            )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: s * 0.35, y: s * 0.12)
        .padding(.top, s * 0.5)
        .fixedSize()
    }

    private var dayOfYear: String {
        let cal = ctx.cal
        let n = cal.ordinality(of: .day, in: .year, for: ctx.today) ?? 1
        let total = cal.range(of: .day, in: .year, for: ctx.today)?.count ?? 365
        return "Day \(n) of \(total) · Week \(cal.component(.weekOfYear, from: ctx.today))"
    }
}

// MARK: - Week strip

private struct WeekFace: View {
    let ctx: FaceContext
    var selected: Binding<Date>?

    var body: some View {
        let s = ctx.size
        let cal = ctx.cal
        let start = cal.dateInterval(of: .weekOfYear, for: ctx.today)?.start ?? ctx.today
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let todays = ctx.events(ctx.today).filter { $0.isAllDay || $0.end > DayClock.shared.now }

        VStack(alignment: .leading, spacing: s * 0.6) {
            HStack(alignment: .firstTextBaseline, spacing: s * 0.4) {
                Text(Fmt.monthName(ctx.today)).font(ctx.font(1.3)).foregroundStyle(ctx.p.digit)
                Text(Fmt.year(ctx.today)).font(ctx.font(1.3, .regular)).foregroundStyle(ctx.p.accent)
                Spacer()
                Text("Week \(cal.component(.weekOfYear, from: ctx.today))")
                    .font(ctx.font(0.75, .semibold))
                    .foregroundStyle(ctx.p.digit.opacity(0.5))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, s * 0.3)
            .frame(width: s * 7 * 2.5 + s * 0.35 * 6 + s * 1.6)
            Card(ctx: ctx) {
                VStack(alignment: .leading, spacing: s * 0.7) {
                    HStack(spacing: s * 0.35) {
                        ForEach(days, id: \.self) { day in dayCell(day) }
                    }
                    if !ctx.compact && ctx.cfg.showEvents && EventStore.shared.hasAccess {
                        if let next = todays.first {
                            EventRow(ctx: ctx, event: next, day: ctx.today)
                                .frame(width: s * 7 * 2.5 + s * 0.35 * 6, alignment: .leading)
                        } else {
                            Text("No more events today")
                                .font(ctx.font(0.75, .medium))
                                .foregroundStyle(ctx.p.digit.opacity(0.5))
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    private func dayCell(_ day: Date) -> some View {
        let s = ctx.size
        let isToday = ctx.cal.isDate(day, inSameDayAs: ctx.today)
        let weekend = ctx.cfg.highlightWeekends && ctx.cal.isDateInWeekend(day)
        let fg: Color = isToday ? .white : (weekend ? ctx.p.accent : ctx.p.digit)
        let events = ctx.events(day)
        return VStack(spacing: s * 0.2) {
            Text(Fmt.shortWeekday(day).uppercased())
                .font(ctx.font(0.6, .bold))
                .foregroundStyle(fg.opacity(isToday ? 0.9 : 0.6))
            Text(Fmt.dayNumber(day))
                .font(ctx.font(1.3))
                .monospacedDigit()
                .foregroundStyle(fg)
            HStack(spacing: s * 0.1) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, e in
                    Circle().fill(isToday ? .white : e.color).frame(width: s * 0.22, height: s * 0.22)
                }
            }
            .frame(height: s * 0.22)
        }
        .frame(width: s * 2.5)
        .padding(.vertical, s * 0.45)
        .background(
            RoundedRectangle(cornerRadius: s * 0.6, style: .continuous)
                .fill(isToday ? ctx.p.accent : ctx.p.digit.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture { selected?.wrappedValue = day }
    }
}
