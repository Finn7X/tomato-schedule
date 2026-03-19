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

    init(
        course: Course,
        studentName: String = "",
        date: Date,
        startTime: Date,
        endTime: Date,
        notes: String = ""
    ) {
        self.id = UUID()
        self.course = course
        self.studentName = studentName
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.createdAt = Date()
    }

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }
}
