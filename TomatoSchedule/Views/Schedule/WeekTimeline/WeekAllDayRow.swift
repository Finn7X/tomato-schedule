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
            // Left label column (aligns with time axis width)
            Text("全天")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 4)

            // 7 day columns (empty for now; structural placeholder)
            ForEach(0..<7, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
    }
}
