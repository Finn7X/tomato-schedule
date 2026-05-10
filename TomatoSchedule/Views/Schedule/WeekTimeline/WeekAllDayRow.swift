import SwiftUI

/// Sticky "全天" / day-summary row directly below the weekday header.
///
/// Shows a compact pill per lesson (Apple-Calendar-style capsule) so the user
/// can see what's scheduled on each day without scrolling the timed grid.
///
/// Adaptive height:
/// - Empty week (no lessons on any day) → minHeight (just the "全天" label band)
/// - Has lessons → expands to fit up to `maxVisiblePillsPerDay` rows, capped at maxHeight
/// - When a day has more lessons than maxVisiblePillsPerDay, shows "+N" overflow indicator
struct WeekAllDayRow: View {
    let days: [DayColumn]

    private let labelGutterWidth: CGFloat = 48
    private let labelInnerWidth: CGFloat = 44
    private let labelGap: CGFloat = 4
    private let pillHeight: CGFloat = 20
    private let pillSpacing: CGFloat = 3
    private let columnPaddingHorizontal: CGFloat = 4
    private let columnPaddingVertical: CGFloat = 6
    private let maxVisiblePillsPerDay: Int = 3
    private let minHeight: CGFloat = 28
    private let maxHeight: CGFloat = 110

    private var rowHeight: CGFloat {
        // Find the max number of "rows" needed across all days, capped at maxVisiblePillsPerDay+1 (for +N indicator).
        var maxRows = 0
        for day in days {
            let count = day.allLessons.count
            if count == 0 { continue }
            let visible = min(count, maxVisiblePillsPerDay)
            let needsOverflow = count > maxVisiblePillsPerDay
            maxRows = max(maxRows, visible + (needsOverflow ? 1 : 0))
        }
        if maxRows == 0 { return minHeight }
        let pills = CGFloat(maxRows) * pillHeight
        let gaps = CGFloat(maxRows - 1) * pillSpacing
        let padding = columnPaddingVertical * 2
        return min(maxHeight, max(minHeight, pills + gaps + padding))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left "全天" label (right-aligned in 44pt + 4pt gap = 48pt total, matches monthLabelColumn / time axis)
            Text("全天")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: labelInnerWidth, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, columnPaddingVertical + 1)
            Color.clear.frame(width: labelGap)

            // 7 day columns of pills
            ForEach(Array(days.enumerated()), id: \.element.id) { offset, day in
                dayColumn(day: day)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .leading) {
                        if offset > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .frame(height: rowHeight)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
        .animation(.easeInOut(duration: 0.18), value: rowHeight)
    }

    private func dayColumn(day: DayColumn) -> some View {
        let lessons = day.allLessons
        let visible = lessons.prefix(maxVisiblePillsPerDay)
        let overflow = max(0, lessons.count - maxVisiblePillsPerDay)
        return VStack(alignment: .leading, spacing: pillSpacing) {
            ForEach(Array(visible), id: \.id) { lesson in
                lessonPill(lesson)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: pillHeight)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, columnPaddingHorizontal)
        .padding(.vertical, columnPaddingVertical)
    }

    private func lessonPill(_ lesson: Lesson) -> some View {
        let trimmedName = lesson.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let color: Color = trimmedName.isEmpty
            ? PresetColors.color(for: lesson.course?.colorHex ?? "#94A3B8")
            : StudentColors.color(for: trimmedName)
        let primaryText = trimmedName.isEmpty
            ? (lesson.course?.name ?? "课时")
            : trimmedName
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(primaryText)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(color)
        }
        .padding(.leading, 5)
        .padding(.trailing, 8)
        .frame(height: pillHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.15))
        )
    }
}
