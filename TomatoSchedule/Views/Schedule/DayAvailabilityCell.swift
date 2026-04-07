import SwiftUI

// MARK: - Mini lesson block for month overview cell

struct MiniBlock: Identifiable {
    let id: UUID
    let startFraction: CGFloat   // position in time axis (0-1)
    let heightFraction: CGFloat  // height in time axis (0-1)
    let timeText: String         // "9-11" compact format
    let studentName: String
    let courseColorHex: String
}

// MARK: - Student color palette

enum StudentColors {
    private static let palette: [Color] = [
        Color(red: 0.90, green: 0.30, blue: 0.30),  // red
        Color(red: 0.25, green: 0.55, blue: 0.83),  // blue
        Color(red: 0.30, green: 0.70, blue: 0.40),  // green
        Color(red: 0.90, green: 0.55, blue: 0.20),  // orange
        Color(red: 0.60, green: 0.35, blue: 0.75),  // purple
        Color(red: 0.85, green: 0.40, blue: 0.60),  // pink
        Color(red: 0.20, green: 0.70, blue: 0.70),  // cyan
        Color(red: 0.40, green: 0.40, blue: 0.75),  // indigo
        Color(red: 0.55, green: 0.75, blue: 0.30),  // lime
        Color(red: 0.75, green: 0.55, blue: 0.35),  // brown
    ]

    static func color(for name: String) -> Color {
        guard !name.isEmpty else { return .gray }
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

// MARK: - Day cell

struct DayAvailabilityCell: View {
    let date: Date
    let blocks: [MiniBlock]
    let lessonCount: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let showStudents: Bool     // false = time text + teal, true = student name + student color
    let cellHeight: CGFloat

    private let teal = Color(red: 0.34, green: 0.77, blue: 0.72)

    private var isPast: Bool {
        isCurrentMonth && DateHelper.calendar.startOfDay(for: date) < DateHelper.calendar.startOfDay(for: .now)
    }

    private var barHeight: CGFloat {
        max(cellHeight - 22, 20)
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
            .frame(height: 18)
            .padding(.horizontal, 2)

            // Lesson blocks area — fills remaining height, 90% width
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                // Light background strip
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.06))
                    .frame(width: w * 0.9, height: h)
                    .position(x: w / 2, y: h / 2)

                ForEach(blocks) { block in
                    let blockH = max(block.heightFraction * h, 10)
                    let blockY = block.startFraction * h + blockH / 2
                    let blockW = w * 0.9
                    let color = showStudents
                        ? StudentColors.color(for: block.studentName)
                        : teal

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.85))
                        .frame(width: blockW, height: blockH)
                        .overlay(
                            Text(showStudents ? block.studentName : block.timeText)
                                .font(.system(size: 7))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, 1)
                        )
                        .position(x: w / 2, y: blockY)
                }
            }
            .frame(height: barHeight)
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
        } else {
            Text("\(day)")
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .padding(.leading, 3)
                .padding(.top, 1)
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
