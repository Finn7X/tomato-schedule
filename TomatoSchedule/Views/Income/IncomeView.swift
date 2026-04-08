import SwiftUI
import SwiftData
import Charts

struct IncomeView: View {
    @Query private var allLessons: [Lesson]
    @Query(sort: \Course.name) private var courses: [Course]

    @AppStorage("showEstimatedIncome") private var showEstimatedIncome = true
    @State private var period: Period = .month
    @State private var referenceDate: Date = .now
    @State private var rankingMode: RankingMode = .byStudent

    enum Period: String, CaseIterable {
        case week = "周"
        case month = "月"
        case year = "年"
    }

    enum RankingMode: String, CaseIterable {
        case byCourse = "按课程"
        case byStudent = "按学生"
    }

    // MARK: - Computed

    private var completedLessons: [Lesson] {
        allLessons.filter { $0.isCompleted || $0.endTime < .now }
    }

    private var currentRange: (start: Date, end: Date) {
        let cal = DateHelper.calendar
        switch period {
        case .week:
            return DateHelper.weekRange(for: referenceDate)
        case .month:
            return DateHelper.monthRange(for: referenceDate)
        case .year:
            let start = cal.date(from: cal.dateComponents([.year], from: referenceDate))!
            let end = cal.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }

    private var allLessonsInRange: [Lesson] {
        let range = currentRange
        return allLessons.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var estimatedIncome: Double {
        allLessonsInRange.reduce(0) { $0 + $1.effectivePrice }
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
        let sortOrder: Int       // for correct x-axis ordering
        let courseName: String
        let courseColor: String
        let studentKey: String
        let income: Double
    }

    private var chartData: [ChartEntry] {
        let cal = DateHelper.calendar
        var entries: [ChartEntry] = []

        for lesson in lessonsInRange {
            let sKey = normalizeStudentName(lesson.studentName)
            if rankingMode == .byStudent && sKey.isEmpty { continue }
            let label: String
            let order: Int
            switch period {
            case .week:
                label = DateHelper.weekdaySymbol(lesson.date)
                // Monday=2..Sunday=1 → remap to 0..6 for sorting
                let wd = cal.component(.weekday, from: lesson.date)
                order = (wd + 5) % 7  // Mon=0, Tue=1, ..., Sun=6
            case .month:
                let day = cal.component(.day, from: lesson.date)
                label = "\(day)日"
                order = day
            case .year:
                let month = cal.component(.month, from: lesson.date)
                label = "\(month)月"
                order = month
            }
            entries.append(ChartEntry(
                label: label,
                sortOrder: order,
                courseName: lesson.course?.name ?? "未知",
                courseColor: lesson.course?.colorHex ?? "#78909C",
                studentKey: sKey,
                income: lesson.effectivePrice
            ))
        }
        // Sort by sortOrder so Chart x-axis renders in chronological order
        return entries.sorted { $0.sortOrder < $1.sortOrder }
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

    // Student ranking
    private struct StudentIncome: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
        let income: Double
        let percentage: Double
    }

    private var studentRanking: [StudentIncome] {
        var map: [String: (count: Int, income: Double)] = [:]
        for lesson in lessonsInRange {
            let key = normalizeStudentName(lesson.studentName)
            guard !key.isEmpty else { continue }
            var entry = map[key] ?? (0, 0)
            entry.count += 1
            entry.income += lesson.effectivePrice
            map[key] = entry
        }
        let total = max(totalIncome, 1)
        return map.map { StudentIncome(name: $0.key, count: $0.value.count, income: $0.value.income, percentage: $0.value.income / total * 100) }
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

                    // Period navigation
                    HStack {
                        Button { movePeriod(-1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(periodTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button { movePeriod(1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        if !isCurrentPeriod {
                            Button("回到当前") {
                                referenceDate = .now
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)

                    // Summary cards
                    if showEstimatedIncome {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            summaryCard(title: periodLabel + "收入", value: "¥\(Int(totalIncome))")
                            summaryCard(title: "预估收入", value: "¥\(Int(estimatedIncome))")
                            summaryCard(title: "已完成", value: "\(lessonCount) 节")
                            summaryCard(title: "课均", value: "¥\(Int(avgIncome))")
                        }
                        .padding(.horizontal)
                    } else {
                        HStack(spacing: 12) {
                            summaryCard(title: periodLabel + "收入", value: "¥\(Int(totalIncome))")
                            summaryCard(title: "已完成", value: "\(lessonCount) 节")
                            summaryCard(title: "课均", value: "¥\(Int(avgIncome))")
                        }
                        .padding(.horizontal)
                    }

                    // Chart
                    if !chartData.isEmpty {
                        Chart(chartData) { entry in
                            BarMark(
                                x: .value("时间", entry.label),
                                y: .value("收入", entry.income)
                            )
                            .foregroundStyle(by: .value(
                                rankingMode == .byCourse ? "课程" : "学生",
                                rankingMode == .byCourse ? entry.courseName : entry.studentKey
                            ))
                        }
                        .frame(height: 220)
                        .padding(.horizontal)
                    } else {
                        Text("暂无收入数据")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(height: 220)
                    }

                    // Ranking mode picker
                    Picker("排行维度", selection: $rankingMode) {
                        ForEach(RankingMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if rankingMode == .byCourse {
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
                    } else {
                        // Student ranking
                        if !studentRanking.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(periodLabel + "学生收入")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)

                                ForEach(studentRanking) { item in
                                    NavigationLink {
                                        StudentIncomeDetailView(studentName: item.name, initialMonth: referenceDate)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(.secondary)
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
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("收入")
        }
        .onChange(of: period) { _, _ in
            referenceDate = .now
        }
    }

    // MARK: - Helpers

    private func movePeriod(_ offset: Int) {
        let cal = DateHelper.calendar
        switch period {
        case .week:
            referenceDate = cal.date(byAdding: .weekOfYear, value: offset, to: referenceDate) ?? referenceDate
        case .month:
            referenceDate = cal.date(byAdding: .month, value: offset, to: referenceDate) ?? referenceDate
        case .year:
            referenceDate = cal.date(byAdding: .year, value: offset, to: referenceDate) ?? referenceDate
        }
    }

    private var periodTitle: String {
        let cal = DateHelper.calendar
        switch period {
        case .week:
            let range = DateHelper.weekRange(for: referenceDate)
            return "\(DateHelper.dateString(range.start)) - \(DateHelper.dateString(range.end))"
        case .month:
            return DateHelper.monthString(referenceDate)
        case .year:
            return "\(cal.component(.year, from: referenceDate))年"
        }
    }

    private var isCurrentPeriod: Bool {
        let now = Date.now
        let range = currentRange
        return now >= range.start && now < range.end
    }

    private var periodLabel: String {
        if isCurrentPeriod {
            switch period {
            case .week: return "本周"
            case .month: return "本月"
            case .year: return "本年"
            }
        }
        let cal = DateHelper.calendar
        switch period {
        case .week: return periodTitle
        case .month: return "\(cal.component(.month, from: referenceDate))月"
        case .year: return "\(cal.component(.year, from: referenceDate))年"
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
