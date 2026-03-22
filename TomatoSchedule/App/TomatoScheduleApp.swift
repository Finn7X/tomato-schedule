import SwiftUI
import SwiftData

@main
struct TomatoScheduleApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [Course.self, Lesson.self])
    }
}
