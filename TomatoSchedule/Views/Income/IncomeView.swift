import SwiftUI
import SwiftData
import Charts

struct IncomeView: View {
    @Query private var allLessons: [Lesson]
    @Query(sort: \Course.name) private var courses: [Course]

    @State private var period: Period = .month

    enum Period: String, CaseIterable {
        case week = "周"
        case month = "月"
        case year = "年"
    }

    // MARK: - Computed

    private var completedLessons: [Lesson] {
        allLessons.filter { $0.isCompleted || $0.endTime < .now }
    }

    private var currentRange: (start: Date, end: Date) {
        let cal = DateHelper.calendar
        let now = Date.now
        switch period {
        case .week:
            return DateHelper.weekRange(for: now)
        case .month:
            return DateHelper.monthRange(for: now)
        case .year:
            let start = cal.date(from: cal.dateComponents([.year], from: now))!
            let end = cal.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }

    private var lessonsInRange: [Lesson] {
        let range = currentRange
        return completedLessons.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var totalIncome: Double {
        lessonsInRange.reduce(0) { $0 + $1.effectivePrice }
    }

    private var lessonCount: Int {
        lessonsInRange.count
    }

    private var avgIncome: Double {
        lessonCount > 0 ? totalIncome / Double(lessonCount) : 0
    }

    // MARK: - Chart data

    private struct ChartEntry: Identifiable {
        let id = UUID()
        let label: String
        let courseName: String
        let courseColor: String
        let income: Double
    }

    private var chartData: [ChartEntry] {
        let cal = DateHelper.calendar
        let range = currentRange
        var entries: [ChartEntry] = []

        for lesson in lessonsInRange {
            let label: String
            switch period {
            case .week:
                label = DateHelper.weekdaySymbol(lesson.date)
            case .month:
                label = "\(cal.component(.day, from: lesson.date))日"
            case .year:
                label = "\(cal.component(.month, from: lesson.date))月"
            }
            entries.append(ChartEntry(
                label: label,
                courseName: lesson.course?.name ?? "未知",
                courseColor: lesson.course?.colorHex ?? "#78909C",
                income: lesson.effectivePrice
            ))
        }
        return entries
    }

    // Course ranking
    private struct CourseIncome: Identifiable {
        let id = UUID()
        let name: String
        let colorHex: String
        let count: Int
        let income: Double
        let percentage: Double
    }

    private var courseRanking: [CourseIncome] {
        var map: [UUID: (name: String, color: String, count: Int, income: Double)] = [:]
        for lesson in lessonsInRange {
            let cid = lesson.course?.id ?? UUID()
            let name = lesson.course?.name ?? "未知"
            let color = lesson.course?.colorHex ?? "#78909C"
            var entry = map[cid] ?? (name, color, 0, 0)
            entry.count += 1
            entry.income += lesson.effectivePrice
            map[cid] = entry
        }
        let total = max(totalIncome, 1)
        return map.values
            .map { CourseIncome(name: $0.name, colorHex: $0.color, count: $0.count, income: $0.income, percentage: $0.income / total * 100) }
            .sorted { $0.income > $1.income }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Period picker
                    Picker("时间维度", selection: $period) {
                        ForEach(Period.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Summary cards
                    HStack(spacing: 12) {
                        summaryCard(title: periodLabel + "收入", value: "¥\(Int(totalIncome))")
                        summaryCard(title: "已完成", value: "\(lessonCount) 节")
                        summaryCard(title: "课均", value: "¥\(Int(avgIncome))")
                    }
                    .padding(.horizontal)

                    // Chart
                    if !chartData.isEmpty {
                        Chart(chartData) { entry in
                            BarMark(
                                x: .value("时间", entry.label),
                                y: .value("收入", entry.income)
                            )
                            .foregroundStyle(by: .value("课程", entry.courseName))
                        }
                        .frame(height: 220)
                        .padding(.horizontal)
                    } else {
                        Text("暂无收入数据")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(height: 220)
                    }

                    // Course ranking
                    if !courseRanking.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(periodLabel + "课程收入")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal)
                                .padding(.bottom, 8)

                            ForEach(courseRanking) { item in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(PresetColors.color(for: item.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(item.name)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(item.count)节")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("¥\(Int(item.income))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(width: 70, alignment: .trailing)
                                    Text(String(format: "%.0f%%", item.percentage))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .trailing)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("收入")
        }
    }

    // MARK: - Helpers

    private var periodLabel: String {
        switch period {
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "本年"
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }
}
