import SwiftUI

struct LessonTimeGroup: View {
    let lesson: Lesson
    var onEdit: () -> Void = {}

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Orange clock icon
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "clock")
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                        )

                    Text(lesson.timeRangeText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Sequence number on right
                    if let seq = lesson.headerSequenceText {
                        Text(seq)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Expanded detail card
            if isExpanded {
                LessonDetailCard(lesson: lesson)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .onTapGesture { onEdit() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
