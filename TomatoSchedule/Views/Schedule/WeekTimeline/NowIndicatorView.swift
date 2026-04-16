import SwiftUI

struct NowIndicatorView: View {
    let timeRangeStart: Int
    let hourHeight: CGFloat
    let totalColumns: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let cal = DateHelper.calendar
            let hour = cal.component(.hour, from: context.date)
            let minute = cal.component(.minute, from: context.date)
            let minutesFromStart = (hour - timeRangeStart) * 60 + minute
            let yOffset = CGFloat(minutesFromStart) / 60 * hourHeight

            if minutesFromStart >= 0 {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color(.systemRed))
                        .frame(width: 8, height: 8)
                        .offset(x: -4)
                    Rectangle()
                        .fill(Color(.systemRed))
                        .frame(height: 1)
                }
                .offset(y: yOffset)
            }
        }
    }
}
