import SwiftUI

struct CalendarHeaderView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    @Binding var isExpanded: Bool
    let lessonCounts: [Date: Int]

    private enum SlideDirection { case backward, forward, none }
    @State private var slideDirection: SlideDirection = .none
    @State private var isAnimating = false

    private let weekdayHeaders = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation
            HStack {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Text(DateHelper.monthString(displayedMonth))
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
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

            // Calendar body with swipe gesture
            Group {
                if isExpanded {
                    MonthGridView(
                        selectedDate: $selectedDate,
                        displayedMonth: displayedMonth,
                        lessonCounts: lessonCounts
                    )
                    .id(displayedMonth)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideDirection == .backward ? .leading : .trailing),
                        removal: .move(edge: slideDirection == .backward ? .trailing : .leading)
                    ))
                } else {
                    WeekStripView(
                        selectedDate: $selectedDate,
                        lessonCounts: lessonCounts
                    )
                    .id(DateHelper.weekRange(for: selectedDate).start)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideDirection == .backward ? .leading : .trailing),
                        removal: .move(edge: slideDirection == .backward ? .trailing : .leading)
                    ))
                }
            }
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard !isAnimating else { return }
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > 50, abs(horizontal) > abs(vertical) else { return }

                        isAnimating = true
                        if horizontal < 0 {
                            // Left swipe → previous
                            slideDirection = .backward
                            if isExpanded {
                                moveMonth(-1)
                            } else {
                                moveWeek(-1)
                            }
                        } else {
                            // Right swipe → next
                            slideDirection = .forward
                            if isExpanded {
                                moveMonth(1)
                            } else {
                                moveWeek(1)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isAnimating = false
                        }
                    }
            )

            // Expand/collapse chevron
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.compact.down")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
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
        slideDirection = offset < 0 ? .backward : .forward
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

    private func moveWeek(_ offset: Int) {
        guard let newDate = DateHelper.calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) else { return }
        let oldMonth = DateHelper.calendar.dateComponents([.year, .month], from: selectedDate)
        let newMonth = DateHelper.calendar.dateComponents([.year, .month], from: newDate)
        let needsMonthSync = oldMonth != newMonth
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = newDate
            if needsMonthSync {
                displayedMonth = newDate
            }
        }
    }
}
