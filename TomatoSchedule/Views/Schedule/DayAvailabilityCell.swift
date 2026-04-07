import SwiftUI

struct DayAvailabilityCell: View {
    let date: Date
    let busyBins: [Bool]
    let lessonCount: Int
    let isCurrentMonth: Bool
    let isToday: Bool

    private let cal = DateHelper.calendar

    private var isPast: Bool {
        isCurrentMonth && DateHelper.calendar.startOfDay(for: date) < DateHelper.calendar.startOfDay(for: .now)
    }

    var body: some View {
        VStack(spacing: 2) {
            dateLabel
                .frame(height: 22)

            busyBar
                .frame(width: 8, height: 40)

            if lessonCount > 0 && isCurrentMonth {
                Text("\(lessonCount)节")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .opacity(isCurrentMonth ? (isPast ? 0.5 : 1.0) : 0.3)
    }

    @ViewBuilder
    private var dateLabel: some View {
        if isToday && isCurrentMonth {
            ZStack {
                Circle()
                    .fill(Color(red: 0.83, green: 0.65, blue: 0.22))
                    .frame(width: 22, height: 22)
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(isCurrentMonth ? 1.0 : 0.3))
        }
    }

    private var busyBar: some View {
        VStack(spacing: 0) {
            ForEach(Array(busyBins.enumerated()), id: \.offset) { _, busy in
                Rectangle()
                    .fill(busy ? Color(red: 0.34, green: 0.77, blue: 0.72) : Color.gray.opacity(0.15))
            }
        }
        .frame(width: 8, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
