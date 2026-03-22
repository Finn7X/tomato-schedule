import SwiftUI
import SwiftData

struct CourseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.createdAt, order: .reverse) private var courses: [Course]

    @State private var showingAddForm = false
    @State private var editingCourse: Course?

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
                                        try? CalendarSyncService.shared.removeEventsForLessons(Array(course.lessons))
                                        modelContext.delete(course)
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
                if !course.notes.isEmpty {
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
