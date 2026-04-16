import Foundation

enum LessonLaneLayout {

    /// Sweep-line cluster builder.
    ///
    /// - Parameters:
    ///   - lessons:   Lessons for a single day (any order).
    ///   - maxLanes:  Maximum side-by-side lanes before overflow.
    ///   - dayRange:  (startHour, endHour) of the visible time grid.
    ///   - dayEnd:    Absolute end of the day (used to detect trailing clips).
    /// - Returns: Array of `ConflictCluster`, one per non-overlapping group.
    static func buildClusters(
        _ lessons: [Lesson],
        maxLanes: Int,
        dayRange: (start: Int, end: Int),
        dayEnd: Date
    ) -> [ConflictCluster] {
        guard !lessons.isEmpty else { return [] }

        let cal = DateHelper.calendar
        let sorted = lessons.sorted { $0.startTime < $1.startTime }
        let rangeStartMinutes = dayRange.start * 60

        // ---- Group into raw clusters by sweep-line overlap detection ----
        var rawClusters: [[Lesson]] = []
        var current: [Lesson] = [sorted[0]]
        var maxEnd = sorted[0].endTime

        for lesson in sorted.dropFirst() {
            if lesson.startTime < maxEnd {
                // Overlaps with the current cluster
                current.append(lesson)
                if lesson.endTime > maxEnd { maxEnd = lesson.endTime }
            } else {
                rawClusters.append(current)
                current = [lesson]
                maxEnd = lesson.endTime
            }
        }
        rawClusters.append(current)

        // ---- Assign lanes within each raw cluster ----
        return rawClusters.map { group in
            let clusterSorted = group.sorted { $0.startTime < $1.startTime }
            var laneEndTimes: [Date] = []   // tracks the end time of the last lesson placed in each lane
            var visible: [PlacedBlock] = []
            var overflow: [Lesson] = []

            for lesson in clusterSorted {
                if let availableLane = laneEndTimes.firstIndex(where: { $0 <= lesson.startTime }) {
                    // Reuse a free lane
                    laneEndTimes[availableLane] = lesson.endTime
                    visible.append(makeBlock(
                        lesson: lesson, lane: availableLane,
                        dayRange: dayRange, dayEnd: dayEnd,
                        rangeStartMinutes: rangeStartMinutes, cal: cal
                    ))
                } else if laneEndTimes.count < maxLanes {
                    // Open a new lane
                    let lane = laneEndTimes.count
                    laneEndTimes.append(lesson.endTime)
                    visible.append(makeBlock(
                        lesson: lesson, lane: lane,
                        dayRange: dayRange, dayEnd: dayEnd,
                        rangeStartMinutes: rangeStartMinutes, cal: cal
                    ))
                } else {
                    // All lanes occupied and maxLanes reached → overflow
                    overflow.append(lesson)
                }
            }

            return ConflictCluster(
                visibleBlocks: visible,
                overflowLessons: overflow,
                laneCount: max(laneEndTimes.count, 1)
            )
        }
    }

    // MARK: - Private helpers

    private static func makeBlock(
        lesson: Lesson,
        lane: Int,
        dayRange: (start: Int, end: Int),
        dayEnd: Date,
        rangeStartMinutes: Int,
        cal: Calendar
    ) -> PlacedBlock {
        let startH = cal.component(.hour, from: lesson.startTime)
        let startM = cal.component(.minute, from: lesson.startTime)
        let rawStart = startH * 60 + startM

        let clipsLeading  = rawStart < rangeStartMinutes
        let clipsTrailing = lesson.endTime > dayEnd

        // Clamp leading edge to the visible range start
        let clippedStart = max(rawStart, rangeStartMinutes) - rangeStartMinutes

        // Clamp trailing edge to the end of the day
        let effectiveEnd: Date = clipsTrailing ? dayEnd : lesson.endTime
        let endH = cal.component(.hour, from: effectiveEnd)
        let endM = cal.component(.minute, from: effectiveEnd)
        let rawEnd = endH * 60 + endM
        let clippedEnd = max(rawEnd - rangeStartMinutes, clippedStart)

        return PlacedBlock(
            id: lesson.id,
            lesson: lesson,
            lane: lane,
            startMinutesFromRangeStart: clippedStart,
            durationMinutes: max(clippedEnd - clippedStart, 1),
            clipsLeading: clipsLeading,
            clipsTrailing: clipsTrailing
        )
    }
}
