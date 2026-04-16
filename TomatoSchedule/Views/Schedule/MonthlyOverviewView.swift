import SwiftUI
import SwiftData

struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @State private var focusDate: Date = DateHelper.calendar.startOfDay(for: .now)

    var onSelectDate: ((Date) -> Void)?

    var body: some View {
        MonthCalendarView(
            focusDate: $focusDate,
            lessons: allLessons,
            onSelectDate: onSelectDate,
            onDismiss: { dismiss() }
        )
    }
}
