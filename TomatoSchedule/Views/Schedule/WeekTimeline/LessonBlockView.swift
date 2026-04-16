import SwiftUI

struct LessonBlockView: View {
    let block: PlacedBlock
    let cluster: ConflictCluster
    let hourHeight: CGFloat
    let columnWidth: CGFloat
    let weekStart: Date
    let onTap: (PreviewContext) -> Void

    @State private var isPressed = false

    private var blockColor: Color {
        if let hex = block.lesson.course?.colorHex {
            return PresetColors.color(for: hex)
        }
        return PresetColors.color(for: "#94A3B8")
    }

    private var fillOpacity: Double {
        block.lesson.isCompleted ? 0.08 : 0.15
    }

    var body: some View {
        let yOffset = CGFloat(block.startMinutesFromRangeStart) / 60 * hourHeight
        let height = max(CGFloat(block.durationMinutes) / 60 * hourHeight, 18)
        let width = columnWidth / CGFloat(cluster.laneCount)
        let xOffset = width * CGFloat(block.lane)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor.opacity(fillOpacity))

            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor)
                .frame(width: 4)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(block.lesson.studentName.isEmpty ? "无学生" : block.lesson.studentName)
                    .font(.system(size: height < 28 ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if height >= 28 {
                    Text(block.lesson.timeRangeText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 2)

            if block.clipsLeading {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if block.clipsTrailing {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)
            }

            if !cluster.overflowLessons.isEmpty && block.lane == cluster.laneCount - 1 {
                Text("+\(cluster.overflowLessons.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(blockColor.opacity(0.8)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
        }
        .frame(width: width - 2, height: height)
        .offset(x: xOffset + 1, y: yOffset)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isPressed = false }
            onTap(PreviewContext(
                id: block.lesson.id,
                lesson: block.lesson,
                overflowCompanions: cluster.overflowLessons,
                weekStart: weekStart
            ))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("学生 \(block.lesson.studentName)，\(block.lesson.course?.name ?? "课时")，\(block.lesson.timeRangeText)")
    }
}
