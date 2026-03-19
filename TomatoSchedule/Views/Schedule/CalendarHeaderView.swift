import SwiftUI

struct CalendarHeaderView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    @Binding var isExpanded: Bool
    let lessonCounts: [Date: Int]

    private let weekdayHeaders = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation + toggle
            HStack {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(DateHelper.monthString(displayedMonth))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "calendar.badge.minus" : "calendar.badge.plus")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { header in
                    Text(header)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // Calendar body
            if isExpanded {
                MonthGridView(
                    selectedDate: $selectedDate,
                    displayedMonth: displayedMonth,
                    lessonCounts: lessonCounts
                )
            } else {
                WeekStripView(
                    selectedDate: $selectedDate,
                    lessonCounts: lessonCounts
                )
            }

            // Expand/collapse chevron
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.77, blue: 0.72),
                    Color(red: 0.29, green: 0.68, blue: 0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16
            )
        )
    }

    private func moveMonth(_ offset: Int) {
        if let newMonth = DateHelper.calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newMonth
                let range = DateHelper.monthRange(for: newMonth)
                if selectedDate < range.start || selectedDate >= range.end {
                    selectedDate = range.start
                }
            }
        }
    }
}
