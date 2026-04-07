import SwiftUI

struct DayAvailabilityCell: View {
    let date: Date
    let busyBins: [Bool]           // 14 x 1-hour bins (8:00-22:00)
    let lessonCount: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let showStudents: Bool         // show student names on bars
    let studentBins: [String]      // student name per hour bin (same count as busyBins)
    let cellHeight: CGFloat        // dynamic height from parent

    private var isPast: Bool {
        isCurrentMonth && DateHelper.calendar.startOfDay(for: date) < DateHelper.calendar.startOfDay(for: .now)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: date + lesson count
            HStack(alignment: .top) {
                dateLabel
                Spacer()
                if lessonCount > 0 && isCurrentMonth {
                    Text("\(lessonCount)节")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 3)
            .padding(.top, 4)

            Spacer()

            // Horizontal time bar
            timeBar
                .padding(.horizontal, 2)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background(cellBackground)
        .opacity(isCurrentMonth ? (isPast ? 0.5 : 1.0) : 0.3)
    }

    // MARK: - Date Label

    @ViewBuilder
    private var dateLabel: some View {
        let day = DateHelper.calendar.component(.day, from: date)
        if isToday && isCurrentMonth {
            ZStack {
                Circle()
                    .fill(Color(red: 0.83, green: 0.65, blue: 0.22))
                    .frame(width: 20, height: 20)
                Text("\(day)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            Text("\(day)")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Cell Background

    private var cellBackground: some View {
        Group {
            if isToday && isCurrentMonth {
                Color(red: 0.34, green: 0.77, blue: 0.72).opacity(0.08)
            } else if lessonCount > 0 && isCurrentMonth {
                Color(red: 0.34, green: 0.77, blue: 0.72).opacity(0.03)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Horizontal Time Bar

    private var timeBar: some View {
        HStack(spacing: 0.5) {
            ForEach(Array(busyBins.enumerated()), id: \.offset) { index, busy in
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(busy
                            ? Color(red: 0.34, green: 0.77, blue: 0.72)
                            : Color.gray.opacity(0.12))

                    // Student name overlay (only in student mode, only on busy slots)
                    if showStudents && busy && index < studentBins.count && !studentBins[index].isEmpty {
                        Text(studentBins[index])
                            .font(.system(size: 6))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            // Time reference markers at 12:00 and 18:00 positions
            // 12:00 = index 4 out of 14 = 4/14 of width
            // 18:00 = index 10 out of 14 = 10/14 of width
            GeometryReader { geo in
                let w = geo.size.width
                Path { path in
                    let x12 = w * 4.0 / 14.0
                    let x18 = w * 10.0 / 14.0
                    path.move(to: CGPoint(x: x12, y: 0))
                    path.addLine(to: CGPoint(x: x12, y: geo.size.height))
                    path.move(to: CGPoint(x: x18, y: 0))
                    path.addLine(to: CGPoint(x: x18, y: geo.size.height))
                }
                .stroke(.white.opacity(0.4), lineWidth: 0.5)
            }
        )
    }
}
