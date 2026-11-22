import SwiftUI
import AppKit
import EventKit

/// Publishes "today" and refreshes it at midnight, after wake, and when the time zone changes.
@Observable
@MainActor
final class DayClock {
    static let shared = DayClock()
    private(set) var today = Date()
    /// Ticks every minute so "now" lines and relative labels stay fresh.
    private(set) var now = Date()
    private var timer: Timer?

    private init() {
        let refresh: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { DayClock.shared.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh)
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refresh)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)
        // One tick per minute, aligned to the minute boundary, with tolerance so macOS can coalesce wakeups.
        let next = (Date().timeIntervalSinceReferenceDate / 60).rounded(.up) * 60 + 0.5
        let t = Timer(fire: Date(timeIntervalSinceReferenceDate: next), interval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { DayClock.shared.refresh() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let d = Date()
        now = d
        if !Calendar.current.isDate(d, inSameDayAs: today) {
            today = d
            EventStore.shared.reload()
        }
    }
}

struct EventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let calendarID: String
    let location: String?
}

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    let color: Color
    let writable: Bool
}

/// Reads events from the macOS Calendar database (iCloud, Google, Exchange… whatever is set up in Calendar.app).
@Observable
@MainActor
final class EventStore {
    static let shared = EventStore()

    private let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [CalendarInfo] = []
    /// Events keyed by the start of each day they touch.
    private(set) var byDay: [Date: [EventItem]] = [:]
    private var loadedRange: DateInterval?
    /// Sample data used by `--snapshot` so renders don't depend on the user's calendars.
    var demoMode = false
    /// Bumped whenever events or calendars change (lets cached renders know they're stale).
    private(set) var version = 0

    var hasAccess: Bool { demoMode || status == .fullAccess }
    var canAsk: Bool { status == .notDetermined }

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { EventStore.shared.reload() }
        }
    }

    func start() {
        status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess { reload() }
    }

    func requestAccess() {
        if status == .denied || status == .restricted || status == .writeOnly {
            openPrivacySettings()
            return
        }
        store.requestFullAccessToEvents { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let s = EventStore.shared
                    s.status = EKEventStore.authorizationStatus(for: .event)
                    s.reload()
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Makes sure events around `date` (the month shown, plus padding) are loaded.
    func ensureLoaded(around date: Date) {
        guard hasAccess, !demoMode else { return }
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: date)?.start ?? date
        if let r = loadedRange, r.contains(monthStart),
           r.contains(cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart) { return }
        load(center: monthStart)
    }

    func reload() {
        guard !demoMode else { return }
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            if !byDay.isEmpty || !calendars.isEmpty { byDay = [:]; calendars = []; version &+= 1 }
            return
        }
        load(center: loadedRange.map { Date(timeInterval: $0.duration / 2, since: $0.start) } ?? DayClock.shared.today)
    }

    private func load(center: Date) {
        let cal = Calendar.current
        let base = cal.dateInterval(of: .month, for: center)?.start ?? center
        // Two months either side keeps month browsing instant.
        let start = cal.date(byAdding: .month, value: -2, to: base)!
        var end = cal.date(byAdding: .month, value: 3, to: base)!
        let agendaEnd = cal.date(byAdding: .day, value: 31, to: cal.startOfDay(for: Date()))!
        if agendaEnd > end { end = agendaEnd }
        let rangeStart = min(start, cal.startOfDay(for: Date()))

        let ekCals = store.calendars(for: .event)
        calendars = ekCals.map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "",
                         color: Color(cgColor: $0.cgColor), writable: $0.allowsContentModifications)
        }.sorted { ($0.source, $0.title) < ($1.source, $1.title) }

        let predicate = store.predicateForEvents(withStart: rangeStart, end: end, calendars: ekCals)
        let items = store.events(matching: predicate).map { e in
            EventItem(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                      title: e.title?.isEmpty == false ? e.title! : "Untitled",
                      start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      color: Color(cgColor: e.calendar.cgColor),
                      calendarID: e.calendar.calendarIdentifier,
                      location: e.location)
        }
        byDay = Self.bucket(items, cal: cal)
        loadedRange = DateInterval(start: rangeStart, end: end)
        version &+= 1
    }

    private static func bucket(_ items: [EventItem], cal: Calendar) -> [Date: [EventItem]] {
        var out: [Date: [EventItem]] = [:]
        for item in items {
            var day = cal.startOfDay(for: item.start)
            // An event ending exactly at midnight doesn't belong to the next day.
            let last = item.end > item.start ? item.end.addingTimeInterval(-1) : item.start
            var guardCount = 0
            while day <= last && guardCount < 62 {
                out[day, default: []].append(item)
                day = cal.date(byAdding: .day, value: 1, to: day)!
                guardCount += 1
            }
        }
        for k in out.keys {
            out[k]!.sort { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
        }
        return out
    }

    func events(on day: Date, config: CalendarConfig) -> [EventItem] {
        events(on: day, show: config.showEvents, hidden: Set(config.hiddenCalendarIDs))
    }

    func events(on day: Date, show: Bool, hidden: Set<String>) -> [EventItem] {
        guard show, hasAccess, let all = byDay[Calendar.current.startOfDay(for: day)] else { return [] }
        return hidden.isEmpty ? all : all.filter { !hidden.contains($0.calendarID) }
    }

    /// Upcoming days that have events, starting today, within `config.agendaDays`.
    func agenda(from today: Date, config: CalendarConfig) -> [(day: Date, events: [EventItem])] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        let now = Date()
        let hidden = Set(config.hiddenCalendarIDs)
        return (0..<max(1, config.agendaDays)).compactMap { offset in
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            var evs = events(on: day, show: config.showEvents, hidden: hidden)
            if offset == 0 { evs = evs.filter { $0.isAllDay || $0.end > now } }
            return evs.isEmpty ? nil : (day, evs)
        }
    }

    var writableCalendars: [CalendarInfo] { calendars.filter(\.writable) }

    var defaultCalendarID: String? { store.defaultCalendarForNewEvents?.calendarIdentifier }

    @discardableResult
    func addEvent(title: String, start: Date, end: Date, allDay: Bool, calendarID: String?, location: String) -> String? {
        let e = EKEvent(eventStore: store)
        e.title = title.isEmpty ? "New Event" : title
        e.startDate = start
        e.endDate = max(end, start)
        e.isAllDay = allDay
        if !location.isEmpty { e.location = location }
        e.calendar = calendarID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
        guard e.calendar != nil else { return "No calendar is available for new events." }
        do {
            try store.save(e, span: .thisEvent)
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Demo data

    func loadDemo(around today: Date) {
        demoMode = true
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: today)
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: day, to: d0)!)!
        }
        let blue = Color(hex: "#0A84FF"), green = Color(hex: "#30D158"), orange = Color(hex: "#FF9F0A"), purple = Color(hex: "#BF5AF2")
        let samples: [(String, Date, Date, Bool, Color)] = [
            ("Design review", at(0, 10), at(0, 11), false, blue),
            ("Lunch with Sam", at(0, 13), at(0, 14), false, green),
            ("Gym", at(0, 18, 30), at(0, 19, 30), false, orange),
            ("Team offsite", at(1, 0), at(2, 0), true, purple),
            ("Dentist", at(2, 9, 15), at(2, 10), false, orange),
            ("Sprint planning", at(3, 11), at(3, 12), false, blue),
            ("Flight to Lisbon", at(5, 7, 40), at(5, 10), false, green),
            ("Book club", at(-3, 19), at(-3, 21), false, purple),
            ("Quarterly report due", at(9, 0), at(10, 0), true, blue),
            ("Birthday 🎂", at(-8, 0), at(-7, 0), true, orange),
        ]
        let items = samples.enumerated().map { i, s in
            EventItem(id: "demo\(i)", title: s.0, start: s.1, end: s.2, isAllDay: s.3, color: s.4, calendarID: "demo", location: nil)
        }
        byDay = Self.bucket(items, cal: cal)
        version &+= 1
    }
}

extension EventItem {
    /// Uses the shared formatter cache; a DateFormatter per label per render was a major allocation source.
    @MainActor func timeLabel(use24h: Bool, on day: Date) -> String {
        if isAllDay { return "All day" }
        let template = use24h ? "HHmm" : "hmma"
        if !Calendar.current.isDate(start, inSameDayAs: day) { return "Until " + Fmt.string(end, template: template) }
        return Fmt.string(start, template: template)
    }
}
