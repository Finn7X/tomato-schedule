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
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
        if let course {
            let needsCalendarSync = course.name != trimmedName || course.subject != trimmedSubject
            course.name = trimmedName
            course.colorHex = colorHex
            course.notes = notes
            course.subject = trimmedSubject
            course.totalHours = totalHours
            course.totalLessons = totalLessons
            course.hourlyRate = hourlyRate
            if needsCalendarSync {
                try? CalendarSyncService.shared.syncLessonsForCourse(course)
            }
        } else {
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
}
