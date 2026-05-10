import SwiftUI

struct WeekContentView: View {
    let snapshot: WeekSnapshot
    let hourHeight: CGFloat
    let onBlockTap: (PreviewContext) -> Void
    let pendingScrollAnchor: ScrollAnchor?
    let onScrollPositionChanged: (Int) -> Void
    let onScrollRequestHandled: () -> Void

    private var totalHours: Int { snapshot.timeRange.end - snapshot.timeRange.start }
    private var contentHeight: CGFloat { CGFloat(totalHours) * hourHeight }

    var body: some View {
        GeometryReader { geo in
            let columnWidth = max((geo.size.width - 48) / 7, 0)
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Single layer: hour grid (background, fills full width).
                        // Each hour row carries .id(hour) so ScrollViewReader.scrollTo works
                        // without a separate anchor VStack.
                        hourGridLayer

                        // Day columns: 7 ZStacks each given an EXPLICIT height = contentHeight,
                        // so blocks positioned via .offset(y:) land at the same y as the matching
                        // hour grid divider in the layer above.
                        dayColumnsLayer(columnWidth: columnWidth)

                        // Now indicator (red line) — overlay only; no contribution to layout.
                        nowIndicatorLayer
                    }
                    .frame(width: geo.size.width, height: contentHeight)
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

    // MARK: - Hour Grid (with embedded scroll anchors)

    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.timeRange.start..<snapshot.timeRange.end, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Text("\(hour):00")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .offset(y: -6)

                    Divider()
                        .opacity(0.25)
                        .padding(.leading, 48)
                }
                .frame(height: hourHeight)
                .id(hour)
            }
        }
    }

    // MARK: - Day Columns (each with explicit full height)

    private func dayColumnsLayer(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { offset, day in
                ZStack(alignment: .topLeading) {
                    // Spacer claims the column's full height (totalHours * hourHeight)
                    // so .offset(y:) inside LessonBlockView aligns with the hour grid above.
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

    private var scrollOffsetTracker: some View {
        ScrollViewOffsetReader { offsetY in
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
