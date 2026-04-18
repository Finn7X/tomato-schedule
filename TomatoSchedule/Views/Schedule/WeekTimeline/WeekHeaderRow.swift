import SwiftUI

struct WeekHeaderRow: View {
    let weekStart: Date
    private let cal = DateHelper.calendar
    private let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: weekStart)!
                let day = cal.component(.day, from: date)
                let isToday = DateHelper.isSameDay(date, Date())

                HStack(spacing: 6) {
                    ZStack {
                        if isToday {
                            Circle()
                                .fill(Color(.systemRed))
                                .frame(width: 26, height: 26)
                        }
                        Text("\(day)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isToday ? .white : .primary)
                    }
                    Text(weekdayLabels[offset])
                        .font(.system(size: 14))
                        .foregroundStyle(isToday ? Color(.systemRed) : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44)
    }
}
