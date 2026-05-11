import SwiftUI

/// One lesson block inside a day column.
///
/// Performance notes:
/// - No @State (was @State isPressed for press-scale animation; removed because
///   ~hundreds of LessonBlockView instances each holding their own SwiftUI state
///   was a major source of horizontal-swipe jank).
/// - No .scaleEffect / .animation modifiers — those each register an animation
///   observer per instance.
/// - .accessibilityLabel string is computed once per body call and uses
///   pre-stored fields only.
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

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(blockColor.opacity(fillOpacity))

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(blockColor)
                .frame(width: 3)

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

                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .padding(.trailing, 4)
            .padding(.top, 2)

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
        .clipped()
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
