import Foundation
import SwiftData

@Model
final class Lesson {
    var id: UUID
    var course: Course?
    var studentName: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var notes: String
    var createdAt: Date

    // V2 新增
    var lessonNumber: Int
    var isCompleted: Bool
    var location: String

    // V3 日历同步
    var calendarEventId: String

    // V4 收入
    var isPriceOverridden: Bool
    var priceOverride: Double

    init(
        course: Course,
        studentName: String = "",
        date: Date,
        startTime: Date,
        endTime: Date,
        notes: String = "",
        lessonNumber: Int = 0,
        isCompleted: Bool = false,
        location: String = ""
    ) {
        self.id = UUID()
        self.course = course
        self.studentName = studentName
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.createdAt = Date()
        self.lessonNumber = lessonNumber
        self.isCompleted = isCompleted
        self.location = location
        self.calendarEventId = ""
        self.isPriceOverridden = false
        self.priceOverride = 0
    }

    var effectivePrice: Double {
        if isPriceOverridden { return priceOverride }
        guard let rate = course?.hourlyRate, rate > 0 else { return 0 }
        let raw = rate * Double(durationMinutes) / 60.0
        return (raw * 100).rounded() / 100
    }

    var priceDisplayText: String? {
        let p = effectivePrice
        guard p > 0 || isPriceOverridden else { return nil }
        if isPriceOverridden && p == 0 { return "免费" }
        return p == p.rounded() ? "¥\(Int(p))" : String(format: "¥%.1f", p)
    }

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }

    /// 序号层：时间行头部右侧 "1/48次"
    var headerSequenceText: String? {
        guard lessonNumber > 0,
              let total = course?.totalLessons,
              total > 0 else { return nil }
        return "\(lessonNumber)/\(total)次"
    }

    var timeRangeText: String {
        "\(DateHelper.timeString(startTime))-\(DateHelper.timeString(endTime))"
    }
}
