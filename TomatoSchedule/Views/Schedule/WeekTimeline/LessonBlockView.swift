import SwiftUI

/// One lesson block inside a day column.
struct LessonBlockView: View {
    let block: PlacedBlock
    let cluster: ConflictCluster
    let hourHeight: CGFloat
    let columnWidth: CGFloat
    let weekStart: Date
    let onTap: (PreviewContext) -> Void

    /// Per-student color (matches portrait MonthCalendarView's StudentColors palette).
    /// Falls back to course color when student name is empty.
    private var blockColor: Color {
        let name = block.lesson.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return StudentColors.color(for: name)
        }
        if let hex = block.lesson.course?.colorHex {
            return PresetColors.color(for: hex)
        }
        return PresetColors.color(for: "#94A3B8")
    }

    private var fillOpacity: Double {
        block.lesson.isCompleted ? 0.10 : 0.18
    }

    var body: some View {
        let yOffset = CGFloat(block.startMinutesFromRangeStart) / 60 * hourHeight
        let height = max(CGFloat(block.durationMinutes) / 60 * hourHeight, 18)
        let width = columnWidth / CGFloat(cluster.laneCount)
        let xOffset = width * CGFloat(block.lane)

        let shape = RoundedRectangle(cornerRadius: 4)

        return ZStack(alignment: .topLeading) {
            // Background fill
            shape.fill(blockColor.opacity(fillOpacity))

            // Left accent bar (no rounded corners — fills full height inside the clip)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(blockColor)
                    .frame(width: 3)
                Spacer(minLength: 0)
            }

            // Text content — natural-size VStack pinned at top-leading.
            // Use .fixedSize(vertical: true) so the VStack uses its natural height
            // rather than expanding via a Spacer; combined with the outer .clipShape
            // this guarantees the text is rendered strictly inside the block frame.
            VStack(alignment: .leading, spacing: 1) {
                Text(block.lesson.studentName.isEmpty ? "无学生" : block.lesson.studentName)
                    .font(.system(size: height < 30 ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(blockColor)

                if height >= 30 {
                    Text(block.lesson.timeRangeText)
                        .font(.system(size: 10))
                        .foregroundStyle(blockColor.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.large)   // cap accessibility scaling
            .padding(.leading, 7)
            .padding(.trailing, 4)
            .padding(.top, 3)

            if block.clipsLeading {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8))
                    .foregroundStyle(blockColor.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 2)
                    .padding(.top, 1)
            }
            if block.clipsTrailing {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8))
                    .foregroundStyle(blockColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 2)
                    .padding(.bottom, 1)
            }

            if !cluster.overflowLessons.isEmpty && block.lane == cluster.laneCount - 1 {
                Text("+\(cluster.overflowLessons.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(blockColor.opacity(0.85)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
        }
        .frame(width: width - 2, height: height, alignment: .topLeading)
        // Use clipShape with an explicit shape instead of .clipped() — the latter
        // proved unreliable when combined with .offset and a VStack containing a
        // Spacer, occasionally letting text render above the block frame.
        .clipShape(shape)
        .offset(x: xOffset + 1, y: yOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(PreviewContext(
                id: block.lesson.id,
                lesson: block.lesson,
                overflowCompanions: cluster.overflowLessons,
                weekStart: weekStart
            ))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("学生 \(block.lesson.studentName)，\(block.lesson.course?.name ?? "课时")，\(block.lesson.timeRangeText)"))
    }
}
