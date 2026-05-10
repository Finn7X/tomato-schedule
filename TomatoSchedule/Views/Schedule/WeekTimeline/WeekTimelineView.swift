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
                // Header band: month label (left) + weekday header (right) on the same row
                HStack(spacing: 0) {
                    monthLabelColumn
                    weekHeaderInline
                }
                WeekAllDayRow(weekStart: currentWeekStart)
                weekPager
                    .overlay(alignment: .topTrailing) { todayButtonOverlay }
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

    /// Top-left column: stacks "4月" + "丙午马年" within the 48pt time-axis gutter
    private var monthLabelColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(monthLabel)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(monthIsCurrent ? Color(.systemRed) : .primary)
            Text(LunarHelper.lunarYearLabel(for: currentWeekStart))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 48, alignment: .leading)
        .padding(.leading, 6)
        .frame(height: 44, alignment: .center)
    }

    /// Inline weekday header without its own left gutter (gutter is now monthLabelColumn).
    private var weekHeaderInline: some View {
        WeekHeaderRowInline(weekStart: currentWeekStart)
    }

    /// "今天" button: floating top-right, only when not on current week.
    @ViewBuilder
    private var todayButtonOverlay: some View {
        if !isTodayWeek {
            Button {
                let todayWeek = DateHelper.weekStart(for: Date())
                recenterVisibleWeeks(around: todayWeek)
                currentWeekStart = todayWeek
                focusDate = DateHelper.calendar.startOfDay(for: Date())
                pendingScrollRequest = (todayWeek, .nowRounded)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Text("今天")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.systemRed).opacity(0.9)))
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
            .accessibilityLabel("回到本周")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// Month label: show month of the Monday for the visible week.
    private var monthLabel: String {
        let cal = DateHelper.calendar
        let month = cal.component(.month, from: currentWeekStart)
        return "\(month)月"
    }

    private var monthIsCurrent: Bool {
        let cal = DateHelper.calendar
        let nowMonth = cal.component(.month, from: Date())
        let nowYear = cal.component(.year, from: Date())
        let weekMonth = cal.component(.month, from: currentWeekStart)
        let weekYear = cal.component(.year, from: currentWeekStart)
        return nowMonth == weekMonth && nowYear == weekYear
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
        // header(44) + allDayRow min(28) = 72  (no separate top bar — month label is in column 1)
        let headerTotal: CGFloat = 44 + 28
        let contentArea = landscapeHeight - headerTotal
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
