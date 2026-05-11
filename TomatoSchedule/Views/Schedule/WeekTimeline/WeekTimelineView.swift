import SwiftUI

/// Reference-typed snapshot cache. Held in @State as a CLASS so that mutations
/// to its internal dictionary do NOT count as @State writes — body can populate
/// it on cache miss without triggering SwiftUI's "Modifying state during view
/// update" undefined behavior.
final class WeekSnapshotStore {
    var cache: [Date: WeekSnapshot] = [:]
}

struct WeekTimelineView: View {
    @Binding var focusDate: Date
    let lessons: [Lesson]
    let onDismiss: () -> Void

    @Environment(\.verticalSizeClass) private var vSize
    @State private var currentWeekStart: Date
    @State private var snapshotStore = WeekSnapshotStore()
    @State private var scrollAnchorByWeek: [Date: ScrollAnchor] = [:]
    @State private var pendingScrollRequest: (week: Date, anchor: ScrollAnchor)?
    @State private var previewingContext: PreviewContext?
    @State private var visibleWeekStarts: [Date] = []
    @State private var hourHeight: CGFloat = 60
    @State private var trackedScrollOffset: CGFloat = 0

    // Cached unified metrics — recomputed ONLY when visibleWeekStarts or lessons change.
    // These were previously computed properties evaluated on every body re-render,
    // which during scroll (60fps trackedScrollOffset writes) caused thousands of array
    // allocations / sorts per second across 5 visible weeks × 7 days each.
    @State private var unifiedAllDayHeight: CGFloat = WeekAllDayMetrics.minHeight
    @State private var globalTimeRange: (start: Int, end: Int) = (9, 24)

    init(focusDate: Binding<Date>, lessons: [Lesson], onDismiss: @escaping () -> Void) {
        self._focusDate = focusDate
        self.lessons = lessons
        self.onDismiss = onDismiss
        let ws = DateHelper.weekStart(for: focusDate.wrappedValue)
        self._currentWeekStart = State(initialValue: ws)
    }

    /// Recompute the cached unified metrics. Call only when the underlying data
    /// (visibleWeekStarts or the lesson list) changes — NOT on every render.
    ///
    /// IMPORTANT ordering:
    /// 1. First scan all lessons → compute `globalTimeRange` (the same range used
    ///    for every snapshot, so block y-positions align 1:1 with the sticky
    ///    TimeAxisColumn).
    /// 2. Invalidate snapshotCache because the new global range may differ from
    ///    what previously-cached snapshots were built with.
    /// 3. Rebuild snapshots for visible weeks using the new global range and
    ///    derive the unified all-day height.
    private func recomputeUnifiedMetrics() {
        let newRange = scanGlobalTimeRange()
        if newRange != globalTimeRange {
            globalTimeRange = newRange
            snapshotStore.cache.removeAll()
        }

        let perWeekDays = visibleWeekStarts.map { snapshotForWeek($0).days }
        unifiedAllDayHeight = WeekAllDayMetrics.unifiedHeight(across: perWeekDays)
    }

    /// One-pass scan over ALL lessons to find the earliest start hour and latest
    /// end hour. Default end stays at 24 (full-day timeline). Default start stays
    /// at 9 and extends down only if there are early-morning lessons. The result
    /// is the time range every snapshot will use, so the sticky TimeAxisColumn
    /// and per-week day grids share one coordinate system.
    private func scanGlobalTimeRange() -> (start: Int, end: Int) {
        let cal = DateHelper.calendar
        var earliest = 9
        var latest = 24
        for lesson in lessons {
            let h = cal.component(.hour, from: lesson.startTime)
            if h < earliest { earliest = h }
            let eComps = cal.dateComponents([.hour, .minute], from: lesson.endTime)
            let endHour = (eComps.minute ?? 0) > 0
                ? (eComps.hour ?? 0) + 1
                : (eComps.hour ?? 0)
            if endHour > latest { latest = min(endHour, 24) }
        }
        return (earliest, latest)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    stickyLeftColumn
                    rightPager(geoWidth: geo.size.width - 48)
                }
                .clipped()

                todayButtonOverlay
            }
            .onAppear {
                computeHourHeight(landscapeHeight: geo.size.height)
                recenterVisibleWeeks(around: currentWeekStart)
                setInitialScroll()
                recomputeUnifiedMetrics()
            }
            .onChange(of: currentWeekStart) { _, newStart in
                previewingContext = nil
                updateFocusDateForWeekChange(newStart)
                extendVisibleWeeksIfNeeded(current: newStart)
                // unified metrics recompute is triggered by the visibleWeekStarts
                // .onChange below if extension actually added a week; no need to
                // recompute on every swipe.
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            }
            .onChange(of: visibleWeekStarts) { _, _ in
                recomputeUnifiedMetrics()
            }
            .onChange(of: lessons.count) { _, _ in
                snapshotStore.cache.removeAll()
                recomputeUnifiedMetrics()
            }
            .sheet(item: $previewingContext) { ctx in
                LessonInfoCard(lesson: ctx.lesson, overflowCompanions: ctx.overflowCompanions)
                    .presentationDetents(previewDetents)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.35)))
            }
        }
    }

    // MARK: - Sticky Left Column (48pt)
    //
    // Top: monthLabelColumn (44pt)  |  matches WeekHeaderRowInline height
    // Middle: "全天" label, height = unifiedAllDayHeight
    // Bottom: TimeAxisColumn, offset(-trackedScrollOffset) follows active week's vertical scroll

    private var stickyLeftColumn: some View {
        VStack(spacing: 0) {
            monthLabelColumn

            allDayLabelCell
                .frame(height: unifiedAllDayHeight)

            // Time axis area — vertically follows the active week's scroll.
            // Wrap in a clipping container so the time axis doesn't bleed up into
            // the headers above when the user is scrolled far down.
            GeometryReader { _ in
                TimeAxisColumn(timeRange: globalTimeRange, hourHeight: hourHeight)
                    .offset(y: -trackedScrollOffset)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .clipped()
            .frame(maxHeight: .infinity)
        }
        .frame(width: 48)
        .background(Color(.systemBackground))
        .allowsHitTesting(false)
    }

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

    private var allDayLabelCell: some View {
        VStack {
            Text("全天")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
                .padding(.top, WeekAllDayMetrics.columnPaddingVertical + 1)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    // MARK: - Right Pager
    //
    // Each TabView page contains:
    //   VStack {
    //     WeekHeaderRowInline       — 7-day header (slides horizontally with page)
    //     WeekAllDayPillsInline     — 7-day pills (unified height, slides with page)
    //     WeekContentView           — vertically scrollable day grid
    //   }
    // The result matches Apple Calendar's behavior where headers/pills/grid
    // smoothly slide together while the left time axis stays put.

    private func rightPager(geoWidth: CGFloat) -> some View {
        TabView(selection: $currentWeekStart) {
            ForEach(visibleWeekStarts, id: \.self) { weekStart in
                let snap = snapshotForWeek(weekStart)
                VStack(spacing: 0) {
                    WeekHeaderRowInline(weekStart: weekStart)

                    WeekAllDayPillsInline(days: snap.days)
                        .frame(height: unifiedAllDayHeight)
                        .background(Color(.systemBackground))
                        .overlay(alignment: .bottom) { Divider().opacity(0.4) }

                    WeekContentView(
                        snapshot: snap,
                        weekWidth: geoWidth,
                        hourHeight: hourHeight,
                        onBlockTap: { ctx in previewingContext = ctx },
                        pendingScrollAnchor: pendingScrollRequest?.week == weekStart
                            ? pendingScrollRequest?.anchor : nil,
                        onScrollPositionChanged: { hour in
                            scrollAnchorByWeek[weekStart] = .hour(hour)
                        },
                        onScrollOffsetChanged: { offsetY in
                            if weekStart == currentWeekStart {
                                trackedScrollOffset = max(0, offsetY)
                            }
                        },
                        onScrollRequestHandled: { pendingScrollRequest = nil }
                    )
                }
                .tag(weekStart)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: geoWidth)
    }

    // MARK: - Today Button Overlay

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

    // MARK: - Computed labels

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

    private var isTodayWeek: Bool {
        DateHelper.weekStart(for: Date()) == currentWeekStart
    }

    private var previewDetents: Set<PresentationDetent> {
        vSize == .compact
            ? [.fraction(0.35), .large]
            : [.fraction(0.35), .medium]
    }

    private func computeHourHeight(landscapeHeight: CGFloat) {
        // header(44) + allDay(min 28) = 72 reserved.
        let headerTotal: CGFloat = 44 + 28
        let contentArea = landscapeHeight - headerTotal
        hourHeight = min(80, max(44, contentArea / 6))
    }

    private func snapshotForWeek(_ weekStart: Date) -> WeekSnapshot {
        if let cached = snapshotStore.cache[weekStart] { return cached }
        // Force every snapshot to use the SAME globalTimeRange so block y-positions
        // align with the sticky TimeAxisColumn (which also uses globalTimeRange).
        let snap = WeekSnapshot.build(
            weekStart: weekStart,
            lessons: lessons,
            forcedTimeRange: globalTimeRange
        )
        // Class-internal mutation — does NOT trigger view update (snapshotStore is
        // a class reference held in @State; only re-assigning the reference would).
        snapshotStore.cache[weekStart] = snap
        return snap
    }

    private func recenterVisibleWeeks(around target: Date, radius: Int = 1) {
        // Radius 1 (3 total pages: prev/current/next) instead of 2 (5 pages) —
        // TabView.page only renders ±1 anyway, but with radius 2 the ForEach was
        // still evaluating 5 weeks' worth of view bodies on every state change.
        // Halving the page count noticeably reduces horizontal-swipe stutter.
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
