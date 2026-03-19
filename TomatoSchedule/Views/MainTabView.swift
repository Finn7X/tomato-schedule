import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ScheduleView()
                .tabItem {
                    Label("课表", systemImage: "calendar")
                }

            CourseListView()
                .tabItem {
                    Label("课程", systemImage: "book")
                }
        }
    }
}
