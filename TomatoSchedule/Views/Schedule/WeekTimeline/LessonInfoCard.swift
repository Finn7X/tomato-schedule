import SwiftUI

struct LessonInfoCard: View {
    let lesson: Lesson
    let overflowCompanions: [Lesson]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let course = lesson.course {
                        LabeledContent("课程", value: course.name)
                    } else {
                        LabeledContent("课程", value: "未关联课程")
                    }
                    LabeledContent("学生", value: lesson.studentName.isEmpty ? "无学生" : lesson.studentName)
                    LabeledContent("时间", value: lesson.timeRangeText)
                    LabeledContent("时长", value: "\(lesson.durationMinutes) 分钟")
                    if !lesson.notes.isEmpty {
                        LabeledContent("备注", value: lesson.notes)
                    }
                    if lesson.effectivePrice > 0 {
                        LabeledContent("价格", value: "¥ \(String(format: "%.0f", lesson.effectivePrice))")
                    }
                }

                if !overflowCompanions.isEmpty {
                    Section("同时段其它课时") {
                        ForEach(overflowCompanions, id: \.id) { companion in
                            HStack {
                                Circle()
                                    .fill(PresetColors.color(for: companion.course?.colorHex ?? "#94A3B8"))
                                    .frame(width: 8, height: 8)
                                Text(companion.studentName)
                                Spacer()
                                Text(companion.timeRangeText)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("课时详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
