import Foundation
import SwiftData

@Model
final class Course {
    var id: UUID
    var name: String
    var colorHex: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Lesson.course)
    var lessons: [Lesson]

    // V2 新增
    var subject: String
    var totalHours: Double
    var totalLessons: Int

    // V4 收入
    var hourlyRate: Double

    init(
        name: String,
        colorHex: String = "#FF6B6B",
        notes: String = "",
        subject: String = "",
        totalHours: Double = 0,
        totalLessons: Int = 0,
        hourlyRate: Double = 0
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.notes = notes
        self.createdAt = Date()
        self.lessons = []
        self.subject = subject
        self.totalHours = totalHours
        self.totalLessons = totalLessons
        self.hourlyRate = hourlyRate
    }

    var totalIncome: Double {
        completedLessons.reduce(0) { $0 + $1.effectivePrice }
    }

    // 累计层
    var completedLessons: [Lesson] {
        lessons.filter { $0.isCompleted }
    }

    var completedHours: Double {
        completedLessons.reduce(0.0) { $0 + Double($1.durationMinutes) / 60.0 }
    }

    /// 卡片内累计进度 badge："4.0/10.0h"
    var hoursProgressText: String? {
        guard totalHours > 0 else { return nil }
        return String(format: "%.1f/%.1fh", completedHours, totalHours)
    }

    var sortedLessons: [Lesson] {
        lessons.sorted { $0.startTime < $1.startTime }
    }

    func autoIndex(for lesson: Lesson) -> Int? {
        guard let idx = sortedLessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }
        return idx + 1
    }
}
