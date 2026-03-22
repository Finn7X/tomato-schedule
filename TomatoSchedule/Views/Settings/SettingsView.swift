import SwiftUI
import SwiftData
import EventKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allLessons: [Lesson]
    @ObservedObject private var syncService = CalendarSyncService.shared
    @AppStorage("showIncomeInCourseList") private var showIncomeInCourseList = true

    @State private var showingSyncConfirmation = false
    @State private var showingDisableConfirmation = false
    @State private var showingPermissionAlert = false
    @State private var showingImport = false
    @State private var alertMessage = ""
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            List {
                // Income summary
                Section("收入概览") {
                    incomeRow("今日", income: incomeForToday)
                    incomeRow("本周", income: incomeForWeek)
                    incomeRow("本月", income: incomeForMonth)
                    NavigationLink("查看详细收入统计") {
                        IncomeView()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }

                // Managed sync section
                Section {
                    Toggle("同步到系统日历", isOn: Binding(
                        get: { syncService.syncEnabled },
                        set: { newValue in
                            if newValue {
                                enableSync()
                            } else {
                                showingDisableConfirmation = true
                            }
                        }
                    ))

                    if syncService.syncEnabled {
                        Text("使用专属\"番茄课表\"日历管理")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            performFullSync()
                        } label: {
                            HStack {
                                Text("立即同步")
                                Spacer()
                                if isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSyncing)

                        if let date = syncService.lastSyncDate {
                            Text("上次同步: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("日历同步")
                }

                // Quick export section
                Section {
                    Button("导出全部课时到默认日历") {
                        performQuickExport()
                    }
                    .disabled(isSyncing)
                } header: {
                    Text("快速导出")
                } footer: {
                    Text("一次性将所有课时添加到系统默认日历，不追踪后续变更。")
                }

                // Import section
                Section {
                    Button("选择日历并导入") {
                        startImport()
                    }
                } header: {
                    Text("从系统日历导入")
                }

                // Display preferences
                Section("显示") {
                    Toggle("课程列表显示收入", isOn: $showIncomeInCourseList)
                }
            }
            .navigationTitle("设置")
            .alert("提示", isPresented: $showingPermissionAlert) {
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog("关闭日历同步", isPresented: $showingDisableConfirmation, titleVisibility: .visible) {
                Button("保留已同步事件") {
                    syncService.syncEnabled = false
                }
                Button("删除已同步事件", role: .destructive) {
                    disableSyncAndDelete()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("是否同时删除系统日历中的已同步事件？")
            }
            .sheet(isPresented: $showingImport) {
                CalendarImportView()
            }
        }
    }

    // MARK: - Actions

    private func enableSync() {
        Task {
            let granted = await syncService.requestFullAccess()
            if granted {
                syncService.syncEnabled = true
                performFullSync()
            } else {
                alertMessage = "需要完整日历访问权限以创建专属日历并管理同步。请在系统设置中开启。"
                showingPermissionAlert = true
            }
        }
    }

    private func performFullSync() {
        isSyncing = true
        Task {
            do {
                let count = try syncService.syncAllLessons(Array(allLessons))
                try modelContext.save()
                isSyncing = false
            } catch {
                isSyncing = false
            }
        }
    }

    private func performQuickExport() {
        Task {
            let granted = await syncService.requestWriteOnlyAccess()
            guard granted else {
                alertMessage = "需要日历写入权限才能导出课时。请在系统设置中开启。"
                showingPermissionAlert = true
                return
            }
            isSyncing = true
            do {
                let count = try syncService.quickExportAll(Array(allLessons))
                isSyncing = false
            } catch {
                isSyncing = false
            }
        }
    }

    private func disableSyncAndDelete() {
        do {
            try syncService.deleteAppCalendar()
            syncService.clearAllCalendarEventIds(for: Array(allLessons))
            try modelContext.save()
        } catch {}
        syncService.syncEnabled = false
    }

    private func startImport() {
        Task {
            let granted = await syncService.requestFullAccess()
            if granted {
                showingImport = true
            } else {
                alertMessage = "需要完整日历访问权限才能读取系统日历中的日程。请在系统设置中开启。"
                showingPermissionAlert = true
            }
        }
    }

    // MARK: - Income helpers

    private var incomeForToday: Double {
        let today = DateHelper.startOfDay(.now)
        let tomorrow = DateHelper.endOfDay(.now)
        return allLessons.filter { $0.isCompleted && $0.date >= today && $0.date < tomorrow }
            .reduce(0) { $0 + $1.effectivePrice }
    }

    private var incomeForWeek: Double {
        let range = DateHelper.weekRange(for: .now)
        return allLessons.filter { $0.isCompleted && $0.date >= range.start && $0.date < range.end }
            .reduce(0) { $0 + $1.effectivePrice }
    }

    private var incomeForMonth: Double {
        let range = DateHelper.monthRange(for: .now)
        return allLessons.filter { $0.isCompleted && $0.date >= range.start && $0.date < range.end }
            .reduce(0) { $0 + $1.effectivePrice }
    }

    @ViewBuilder
    private func incomeRow(_ label: String, income: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("¥\(Int(income))")
                .fontWeight(.medium)
                .foregroundStyle(income > 0 ? .primary : .secondary)
        }
    }
}
