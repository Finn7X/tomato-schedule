import SwiftUI

/// Vertical time axis column on the left of the timed grid (Apple Calendar style).
/// Shows hour labels like "9:00", "10:00" right-aligned in a 44pt label area
/// with a 4pt gap before the day columns (total 48pt left gutter).
///
/// This view is intentionally OUTSIDE the horizontal pager (TabView) so that
/// horizontal week swipes don't move the time labels — only the day columns slide.
struct TimeAxisColumn: View {
    let timeRange: (start: Int, end: Int)
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(timeRange.start..<timeRange.end, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Text("\(hour):00")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .offset(y: -6)
                }
                .frame(height: hourHeight)
            }
        }
        .frame(width: 48)
    }
}
