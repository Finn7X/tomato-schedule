import SwiftUI
import SwiftData

struct StudentIncomeDetailView: View {
    let studentName: String
    @Query private var allLessons: [Lesson]
    @AppStorage("showEstimatedIncome") private var showEstimatedIncome = true
    @State private var referenceDate: Date

    init(studentName: String, initialMonth: Date = .now) {
        self.studentName = studentName
        _referenceDate = State(initialValue: initialMonth)
    }

    // MARK: - Computed

    private var studentLessons: [Lesson] {
        let key = normalizeStudentName(studentName)
        return allLessons.filter { normalizeStudentName($0.studentName) == key }
    }

    private var lessonsInMonth: [Lesson] {
        let range = DateHelper.monthRange(for: referenceDate)
        return studentLessons
            .filter { $0.date >= range.start && $0.date < range.end }
            .sorted { $0.startTime < $1.startTime }
    }

    private var completedInMonth: [Lesson] {
        lessonsInMonth.filter { $0.isCompleted || $0.endTime < .now }
    }

    private var actualIncome: Double {
        completedInMonth.reduce(0) { $0 + $1.effectivePrice }
    }

    private var estimatedIncome: Double {
        lessonsInMonth.reduce(0) { $0 + $1.effectivePrice }
    }

    private var isCurrentMonth: Bool {
        let now = Date.now
        let range = DateHelper.monthRange(for: referenceDate)
        return now >= range.start && now < range.end
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Month navigation
                HStack {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(DateHelper.monthString(referenceDate))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    if !isCurrentMonth {
                        Button("回到本月") {
                            referenceDate = .now
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal)

                // Summary cards
                HStack(spacing: 12) {
                    summaryCard(title: "本月收入", value: "¥\(Int(actualIncome))")
                    if showEstimatedIncome && estimatedIncome > actualIncome {
                        summaryCard(title: "预估收入", value: "¥\(Int(estimatedIncome))")
                    }
                    summaryCard(title: "已完成", value: "\(completedInMonth.count) 节")
                }
                .padding(.horizontal)

                // Lesson list
                if lessonsInMonth.isEmpty {
                    Text("该月无课时记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(lessonsInMonth) { lesson in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(DateHelper.dateString(lesson.date))
                                            .font(.subheadline)
                                        Text(DateHelper.weekdaySymbol(lesson.date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(lesson.course?.name ?? "未知课程")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(lesson.timeRangeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if lesson.effectivePrice > 0 {
                                    Text("¥\(Int(lesson.effectivePrice))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(width: 70, alignment: .trailing)
                                } else {
                                    Text("")
                                        .frame(width: 70)
                                }
                                if lesson.isCompleted || lesson.endTime < .now {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            Divider().padding(.leading)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
        .navigationTitle(studentName)
    }

    // MARK: - Helpers

    private func moveMonth(_ offset: Int) {
        if let newMonth = DateHelper.calendar.date(byAdding: .month, value: offset, to: referenceDate) {
            referenceDate = newMonth
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
