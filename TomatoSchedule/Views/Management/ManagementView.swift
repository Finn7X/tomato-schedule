import SwiftUI

struct ManagementView: View {
    @State private var tab: ManagementTab = .students
    @State private var showingAddCourse = false
    @State private var selectedStudent: String?

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
                    StudentListContent(selectedStudent: $selectedStudent)
                        .tag(ManagementTab.students)
                    CourseListContent()
                        .tag(ManagementTab.courses)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("教务")
            .navigationDestination(item: $selectedStudent) { name in
                StudentDetailView(studentName: name, onRenamed: { newName in
                    selectedStudent = newName
                })
            }
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
