import Foundation
import SwiftData

@Model
final class Course {
    var id: UUID
    var name: String
    var colorHex: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Lesson.course)
    var lessons: [Lesson]

    init(name: String, colorHex: String = "#FF6B6B", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.notes = notes
        self.createdAt = Date()
        self.lessons = []
    }
}
