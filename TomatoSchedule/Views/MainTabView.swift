import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ScheduleView()
                .tabItem {
                    Label("课表", systemImage: "calendar")
                }
                .tag(0)

            IncomeView()
                .tabItem {
                    Label("收入", systemImage: "yensign.circle")
                }
                .tag(1)

            ManagementView()
                .tabItem {
                    Label("管理", systemImage: "rectangle.stack")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(3)
        }
    }
}
