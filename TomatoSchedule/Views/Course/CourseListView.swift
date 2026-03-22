import SwiftUI
import SwiftData

struct CourseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.createdAt, order: .reverse) private var courses: [Course]

    @State private var showingAddForm = false
    @State private var editingCourse: Course?
    @State private var courseToDelete: Course?

    var body: some View {
        NavigationStack {
            Group {
                if courses.isEmpty {
                    EmptyStateView(
                        icon: "book.closed",
                        title: "还没有课程",
                        subtitle: "点击右上角 + 添加你的第一个课程"
                    )
                } else {
                    List {
                        ForEach(courses) { course in
                            courseRow(course)
                                .contentShape(Rectangle())
                                .onTapGesture { editingCourse = course }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        courseToDelete = course
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("我的课程")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddForm) {
                CourseFormView()
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
                        try? CalendarSyncService.shared.removeEventsForLessons(Array(course.lessons))
                        modelContext.delete(course)
                        courseToDelete = nil
                    }
                }
                Button("取消", role: .cancel) { courseToDelete = nil }
            } message: {
                if let course = courseToDelete {
                    let completed = course.completedLessons.count
                    let income = course.totalIncome
                    if completed > 0 && income > 0 {
                        Text("「\(course.name)」下有 \(completed) 节已完成课时，总收入 ¥\(Int(income))。删除后相关收入记录将一并移除且不可恢复。")
                    } else if completed > 0 {
                        Text("「\(course.name)」下有 \(completed) 节已完成课时。删除后不可恢复。")
                    } else {
                        Text("确定要删除「\(course.name)」吗？")
                    }
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
                if course.hourlyRate > 0 {
                    Text("¥\(Int(course.hourlyRate))/h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !course.notes.isEmpty {
                    Text(course.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
