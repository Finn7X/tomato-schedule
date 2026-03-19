import SwiftUI
import SwiftData

struct DayScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Date.now
    @State private var showingAddLesson = false
    @State private var editingLesson: Lesson?

    @Query private var allLessons: [Lesson]

    private var lessonsForDay: [Lesson] {
        allLessons
            .filter { DateHelper.isSameDay($0.date, selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { moveDay(-1) } label: {
                        Image(systemName: "chevron.left")
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(DateHelper.dateString(selectedDate))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(DateHelper.weekdaySymbol(selectedDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture { selectedDate = .now }

                    Spacer()

                    Button { moveDay(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding()

                Divider()

                if lessonsForDay.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: "今天没有课",
                        subtitle: "点击右上角 + 添加课时"
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(lessonsForDay) { lesson in
                            LessonCardView(lesson: lesson)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture { editingLesson = lesson }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("日视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddLesson = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") { selectedDate = .now }
                        .disabled(DateHelper.isSameDay(selectedDate, .now))
                }
            }
            .sheet(isPresented: $showingAddLesson) {
                LessonFormView(initialDate: selectedDate)
            }
            .sheet(item: $editingLesson) { lesson in
                LessonFormView(lesson: lesson, initialDate: lesson.date)
            }
        }
    }

    private func moveDay(_ offset: Int) {
        if let newDate = DateHelper.calendar.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = newDate
        }
    }
}
