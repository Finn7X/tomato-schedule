import SwiftUI

struct WeekStripView: View {
    @Binding var selectedDate: Date
    let lessonCounts: [Date: Int]

    private var weekDays: [Date] {
        let range = DateHelper.weekRange(for: selectedDate)
        return (0..<7).compactMap {
            DateHelper.calendar.date(byAdding: .day, value: $0, to: range.start)
        }
    }

    private let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                let isToday = DateHelper.isSameDay(day, .now)
                let isSelected = DateHelper.isSameDay(day, selectedDate)
                let count = lessonCounts[DateHelper.startOfDay(day)] ?? 0

                VStack(spacing: 4) {
                    Text(weekdayLabels[index])
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))

                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(Color(red: 0.16, green: 0.54, blue: 0.50))
                                .frame(width: 32, height: 32)
                        }

                        if isToday {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.83, green: 0.65, blue: 0.22))
                                    .frame(width: 28, height: 28)
                                Text("今")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Text("\(DateHelper.calendar.component(.day, from: day))")
                                .font(.callout)
                                .fontWeight(isSelected ? .bold : .regular)
                                .foregroundStyle(.white)
                        }
                    }

                    DotIndicator(count: count, isSelected: isSelected, isOnTintedBackground: true)
                        .frame(height: 6)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { selectedDate = day }
            }
        }
        .padding(.vertical, 4)
    }
}
