import SwiftUI
import SwiftData

struct LessonFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]

    let lesson: Lesson?
    let initialDate: Date

    @State private var selectedCourse: Course?
    @State private var studentName: String = ""
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String = ""
    @State private var showAdvanced: Bool = false
    @State private var lessonNumber: Int = 0
    @State private var isCompleted: Bool = false
    @State private var location: String = ""
    @State private var isManualPrice: Bool = false
    @State private var priceOverride: Double = 0

    var isEditing: Bool { lesson != nil }

    init(lesson: Lesson? = nil, initialDate: Date = .now) {
        self.lesson = lesson
        self.initialDate = initialDate

        let calendar = DateHelper.calendar
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: initialDate) ?? initialDate
        let defaultEnd = calendar.date(byAdding: .hour, value: 1, to: defaultStart) ?? initialDate

        _date = State(initialValue: initialDate)
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: defaultEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程") {
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

                Section("学生") {
                    TextField("学生姓名（可选）", text: $studentName)
                }

                Section("时间") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section("备注") {
                    TextField("可选备注", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                DisclosureGroup("更多设置", isExpanded: $showAdvanced) {
                    HStack {
                        Text("第几节课")
                        Spacer()
                        TextField("节次", value: $lessonNumber, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        if let total = selectedCourse?.totalLessons, total > 0 {
                            Text("/ \(total)").foregroundStyle(.secondary)
                        }
                    }
                    Toggle("已完成", isOn: $isCompleted)
                    TextField("上课地点（可选）", text: $location)

                    // Pricing
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("课时费用", selection: $isManualPrice) {
                            Text("自动计算").tag(false)
                            Text("自定义").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if isManualPrice {
                            HStack {
                                Text("¥")
                                TextField("金额", value: $priceOverride, format: .number)
                                    .keyboardType(.decimalPad)
                                Text("(0 = 免费)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if isEditing, let lesson {
                            let snapshot = lesson.priceOverride
                            if snapshot > 0 {
                                Text("\(formatPrice(snapshot)) (已锁定)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未定价")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if let rate = selectedCourse?.hourlyRate, rate > 0 {
                                let auto = (rate * Double(durationMinutes) / 60.0 * 100).rounded() / 100
                                Text("\(formatPrice(auto)) (\(formatPrice(rate))/h)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let lesson { modelContext.delete(lesson) }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("删除此课时")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑课时" : "添加课时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(selectedCourse == nil)
                }
            }
            .onAppear {
                if let lesson {
                    selectedCourse = lesson.course
                    studentName = lesson.studentName
                    date = lesson.date
                    startTime = lesson.startTime
                    endTime = lesson.endTime
                    notes = lesson.notes
                    lessonNumber = lesson.lessonNumber
                    isCompleted = lesson.isCompleted
                    location = lesson.location
                    isManualPrice = lesson.isManualPrice
                    priceOverride = lesson.priceOverride
                    showAdvanced = lesson.lessonNumber > 0 || lesson.isCompleted || !lesson.location.isEmpty || lesson.isManualPrice
                }
            }
        }
    }

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

    private func formatPrice(_ p: Double) -> String {
        p == p.rounded() ? "¥\(Int(p))" : String(format: "¥%.1f", p)
    }

    private var durationMinutes: Int {
        max(DateHelper.calendar.dateComponents([.minute], from: startTime, to: endTime).minute ?? 60, 1)
    }

    private func save() {
        guard let selectedCourse else { return }

        let actualStart = DateHelper.combine(date: date, time: startTime)
        let actualEnd = DateHelper.combine(date: date, time: endTime)

        if let lesson {
            lesson.course = selectedCourse
            lesson.studentName = studentName.trimmingCharacters(in: .whitespaces)
            lesson.date = DateHelper.startOfDay(date)
            lesson.startTime = actualStart
            lesson.endTime = actualEnd
            lesson.notes = notes
            lesson.lessonNumber = lessonNumber
            lesson.isCompleted = isCompleted
            lesson.location = location.trimmingCharacters(in: .whitespaces)

            let wasManual = lesson.isManualPrice
            lesson.isManualPrice = isManualPrice
            if isManualPrice {
                lesson.isPriceOverridden = true
                lesson.priceOverride = priceOverride
            } else if wasManual && !isManualPrice {
                let rate = selectedCourse.hourlyRate
                let minutes = DateHelper.calendar.dateComponents(
                    [.minute], from: actualStart, to: actualEnd
                ).minute ?? 0
                let price = rate > 0 ? (rate * Double(minutes) / 60.0 * 100).rounded() / 100 : 0
                lesson.priceOverride = price
                lesson.isPriceOverridden = true
            }
        } else {
            let newLesson = Lesson(
                course: selectedCourse,
                studentName: studentName.trimmingCharacters(in: .whitespaces),
                date: DateHelper.startOfDay(date),
                startTime: actualStart,
                endTime: actualEnd,
                notes: notes,
                lessonNumber: lessonNumber,
                isCompleted: isCompleted,
                location: location.trimmingCharacters(in: .whitespaces)
            )
            if isManualPrice {
                newLesson.isPriceOverridden = true
                newLesson.isManualPrice = true
                newLesson.priceOverride = priceOverride
            } else {
                freezePrice(for: newLesson)
            }
            modelContext.insert(newLesson)
            try? CalendarSyncService.shared.syncLesson(newLesson)
        }
        if let lesson {
            try? CalendarSyncService.shared.syncLesson(lesson)
        }
        dismiss()
    }
}
