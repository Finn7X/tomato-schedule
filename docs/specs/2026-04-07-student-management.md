# 学生管理模块 — 设计方案

> 日期：2026-04-07
> 版本：final（经 2 轮 codex 评审定稿）
> 状态：已通过评审，待实施

---

## 1. 背景与目标

当前 app 没有集中管理学生的入口。学生信息（姓名）分散在每节课的 `studentName` 字段中，教师无法：
- 集中查看所有学生及其课时/收入汇总
- 给学生改名（拼写错误、英文名变更等）
- 从学生维度浏览课程分布

同时，"课程" Tab 当前功能过于单一（仅课程列表+增删改），利用率低。

**本方案目标：**
- 将"课程" Tab 升级为"管理" Tab，包含 `[课程] [学生]` 两个子页面
- 学生列表：从所有课时中自动聚合学生，展示课时数/总小时/总收入
- 学生详情：查看该学生的课程分布、课时历史，支持改名
- 不新增 Student 实体——继续使用 `studentName` 字符串聚合

---

## 2. Tab 改造

### 2.1 MainTabView 变更

| 项目 | 当前 | 改为 |
|------|------|------|
| Tab 图标 | `book` | `rectangle.stack` |
| Tab 标题 | `课程` | `管理` |
| Tab 内容 | `CourseListView` | `ManagementView`（新建） |

### 2.2 ManagementView（新建）

顶部 Segmented Picker 切换课程/学生：

```swift
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
                // + 按钮仅在课程分段时显示
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
```

**toolbar 职责划分：**
- `ManagementView` 持有 `showingAddCourse`，仅在 `.courses` 时显示 `+` 按钮
- `CourseListContent` 持有 `editingCourse`、`courseToDelete`（编辑/删除是行级操作，留在列表内部）
- 学生分段没有"新增"操作（学生自动从课时聚合），不显示 `+`

### 2.3 CourseListView 改造

将 `CourseListView` 改为 `CourseListContent`：
- 移除 `NavigationStack` 和 `.navigationTitle("我的课程")`
- 移除 toolbar 的 `+` 按钮和 `showingAddForm` 状态（由 ManagementView 管理）
- 保留：编辑 sheet（`editingCourse`）、删除确认（`courseToDelete`）、列表内容

---

## 3. 学生列表（StudentListContent）

### 3.1 数据聚合

从所有课时中按 `normalizeStudentName` 聚合：

```swift
struct StudentSummary: Identifiable {
    var id: String { name }  // 用 normalized name 作为稳定 id
    let name: String
    let lessonCount: Int
    let totalHours: Double
    let totalIncome: Double
    let courseNames: [String]
}
```

**id 使用 `name` 而非随机 `UUID()`**——确保搜索/改名后列表身份稳定，避免滚动位置和导航过渡抖动。

### 3.2 列表布局

```
┌──────────────────────────────────────┐
│  🔍 搜索学生                         │
│                                      │
│  傅褚备                              │
│  12节 · 24.0小时 · ¥9600         ▸   │
│  雅思阅读(线下), 雅思阅读(线上)       │
│                                      │
│  丹怡                                │
│  4节 · 8.0小时 · ¥2800           ▸   │
│  雅思阅读(线上)                       │
│                                      │
└──────────────────────────────────────┘
```

### 3.3 搜索

`.searchable(text: $searchText)`，过滤用 `localizedCaseInsensitiveContains`。

### 3.4 导航方式：显式路由状态

**不使用行内 `NavigationLink`**——改名会改变 `StudentSummary.id`（= name），行内 NavigationLink 的来源行消失后 SwiftUI 会 pop 回列表。

改用显式路由状态 + `.navigationDestination`：

```swift
// StudentListContent 内部
@State private var selectedStudent: String?  // normalized name

// 列表行
ForEach(filteredStudents) { student in
    Button { selectedStudent = student.name } label: {
        studentRow(student)
    }
}

// 导航目标（挂在外层，不依赖行的存在）
.navigationDestination(item: $selectedStudent) { name in
    StudentDetailView(studentName: name, onRenamed: { newName in
        // 改名后更新路由状态，防止 pop
        selectedStudent = newName
    })
}
```

`StudentDetailView` 改名后通过 `onRenamed` 回调通知列表更新路由键，导航保持稳定。

### 3.4 normalizeStudentName 的已知限制

当前 `normalizeStudentName` 只处理空白（trim + 合并连续空格），**不处理大小写、全角/半角、Unicode 归一化**。这意味着：
- `"Hailey"` 和 `"hailey"` 会被视为两个不同学生
- `"Ｓｕｒｉ"`（全角）和 `"Suri"`（半角）也是不同学生

这是刻意的产品取舍——教师录入的学生名通常是固定写法，出现大小写/全角混用的概率极低。如果确实发生了，教师可以通过**改名功能**手动统一。

---

## 4. 学生详情页（StudentDetailView）

### 4.1 入口

从学生列表点击某行进入。导航由 `StudentListContent` 的显式路由状态 `selectedStudent` + `.navigationDestination(item:)` 驱动（见 3.4 节），不使用行内 NavigationLink。

### 4.2 页面身份：可变 currentName

**核心设计决策：** `StudentDetailView` 使用 `@State private var currentName: String` 作为页面身份，而非不可变的 `let studentName`。改名后更新 `currentName`，页面数据自动刷新。

```swift
struct StudentDetailView: View {
    @Query private var allLessons: [Lesson]
    @State private var currentName: String   // 可变，改名后更新
    @State private var showRenameAlert = false
    @State private var showConflictAlert = false
    @State private var showSyncFailedAlert = false
    @State private var newName: String = ""
    var onRenamed: ((String) -> Void)?       // 通知父级更新路由键

    init(studentName: String, onRenamed: ((String) -> Void)? = nil) {
        _currentName = State(initialValue: studentName)
        self.onRenamed = onRenamed
    }

    // 所有查询都基于 currentName
    private var studentLessons: [Lesson] {
        let key = normalizeStudentName(currentName)
        return allLessons
            .filter { normalizeStudentName($0.studentName) == key }
            .sorted { $0.startTime > $1.startTime }
    }
    // ...
}
```

**为什么不用 `let studentName`：** 改名后 `let` 值不变，页面会继续用旧名查询——要么查不到数据（已经改成新名了），要么需要 dismiss 再重新进入。`@State` 可变状态让改名后页面无缝更新。

### 4.3 布局

```
┌─ 傅褚备 ────────────────────────┐
│                                  │
│  [✏️ 修改姓名]                   │
│                                  │
│  ── 总计 ──                      │
│  ┌────────┐ ┌────────┐ ┌──────┐ │
│  │ 12节课 │ │ 24小时 │ │¥9600 │ │
│  └────────┘ └────────┘ └──────┘ │
│                                  │
│  ── 课程分布 ──                  │
│  ● 雅思阅读(线下)  10节  ¥8000  │
│  ● 雅思阅读(线上)   2节  ¥1600  │
│                                  │
│  ── 最近课时 ──                  │
│  4/7 周一  雅思阅读(线下)  ¥800  │
│  4/4 周五  雅思阅读(线下)  ¥800  │
│  ...                             │
│                                  │
│  [查看月度明细 ▸]                │
└──────────────────────────────────┘
```

导航标题绑定 `currentName`：`.navigationTitle(currentName)`

### 4.4 最近课时列表

显示最近 20 节课（倒序），每行样式：`日期 星期 课程名 时间段 价格 ✅`

### 4.5 "查看月度明细"跳转

底部 NavigationLink 到 `StudentIncomeDetailView`。**传入该学生最近一节课的月份**（而非默认 `.now`），避免落在空月份：

```swift
NavigationLink("查看月度明细") {
    StudentIncomeDetailView(
        studentName: currentName,
        initialMonth: studentLessons.first?.date ?? .now
    )
}
```

`studentLessons` 按时间倒序，`.first` 是最近一节课的日期——打开后直接看到最近有课的月份。

---

## 5. 改名功能

### 5.1 交互流程

学生详情页顶部 `[✏️ 修改姓名]` 按钮 → `.alert` 带 TextField：

```swift
.alert("修改学生姓名", isPresented: $showRenameAlert) {
    TextField("新姓名", text: $newName)
    Button("确认") { performRename() }
    Button("取消", role: .cancel) {}
} message: {
    Text("将更新该学生的全部 \(studentLessons.count) 节课时记录")
}
```

### 5.2 改名逻辑

```swift
private func performRename() {
    let oldKey = normalizeStudentName(currentName)
    let newKey = normalizeStudentName(newName)
    guard !newKey.isEmpty, newKey != oldKey else { return }

    // 检查新名是否与现有学生冲突
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
    // 批量更新所有匹配课时
    for lesson in allLessons where normalizeStudentName(lesson.studentName) == oldKey {
        lesson.studentName = newKey
    }

    // 更新页面身份（@State）
    currentName = newKey

    // 通知父级更新路由键，防止导航 pop
    onRenamed?(newKey)

    // 日历重同步：更新事件标题中的学生名
    syncAfterRename(newKey: newKey)
}
```

### 5.3 冲突处理

```swift
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
```

### 5.4 日历同步

改名后需要重同步受影响课时——日历事件的**标题**含学生名（格式 `"课程名 · 学生名"`，见 `CalendarSyncService.populateEvent` line 209），备注含 `"学生第N节"`。

```swift
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
```

**同步失败处理：** 使用 `.alert`（与仓库现有 SettingsView/CourseListView 模式一致）：

```swift
.alert("日历同步提示", isPresented: $showSyncFailedAlert) {
    Button("我知道了") {}
} message: {
    Text("部分日历事件未能更新，可在设置中手动执行全量同步")
}
```

---

## 6. 与现有 StudentIncomeDetailView 的关系

`StudentIncomeDetailView` 保留不动——它负责"按月查看某学生收入明细"。

新的 `StudentDetailView` 负责"学生概览+改名"，两者通过导航链路衔接：
- 学生列表 → `StudentDetailView`（概览+改名）
- `StudentDetailView` 底部"查看月度明细" → `StudentIncomeDetailView`（传入最近课时月份）
- 收入页学生排行 → `StudentIncomeDetailView`（保持不变）

---

## 7. 涉及文件

### 新建文件

| 文件 | 用途 |
|------|------|
| `Views/Management/ManagementView.swift` | 管理页容器（Segmented Picker + toolbar 条件显示） |
| `Views/Management/StudentListContent.swift` | 学生列表（聚合+搜索+导航） |
| `Views/Management/StudentDetailView.swift` | 学生详情（汇总+课程分布+最近课时+改名+冲突合并） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Views/MainTabView.swift` | Tab 从 CourseListView 改为 ManagementView，图标 `rectangle.stack`，标题"管理" |
| `Views/Course/CourseListView.swift` | 重命名为 `CourseListContent`，移除 NavigationStack + 新增课程的 toolbar/sheet |

### 不修改文件

| 文件 | 原因 |
|------|------|
| `Models/Lesson.swift` | 无 schema 变更 |
| `Views/Income/StudentIncomeDetailView.swift` | 保留不动，被 StudentDetailView 引用 |
| `Views/Income/IncomeView.swift` | 保留不动 |

---

## 8. 实现优先级

| 阶段 | 内容 |
|------|------|
| Phase 1 | ManagementView + CourseListContent 提取 + MainTabView 改造 |
| Phase 2 | StudentListContent（学生列表+搜索） |
| Phase 3 | StudentDetailView（汇总+课程分布+最近课时+跳转） |
| Phase 4 | 改名功能（alert + 批量更新 + 冲突合并 + 日历重同步 + 失败 alert） |

---

## 9. 风险与注意事项

| 风险 | 缓解措施 |
|------|----------|
| CourseListContent 拆分后遗漏功能 | 编辑/删除状态留在 CourseListContent，新增由 ManagementView 管理 |
| 学生分段误显示 + 按钮 | ManagementView toolbar 条件判断 `if tab == .courses` |
| 改名后详情页数据消失 | 使用 `@State currentName` 可变状态，改名后自动刷新 |
| 改名后日历同步失败 | 显示 .alert 提示，不静默吞掉 |
| 学生名冲突合并不可逆 | 合并前 confirmationDialog 明确说明影响 |
| normalizeStudentName 不处理大小写 | 已知限制，文档中明确说明，用户可通过改名手动统一 |
| "查看月度明细"落在空月份 | 传入 `studentLessons.first?.date` 而非 `.now` |
| StudentSummary 列表抖动 | id 使用 `name` 字符串，不用随机 UUID |

---

## 10. 测试要点

| 测试场景 | 覆盖需求 |
|----------|----------|
| Tab 标题"管理"、图标 `rectangle.stack` | Tab 改造 |
| Segmented Picker 切换课程/学生，内容正确 | 管理页容器 |
| 课程分段显示 + 按钮，学生分段不显示 + | toolbar 条件 |
| 课程列表保持原有全部功能（增删改、收入显示） | 不回归 |
| 学生列表按课时数降序，显示节数/小时/收入/课程 | 学生聚合 |
| 搜索学生名模糊匹配 | 搜索 |
| 无学生名课时不出现在学生列表 | 空名过滤 |
| 学生详情显示总计/课程分布/最近 20 节课时 | 详情页 |
| "查看月度明细"跳转到最近有课的月份（非当前月） | 跳转锚定 |
| 改名"张三"→"张三丰"，所有课时 studentName 更新 | 改名核心 |
| 改名后详情页标题和数据自动刷新（不需要退出重进） | 页面身份 |
| 改名为已存在学生名，弹出合并确认 | 冲突处理 |
| 合并后两个学生课时归为一人 | 合并逻辑 |
| 改名后日历事件标题中学生名已更新 | 日历同步 |
| 日历同步失败时显示 .alert 提示 | 同步失败 |
| 改名为空字符串，确认按钮不生效 | 边界 |
| "Hailey" 和 "hailey" 显示为两个学生（已知限制） | normalize 边界 |
