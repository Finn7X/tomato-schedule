import EventKit
import SwiftUI

@MainActor
final class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    private let store = EKEventStore()
    private let urlScheme = "tomatoschedule://lesson/"
    private let calendarTitle = "番茄课表"

    @AppStorage("calendarSyncEnabled") var syncEnabled: Bool = false
    @AppStorage("appCalendarIdentifier") private var appCalendarId: String = ""
    @AppStorage("lastSyncDate") private var lastSyncTimestamp: Double = 0

    var lastSyncDate: Date? {
        lastSyncTimestamp > 0 ? Date(timeIntervalSince1970: lastSyncTimestamp) : nil
    }

    var currentAuthStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Permissions

    func requestWriteOnlyAccess() async -> Bool {
        let status = currentAuthStatus
        if status == .fullAccess || status == .writeOnly { return true }
        return await withCheckedContinuation { cont in
            store.requestWriteOnlyAccessToEvents { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    func requestFullAccess() async -> Bool {
        let status = currentAuthStatus
        if status == .fullAccess { return true }
        return await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - App Calendar

    func getOrCreateAppCalendar() throws -> EKCalendar {
        if !appCalendarId.isEmpty, let existing = store.calendar(withIdentifier: appCalendarId) {
            return existing
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.cgColor = UIColor(red: 0.34, green: 0.77, blue: 0.72, alpha: 1).cgColor

        if let defaultSource = store.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            calendar.source = store.sources.first!
        }

        try store.saveCalendar(calendar, commit: true)
        appCalendarId = calendar.calendarIdentifier
        return calendar
    }

    func deleteAppCalendar() throws {
        guard !appCalendarId.isEmpty,
              let calendar = store.calendar(withIdentifier: appCalendarId) else { return }
        try store.removeCalendar(calendar, commit: true)
        appCalendarId = ""
    }

    // MARK: - Quick Export (write-only)

    func quickExportAll(_ lessons: [Lesson]) throws -> Int {
        var count = 0
        for lesson in lessons {
            let event = EKEvent(eventStore: store)
            populateEvent(event, from: lesson)
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        return count
    }

    // MARK: - Managed Sync

    func syncAllLessons(_ lessons: [Lesson]) throws -> Int {
        let calendar = try getOrCreateAppCalendar()
        let allEvents = fetchAllEvents(in: calendar)

        // Build URL index: lesson UUID → EKEvent
        var urlIndex: [UUID: EKEvent] = [:]
        for event in allEvents {
            if let lessonId = extractLessonId(from: event) {
                urlIndex[lessonId] = event
            }
        }

        var matchedIds = Set<String>()
        var count = 0

        for lesson in lessons {
            let existing = urlIndex[lesson.id] ?? findEvent(for: lesson, in: calendar)

            if let event = existing {
                populateEvent(event, from: lesson)
                try store.save(event, span: .thisEvent, commit: false)
                lesson.calendarEventId = event.eventIdentifier
                matchedIds.insert(event.eventIdentifier)
            } else {
                let event = EKEvent(eventStore: store)
                populateEvent(event, from: lesson)
                event.calendar = calendar
                event.url = buildEventURL(for: lesson)
                try store.save(event, span: .thisEvent, commit: false)
                lesson.calendarEventId = event.eventIdentifier
                matchedIds.insert(event.eventIdentifier)
            }
            count += 1
        }

        // Remove orphaned events
        for event in allEvents where !matchedIds.contains(event.eventIdentifier) {
            try store.remove(event, span: .thisEvent, commit: false)
        }

        try store.commit()
        lastSyncTimestamp = Date.now.timeIntervalSince1970
        return count
    }

    func syncLesson(_ lesson: Lesson) throws {
        guard syncEnabled else { return }
        let calendar = try getOrCreateAppCalendar()

        if let existing = findEvent(for: lesson, in: calendar) {
            populateEvent(existing, from: lesson)
            try store.save(existing, span: .thisEvent, commit: true)
            lesson.calendarEventId = existing.eventIdentifier
        } else {
            let event = EKEvent(eventStore: store)
            populateEvent(event, from: lesson)
            event.calendar = calendar
            event.url = buildEventURL(for: lesson)
            try store.save(event, span: .thisEvent, commit: true)
            lesson.calendarEventId = event.eventIdentifier
        }
    }

    func removeSyncedEvent(for lesson: Lesson) throws {
        guard syncEnabled else { return }
        guard let calendar = store.calendar(withIdentifier: appCalendarId) else { return }

        if let event = findEvent(for: lesson, in: calendar) {
            try store.remove(event, span: .thisEvent, commit: true)
        }
        lesson.calendarEventId = ""
    }

    func syncLessonsForCourse(_ course: Course) throws {
        guard syncEnabled else { return }
        for lesson in course.lessons {
            try syncLesson(lesson)
        }
    }

    func removeEventsForLessons(_ lessons: [Lesson]) throws {
        guard syncEnabled else { return }
        guard let calendar = store.calendar(withIdentifier: appCalendarId) else { return }

        for lesson in lessons {
            if let event = findEvent(for: lesson, in: calendar) {
                try store.remove(event, span: .thisEvent, commit: false)
            }
            lesson.calendarEventId = ""
        }
        try store.commit()
    }

    // MARK: - Import helpers

    func fetchCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.calendarIdentifier != appCalendarId }
    }

    func fetchEvents(from calendars: [EKCalendar], start: Date, end: Date) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }

    func clearAllCalendarEventIds(for lessons: [Lesson]) {
        for lesson in lessons {
            lesson.calendarEventId = ""
        }
    }

    // MARK: - Private helpers

    private func populateEvent(_ event: EKEvent, from lesson: Lesson) {
        var title = lesson.course?.name ?? "课时"
        if !lesson.studentName.isEmpty {
            title += " · \(lesson.studentName)"
        }
        event.title = title
        event.startDate = lesson.startTime
        event.endDate = lesson.endTime
        event.location = lesson.location.isEmpty ? nil : lesson.location

        var noteParts: [String] = []
        if let seq = lesson.headerSequenceText {
            noteParts.append("第\(seq)")
        }
        if lesson.isCompleted {
            noteParts.append("✅ 已完成")
        }
        if !lesson.notes.isEmpty {
            noteParts.append(lesson.notes)
        }
        event.notes = noteParts.isEmpty ? nil : noteParts.joined(separator: "\n")

        if event.url == nil {
            event.url = buildEventURL(for: lesson)
        }
    }

    private func findEvent(for lesson: Lesson, in calendar: EKCalendar) -> EKEvent? {
        // Fast path
        if !lesson.calendarEventId.isEmpty,
           let event = store.event(withIdentifier: lesson.calendarEventId) {
            if event.calendar?.calendarIdentifier == calendar.calendarIdentifier,
               extractLessonId(from: event) == lesson.id {
                return event
            }
        }

        // Slow path: scan by URL
        let events = fetchAllEvents(in: calendar)
        return events.first { extractLessonId(from: $0) == lesson.id }
    }

    private func fetchAllEvents(in calendar: EKCalendar) -> [EKEvent] {
        let start = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate)
    }

    private func buildEventURL(for lesson: Lesson) -> URL {
        URL(string: "\(urlScheme)\(lesson.id.uuidString)")!
    }

    private func extractLessonId(from event: EKEvent) -> UUID? {
        guard let url = event.url, url.absoluteString.hasPrefix(urlScheme) else { return nil }
        let idString = url.absoluteString.dropFirst(urlScheme.count)
        return UUID(uuidString: String(idString))
    }
}
