import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DayScheduleView()
                .tabItem {
                    Label("日", systemImage: "sun.max")
                }

            WeekScheduleView()
                .tabItem {
                    Label("周", systemImage: "calendar.day.timeline.left")
                }

            MonthScheduleView()
                .tabItem {
                    Label("月", systemImage: "calendar")
                }

            CourseListView()
                .tabItem {
                    Label("课程", systemImage: "book")
                }
        }
    }
}
