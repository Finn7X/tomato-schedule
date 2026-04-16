import SwiftUI

struct WeekHeaderRow: View {
    let weekStart: Date
    private let cal = DateHelper.calendar
    private let teal = Color(red: 0.34, green: 0.77, blue: 0.72)
    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: weekStart)!
                let day = cal.component(.day, from: date)
                let isToday = DateHelper.isSameDay(date, Date())
                let weekday = cal.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7

                VStack(spacing: 2) {
                    Text(weekdayLabels[offset])
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    ZStack {
                        if isToday {
                            Circle()
                                .fill(teal)
                                .frame(width: 28, height: 28)
                        }
                        Text("\(day)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isToday ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(isWeekend ? Color.secondary.opacity(0.04) : Color.clear)
            }
        }
        .frame(height: 40)
    }
}
