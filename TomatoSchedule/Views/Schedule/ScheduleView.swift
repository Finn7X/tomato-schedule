import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allLessons: [Lesson]

    @State private var selectedDate: Date = .now
    @State private var displayedMonth: Date = .now
    @State private var isExpanded: Bool = true
    @State private var showingAddLesson: Bool = false
    @State private var editingLesson: Lesson?

    // MARK: - Computed

    private var lessonCountsByDate: [Date: Int] {
        var counts: [Date: Int] = [:]
        for lesson in allLessons {
            let key = DateHelper.startOfDay(lesson.date)
            counts[key, default: 0] += 1
        }
        return counts
    }

    private var lessonsForSelectedDate: [Lesson] {
        allLessons
            .filter { DateHelper.isSameDay($0.date, selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }

    private var statisticsTotal: Int {
        lessonsInRange.count
    }

    private var statisticsCompleted: Int {
        lessonsInRange.filter(\.isCompleted).count
    }

    private var lessonsInRange: [Lesson] {
        if isExpanded {
            let range = DateHelper.monthRange(for: displayedMonth)
            return allLessons.filter { $0.date >= range.start && $0.date < range.end }
        } else {
            let range = DateHelper.weekRange(for: selectedDate)
            return allLessons.filter { $0.date >= range.start && $0.date < range.end }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CalendarHeaderView(
                    selectedDate: $selectedDate,
                    displayedMonth: $displayedMonth,
                    isExpanded: $isExpanded,
                    lessonCounts: lessonCountsByDate
                )

                StatisticsBar(
                    isMonthMode: isExpanded,
                    month: displayedMonth,
                    weekStart: DateHelper.weekRange(for: selectedDate).start,
                    totalCount: statisticsTotal,
                    completedCount: statisticsCompleted
                )

                Divider()

                if lessonsForSelectedDate.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: "暂无课程",
                        subtitle: "点击右上角 + 添加课时"
                    )
                    Spacer()
                } else {
                    lessonList
                }
            }
            .navigationTitle("课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddLesson = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") {
                        selectedDate = .now
                        displayedMonth = .now
                    }
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

    // MARK: - Lesson List

    private var lessonList: some View {
        List {
            ForEach(lessonsForSelectedDate) { lesson in
                LessonTimeGroup(lesson: lesson) {
                    editingLesson = lesson
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        withAnimation { modelContext.delete(lesson) }
                    } label: {
                        Image(systemName: "trash")
                    }

                    Button {
                        withAnimation { lesson.isCompleted.toggle() }
                    } label: {
                        Image(systemName: lesson.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(lesson.isCompleted ? .gray : .green)
                }
            }
        }
        .listStyle(.plain)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newValue in
            // Collapse: user scrolled down past threshold
            if newValue > 60 && isExpanded {
                withAnimation(.easeInOut(duration: 0.3)) { isExpanded = false }
            }
            // Expand: user pulled down past top (rubber band bounce)
            // Negative offset only occurs during active pull-down,
            // never from passive layout changes — no feedback loop.
            if newValue < -10 && !isExpanded {
                withAnimation(.easeInOut(duration: 0.3)) { isExpanded = true }
            }
        }
    }
}
