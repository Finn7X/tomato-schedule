import SwiftUI

struct LessonTimeGroup: View {
    let lesson: Lesson
    var onEdit: () -> Void = {}

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(lesson.timeRangeText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let seq = lesson.headerSequenceText {
                        Text(seq)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? -180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Detail card
            if isExpanded {
                LessonDetailCard(lesson: lesson)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .onTapGesture { onEdit() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
