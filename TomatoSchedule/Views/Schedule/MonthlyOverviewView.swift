import SwiftUI
import SwiftData

struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @State private var displayMonth: Date = .now
    @State private var selectedDay: Date?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

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
        let lessons = lessonsInMonth
        guard !lessons.isEmpty else { return (8, 22) }
        let cal = DateHelper.calendar
        let earliest = lessons.map { cal.component(.hour, from: $0.startTime) }.min() ?? 8
        let latest = lessons.map {
            let h = cal.component(.hour, from: $0.endTime)
            let m = cal.component(.minute, from: $0.endTime)
            return m > 0 ? h + 1 : h
        }.max() ?? 22
        return (max(earliest - 1, 0), min(latest + 1, 24))
    }

    private func busyBins(for date: Date) -> [Bool] {
        let totalSlots = timeRange.end - timeRange.start
        guard totalSlots > 0 else { return [] }
        var bins = Array(repeating: false, count: totalSlots)
        let lessons = lessonsByDate[DateHelper.startOfDay(date)] ?? []
        let cal = DateHelper.calendar
        for lesson in lessons {
            let startH = cal.component(.hour, from: lesson.startTime)
            let endH = cal.component(.hour, from: lesson.endTime)
            let endM = cal.component(.minute, from: lesson.endTime)
            let startSlot = max(startH - timeRange.start, 0)
            let endSlot = min(endM > 0 ? endH - timeRange.start + 1 : endH - timeRange.start, totalSlots)
            for i in startSlot..<endSlot { bins[i] = true }
        }
        return bins
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

    // MARK: - Actions

    private func moveMonth(_ offset: Int) {
        if let newMonth = DateHelper.calendar.date(byAdding: .month, value: offset, to: displayMonth) {
            displayMonth = newMonth
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthNavigation

                weekdayHeaders

                let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, cell in
                        let key = DateHelper.startOfDay(cell.date)
                        let lessons = lessonsByDate[key] ?? []
                        DayAvailabilityCell(
                            date: cell.date,
                            busyBins: busyBins(for: cell.date),
                            lessonCount: lessons.count,
                            isCurrentMonth: cell.isCurrentMonth,
                            isToday: DateHelper.isSameDay(cell.date, .now)
                        )
                        .onTapGesture {
                            if cell.isCurrentMonth {
                                selectedDay = cell.date
                            }
                        }
                    }
                }

                legend

                Spacer()
            }
            .navigationTitle("月度排课总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
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
            .sheet(isPresented: $showShareSheet) {
                if let image = shareImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }

    // MARK: - Export

    @MainActor
    private func exportImage() {
        let content = MonthlyExportCard(
            month: displayMonth,
            lessonsByDate: lessonsByDate,
            timeRange: timeRange
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
    }

    // MARK: - Subviews

    private var monthNavigation: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(DateHelper.monthString(displayMonth))
                .font(.headline)
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
            if !isCurrentMonth {
                Button("回到本月") { displayMonth = .now }
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var weekdayHeaders: some View {
        let headers = ["一", "二", "三", "四", "五", "六", "日"]
        return HStack(spacing: 0) {
            ForEach(headers, id: \.self) { h in
                Text(h)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    private struct IdentifiableDate: Identifiable {
        let id = UUID()
        let date: Date
    }

    private struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }
        func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
    }

    private var legend: some View {
        VStack(spacing: 2) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.34, green: 0.77, blue: 0.72))
                        .frame(width: 12, height: 12)
                    Text("已排课")
                        .font(.caption2)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 12, height: 12)
                    Text("可约时间")
                        .font(.caption2)
                }
            }
            Text("月网格为粗粒度忙闲趋势，精确时间以导出图为准")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }
}
