import SwiftUI

struct DayAvailabilityCell: View {
    let date: Date
    let busyBins: [Bool]           // 14 x 1-hour bins (8:00-22:00)
    let lessonCount: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let showCourseColors: Bool     // show per-course colors vs unified teal
    let binColors: [String]        // colorHex per bin (only used when showCourseColors)
    let cellHeight: CGFloat

    private let teal = Color(red: 0.34, green: 0.77, blue: 0.72)

    private var isPast: Bool {
        isCurrentMonth && DateHelper.calendar.startOfDay(for: date) < DateHelper.calendar.startOfDay(for: .now)
    }

    // Height for the vertical bar = cell height minus header and padding
    private var barHeight: CGFloat {
        max(cellHeight - 24, 30)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: date left, count right
            HStack(alignment: .top, spacing: 0) {
                dateLabel
                Spacer(minLength: 0)
                if lessonCount > 0 && isCurrentMonth {
                    Text("\(lessonCount)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                }
            }
            .frame(height: 20)
            .padding(.horizontal, 2)

            // Vertical time bar — centered, 8:00 (top) to 22:00 (bottom)
            VStack(spacing: 0.5) {
                ForEach(Array(busyBins.enumerated()), id: \.offset) { index, busy in
                    let color: Color = {
                        if !busy { return Color.gray.opacity(0.12) }
                        if showCourseColors && index < binColors.count && !binColors[index].isEmpty {
                            return PresetColors.color(for: binColors[index])
                        }
                        return teal
                    }()
                    Rectangle()
                        .fill(color)
                }
            }
            .frame(width: 16, height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                // Reference lines at 12:00 and 18:00
                GeometryReader { geo in
                    let h = geo.size.height
                    let count = CGFloat(max(busyBins.count, 1))
                    Path { path in
                        // 12:00 = bin index 4 → y = 4/14 of height
                        let y12 = h * 4.0 / count
                        path.move(to: CGPoint(x: 0, y: y12))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y12))
                        // 18:00 = bin index 10 → y = 10/14 of height
                        let y18 = h * 10.0 / count
                        path.move(to: CGPoint(x: 0, y: y18))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y18))
                    }
                    .stroke(.white.opacity(0.5), lineWidth: 0.5)
                }
            )
            .padding(.bottom, 2)
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
                    .frame(width: 18, height: 18)
                Text("\(day)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 1)
            .padding(.top, 1)
        } else {
            Text("\(day)")
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .padding(.leading, 3)
                .padding(.top, 2)
        }
    }

    // MARK: - Cell Background

    private var cellBackground: some View {
        Group {
            if isToday && isCurrentMonth {
                teal.opacity(0.08)
            } else if lessonCount > 0 && isCurrentMonth {
                teal.opacity(0.03)
            } else {
                Color.clear
            }
        }
    }
}
