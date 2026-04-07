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

    // MARK: - Computed Properties

    private var lessonsInMonth: [Lesson] {
        let range = DateHelper.monthRange(for: displayMonth)
        return allLessons.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var lessonsByDate: [Date: [Lesson]] {
        var map: [Date: [Lesson]] = [:]
        for lesson in lessonsInMonth {
            let key = DateHelper.startOfDay(lesson.date)
            map[key, default: []].append(lesson)
        }
        return map
    }

    private var timeRange: (start: Int, end: Int) {
        // 最小范围固定为 8:00-22:00，只在有超出范围的课时才扩展
        // 确保同样 2 小时的课在不同月份显示高度一致
        let lessons = lessonsInMonth
        guard !lessons.isEmpty else { return (8, 22) }
        let cal = DateHelper.calendar
        let earliest = lessons.map { cal.component(.hour, from: $0.startTime) }.min() ?? 8
        let latest = lessons.map {
            let h = cal.component(.hour, from: $0.endTime)
            let m = cal.component(.minute, from: $0.endTime)
            return m > 0 ? h + 1 : h
        }.max() ?? 22
        return (min(max(earliest - 1, 0), 8), max(min(latest + 1, 24), 22))
    }

    /// Build mini blocks for a day cell (positioned by time fraction)
    private func miniBlocks(for date: Date) -> [MiniBlock] {
        let totalHours = CGFloat(max(timeRange.end - timeRange.start, 1))
        let lessons = lessonsByDate[DateHelper.startOfDay(date)] ?? []
        let cal = DateHelper.calendar
        return lessons.map { lesson in
            let startH = cal.component(.hour, from: lesson.startTime)
            let startM = cal.component(.minute, from: lesson.startTime)
            let endH = cal.component(.hour, from: lesson.endTime)
            let endM = cal.component(.minute, from: lesson.endTime)
            let startDecimal = CGFloat(startH) + CGFloat(startM) / 60.0
            let endDecimal = CGFloat(endH) + CGFloat(endM) / 60.0
            let rangeStart = CGFloat(timeRange.start)
            let startFrac = max((startDecimal - rangeStart) / totalHours, 0)
            let heightFrac = min((endDecimal - startDecimal) / totalHours, 1 - startFrac)

            // Compact time text: "9-11" or "9:30-11"
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

    private var calendarCells: [(date: Date, isCurrentMonth: Bool)] {
        let days = DateHelper.daysInMonth(for: displayMonth)
        guard let firstDay = days.first else { return [] }

        let weekday = DateHelper.calendar.component(.weekday, from: firstDay)
        let leadingOffset = (weekday + 5) % 7

        var result: [(Date, Bool)] = []

        // Leading days from previous month
        for i in (0..<leadingOffset).reversed() {
            if let prev = DateHelper.calendar.date(byAdding: .day, value: -(i + 1), to: firstDay) {
                result.append((prev, false))
            }
        }

        // Current month days
        for day in days {
            result.append((day, true))
        }

        // Trailing days to fill last row
        let remainder = result.count % 7
        if remainder > 0, let lastDay = days.last {
            for i in 1...(7 - remainder) {
                if let next = DateHelper.calendar.date(byAdding: .day, value: i, to: lastDay) {
                    result.append((next, false))
                }
            }
        }

        return result
    }

    private var isCurrentMonth: Bool {
        let now = Date.now
        let range = DateHelper.monthRange(for: displayMonth)
        return now >= range.start && now < range.end
    }

    private var weeksCount: Int {
        calendarCells.count / 7
    }

    private func cellHeight(in geometry: GeometryProxy) -> CGFloat {
        let navHeight: CGFloat = 44  // month navigation
        let weekdayHeight: CGFloat = 24
        let legendHeight: CGFloat = 32
        let available = geometry.size.height - navHeight - weekdayHeight - legendHeight
        return max(available / CGFloat(weeksCount), 70)
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
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    monthNavigation
                    weekdayHeaders

                    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, cell in
                            let key = DateHelper.startOfDay(cell.date)
                            let lessons = lessonsByDate[key] ?? []
                            let height = cellHeight(in: geometry)
                            DayAvailabilityCell(
                                date: cell.date,
                                blocks: miniBlocks(for: cell.date),
                                lessonCount: lessons.count,
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
                    lessons: lessonsByDate[DateHelper.startOfDay(item.date)] ?? [],
                    timeRange: timeRange,
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
