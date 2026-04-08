import SwiftUI
import SwiftData

struct StudentListContent: View {
    @Query private var allLessons: [Lesson]
    @State private var searchText = ""
    @Binding var selectedStudent: String?

    // MARK: - Student aggregation

    private struct StudentSummary: Identifiable {
        var id: String { name }
        let name: String
        let lessonCount: Int
        let totalHours: Double
        let totalIncome: Double
        let courseNames: [String]
    }

    private var students: [StudentSummary] {
        var map: [String: (count: Int, hours: Double, income: Double, courses: Set<String>)] = [:]
        for lesson in allLessons {
            let key = normalizeStudentName(lesson.studentName)
            guard !key.isEmpty else { continue }
            var entry = map[key] ?? (0, 0, 0, [])
            entry.count += 1
            entry.hours += Double(lesson.durationMinutes) / 60.0
            if lesson.isCompleted || lesson.endTime < .now {
                entry.income += lesson.effectivePrice
            }
            if let name = lesson.course?.name {
                entry.courses.insert(name)
            }
            map[key] = entry
        }
        return map.map { StudentSummary(
            name: $0.key,
            lessonCount: $0.value.count,
            totalHours: $0.value.hours,
            totalIncome: $0.value.income,
            courseNames: Array($0.value.courses).sorted()
        ) }
        .sorted { $0.lessonCount > $1.lessonCount }
    }

    private var filteredStudents: [StudentSummary] {
        let query = normalizeStudentName(searchText)
        if query.isEmpty { return students }
        return students.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if students.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无学生")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("添加课时并填写学生姓名后，学生会自动出现在这里")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredStudents) { student in
                        Button {
                            selectedStudent = student.name
                        } label: {
                            studentRow(student)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "搜索学生")
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func studentRow(_ student: StudentSummary) -> some View {
        HStack(spacing: 12) {
            // Student color indicator
            Circle()
                .fill(StudentColors.color(for: student.name))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(student.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text("\(student.lessonCount)节")
                    Text("·")
                    Text(String(format: "%.1f小时", student.totalHours))
                    Text("·")
                    Text("¥\(Int(student.totalIncome))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !student.courseNames.isEmpty {
                    Text(student.courseNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
