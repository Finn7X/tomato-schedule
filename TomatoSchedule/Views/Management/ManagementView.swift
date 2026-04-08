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

                Group {
                    switch tab {
                    case .courses:
                        CourseListContent()
                    case .students:
                        StudentListContent()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let h = value.translation.width
                            guard abs(h) > 60, abs(h) > abs(value.translation.height) else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if h < 0 {
                                    // swipe left → next tab
                                    if tab == .students { tab = .courses }
                                } else {
                                    // swipe right → prev tab
                                    if tab == .courses { tab = .students }
                                }
                            }
                        }
                )
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
