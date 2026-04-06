import Foundation
import SwiftData

// MARK: - Name Normalization

/// Normalize student name: trim whitespace + collapse consecutive spaces
/// "  张  三  " → "张 三", "张三\t" → "张三"
func normalizeStudentName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
       .components(separatedBy: .whitespaces)
       .filter { !$0.isEmpty }
       .joined(separator: " ")
}

// MARK: - StudentProgress

/// Student's global lesson position and cumulative hours
struct StudentProgress {
    let lessonIndex: Int      // 第 N 节 (1-indexed)
    let hourStart: Double     // cumulative hours before this lesson
    let hourEnd: Double       // cumulative hours after this lesson
}

/// Calculate a lesson's position in its student's global timeline
/// Returns nil if studentName is empty after normalization
func studentProgress(for lesson: Lesson, allLessons: [Lesson]) -> StudentProgress? {
    let key = normalizeStudentName(lesson.studentName)
    guard !key.isEmpty else { return nil }
    let studentLessons = allLessons
        .filter { normalizeStudentName($0.studentName) == key }
        .sorted {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id.uuidString < $1.id.uuidString  // stable tie-breaker
        }

    guard let index = studentLessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }

    let lessonIndex = index + 1
    let priorHours = studentLessons[..<index].reduce(0.0) { $0 + Double($1.durationMinutes) / 60.0 }
    let thisHours = Double(lesson.durationMinutes) / 60.0

    return StudentProgress(
        lessonIndex: lessonIndex,
        hourStart: priorHours,
        hourEnd: priorHours + thisHours
    )
}

// MARK: - Student Index (New / Edit)

/// Calculate student index for a target lesson, handling new/edit scenarios
/// targetLesson may not be in existingLessons yet (new lesson scenario)
func computeStudentIndex(for targetLesson: Lesson, existingLessons: [Lesson]) -> Int? {
    let key = normalizeStudentName(targetLesson.studentName)
    guard !key.isEmpty else { return nil }

    var pool = existingLessons.filter {
        normalizeStudentName($0.studentName) == key && $0.id != targetLesson.id
    }
    pool.append(targetLesson)
    pool.sort {
        if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
        return $0.id.uuidString < $1.id.uuidString
    }
    guard let idx = pool.firstIndex(where: { $0.id == targetLesson.id }) else { return nil }
    return idx + 1
}
