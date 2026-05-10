import SwiftUI

// MARK: - ScrollAnchor

enum ScrollAnchor: Equatable, Hashable {
    case hour(Int)
    case nowRounded
}

// MARK: - PreviewContext

struct PreviewContext: Identifiable {
    let id: UUID
    let lesson: Lesson
    let overflowCompanions: [Lesson]
    let weekStart: Date
}

// MARK: - PlacedBlock

struct PlacedBlock: Identifiable {
    let id: UUID
    let lesson: Lesson
    let lane: Int
    let startMinutesFromRangeStart: Int
    let durationMinutes: Int
    let clipsLeading: Bool
    let clipsTrailing: Bool
}

// MARK: - ConflictCluster

struct ConflictCluster {
    let visibleBlocks: [PlacedBlock]
    let overflowLessons: [Lesson]
    let laneCount: Int
}

// MARK: - DayColumn

struct DayColumn: Identifiable {
    let id: Date
    let date: Date
    let isToday: Bool
    let isWeekend: Bool
    let clusters: [ConflictCluster]

    /// Flat list of all lessons on this day (visible + overflow), sorted by start time.
    /// Used by WeekAllDayRow to show daily summaries.
    var allLessons: [Lesson] {
        clusters
            .flatMap { $0.visibleBlocks.map(\.lesson) + $0.overflowLessons }
            .sorted { $0.startTime < $1.startTime }
    }
}

// MARK: - WeekSnapshot (two-pass builder)

struct WeekSnapshot {
    let weekStart: Date
    let days: [DayColumn]
    let timeRange: (start: Int, end: Int)

    static func build(weekStart: Date, lessons: [Lesson], maxLanes: Int = 3) -> WeekSnapshot {
        let cal = DateHelper.calendar
        let today = cal.startOfDay(for: Date())

        // Group lessons by day (offset 0..6 from weekStart)
        var lessonsByDay: [[Lesson]] = Array(repeating: [], count: 7)
        for offset in 0..<7 {
            let dayDate = cal.date(byAdding: .day, value: offset, to: weekStart)!
            let startOfDay = cal.startOfDay(for: dayDate)
            lessonsByDay[offset] = lessons.filter { DateHelper.isSameDay($0.date, startOfDay) }
        }

        // Pass 1: compute global time range across all 7 days
        var earliest = 9
        var latest = 21
        for dayLessons in lessonsByDay {
            for lesson in dayLessons {
                let h = cal.component(.hour, from: lesson.startTime)
                if h < earliest { earliest = h }
                let eComps = cal.dateComponents([.hour, .minute], from: lesson.endTime)
                let endHour = (eComps.minute ?? 0) > 0
                    ? (eComps.hour ?? 0) + 1
                    : (eComps.hour ?? 0)
                if endHour > latest { latest = min(endHour, 24) }
            }
        }
        let finalRange = (earliest, latest)

        // Pass 2: build DayColumns using the globally-consistent time range
        let days: [DayColumn] = (0..<7).map { offset in
            let dayDate = cal.date(byAdding: .day, value: offset, to: weekStart)!
            let startOfDay = cal.startOfDay(for: dayDate)
            let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: startOfDay)!
            let weekday = cal.component(.weekday, from: dayDate)
            let isWeekend = weekday == 1 || weekday == 7
            let clusters = LessonLaneLayout.buildClusters(
                lessonsByDay[offset],
                maxLanes: maxLanes,
                dayRange: finalRange,
                dayEnd: dayEnd
            )
            return DayColumn(
                id: startOfDay,
                date: startOfDay,
                isToday: DateHelper.isSameDay(startOfDay, today),
                isWeekend: isWeekend,
                clusters: clusters
            )
        }

        return WeekSnapshot(weekStart: weekStart, days: days, timeRange: finalRange)
    }
}
