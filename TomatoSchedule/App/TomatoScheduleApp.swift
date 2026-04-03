import SwiftUI
import SwiftData

@main
struct TomatoScheduleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    migrateV5PriceFreeze()
                    autoCompletePastLessons()
                }
        }
        .modelContainer(for: [Course.self, Lesson.self])
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                autoCompletePastLessons()
            }
        }
    }

    @MainActor
    private func migrateV5PriceFreeze() {
        guard !UserDefaults.standard.bool(forKey: "v5PriceMigrationDone") else { return }
        guard let container = try? ModelContainer(for: Course.self, Lesson.self) else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<Lesson>()
        guard let lessons = try? context.fetch(descriptor) else { return }
        var changed = false
        for lesson in lessons {
            if lesson.isPriceOverridden && !lesson.isCompleted {
                // Scenario B: user manually set price in V4
                lesson.isManualPrice = true
                changed = true
            } else if lesson.isPriceOverridden && lesson.isCompleted {
                // Scenario C: system auto-freeze
                lesson.isManualPrice = false
                changed = true
            } else if !lesson.isPriceOverridden {
                // Scenario A: not yet frozen — freeze now
                lesson.priceOverride = lesson.effectivePrice
                lesson.isPriceOverridden = true
                lesson.isManualPrice = false
                changed = true
            }
        }
        if changed { try? context.save() }
        UserDefaults.standard.set(true, forKey: "v5PriceMigrationDone")
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
