import SwiftUI
import SwiftData

// MARK: - iOS 17 scroll offset observer (UIKit KVO inside List row → finds UIScrollView)

private struct ScrollOffsetObserver: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = _IntrospectionView()
        view.onOffsetChange = onOffsetChange
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _IntrospectionView: UIView {
        var onOffsetChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            trySetupObservation()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            trySetupObservation()
        }

        private func trySetupObservation() {
            guard observation == nil, window != nil else { return }
            var current: UIView? = superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    observation = scrollView.observe(\.contentOffset, options: .new) { [weak self] sv, _ in
                        DispatchQueue.main.async {
                            self?.onOffsetChange?(sv.contentOffset.y)
                        }
                    }
                    return
                }
                current = view.superview
            }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil { observation?.invalidate(); observation = nil }
        }
    }
}

// MARK: - Scroll-driven calendar fold modifier (iOS 18 only)

private struct ScrollCalendarFoldModifier: ViewModifier {
    @Binding var isExpanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newValue in
                    if newValue > 60 && isExpanded {
                        withAnimation(.easeInOut(duration: 0.3)) { isExpanded = false }
                    }
                    if newValue < -10 && !isExpanded {
                        withAnimation(.easeInOut(duration: 0.3)) { isExpanded = true }
                    }
                }
        } else {
            // iOS 17: observer placed inside List row (see lessonList)
            content
        }
    }
}

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allLessons: [Lesson]

    @State private var selectedDate: Date = .now
    @State private var displayedMonth: Date = .now
    @State private var isExpanded: Bool = true
    @State private var showingAddLesson: Bool = false
    @State private var showingBatchLesson: Bool = false
    @State private var editingLesson: Lesson?
    @AppStorage("showIncomeInCourseList") private var showIncome = true
    @AppStorage("showEstimatedIncome") private var showEstimatedIncome = true

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
        lessonsInRange.filter { $0.isCompleted || $0.endTime < .now }.count
    }

    private var statisticsIncome: Double {
        lessonsInRange.filter { $0.isCompleted || $0.endTime < .now }
            .reduce(0) { $0 + $1.effectivePrice }
    }

    private var statisticsEstimatedIncome: Double {
        lessonsInRange.reduce(0) { $0 + $1.effectivePrice }
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
                    completedCount: statisticsCompleted,
                    income: showIncome ? statisticsIncome : 0,
                    estimatedIncome: showIncome && showEstimatedIncome ? statisticsEstimatedIncome : 0
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
                    Menu {
                        Button { showingAddLesson = true } label: {
                            Label("添加单节课时", systemImage: "plus")
                        }
                        Button { showingBatchLesson = true } label: {
                            Label("批量排课", systemImage: "calendar.badge.plus")
                        }
                    } label: {
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
            .sheet(isPresented: $showingBatchLesson) {
                BatchLessonFormView()
            }
            .sheet(item: $editingLesson) { lesson in
                LessonFormView(lesson: lesson, initialDate: lesson.date)
            }
            .onAppear { autoCompletePastLessons() }
        }
    }

    /// Auto-complete past lessons that haven't been manually checked
    private func autoCompletePastLessons() {
        let now = Date.now
        for lesson in allLessons where !lesson.isCompleted && lesson.endTime < now {
            lesson.isCompleted = true
            if !lesson.isPriceOverridden {
                lesson.priceOverride = lesson.effectivePrice
                lesson.isPriceOverridden = true
            }
        }
    }

    // MARK: - Lesson List

    private var lessonList: some View {
        List {
            // iOS 17: invisible row with KVO observer INSIDE List content
            // Must be inside a row so the UIView is a descendant of UICollectionViewCell → UIScrollView
            if #unavailable(iOS 18.0) {
                ScrollOffsetObserver { offset in
                    if offset > 60 && isExpanded {
                        withAnimation(.easeInOut(duration: 0.3)) { isExpanded = false }
                    }
                    if offset < 10 && !isExpanded {
                        withAnimation(.easeInOut(duration: 0.3)) { isExpanded = true }
                    }
                }
                .frame(height: 0)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            ForEach(lessonsForSelectedDate) { lesson in
                LessonTimeGroup(lesson: lesson, allLessons: allLessons) {
                    editingLesson = lesson
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        try? CalendarSyncService.shared.removeSyncedEvent(for: lesson)
                        withAnimation { modelContext.delete(lesson) }
                    } label: {
                        Image(systemName: "trash")
                    }

                    Button {
                        withAnimation { lesson.isCompleted.toggle() }
                        // Freeze price on completion
                        if lesson.isCompleted && !lesson.isPriceOverridden {
                            lesson.priceOverride = lesson.effectivePrice
                            lesson.isPriceOverridden = true
                        }
                        let idx = computeStudentIndex(for: lesson, existingLessons: Array(allLessons))
                        try? CalendarSyncService.shared.syncLesson(lesson, studentIndex: idx)
                    } label: {
                        Image(systemName: lesson.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(lesson.isCompleted ? .gray : .green)
                }
            }
        }
        .listStyle(.plain)
        .modifier(ScrollCalendarFoldModifier(isExpanded: $isExpanded))
    }
}
