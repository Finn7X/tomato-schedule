import SwiftUI
import SwiftData

struct DayScheduleDetailView: View {
    let date: Date
    let lessons: [Lesson]
    let timeRange: (start: Int, end: Int)
    var onNavigateToSchedule: (() -> Void)?

    private let hourHeight: CGFloat = 60

    private var clusters: [ConflictCluster] {
        let cal = DateHelper.calendar
        let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date)!
        return LessonLaneLayout.buildClusters(
            lessons, maxLanes: 2, dayRange: timeRange, dayEnd: dayEnd
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(DateHelper.dateString(date)) \(DateHelper.weekdaySymbol(date))")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let nav = onNavigateToSchedule {
                    Button {
                        nav()
                    } label: {
                        Label("课表", systemImage: "arrow.right.circle")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.77, blue: 0.72),
                        Color(red: 0.29, green: 0.68, blue: 0.64)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid

                    ForEach(clusters, id: \.visibleBlocks.first?.id) { cluster in
                        ForEach(cluster.visibleBlocks) { block in
                            dayBlockView(block, cluster: cluster)
                        }
                    }
                }
                .frame(height: CGFloat(totalHours) * hourHeight)
                .padding(.leading, 44)
            }
        }
    }

    private var totalHours: Int { timeRange.end - timeRange.start }

    private var hourGrid: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...totalHours, id: \.self) { i in
                let y = CGFloat(i) * hourHeight
                Text("\(timeRange.start + i):00")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .offset(x: -44, y: y - 6)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)
                    .offset(y: y)
            }
        }
    }

    @ViewBuilder
    private func dayBlockView(_ block: PlacedBlock, cluster: ConflictCluster) -> some View {
        let y = CGFloat(block.startMinutesFromRangeStart) / 60.0 * hourHeight
        let h = max(CGFloat(block.durationMinutes) / 60.0 * hourHeight, 20)

        GeometryReader { geo in
            let totalWidth = geo.size.width
            let blockWidth = cluster.laneCount > 1 ? totalWidth / CGFloat(cluster.laneCount) : totalWidth
            let xOffset = blockWidth * CGFloat(block.lane)
            let colorHex = block.lesson.course?.colorHex ?? "#78909C"

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if cluster.laneCount > 1 && block.lane == 0 {
                        Rectangle()
                            .fill(.orange)
                            .frame(width: 3)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.lesson.course?.name ?? "未知课程")
                            .font(.system(size: 11, weight: .medium))
                        if !block.lesson.studentName.isEmpty {
                            Text(block.lesson.studentName)
                                .font(.system(size: 10))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    Spacer(minLength: 0)
                }
                .frame(width: blockWidth, height: h)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PresetColors.color(for: colorHex).opacity(0.85))
                )
                .foregroundStyle(.white)

                if !cluster.overflowLessons.isEmpty && block.lane == cluster.laneCount - 1 {
                    Text("+\(cluster.overflowLessons.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(PresetColors.color(for: colorHex)))
                        .frame(maxWidth: blockWidth, maxHeight: h, alignment: .bottomTrailing)
                        .padding(2)
                }
            }
            .offset(x: xOffset, y: y)
        }
    }
}
