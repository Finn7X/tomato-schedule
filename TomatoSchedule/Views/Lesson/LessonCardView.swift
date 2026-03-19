import SwiftUI

struct LessonCardView: View {
    let lesson: Lesson
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(PresetColors.color(for: lesson.course?.colorHex ?? "#78909C"))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(lesson.course?.name ?? "未知课程")
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !compact {
                    HStack(spacing: 8) {
                        Label(
                            "\(DateHelper.timeString(lesson.startTime))-\(DateHelper.timeString(lesson.endTime))",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !lesson.studentName.isEmpty {
                            Label(lesson.studentName, systemImage: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 4 : 8)

            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(PresetColors.color(for: lesson.course?.colorHex ?? "#78909C").opacity(0.1))
        )
    }
}
