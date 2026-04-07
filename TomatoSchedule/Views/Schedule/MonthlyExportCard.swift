import SwiftUI

struct MonthlyExportCard: View {
    let month: Date
    let lessonsByDate: [Date: [Lesson]]
    let timeRange: (start: Int, end: Int)

    // MARK: - Helpers

    private var futureDates: [Date] {
        let cal = DateHelper.calendar
        let range = DateHelper.monthRange(for: month)
        let today = cal.startOfDay(for: .now)
        var dates: [Date] = []
        var current = max(range.start, today)
        while current < range.end {
            dates.append(current)
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }

    private func exportBins(for date: Date) -> [Bool] {
        let totalSlots = (timeRange.end - timeRange.start) * 2 // 30-min bins
        guard totalSlots > 0 else { return [] }
        var bins = Array(repeating: false, count: totalSlots)
        let lessons = lessonsByDate[DateHelper.startOfDay(date)] ?? []
        let cal = DateHelper.calendar
        for lesson in lessons {
            let startH = cal.component(.hour, from: lesson.startTime)
            let startM = cal.component(.minute, from: lesson.startTime)
            let endH = cal.component(.hour, from: lesson.endTime)
            let endM = cal.component(.minute, from: lesson.endTime)
            let startSlot = max(((startH - timeRange.start) * 60 + startM) / 30, 0)
            let endSlot = min(((endH - timeRange.start) * 60 + endM + 29) / 30, totalSlots)
            for i in startSlot..<endSlot { bins[i] = true }
        }
        return bins
    }

    // MARK: - Subviews

    private var timeAxisLabels: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 60)
            let hours = Array(stride(from: timeRange.start, through: timeRange.end, by: 2))
            ForEach(hours, id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayRow(date: Date) -> some View {
        let bins = exportBins(for: date)
        return HStack(spacing: 0) {
            // Date label
            HStack(spacing: 2) {
                Text(shortDateString(date))
                    .font(.system(size: 11))
                Text(DateHelper.weekdaySymbol(date).replacingOccurrences(of: "周", with: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60, alignment: .leading)

            // Time bar
            HStack(spacing: 0) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, busy in
                    Rectangle()
                        .fill(busy ? Color(red: 0.34, green: 0.77, blue: 0.72).opacity(0.85) : Color.gray.opacity(0.12))
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 12)
    }

    /// Short date format for export card: "M/d"
    private func shortDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Title
            Text("番茄课表 · \(DateHelper.calendar.component(.month, from: month))月排课总览")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 16)

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.34, green: 0.77, blue: 0.72))
                        .frame(width: 12, height: 12)
                    Text("已排课（不可约）")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 12, height: 12)
                    Text("空闲（可约）")
                        .font(.caption)
                }
            }

            // Time axis
            timeAxisLabels

            // Day rows
            if futureDates.isEmpty {
                Text("本月课程已全部结束")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(futureDates, id: \.self) { date in
                    dayRow(date: date)
                }
            }

            // Footer
            VStack(spacing: 2) {
                Text("导出时间：\(DateHelper.dateString(.now))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("灰色区域为可约时间，欢迎联系老师预约")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(width: 390)
        .background(.white)
    }
}
