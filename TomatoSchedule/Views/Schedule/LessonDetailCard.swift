import SwiftUI

struct LessonDetailCard: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 0) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(PresetColors.color(for: lesson.course?.colorHex ?? "#78909C"))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                // Course name
                Text(lesson.course?.name ?? "未知课程")
                    .font(.body)
                    .fontWeight(.bold)
                    .lineLimit(2)

                // Badges: subject + hours progress
                let subject = lesson.course?.subject ?? ""
                let progress = lesson.course?.hoursProgressText

                if !subject.isEmpty || progress != nil {
                    HStack(spacing: 6) {
                        if !subject.isEmpty {
                            Text(subject)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 0.96, green: 0.78, blue: 0.26)))
                                .foregroundStyle(.black.opacity(0.8))
                        }

                        if let progress {
                            Text(progress)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                                .foregroundStyle(.white)
                        }
                    }
                }

                // Student
                if !lesson.studentName.isEmpty {
                    HStack(spacing: 4) {
                        Text("学 生：")
                            .foregroundStyle(.secondary)
                        Text(lesson.studentName)
                    }
                    .font(.subheadline)
                }

                // Location
                if !lesson.location.isEmpty {
                    Label(lesson.location, systemImage: "mappin.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}
