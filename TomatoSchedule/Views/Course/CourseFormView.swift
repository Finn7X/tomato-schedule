import SwiftUI
import SwiftData

struct CourseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let course: Course?

    @State private var name: String = ""
    @State private var colorHex: String = "#FF6B6B"
    @State private var notes: String = ""
    @State private var showAdvanced: Bool = false
    @State private var subject: String = ""
    @State private var totalHours: Double = 0
    @State private var totalLessons: Int = 0
    @State private var hourlyRate: Double = 0
    @State private var showRateChangeConfirmation = false
    @State private var pendingRate: Double = 0
    @State private var pendingOldRate: Double = 0

    var isEditing: Bool { course != nil }

    init(course: Course? = nil) {
        self.course = course
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程名称") {
                    TextField("例如：钢琴课、数学辅导", text: $name)
                }

                Section("课程颜色") {
                    ColorPickerGrid(selectedHex: $colorHex)
                }

                Section("备注") {
                    TextField("可选备注信息", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                    HStack {
                        Text("小时单价")
                        Spacer()
                        TextField("元", value: $hourlyRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("元/h").foregroundStyle(.secondary)
                    }
                    TextField("科目类型（如：阅读、数学）", text: $subject)
                    HStack {
                        Text("计划总课时")
                        Spacer()
                        TextField("小时", value: $totalHours, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("小时").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("计划总节数")
                        Spacer()
                        TextField("节", value: $totalLessons, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("节").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑课程" : "新建课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let course {
                    name = course.name
                    colorHex = course.colorHex
                    notes = course.notes
                    subject = course.subject
                    totalHours = course.totalHours
                    totalLessons = course.totalLessons
                    hourlyRate = course.hourlyRate
                    showAdvanced = !course.subject.isEmpty || course.totalHours > 0 || course.totalLessons > 0 || course.hourlyRate > 0
                }
            }
            .confirmationDialog(
                "课时单价已更改",
                isPresented: $showRateChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("更新未来课程") {
                    if let course {
                        applyAllChanges(course: course, updateFutureLessons: true)
                    }
                }
                Button("全部不更新") {
                    if let course {
                        applyAllChanges(course: course, updateFutureLessons: false)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("课时单价从 ¥\(Int(pendingOldRate))/h 更改为 ¥\(Int(pendingRate))/h。\n更新未来自动定价的课程？（手动设定过价格的课不受影响）")
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let course {
            let rateChanged = course.hourlyRate != hourlyRate && hourlyRate > 0
            if rateChanged && course.lessons.contains(where: { !$0.isCompleted }) {
                pendingRate = hourlyRate
                pendingOldRate = course.hourlyRate
                showRateChangeConfirmation = true
                return
            }
            applyAllChanges(course: course)
        } else {
            let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
            let newCourse = Course(
                name: trimmedName,
                colorHex: colorHex,
                notes: notes,
                subject: trimmedSubject,
                totalHours: totalHours,
                totalLessons: totalLessons,
                hourlyRate: hourlyRate
            )
            modelContext.insert(newCourse)
        }
        dismiss()
    }

    private func applyAllChanges(course: Course, updateFutureLessons: Bool = false) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
        let oldTotalLessons = course.totalLessons
        let needsCalendarSync = course.name != trimmedName || course.subject != trimmedSubject
        let needsSequenceResync = oldTotalLessons != totalLessons

        course.name = trimmedName
        course.colorHex = colorHex
        course.notes = notes
        course.subject = trimmedSubject
        course.totalHours = totalHours
        course.totalLessons = totalLessons
        course.hourlyRate = hourlyRate

        if updateFutureLessons {
            let futureLessons = course.lessons.filter {
                !$0.isCompleted && $0.startTime > .now && !$0.isManualPrice
            }
            for lesson in futureLessons {
                let minutes = DateHelper.calendar.dateComponents(
                    [.minute], from: lesson.startTime, to: lesson.endTime
                ).minute ?? 0
                lesson.priceOverride = (hourlyRate * Double(minutes) / 60.0 * 100).rounded() / 100
            }
        }

        if needsCalendarSync || needsSequenceResync {
            try? CalendarSyncService.shared.syncLessonsForCourse(course)
        }

        dismiss()
    }
}
