import SwiftUI

struct ManagementView: View {
    @State private var tab: ManagementTab = .students
    @State private var showingAddCourse = false

    enum ManagementTab: String, CaseIterable {
        case students = "学生"
        case courses = "课程"
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
                .padding(.bottom, 4)

                TabView(selection: $tab) {
                    StudentListContent()
                        .tag(ManagementTab.students)
                    CourseListContent()
                        .tag(ManagementTab.courses)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("教务")
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
