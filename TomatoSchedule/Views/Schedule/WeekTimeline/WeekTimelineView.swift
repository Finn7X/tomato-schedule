import SwiftUI

struct WeekTimelineView: View {
    @Binding var focusDate: Date
    let lessons: [Lesson]
    let onDismiss: () -> Void

    @Environment(\.verticalSizeClass) private var vSize
    @State private var currentWeekStart: Date
    @State private var snapshotCache: [Date: WeekSnapshot] = [:]
    @State private var scrollAnchorByWeek: [Date: ScrollAnchor] = [:]
    @State private var pendingScrollRequest: (week: Date, anchor: ScrollAnchor)?
    @State private var previewingContext: PreviewContext?
    @State private var visibleWeekStarts: [Date] = []
    @State private var hourHeight: CGFloat = 60

    private let teal = Color(red: 0.34, green: 0.77, blue: 0.72)

    init(focusDate: Binding<Date>, lessons: [Lesson], onDismiss: @escaping () -> Void) {
        self._focusDate = focusDate
        self.lessons = lessons
        self.onDismiss = onDismiss
        let ws = DateHelper.weekStart(for: focusDate.wrappedValue)
        self._currentWeekStart = State(initialValue: ws)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                WeekHeaderRow(weekStart: currentWeekStart)
                weekPager
            }
            .onAppear {
                computeHourHeight(landscapeHeight: geo.size.height)
                recenterVisibleWeeks(around: currentWeekStart)
                setInitialScroll()
            }
            .onChange(of: currentWeekStart) { _, newStart in
                previewingContext = nil
                updateFocusDateForWeekChange(newStart)
                extendVisibleWeeksIfNeeded(current: newStart)
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            }
            .onChange(of: lessons.count) { _, _ in
                snapshotCache.removeAll()
            }
            .sheet(item: $previewingContext) { ctx in
                LessonInfoCard(lesson: ctx.lesson, overflowCompanions: ctx.overflowCompanions)
                    .presentationDetents(previewDetents)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.35)))
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
            }
            Spacer()
            Text(DateHelper.weekRangeText(currentWeekStart))
                .font(.body.weight(.semibold))
            Spacer()
            Button {
                let todayWeek = DateHelper.weekStart(for: Date())
                recenterVisibleWeeks(around: todayWeek)
                currentWeekStart = todayWeek
                focusDate = DateHelper.calendar.startOfDay(for: Date())
                pendingScrollRequest = (todayWeek, .nowRounded)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Text("今天")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isTodayWeek ? .secondary : teal)
            }
            .disabled(isTodayWeek)
            .accessibilityLabel("回到本周")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var weekPager: some View {
        TabView(selection: $currentWeekStart) {
            ForEach(visibleWeekStarts, id: \.self) { weekStart in
                let snap = snapshotForWeek(weekStart)
                WeekContentView(
                    snapshot: snap,
                    hourHeight: hourHeight,
                    onBlockTap: { ctx in previewingContext = ctx },
                    pendingScrollAnchor: pendingScrollRequest?.week == weekStart
                        ? pendingScrollRequest?.anchor : nil,
                    onScrollPositionChanged: { hour in
                        scrollAnchorByWeek[weekStart] = .hour(hour)
                    },
                    onScrollRequestHandled: { pendingScrollRequest = nil }
                )
                .tag(weekStart)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var isTodayWeek: Bool {
        DateHelper.weekStart(for: Date()) == currentWeekStart
    }

    private var previewDetents: Set<PresentationDetent> {
        vSize == .compact
            ? [.fraction(0.35), .large]
            : [.fraction(0.35), .medium]
    }

    private func computeHourHeight(landscapeHeight: CGFloat) {
        let contentArea = landscapeHeight - 56 - 40
        hourHeight = min(80, max(44, contentArea / 6))
    }

    private func snapshotForWeek(_ weekStart: Date) -> WeekSnapshot {
        if let cached = snapshotCache[weekStart] { return cached }
        let snap = WeekSnapshot.build(weekStart: weekStart, lessons: lessons)
        snapshotCache[weekStart] = snap
        return snap
    }

    private func recenterVisibleWeeks(around target: Date, radius: Int = 2) {
        let cal = DateHelper.calendar
        visibleWeekStarts = (-radius...radius).compactMap {
            cal.date(byAdding: .weekOfYear, value: $0, to: target)
        }
    }

    private func extendVisibleWeeksIfNeeded(current: Date) {
        let cal = DateHelper.calendar
        if let first = visibleWeekStarts.first, DateHelper.isSameDay(current, first),
           let prev = cal.date(byAdding: .weekOfYear, value: -1, to: first) {
            visibleWeekStarts.insert(prev, at: 0)
        }
        if let last = visibleWeekStarts.last, DateHelper.isSameDay(current, last),
           let next = cal.date(byAdding: .weekOfYear, value: 1, to: last) {
            visibleWeekStarts.append(next)
        }
    }

    private func setInitialScroll() {
        if isTodayWeek {
            pendingScrollRequest = (currentWeekStart, .nowRounded)
        } else {
            pendingScrollRequest = (currentWeekStart, .hour(9))
        }
    }

    private func updateFocusDateForWeekChange(_ newWeekStart: Date) {
        let cal = DateHelper.calendar
        let currentWeekday = cal.component(.weekday, from: focusDate)
        if let adjusted = cal.date(bySetting: .weekday, value: currentWeekday, of: newWeekStart) {
            focusDate = cal.startOfDay(for: adjusted)
        } else {
            focusDate = newWeekStart
        }
    }
}
