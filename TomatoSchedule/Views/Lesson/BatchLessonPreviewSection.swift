import SwiftUI

/// The preview list inside BatchLessonFormView.
/// Renders generated dates with conflict markers, student-progress badges,
/// and swipe-to-exclude. All state lives in the parent; this view only
/// consumes precomputed data and fires callbacks.
struct BatchLessonPreviewSection: View {
    let generatedDates: [Date]
    let progressMap: [Date: Int]
    let startTime: Date
    let endTime: Date
    let conflictDates: Set<Date>
    let onExclude: (Date) -> Void

    var body: some View {
        Section("预览（\(generatedDates.count)节课）") {
            if generatedDates.isEmpty {
                Text("请选择重复星期")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(generatedDates.enumerated()), id: \.offset) { _, date in
                    HStack {
                        if conflictDates.contains(date) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        Text(DateHelper.dateString(date))
                        Text(DateHelper.weekdaySymbol(date))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(DateHelper.timeString(startTime))-\(DateHelper.timeString(endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let studentIdx = progressMap[date] {
                            Text("第\(studentIdx)节")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onExclude(date)
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }

                if generatedDates.count >= 100 {
                    Text("最多显示100节")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
