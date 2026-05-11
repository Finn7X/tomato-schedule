import SwiftUI

/// Sticky "全天" / day-summary row directly below the weekday header.
///
/// Shows a compact pill per lesson (Apple-Calendar-style capsule) so the user
/// can see what's scheduled on each day without scrolling the timed grid.
struct WeekAllDayRow: View {
    let days: [DayColumn]

    var body: some View {
        HStack(spacing: 0) {
            // Sticky left label (mirrors the time-axis 48pt gutter)
            Text("全天")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, WeekAllDayMetrics.columnPaddingVertical + 1)
            Color.clear.frame(width: 4)

            // 7 day columns of pills
            WeekAllDayPillsInline(days: days)
        }
        .frame(height: WeekAllDayMetrics.height(for: days))
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }
}

/// Just the 7-column pills area (no left "全天" label and no left gutter).
/// Used inside the TabView page so the pills slide horizontally with the day grid,
/// while the parent renders the "全天" label as a sticky non-sliding element.
struct WeekAllDayPillsInline: View {
    let days: [DayColumn]

    var body: some View {
        HStack(spacing: 0) {
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
    }

    private func dayColumn(day: DayColumn) -> some View {
        let lessons = day.allLessons
        let visible = lessons.prefix(WeekAllDayMetrics.maxVisiblePillsPerDay)
        let overflow = max(0, lessons.count - WeekAllDayMetrics.maxVisiblePillsPerDay)
        return VStack(alignment: .leading, spacing: WeekAllDayMetrics.pillSpacing) {
            ForEach(Array(visible), id: \.id) { lesson in
                lessonPill(lesson)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: WeekAllDayMetrics.pillHeight)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WeekAllDayMetrics.columnPaddingHorizontal)
        .padding(.vertical, WeekAllDayMetrics.columnPaddingVertical)
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
        .frame(height: WeekAllDayMetrics.pillHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule(style: .continuous).fill(color.opacity(0.15)))
    }
}

/// Shared metric helpers so the sticky left "全天" label and the per-page pill
/// content always agree on heights (used by WeekTimelineView to compute a unified
/// row height across the visible weeks).
enum WeekAllDayMetrics {
    static let pillHeight: CGFloat = 20
    static let pillSpacing: CGFloat = 3
    static let columnPaddingHorizontal: CGFloat = 4
    static let columnPaddingVertical: CGFloat = 6
    static let maxVisiblePillsPerDay: Int = 3
    static let minHeight: CGFloat = 28
    static let maxHeight: CGFloat = 110

    /// Height needed for ONE week's pill content.
    static func height(for days: [DayColumn]) -> CGFloat {
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

    /// Unified height = max(per-week heights) across the visible weeks so the
    /// horizontal pager swipe doesn't shift the day grid vertically.
    static func unifiedHeight(across weekDays: [[DayColumn]]) -> CGFloat {
        weekDays.map(height(for:)).max() ?? minHeight
    }
}
