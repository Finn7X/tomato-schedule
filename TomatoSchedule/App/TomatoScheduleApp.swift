import SwiftUI
import SwiftData

@main
struct TomatoScheduleApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear { autoCompletePastLessons() }
        }
        .modelContainer(for: [Course.self, Lesson.self])
    }

    @MainActor
    private func autoCompletePastLessons() {
        guard let container = try? ModelContainer(for: Course.self, Lesson.self) else { return }
        let context = container.mainContext
        let now = Date.now
        let descriptor = FetchDescriptor<Lesson>()
        guard let lessons = try? context.fetch(descriptor) else { return }
        var changed = false
        for lesson in lessons where !lesson.isCompleted && lesson.endTime < now {
            lesson.isCompleted = true
            if !lesson.isPriceOverridden {
                lesson.priceOverride = lesson.effectivePrice
                lesson.isPriceOverridden = true
            }
            changed = true
        }
        if changed { try? context.save() }
    }
}
