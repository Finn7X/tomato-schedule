import SwiftUI

struct MonthGridView: View {
    @Binding var selectedDate: Date
    let displayedMonth: Date
    let lessonCounts: [Date: Int]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var calendarCells: [(date: Date, isCurrentMonth: Bool)] {
        let days = DateHelper.daysInMonth(for: displayedMonth)
        guard let firstDay = days.first else { return [] }

        let weekday = DateHelper.calendar.component(.weekday, from: firstDay)
        let leadingOffset = (weekday + 5) % 7 // Monday=0

        var result: [(Date, Bool)] = []

        // Leading days from previous month
        for i in (0..<leadingOffset).reversed() {
            if let prev = DateHelper.calendar.date(byAdding: .day, value: -(i + 1), to: firstDay) {
                result.append((prev, false))
            }
        }

        // Current month days
        for day in days {
            result.append((day, true))
        }

        // Trailing days to fill last row
        let remainder = result.count % 7
        if remainder > 0 {
            let lastDay = days.last!
            for i in 1...(7 - remainder) {
                if let next = DateHelper.calendar.date(byAdding: .day, value: i, to: lastDay) {
                    result.append((next, false))
                }
            }
        }

        return result
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, cell in
                dayCell(date: cell.date, isCurrentMonth: cell.isCurrentMonth)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayCell(date: Date, isCurrentMonth: Bool) -> some View {
        let isToday = DateHelper.isSameDay(date, .now)
        let isSelected = DateHelper.isSameDay(date, selectedDate) && isCurrentMonth
        let count = isCurrentMonth ? (lessonCounts[DateHelper.startOfDay(date)] ?? 0) : 0

        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.54, blue: 0.50))
                        .frame(width: 30, height: 30)
                }

                if isToday && isCurrentMonth {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.83, green: 0.65, blue: 0.22))
                            .frame(width: 26, height: 26)
                        Text("今")
                            .font(.system(size: 11))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("\(DateHelper.calendar.component(.day, from: date))")
                        .font(.callout)
                        .foregroundStyle(isCurrentMonth ? (isSelected ? .white : .white.opacity(0.9)) : .white.opacity(0.3))
                }
            }
            .frame(height: 30)

            DotIndicator(count: count, isSelected: isSelected, isOnTintedBackground: true)
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrentMonth {
                selectedDate = date
            }
        }
    }
}
