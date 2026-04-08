import SwiftUI
import SwiftData

struct CourseListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.createdAt, order: .reverse) private var courses: [Course]

    @AppStorage("showIncomeInCourseList") private var showIncome = true
    @State private var editingCourse: Course?
    @State private var courseToDelete: Course?
    @State private var searchText = ""

    private var filteredCourses: [Course] {
        if searchText.isEmpty { return courses }
        return courses.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if courses.isEmpty {
                EmptyStateView(
                    icon: "book.closed",
                    title: "还没有课程",
                    subtitle: "点击右上角 + 添加你的第一个课程"
                )
            } else {
                List {
                    ForEach(filteredCourses) { course in
                        HStack {
                            courseRow(course)
                            if showIncome && course.totalIncome > 0 {
                                Text("¥\(Int(course.totalIncome))")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingCourse = course }
                        .contextMenu {
                            Button(role: .destructive) {
                                courseToDelete = course
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "搜索课程")
            }
        }
        .sheet(item: $editingCourse) { course in
            CourseFormView(course: course)
        }
        .confirmationDialog(
            "确认删除课程",
            isPresented: Binding(
                get: { courseToDelete != nil },
                set: { if !$0 { courseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认删除", role: .destructive) {
                if let course = courseToDelete {
                    modelContext.delete(course)
                    courseToDelete = nil
                }
            }
            Button("取消", role: .cancel) { courseToDelete = nil }
        } message: {
            if let course = courseToDelete {
                let lessonCount = course.lessons.count
                if lessonCount > 0 {
                    Text("「\(course.name)」下有 \(lessonCount) 节课时。删除课程后课时记录和收入将保留，但不再关联此课程。")
                } else {
                    Text("确定要删除「\(course.name)」吗？")
                }
            }
        }
    }

    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(PresetColors.color(for: course.colorHex))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    if course.hourlyRate > 0 {
                        Text("¥\(Int(course.hourlyRate))/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !course.notes.isEmpty {
                        Text(course.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text("\(course.lessons.count) 节课")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
