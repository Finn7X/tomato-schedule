import SwiftUI

/// Ranking list under the income chart — either per-course or per-student.
/// Renders nothing when the chosen side's data is empty.
struct IncomeRankingView: View {
    let rankingMode: RankingMode
    let courseRanking: [CourseIncome]
    let studentRanking: [StudentIncome]
    let periodLabel: String
    let referenceDate: Date

    var body: some View {
        if rankingMode == .byCourse {
            if !courseRanking.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(periodLabel + "课程收入")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                    ForEach(courseRanking) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(PresetColors.color(for: item.colorHex))
                                .frame(width: 10, height: 10)
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.count)节")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("¥\(Int(item.income))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 70, alignment: .trailing)
                            Text(String(format: "%.0f%%", item.percentage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                }
            }
        } else {
            if !studentRanking.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(periodLabel + "学生收入")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                    ForEach(studentRanking) { item in
                        NavigationLink {
                            StudentIncomeDetailView(studentName: item.name, initialMonth: referenceDate)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(.secondary)
                                    .frame(width: 10, height: 10)
                                Text(item.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.count)节")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("¥\(Int(item.income))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 70, alignment: .trailing)
                                Text(String(format: "%.0f%%", item.percentage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}
