import SwiftUI

struct WeekContentView: View {
    let snapshot: WeekSnapshot
    let hourHeight: CGFloat
    let onBlockTap: (PreviewContext) -> Void
    let pendingScrollAnchor: ScrollAnchor?
    let onScrollPositionChanged: (Int) -> Void
    let onScrollRequestHandled: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(snapshot.timeRange.start...snapshot.timeRange.end, id: \.self) { hour in
                                Color.clear
                                    .frame(height: hourHeight)
                                    .id(hour)
                            }
                        }

                        hourGridLayer

                        dayColumnsLayer(geo: geo)

                        nowIndicatorLayer(geo: geo)
                    }
                    .frame(height: CGFloat(snapshot.timeRange.end - snapshot.timeRange.start) * hourHeight)
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

    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.timeRange.start..<snapshot.timeRange.end, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Text("\(hour)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .offset(y: -7)

                    Divider()
                        .opacity(0.25)
                        .padding(.leading, 48)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private func dayColumnsLayer(geo: GeometryProxy) -> some View {
        let columnWidth = (geo.size.width - 48) / 7
        return HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { _, day in
                ZStack(alignment: .topLeading) {
                    if day.isToday {
                        Rectangle()
                            .fill(Color(red: 0.34, green: 0.77, blue: 0.72).opacity(0.04))
                    } else if day.isWeekend {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.04))
                    }

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
                .frame(width: columnWidth)
            }
        }
    }

    private func nowIndicatorLayer(geo: GeometryProxy) -> some View {
        let todayIndex = snapshot.days.firstIndex(where: \.isToday)
        return Group {
            if todayIndex != nil {
                NowIndicatorView(
                    timeRangeStart: snapshot.timeRange.start,
                    hourHeight: hourHeight,
                    totalColumns: 7
                )
                .padding(.leading, 48)
            }
        }
    }

    private var scrollOffsetTracker: some View {
        ScrollViewOffsetReader { offsetY in
            let hour = Int(offsetY / hourHeight) + snapshot.timeRange.start
            onScrollPositionChanged(max(snapshot.timeRange.start, min(hour, snapshot.timeRange.end)))
        }
        .frame(width: 0, height: 0)
    }

    private func applyScrollAnchor(reader: ScrollViewProxy) {
        guard let anchor = pendingScrollAnchor else { return }
        let targetHour: Int
        switch anchor {
        case .hour(let h): targetHour = h
        case .nowRounded:
            targetHour = DateHelper.calendar.component(.hour, from: Date())
        }
        let clampedHour = max(snapshot.timeRange.start, min(targetHour, snapshot.timeRange.end))
        withAnimation(.easeOut(duration: 0.3)) {
            reader.scrollTo(clampedHour, anchor: .top)
        }
        onScrollRequestHandled()
    }
}
