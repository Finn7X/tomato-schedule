import SwiftUI
import SwiftData

struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSize
    @EnvironmentObject private var coordinator: AppOrientationCoordinator

    @State private var focusDate: Date = DateHelper.calendar.startOfDay(for: .now)

    var onSelectDate: ((Date) -> Void)?

    var body: some View {
        Group {
            if vSize == .compact {
                WeekTimelineView(
                    focusDate: $focusDate,
                    lessons: allLessons,
                    onDismiss: dismissWithOrientationRestore
                )
            } else {
                MonthCalendarView(
                    focusDate: $focusDate,
                    lessons: allLessons,
                    onSelectDate: onSelectDate,
                    onDismiss: dismissWithOrientationRestore
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vSize)
        .onAppear {
            coordinator.allowedMask = .allButUpsideDown
        }
        .onDisappear {
            coordinator.allowedMask = .portrait
        }
    }

    private func dismissWithOrientationRestore() {
        if let scene = UIApplication.shared.activeWindowScene,
           scene.interfaceOrientation.isLandscape {
            coordinator.requestOrientation(.portrait)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                coordinator.allowedMask = .portrait
                dismiss()
            }
        } else {
            coordinator.allowedMask = .portrait
            dismiss()
        }
    }
}
