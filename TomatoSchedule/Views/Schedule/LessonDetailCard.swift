import SwiftUI

struct LessonDetailCard: View {
    let lesson: Lesson
    @AppStorage("showIncomeInCourseList") private var showIncome = true

    private var courseColor: Color {
        PresetColors.color(for: lesson.course?.colorHex ?? "#78909C")
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(courseColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(lesson.course?.name ?? "未知课程")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if lesson.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // Time + student
                HStack(spacing: 0) {
                    Text(lesson.timeRangeText)
                    if !lesson.studentName.isEmpty {
                        Text(" · \(lesson.studentName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Subject + progress (only if data exists)
                let parts = progressParts
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Location
                if !lesson.location.isEmpty {
                    Text(lesson.location)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Spacer(minLength: 0)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(courseColor.opacity(0.08))
        )
    }

    private var progressParts: [String] {
        var parts: [String] = []
        if let subject = lesson.course?.subject, !subject.isEmpty {
            parts.append(subject)
        }
        if let progress = lesson.course?.hoursProgressText {
            parts.append(progress)
        }
        if showIncome, let price = lesson.priceDisplayText {
            parts.append(price)
        }
        if let seq = lesson.headerSequenceText {
            parts.append(seq)
        }
        return parts
    }
}
