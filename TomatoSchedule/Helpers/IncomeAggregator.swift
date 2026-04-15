import Foundation

/// Pure aggregation functions for income-dimension data.
/// All inputs are already filtered (e.g. by time range); these functions
/// only reshape lessons into chart / ranking views. No side effects.
enum IncomeAggregator {

    // MARK: - Chart

    /// Build chart bar entries grouped by the current time period.
    /// `.byStudent` mode skips lessons without a normalized student name.
    static func chartData(
        from lessons: [Lesson],
        period: Period,
        rankingMode: RankingMode
    ) -> [ChartEntry] {
        let cal = DateHelper.calendar
        var entries: [ChartEntry] = []

        for lesson in lessons {
            let sKey = normalizeStudentName(lesson.studentName)
            if rankingMode == .byStudent && sKey.isEmpty { continue }

            let label: String
            let order: Int
            switch period {
            case .week:
                label = DateHelper.weekdaySymbol(lesson.date)
                // Monday=2..Sunday=1 → remap to 0..6 for sorting
                let wd = cal.component(.weekday, from: lesson.date)
                order = (wd + 5) % 7  // Mon=0, Tue=1, ..., Sun=6
            case .month:
                let day = cal.component(.day, from: lesson.date)
                label = "\(day)日"
                order = day
            case .year:
                let month = cal.component(.month, from: lesson.date)
                label = "\(month)月"
                order = month
            }

            entries.append(ChartEntry(
                label: label,
                sortOrder: order,
                courseName: lesson.course?.name ?? "未知",
                courseColor: lesson.course?.colorHex ?? "#78909C",
                studentKey: sKey,
                income: lesson.effectivePrice
            ))
        }
        // Sort by sortOrder so Chart x-axis renders in chronological order
        return entries.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Rankings

    static func courseRanking(from lessons: [Lesson]) -> [CourseIncome] {
        var map: [UUID: (name: String, color: String, count: Int, income: Double)] = [:]
        for lesson in lessons {
            let cid = lesson.course?.id ?? UUID()
            let name = lesson.course?.name ?? "未知"
            let color = lesson.course?.colorHex ?? "#78909C"
            var entry = map[cid] ?? (name, color, 0, 0)
            entry.count += 1
            entry.income += lesson.effectivePrice
            map[cid] = entry
        }
        let total = max(lessons.reduce(0) { $0 + $1.effectivePrice }, 1)
        return map.values
            .map { CourseIncome(name: $0.name, colorHex: $0.color, count: $0.count, income: $0.income, percentage: $0.income / total * 100) }
            .sorted { $0.income > $1.income }
    }

    static func studentRanking(from lessons: [Lesson]) -> [StudentIncome] {
        var map: [String: (count: Int, income: Double)] = [:]
        for lesson in lessons {
            let key = normalizeStudentName(lesson.studentName)
            guard !key.isEmpty else { continue }
            var entry = map[key] ?? (0, 0)
            entry.count += 1
            entry.income += lesson.effectivePrice
            map[key] = entry
        }
        let total = max(lessons.reduce(0) { $0 + $1.effectivePrice }, 1)
        return map
            .map { StudentIncome(name: $0.key, count: $0.value.count, income: $0.value.income, percentage: $0.value.income / total * 100) }
            .sorted { $0.income > $1.income }
    }
}
