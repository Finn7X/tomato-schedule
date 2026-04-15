import SwiftUI
import SwiftData

struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @State private var displayMonth: Date = .now
    @State private var selectedDay: Date?
    @State private var showStudents: Bool = false
    @State private var slideForward: Bool = true
    @State private var isAnimating: Bool = false

    var onSelectDate: ((Date) -> Void)?

    // MARK: - Precomputed snapshot

    fileprivate struct MonthSnapshot {
        let cells: [(date: Date, isCurrentMonth: Bool)]
        let lessonsByDate: [Date: [Lesson]]
        let timeRange: (start: Int, end: Int)
        let blocksByDate: [Date: [MiniBlock]]
        let weeks: Int
    }

    /// Build everything for the current `displayMonth` in one pass.
    /// This is called once per `body` render, replacing ~42×N-scale computed-property thrash.
    private func buildSnapshot() -> MonthSnapshot {
        let cal = DateHelper.calendar
        let range = DateHelper.monthRange(for: displayMonth)
        let monthLessons = allLessons.filter { $0.date >= range.start && $0.date < range.end }

        // Group by start-of-day
        var grouped: [Date: [Lesson]] = [:]
        grouped.reserveCapacity(monthLessons.count)
        for lesson in monthLessons {
            let key = cal.startOfDay(for: lesson.date)
            grouped[key, default: []].append(lesson)
        }

        // Time range (min 8:00-22:00, expand if needed)
        var tr: (start: Int, end: Int) = (8, 22)
        if !monthLessons.isEmpty {
            var earliest = 8
            var latest = 22
            for lesson in monthLessons {
                let s = cal.component(.hour, from: lesson.startTime)
                if s < earliest { earliest = s }
                let eComp = cal.dateComponents([.hour, .minute], from: lesson.endTime)
                let e = (eComp.minute ?? 0) > 0 ? (eComp.hour ?? 0) + 1 : (eComp.hour ?? 0)
                if e > latest { latest = e }
            }
            tr = (min(max(earliest - 1, 0), 8), max(min(latest + 1, 24), 22))
        }

        // Calendar cells (leading/current/trailing)
        let days = DateHelper.daysInMonth(for: displayMonth)
        var cells: [(Date, Bool)] = []
        if let firstDay = days.first {
            let weekday = cal.component(.weekday, from: firstDay)
            let leadingOffset = (weekday + 5) % 7
            for i in (0..<leadingOffset).reversed() {
                if let prev = cal.date(byAdding: .day, value: -(i + 1), to: firstDay) {
                    cells.append((prev, false))
                }
            }
            for day in days { cells.append((day, true)) }
            let remainder = cells.count % 7
            if remainder > 0, let lastDay = days.last {
                for i in 1...(7 - remainder) {
                    if let next = cal.date(byAdding: .day, value: i, to: lastDay) {
                        cells.append((next, false))
                    }
                }
            }
        }

        // Precompute mini blocks per day (only for days with lessons)
        let totalHours = CGFloat(max(tr.end - tr.start, 1))
        let rangeStart = CGFloat(tr.start)
        var blocks: [Date: [MiniBlock]] = [:]
        blocks.reserveCapacity(grouped.count)
        for (key, lessons) in grouped {
            blocks[key] = lessons.map { lesson in
                let sComp = cal.dateComponents([.hour, .minute], from: lesson.startTime)
                let eComp = cal.dateComponents([.hour, .minute], from: lesson.endTime)
                let startH = sComp.hour ?? 0
                let startM = sComp.minute ?? 0
                let endH = eComp.hour ?? 0
                let endM = eComp.minute ?? 0
                let startDecimal = CGFloat(startH) + CGFloat(startM) / 60.0
                let endDecimal = CGFloat(endH) + CGFloat(endM) / 60.0
                let startFrac = max((startDecimal - rangeStart) / totalHours, 0)
                let heightFrac = min((endDecimal - startDecimal) / totalHours, 1 - startFrac)
                let startText = startM == 0 ? "\(startH)" : "\(startH):\(String(format: "%02d", startM))"
                let endText = endM == 0 ? "\(endH)" : "\(endH):\(String(format: "%02d", endM))"
                return MiniBlock(
                    id: lesson.id,
                    startFraction: startFrac,
                    heightFraction: heightFrac,
                    timeText: "\(startText)-\(endText)",
                    studentName: lesson.studentName,
                    courseColorHex: lesson.course?.colorHex ?? "#78909C"
                )
            }
        }

        return MonthSnapshot(
            cells: cells,
            lessonsByDate: grouped,
            timeRange: tr,
            blocksByDate: blocks,
            weeks: max(cells.count / 7, 1)
        )
    }

    private func cellHeight(in geometry: GeometryProxy, weeks: Int) -> CGFloat {
        let navHeight: CGFloat = 44
        let weekdayHeight: CGFloat = 24
        let legendHeight: CGFloat = 32
        let available = geometry.size.height - navHeight - weekdayHeight - legendHeight
        return max(available / CGFloat(weeks), 70)
    }

    // MARK: - Actions

    private func moveMonth(_ offset: Int) {
        slideForward = offset > 0
        if let newMonth = DateHelper.calendar.date(byAdding: .month, value: offset, to: displayMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayMonth = newMonth
            }
        }
    }

    // MARK: - Body

    var body: some View {
        let snap = buildSnapshot()
        return NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    monthNavigation
                    weekdayHeaders

                    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                    let height = cellHeight(in: geometry, weeks: snap.weeks)
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(Array(snap.cells.enumerated()), id: \.offset) { _, cell in
                            let key = DateHelper.startOfDay(cell.date)
                            let lessonCount = snap.lessonsByDate[key]?.count ?? 0
                            DayAvailabilityCell(
                                date: cell.date,
                                blocks: snap.blocksByDate[key] ?? [],
                                lessonCount: lessonCount,
                                isCurrentMonth: cell.isCurrentMonth,
                                isToday: DateHelper.isSameDay(cell.date, .now),
                                showStudents: showStudents,
                                cellHeight: height
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                            )
                            .onTapGesture {
                                if cell.isCurrentMonth {
                                    selectedDay = cell.date
                                }
                            }
                        }
                    }
                    .id(displayMonth)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideForward ? .trailing : .leading),
                        removal: .move(edge: slideForward ? .leading : .trailing)
                    ))
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                guard !isAnimating else { return }
                                let h = value.translation.width
                                let v = value.translation.height
                                guard abs(h) > 50, abs(h) > abs(v) else { return }
                                isAnimating = true
                                if h < 0 {
                                    slideForward = true
                                    moveMonth(1)
                                } else {
                                    slideForward = false
                                    moveMonth(-1)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isAnimating = false
                                }
                            }
                    )

                    legend
                }
            }
            .navigationTitle("月度总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showStudents.toggle()
                    } label: {
                        Image(systemName: showStudents ? "person.fill" : "person")
                    }
                    .accessibilityLabel(showStudents ? "隐藏学生" : "显示学生")
                }
            }
            .sheet(item: Binding(
                get: { selectedDay.map { IdentifiableDate(date: $0) } },
                set: { selectedDay = $0?.date }
            )) { item in
                DayScheduleDetailView(
                    date: item.date,
                    lessons: snap.lessonsByDate[DateHelper.startOfDay(item.date)] ?? [],
                    timeRange: snap.timeRange,
                    onNavigateToSchedule: {
                        selectedDay = nil
                        onSelectDate?(item.date)
                        dismiss()
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Subviews

    private var monthNavigation: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Text(DateHelper.monthString(displayMonth))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.77, blue: 0.72),
                    Color(red: 0.29, green: 0.68, blue: 0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var weekdayHeaders: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { h in
                Text(h)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private struct IdentifiableDate: Identifiable {
        let id = UUID()
        let date: Date
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.34, green: 0.77, blue: 0.72))
                    .frame(width: 10, height: 10)
                Text("已排课")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 10, height: 10)
                Text("可约")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
