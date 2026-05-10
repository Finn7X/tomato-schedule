import SwiftUI

/// Sticky "全天" row directly below the weekday header.
/// Structurally mirrors Apple Calendar's all-day row: left label + 7 day columns.
/// Current app has no all-day lessons — row stays at min height.
/// Future: holidays, day summaries, or multi-day events can populate per-day content.
struct WeekAllDayRow: View {
    let weekStart: Date

    /// Min height (empty state, Apple-like thin band).
    private let minHeight: CGFloat = 28
    /// Max height when content exists (cap per user spec).
    private let maxHeight: CGFloat = 84

    var body: some View {
        HStack(spacing: 0) {
            // Left label column: text right-aligned at 44pt, 4pt gap → total 48pt (matches monthLabelColumn + hourGrid time axis)
            Text("全天")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Color.clear.frame(width: 4)

            // 7 day columns (empty placeholder; vertical hairline dividers between)
            ForEach(0..<7, id: \.self) { offset in
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        if offset > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
    }
}
