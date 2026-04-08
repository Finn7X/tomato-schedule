import SwiftUI
import SwiftData

struct StudentDetailView: View {
    @Query private var allLessons: [Lesson]
    @State private var currentName: String
    @State private var showRenameAlert = false
    @State private var showConflictAlert = false
    @State private var showSyncFailedAlert = false
    @State private var newName: String = ""
    var onRenamed: ((String) -> Void)?

    init(studentName: String, onRenamed: ((String) -> Void)? = nil) {
        _currentName = State(initialValue: studentName)
        self.onRenamed = onRenamed
    }

    // MARK: - Data

    private var studentLessons: [Lesson] {
        let key = normalizeStudentName(currentName)
        return allLessons
            .filter { normalizeStudentName($0.studentName) == key }
            .sorted { $0.startTime > $1.startTime }
    }

    private var totalLessons: Int { studentLessons.count }

    private var totalHours: Double {
        studentLessons.reduce(0) { $0 + Double($1.durationMinutes) / 60.0 }
    }

    private var totalIncome: Double {
        studentLessons.filter { $0.isCompleted || $0.endTime < .now }
            .reduce(0) { $0 + $1.effectivePrice }
    }

    private var courseDistribution: [(name: String, colorHex: String, count: Int, income: Double)] {
        var map: [UUID: (name: String, color: String, count: Int, income: Double)] = [:]
        for lesson in studentLessons {
            let cid = lesson.course?.id ?? UUID()
            let name = lesson.course?.name ?? "未知"
            let color = lesson.course?.colorHex ?? "#78909C"
            var entry = map[cid] ?? (name, color, 0, 0)
            entry.count += 1
            if lesson.isCompleted || lesson.endTime < .now {
                entry.income += lesson.effectivePrice
            }
            map[cid] = entry
        }
        return map.values.map { ($0.name, $0.color, $0.count, $0.income) }
            .sorted { $0.count > $1.count }
    }

    private var recentLessons: [Lesson] {
        Array(studentLessons.prefix(20))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Rename button
                Button {
                    newName = currentName
                    showRenameAlert = true
                } label: {
                    Label("修改姓名", systemImage: "pencil")
                        .font(.subheadline)
                }
                .padding(.top, 8)

                // Summary cards
                HStack(spacing: 12) {
                    summaryCard(title: "课时", value: "\(totalLessons)节")
                    summaryCard(title: "总时长", value: String(format: "%.1fh", totalHours))
                    summaryCard(title: "收入", value: "¥\(Int(totalIncome))")
                }
                .padding(.horizontal)

                // Course distribution
                if !courseDistribution.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("课程分布")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal)
                            .padding(.bottom, 8)

                        ForEach(Array(courseDistribution.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(PresetColors.color(for: item.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(item.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.count)节")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("¥\(Int(item.income))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                    }
                }

                // Recent lessons
                if !recentLessons.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("最近课时")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal)
                            .padding(.bottom, 8)

                        ForEach(recentLessons) { lesson in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(DateHelper.dateString(lesson.date))
                                            .font(.subheadline)
                                        Text(DateHelper.weekdaySymbol(lesson.date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(lesson.course?.name ?? "未知课程")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(lesson.timeRangeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if lesson.effectivePrice > 0 {
                                    Text("¥\(Int(lesson.effectivePrice))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                if lesson.isCompleted || lesson.endTime < .now {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            Divider().padding(.leading)
                        }
                    }
                }

                // Navigate to monthly detail
                NavigationLink("查看月度明细") {
                    StudentIncomeDetailView(
                        studentName: currentName,
                        initialMonth: studentLessons.first?.date ?? .now
                    )
                }
                .font(.subheadline)
                .padding(.vertical, 12)

                Spacer(minLength: 20)
            }
        }
        .navigationTitle(currentName)
        .alert("修改学生姓名", isPresented: $showRenameAlert) {
            TextField("新姓名", text: $newName)
            Button("确认") { performRename() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将更新该学生的全部 \(totalLessons) 节课时记录")
        }
        .confirmationDialog("学生姓名冲突", isPresented: $showConflictAlert, titleVisibility: .visible) {
            Button("合并") {
                let oldKey = normalizeStudentName(currentName)
                let newKey = normalizeStudentName(newName)
                applyRename(oldKey: oldKey, newKey: newKey)
            }
            Button("取消", role: .cancel) {}
        } message: {
            let newKey = normalizeStudentName(newName)
            let count = allLessons.filter { normalizeStudentName($0.studentName) == newKey }.count
            Text("学生「\(newKey)」已存在（\(count)节课）。\n确认改名将合并两个学生的所有课时记录，此操作不可逆。")
        }
        .alert("日历同步提示", isPresented: $showSyncFailedAlert) {
            Button("我知道了") {}
        } message: {
            Text("部分日历事件未能更新，可在设置中手动执行全量同步")
        }
    }

    // MARK: - Rename

    private func performRename() {
        let oldKey = normalizeStudentName(currentName)
        let newKey = normalizeStudentName(newName)
        guard !newKey.isEmpty, newKey != oldKey else { return }

        let existingCount = allLessons.filter {
            normalizeStudentName($0.studentName) == newKey
        }.count
        if existingCount > 0 {
            showConflictAlert = true
            return
        }

        applyRename(oldKey: oldKey, newKey: newKey)
    }

    private func applyRename(oldKey: String, newKey: String) {
        for lesson in allLessons where normalizeStudentName(lesson.studentName) == oldKey {
            lesson.studentName = newKey
        }
        currentName = newKey
        onRenamed?(newKey)
        syncAfterRename(newKey: newKey)
    }

    private func syncAfterRename(newKey: String) {
        let affected = allLessons.filter { normalizeStudentName($0.studentName) == newKey }
        let indexMap = CalendarSyncService.buildStudentIndexMap(Array(allLessons))
        var syncFailed = false
        for lesson in affected {
            do {
                try CalendarSyncService.shared.syncLesson(lesson, studentIndex: indexMap[lesson.id])
            } catch {
                syncFailed = true
            }
        }
        if syncFailed {
            showSyncFailedAlert = true
        }
    }

    // MARK: - Summary Card

    @ViewBuilder
    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }
}
