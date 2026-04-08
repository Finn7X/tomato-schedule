import SwiftUI

struct ManagementView: View {
    @State private var tab: ManagementTab = .courses
    @State private var showingAddCourse = false

    enum ManagementTab: String, CaseIterable {
        case courses = "课程"
        case students = "学生"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(ManagementTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch tab {
                case .courses:
                    CourseListContent()
                case .students:
                    StudentListContent()
                }
            }
            .navigationTitle("管理")
            .toolbar {
                if tab == .courses {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddCourse = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddCourse) {
                CourseFormView()
            }
        }
    }
}
