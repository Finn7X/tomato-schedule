import SwiftUI

/// Apple Calendar-style weekday header (with built-in left gutter).
/// Top row: "15 周三" pair (date number + weekday name)
/// Bottom row: lunar date "廿八" or month boundary "三月" (red)
/// Today: red filled circle on date number, red weekday text
/// Weekend (Sat/Sun): muted gray text
/// Vertical hairline dividers between columns
struct WeekHeaderRow: View {
    let weekStart: Date

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            WeekHeaderRowInline(weekStart: weekStart)
        }
        .frame(height: 44)
        .background(Color(.systemBackground))
    }
}

/// Inline variant: 7 columns only, no left gutter. Use when caller provides its own left column.
struct WeekHeaderRowInline: View {
    let weekStart: Date
    private let cal = DateHelper.calendar
    private let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: weekStart)!
                let day = cal.component(.day, from: date)
                let isToday = DateHelper.isSameDay(date, Date())
                let isWeekend = (offset == 5 || offset == 6)
                let lunar = LunarHelper.lunarDayLabel(for: date)
                let isLunarMonthBoundary = lunar.hasSuffix("月")

                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        ZStack {
                            if isToday {
                                Circle()
                                    .fill(Color(.systemRed))
                                    .frame(width: 24, height: 24)
                            }
                            Text("\(day)")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(
                                    isToday ? Color.white
                                    : isWeekend ? .secondary
                                    : .primary
                                )
                        }
                        Text(weekdayLabels[offset])
                            .font(.system(size: 13))
                            .foregroundStyle(
                                isToday ? Color(.systemRed)
                                : isWeekend ? .secondary
                                : .primary
                            )
                    }

                    Text(lunar)
                        .font(.system(size: 10))
                        .foregroundStyle(isLunarMonthBoundary ? Color(.systemRed) : .secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(alignment: .leading) {
                    if offset > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 0.5)
                    }
                }
            }
        }
        .frame(height: 44)
        .background(Color(.systemBackground))
    }
}
