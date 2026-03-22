import SwiftUI

struct StatisticsBar: View {
    let isMonthMode: Bool
    let month: Date
    let weekStart: Date
    let totalCount: Int
    let completedCount: Int
    let income: Double

    var body: some View {
        Text(displayText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var displayText: String {
        let incomeText = income > 0 ? "，收入¥\(Int(income))" : ""
        if isMonthMode {
            let monthNum = DateHelper.calendar.component(.month, from: month)
            return "\(monthNum)月排课\(totalCount)次，已上\(completedCount)次\(incomeText)"
        } else {
            return "本周排课\(totalCount)次，已上\(completedCount)次\(incomeText)"
        }
    }
}
