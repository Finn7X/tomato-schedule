import SwiftUI

/// Renders ONE week's day columns + hour gridlines + now indicator.
/// Time axis labels are NOT rendered here — they live in TimeAxisColumn at the
/// WeekTimelineView level so horizontal week swipes do not slide the labels.
struct WeekContentView: View {
    let snapshot: WeekSnapshot
    let hourHeight: CGFloat
    let onBlockTap: (PreviewContext) -> Void
    let pendingScrollAnchor: ScrollAnchor?
    let onScrollPositionChanged: (Int) -> Void
    let onScrollOffsetChanged: (CGFloat) -> Void
    let onScrollRequestHandled: () -> Void

    private var totalHours: Int { snapshot.timeRange.end - snapshot.timeRange.start }
    private var contentHeight: CGFloat { CGFloat(totalHours) * hourHeight }

    var body: some View {
        GeometryReader { geo in
            let columnWidth = max((geo.size.width - 48) / 7, 0)
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Hour gridlines (background) — left 48pt is reserved for the
                        // sticky TimeAxisColumn rendered by the parent view.
                        hourGridLayer

                        dayColumnsLayer(columnWidth: columnWidth)

                        nowIndicatorLayer
                    }
                    .frame(width: geo.size.width, height: contentHeight, alignment: .top)
                    .background(scrollOffsetTracker)
                }
                .onAppear {
                    applyScrollAnchor(reader: reader)
                }
                .onChange(of: pendingScrollAnchor) { _, _ in
                    applyScrollAnchor(reader: reader)
                }
            }
        }
    }

    // MARK: - Hour Gridlines (no labels)

    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.timeRange.start..<snapshot.timeRange.end, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Divider()
                        .opacity(0.25)
                        .padding(.leading, 48)
                }
                .frame(height: hourHeight)
                .id(hour)
            }
        }
    }

    // MARK: - Day Columns

    private func dayColumnsLayer(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { offset, day in
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: columnWidth, height: contentHeight)

                    ForEach(day.clusters, id: \.visibleBlocks.first?.id) { cluster in
                        ForEach(cluster.visibleBlocks) { block in
                            LessonBlockView(
                                block: block,
                                cluster: cluster,
                                hourHeight: hourHeight,
                                columnWidth: columnWidth,
                                weekStart: snapshot.weekStart,
                                onTap: onBlockTap
                            )
                        }
                    }
                }
                .frame(width: columnWidth, height: contentHeight)
                .overlay(alignment: .leading) {
                    if offset > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 0.5)
                    }
                }
            }
        }
        .frame(height: contentHeight)
    }

    // MARK: - Now Indicator

    private var nowIndicatorLayer: some View {
        Group {
            if snapshot.days.contains(where: \.isToday) {
                NowIndicatorView(
                    timeRangeStart: snapshot.timeRange.start,
                    hourHeight: hourHeight,
                    totalColumns: 7
                )
                .padding(.leading, 48)
            }
        }
    }

    // MARK: - Scroll Offset Tracker (iOS 17 compat)
    // Reports both the integer hour anchor (for cache) AND the raw offsetY
    // (for parent's TimeAxisColumn sync).

    private var scrollOffsetTracker: some View {
        ScrollViewOffsetReader { offsetY in
            onScrollOffsetChanged(offsetY)
            let hour = Int((offsetY / hourHeight).rounded(.down)) + snapshot.timeRange.start
            let clamped = max(snapshot.timeRange.start, min(hour, snapshot.timeRange.end - 1))
            onScrollPositionChanged(clamped)
        }
        .frame(width: 0, height: 0)
    }

    // MARK: - Scroll Restore

    private func applyScrollAnchor(reader: ScrollViewProxy) {
        guard let anchor = pendingScrollAnchor else { return }
        let targetHour: Int
        switch anchor {
        case .hour(let h): targetHour = h
        case .nowRounded:
            targetHour = DateHelper.calendar.component(.hour, from: Date())
        }
        let clampedHour = max(snapshot.timeRange.start, min(targetHour, snapshot.timeRange.end - 1))
        withAnimation(.easeOut(duration: 0.3)) {
            reader.scrollTo(clampedHour, anchor: .top)
        }
        onScrollRequestHandled()
    }
}
