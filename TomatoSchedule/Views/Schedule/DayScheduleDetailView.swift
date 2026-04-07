import SwiftUI
import SwiftData

struct DayScheduleDetailView: View {
    let date: Date
    let lessons: [Lesson]
    let timeRange: (start: Int, end: Int)
    var onNavigateToSchedule: (() -> Void)?

    private let hourHeight: CGFloat = 60

    // MARK: - TimeBlock

    private struct TimeBlock: Identifiable {
        let id: UUID
        let startMinutes: Int
        let durationMinutes: Int
        let colorHex: String
        let courseName: String
        let studentName: String
        let lane: Int // 0=left, 1=right, -1=overflow
    }

    // MARK: - Overlap Grouping

    private func overlapGroups() -> [[Lesson]] {
        let sorted = lessons.sorted { $0.startTime < $1.startTime }
        var groups: [[Lesson]] = []
        var current: [Lesson] = []
        var maxEnd: Date = .distantPast
        for lesson in sorted {
            if lesson.startTime < maxEnd {
                current.append(lesson)
                maxEnd = max(maxEnd, lesson.endTime)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [lesson]
                maxEnd = lesson.endTime
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // MARK: - Lane Assignment

    private func assignLanes(for group: [Lesson]) -> [(lesson: Lesson, lane: Int)] {
        let sorted = group.sorted { $0.startTime < $1.startTime }
        var laneEndTimes: [Date] = []
        var result: [(Lesson, Int)] = []
        for lesson in sorted {
            if let available = laneEndTimes.firstIndex(where: { $0 <= lesson.startTime }) {
                laneEndTimes[available] = lesson.endTime
                result.append((lesson, available))
            } else if laneEndTimes.count < 2 {
                result.append((lesson, laneEndTimes.count))
                laneEndTimes.append(lesson.endTime)
            } else {
                result.append((lesson, -1))
            }
        }
        return result
    }

    // MARK: - Build TimeBlocks

    private var timeBlocks: [TimeBlock] {
        var blocks: [TimeBlock] = []
        let cal = DateHelper.calendar
        let groups = overlapGroups()
        for group in groups {
            let lanes = assignLanes(for: group)
            for (lesson, lane) in lanes {
                let startH = cal.component(.hour, from: lesson.startTime)
                let startM = cal.component(.minute, from: lesson.startTime)
                let endH = cal.component(.hour, from: lesson.endTime)
                let endM = cal.component(.minute, from: lesson.endTime)
                let startOffset = (startH - timeRange.start) * 60 + startM
                let endOffset = (endH - timeRange.start) * 60 + endM
                blocks.append(TimeBlock(
                    id: lesson.id,
                    startMinutes: max(startOffset, 0),
                    durationMinutes: max(endOffset - startOffset, 1),
                    colorHex: lesson.course?.colorHex ?? "#78909C",
                    courseName: lesson.course?.name ?? "未知课程",
                    studentName: lesson.studentName,
                    lane: lane
                ))
            }
        }
        return blocks
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text("\(DateHelper.dateString(date)) \(DateHelper.weekdaySymbol(date))")
                .font(.headline)
                .padding(.top, 12)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid

                    ForEach(timeBlocks) { block in
                        if block.lane >= 0 {
                            lessonBlockView(block)
                        }
                    }
                }
                .frame(height: CGFloat(totalHours) * hourHeight)
                .padding(.leading, 44)
            }

            if let nav = onNavigateToSchedule {
                Button("在课表中查看") { nav() }
                    .font(.subheadline)
                    .padding(.vertical, 12)
            }
        }
    }

    private var totalHours: Int { timeRange.end - timeRange.start }

    // MARK: - Hour Grid

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

    // MARK: - Lesson Block

    @ViewBuilder
    private func lessonBlockView(_ block: TimeBlock) -> some View {
        let y = CGFloat(block.startMinutes) / 60.0 * hourHeight
        let h = max(CGFloat(block.durationMinutes) / 60.0 * hourHeight, 20)
        let hasOverlap = timeBlocks.contains { $0.id != block.id && $0.lane >= 0 && blocksOverlap(block, $0) }

        GeometryReader { geo in
            let totalWidth = geo.size.width
            let blockWidth = hasOverlap ? totalWidth / 2 : totalWidth
            let xOffset = block.lane == 1 ? totalWidth / 2 : 0

            HStack(spacing: 0) {
                if hasOverlap && block.lane == 0 {
                    Rectangle()
                        .fill(.orange)
                        .frame(width: 3)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.courseName)
                        .font(.system(size: 11, weight: .medium))
                    if !block.studentName.isEmpty {
                        Text(block.studentName)
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
                    .fill(PresetColors.color(for: block.colorHex).opacity(0.85))
            )
            .foregroundStyle(.white)
            .offset(x: xOffset, y: y)
        }
    }

    private func blocksOverlap(_ a: TimeBlock, _ b: TimeBlock) -> Bool {
        a.startMinutes < b.startMinutes + b.durationMinutes &&
        b.startMinutes < a.startMinutes + a.durationMinutes
    }
}
