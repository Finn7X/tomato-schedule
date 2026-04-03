import SwiftUI
import SwiftData

struct BatchLessonFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]
    @Query private var allLessons: [Lesson]

    // MARK: - Form State

    @State private var selectedCourse: Course?
    @State private var studentName: String = ""
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var startDate: Date = .now
    @State private var endDate: Date = {
        Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    }()
    @State private var selectedWeekdays: Set<Int> = [] // 1=Sunday...7=Saturday
    @State private var startTime: Date = {
        DateHelper.calendar.date(bySettingHour: 14, minute: 0, second: 0, of: .now) ?? .now
    }()
    @State private var endTime: Date = {
        DateHelper.calendar.date(bySettingHour: 16, minute: 0, second: 0, of: .now) ?? .now
    }()
    @State private var excludedDates: Set<Date> = []

    // MARK: - Weekday Config

    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    // Map display index to Calendar weekday: Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7, Sun=1
    private let weekdayValues = [2, 3, 4, 5, 6, 7, 1]

    // MARK: - Date Generation

    private var generatedDates: [Date] {
        guard !selectedWeekdays.isEmpty else { return [] }
        var dates: [Date] = []
        let cal = DateHelper.calendar
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            let weekday = cal.component(.weekday, from: current)
            if selectedWeekdays.contains(weekday) && !excludedDates.contains(current) {
                dates.append(current)
            }
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return Array(dates.prefix(100))
    }

    // MARK: - Conflict Detection

    private func hasConflict(on date: Date) -> Bool {
        let dayStart = DateHelper.combine(date: date, time: startTime)
        let dayEnd = DateHelper.combine(date: date, time: endTime)
        return allLessons.contains { existing in
            DateHelper.isSameDay(existing.date, date) &&
            existing.startTime < dayEnd &&
            existing.endTime > dayStart
        }
    }

    // MARK: - Lesson Numbering

    private func nextLessonNumber(for course: Course) -> Int {
        let maxStored = course.lessons.map(\.lessonNumber).max() ?? 0
        let totalCount = course.lessons.count
        return max(maxStored, totalCount) + 1
    }

    // MARK: - Price Freeze

    private func freezePrice(for lesson: Lesson) {
        guard !lesson.isPriceOverridden else { return }
        let rate = lesson.course?.hourlyRate ?? 0
        let minutes = DateHelper.calendar.dateComponents(
            [.minute], from: lesson.startTime, to: lesson.endTime
        ).minute ?? 0
        let price = rate > 0 ? (rate * Double(minutes) / 60.0 * 100).rounded() / 100 : 0
        lesson.priceOverride = price
        lesson.isPriceOverridden = true
        lesson.isManualPrice = false
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                courseSection
                studentSection
                recurrenceSection
                timeSection
                notesSection
                locationSection
                previewSection
            }
            .navigationTitle("批量排课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建 \(generatedDates.count) 节课") { createLessons() }
                        .disabled(selectedCourse == nil || generatedDates.isEmpty)
                }
            }
        }
    }

    // MARK: - Sections

    private var courseSection: some View {
        Section("课程选择") {
            if courses.isEmpty {
                Text("请先添加课程")
                    .foregroundStyle(.secondary)
            } else {
                Picker("选择课程", selection: $selectedCourse) {
                    Text("请选择").tag(nil as Course?)
                    ForEach(courses) { course in
                        HStack {
                            Circle()
                                .fill(PresetColors.color(for: course.colorHex))
                                .frame(width: 10, height: 10)
                            Text(course.name)
                        }
                        .tag(course as Course?)
                    }
                }
            }
        }
    }

    private var studentSection: some View {
        Section("学生") {
            TextField("学生姓名（可选）", text: $studentName)
        }
    }

    private var recurrenceSection: some View {
        Section("重复规则") {
            DatePicker("起始日期", selection: $startDate, displayedComponents: .date)
            DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)

            VStack(alignment: .leading, spacing: 8) {
                Text("重复星期")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        let value = weekdayValues[index]
                        let isSelected = selectedWeekdays.contains(value)

                        Button {
                            if isSelected {
                                selectedWeekdays.remove(value)
                            } else {
                                selectedWeekdays.insert(value)
                            }
                        } label: {
                            Text(weekdayLabels[index])
                                .font(.subheadline)
                                .frame(width: 36, height: 36)
                                .background(isSelected ? Color.teal : Color(.quaternarySystemFill))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        Section("上课时间") {
            TimeSlotPicker(
                startTime: $startTime,
                endTime: $endTime,
                date: startDate
            )
        }
    }

    private var notesSection: some View {
        Section("备注") {
            TextField("可选备注", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var locationSection: some View {
        Section("上课地点") {
            TextField("地点（可选）", text: $location)
        }
    }

    private var previewSection: some View {
        Section("预览（\(generatedDates.count)节课）") {
            if generatedDates.isEmpty {
                Text("请选择重复星期")
                    .foregroundStyle(.secondary)
            } else {
                let startNumber = selectedCourse.map { nextLessonNumber(for: $0) } ?? 1

                ForEach(Array(generatedDates.enumerated()), id: \.offset) { index, date in
                    HStack {
                        if hasConflict(on: date) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        Text(DateHelper.dateString(date))
                        Text(DateHelper.weekdaySymbol(date))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(DateHelper.timeString(startTime))-\(DateHelper.timeString(endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("第\(startNumber + index)节")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            excludedDates.insert(date)
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }

                if generatedDates.count >= 100 {
                    Text("最多显示100节")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Create Lessons

    private func createLessons() {
        guard let course = selectedCourse else { return }
        var number = nextLessonNumber(for: course)

        for date in generatedDates {
            let actualStart = DateHelper.combine(date: date, time: startTime)
            let actualEnd = DateHelper.combine(date: date, time: endTime)

            let lesson = Lesson(
                course: course,
                studentName: studentName.trimmingCharacters(in: .whitespaces),
                date: DateHelper.startOfDay(date),
                startTime: actualStart,
                endTime: actualEnd,
                notes: notes,
                lessonNumber: number,
                location: location.trimmingCharacters(in: .whitespaces)
            )
            freezePrice(for: lesson)
            modelContext.insert(lesson)
            try? CalendarSyncService.shared.syncLesson(lesson)
            number += 1
        }
        dismiss()
    }
}
