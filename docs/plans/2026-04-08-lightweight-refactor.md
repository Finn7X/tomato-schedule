# 轻量级项目整理 实施计划

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 对 TomatoSchedule 进行阶段性轻量级整理，解决架构名不副实（空 ViewModels 目录）、View 层过重（85% 代码在 Views）、业务逻辑散落在 View 中、学生逻辑重复等问题。整理原则：不改功能、不改 UI、不引入新依赖，只做结构优化。

**Architecture:** 按风险递增分 4 个 Phase 实施。Phase 1 是无风险清理，Phase 2-3 抽取业务逻辑到独立模块，Phase 4 拆分胖 View。每个 Phase 完成后应编译验证。

**Tech Stack:** Swift 5 / SwiftUI / SwiftData / EventKit / iOS 17+ / XcodeGen

**Branch:** `refactor/lightweight-cleanup`

**Build verify:** `cd /Users/xujifeng/dev/TomatoSchedule && xcodegen generate && xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build`

---

## 现状分析

| 指标 | 数据 |
|------|------|
| Swift 文件数 | 33 |
| 总代码量 | ~5,075 行 |
| Views 占比 | 85%（26 文件 / ~4,352 行） |
| Services | 1 个（CalendarSyncService） |
| Helpers | 3 个（DateHelper / StudentProgress / PresetColors） |
| ViewModels | 0 个（空目录） |

**核心问题：**

1. **空 ViewModels 目录** — 在 project.yml 和 Xcode 中占位，暗示 MVVM 但未实际使用，误导架构理解
2. **IncomeView 过重** — 407 行，混合了 6 个 computed 聚合属性（chartData / courseRanking / studentRanking 等）+ UI 渲染 + 时间导航逻辑
3. **学生逻辑分散** — `normalizeStudentName()` 在 `StudentProgress.swift` 中定义，`buildStudentIndexMap()` 在 `CalendarSyncService` 中定义，两处有相似的排序/分组逻辑但没有统一接口
4. **ScheduleView 混合 UIKit hack** — 52 行 `ScrollOffsetObserver`（UIKit KVO introspection）与业务视图混在同一文件

---

## Phase 1: 无风险清理

> 删除空目录、移动与视图无关的 UIKit 代码。零功能影响，纯文件组织调整。

### Task 1.1: 删除空的 ViewModels 目录

**Files:**
- Delete: `TomatoSchedule/ViewModels/` (空目录)

**Note:** 当前 `project.yml` 使用 `sources: - TomatoSchedule` 整目录收录，且未对 `ViewModels` 做显式 group 引用（见 `project.yml:14-20`），因此**不需要改 `project.yml`**。同理，**不要手动改 `TomatoSchedule.xcodeproj/project.pbxproj`**，由 `xcodegen generate` 重新生成即可。

- [ ] **Step 1:** 确认 `ViewModels/` 目录为空，删除该目录
- [ ] **Step 2:** 运行 `xcodegen generate` 重新生成项目文件
- [ ] **Step 3:** 编译验证

### Task 1.2: 将 ScrollOffsetObserver 移到 Components

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/ScheduleView.swift` — 移除前 77 行（`ScrollOffsetObserver` + `ScrollCalendarFoldModifier`）
- Create: `TomatoSchedule/Views/Components/ScrollCalendarFold.swift` — 接收移出的代码

**Why:** `ScrollOffsetObserver` 是一个通用的 UIKit introspection 工具，与 Schedule 业务无关。`ScrollCalendarFoldModifier` 依赖它，二者一起移动。

- [ ] **Step 1:** 新建 `TomatoSchedule/Views/Components/ScrollCalendarFold.swift`
- [ ] **Step 2:** 将 `ScheduleView.swift` 中 line 1-77 的以下代码移入新文件：
  - `ScrollOffsetObserver`（`private struct` → `struct`，去掉 `private`）
  - `ScrollCalendarFoldModifier`（`private struct` → `struct`，去掉 `private`）
- [ ] **Step 3:** 在 `ScheduleView.swift` 中删除已移出的代码（仅保留 `import` 和 `ScheduleView` struct）
- [ ] **Step 4:** 编译验证

**验证点:** ScheduleView.swift 从 ~288 行降至 ~211 行，Schedule 滑动折叠行为不变。

---

## Phase 2: 抽取收入聚合逻辑

> 将 IncomeView 中的数据聚合逻辑（占该文件约 120 行）抽取为独立模块，View 只负责渲染。

**命名决定：** 为避免命名歧义（`IncomeAggregator` 名字偏纯聚合，但又会承载 UI 枚举），拆成两个文件：
- `IncomeTypes.swift` — 共享类型（`Period` / `RankingMode` / `ChartEntry` / `CourseIncome` / `StudentIncome`），供 View 和 Aggregator 共用
- `IncomeAggregator.swift` — 纯聚合函数

### Task 2.1a: 新建 IncomeTypes.swift

**Files:**
- Create: `TomatoSchedule/Helpers/IncomeTypes.swift`

- [ ] **Step 1:** 新建 `IncomeTypes.swift`，定义共享类型：

```swift
import Foundation

enum Period: String, CaseIterable {
    case week = "周"
    case month = "月"
    case year = "年"
}

enum RankingMode: String, CaseIterable {
    case byCourse = "按课程"
    case byStudent = "按学生"
}

struct ChartEntry: Identifiable {
    let id = UUID()
    let label: String
    let sortOrder: Int
    let courseName: String
    let courseColor: String
    let studentKey: String
    let income: Double
}

struct CourseIncome: Identifiable {
    let id = UUID()
    let name: String
    let colorHex: String
    let count: Int
    let income: Double
    let percentage: Double
}

struct StudentIncome: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let income: Double
    let percentage: Double
}
```

- [ ] **Step 2:** 从 `IncomeView.swift` 中删除原有的 `Period` / `RankingMode` 定义（line 14-23）

### Task 2.1b: 新建 IncomeAggregator.swift

**Files:**
- Create: `TomatoSchedule/Helpers/IncomeAggregator.swift`

- [ ] **Step 1:** 新建 `IncomeAggregator.swift`，仅存放纯聚合函数：

```swift
import Foundation

enum IncomeAggregator {
    static func chartData(
        from lessons: [Lesson],
        period: Period,
        rankingMode: RankingMode
    ) -> [ChartEntry] { ... }

    static func courseRanking(from lessons: [Lesson]) -> [CourseIncome] { ... }

    static func studentRanking(from lessons: [Lesson]) -> [StudentIncome] { ... }
}
```

### Task 2.2: IncomeView 改为调用 IncomeAggregator

**Files:**
- Modify: `TomatoSchedule/Views/Income/IncomeView.swift`

- [ ] **Step 1:** 删除 IncomeView 中的以下内联类型和计算属性：
  - `Period` enum (line 14-18) — 已在 IncomeTypes.swift
  - `RankingMode` enum (line 20-23) — 已在 IncomeTypes.swift
  - `ChartEntry` struct (line 73-81)
  - `chartData` computed property (line 83-118)
  - `CourseIncome` struct (line 121-128)
  - `courseRanking` computed property (line 130-145)
  - `StudentIncome` struct (line 148-154)
  - `studentRanking` computed property (line 156-169)

- [ ] **Step 2:** 替换为调用 `IncomeAggregator` 的计算属性：

```swift
private var chartData: [ChartEntry] {
    IncomeAggregator.chartData(from: lessonsInRange, period: period, rankingMode: rankingMode)
}

private var courseRanking: [CourseIncome] {
    IncomeAggregator.courseRanking(from: lessonsInRange)
}

private var studentRanking: [StudentIncome] {
    IncomeAggregator.studentRanking(from: lessonsInRange)
}
```

- [ ] **Step 3:** 编译验证

**验证点:**
- IncomeView.swift 从 407 行降至 ~310 行
- 收入页面所有功能不变：周/月/年切换、预估收入、课程排行、学生排行
- **运行时验证：** 打开"学生"排行榜 → 点击某个学生 → 跳转 `StudentIncomeDetailView` 正常

---

## Phase 3: 统一学生逻辑

> 将分散在 `StudentProgress.swift`、`CalendarSyncService` 和 `BatchLessonFormView` 中的学生分组/排序/索引逻辑归位到同一模块，并抽出共享排序规则，避免 4 个函数各自维护同一套排序。

**目标明确化：** 不仅是"换文件名 + 挪函数"，还要抽出一个极小的内部排序规则（`lessonOrdering`），让 `studentProgress` / `computeStudentIndex` / `buildStudentIndexMap` 三个函数共用同一排序逻辑。`BatchLessonFormView.batchStudentProgress` 由于需要混合 existing/pending tuple 排序、tie-breaker 结构不同，**本阶段不改造，留待后续评估**（Phase 4 及之后）。

### Task 3.1: StudentProgress.swift 重命名 + 抽出共享排序

**Files:**
- Rename: `TomatoSchedule/Helpers/StudentProgress.swift` → `TomatoSchedule/Helpers/StudentService.swift`

**Why:** 当前 `buildStudentIndexMap()` 在 `CalendarSyncService` 中作为 static 方法存在，但它是纯粹的学生业务逻辑（按学生分组、按时间排序、分配序号），与日历无关。应移到学生相关的模块中。同时 `studentProgress` / `computeStudentIndex` / `buildStudentIndexMap` 三处重复了同一段 `sorted { startTime → id.uuidString }` 的规则，应抽成内部 helper。

- [ ] **Step 1:** 将文件重命名为 `StudentService.swift`
- [ ] **Step 2:** 在 `StudentService.swift` 顶部新增共享排序规则：

```swift
/// Standard lesson ordering for student-scoped operations:
/// earlier startTime first, with id.uuidString as stable tie-breaker.
func lessonOrdering(_ a: Lesson, _ b: Lesson) -> Bool {
    if a.startTime != b.startTime { return a.startTime < b.startTime }
    return a.id.uuidString < b.id.uuidString
}
```

- [ ] **Step 3:** 修改 `studentProgress(for:allLessons:)` 和 `computeStudentIndex(for:existingLessons:)`，把原有的 inline `sorted { ... }` 闭包替换为 `sorted(by: lessonOrdering)`
- [ ] **Step 4:** 将 `CalendarSyncService.buildStudentIndexMap(_:)` (line 243-261) 移至 `StudentService.swift`，改为顶层函数，内部同样使用 `sorted(by: lessonOrdering)`：

```swift
/// Build a map of lesson UUID → student index (1-based) for all lessons
func buildStudentIndexMap(_ lessons: [Lesson]) -> [UUID: Int] {
    var groups: [String: [Lesson]] = [:]
    for lesson in lessons {
        let key = normalizeStudentName(lesson.studentName)
        guard !key.isEmpty else { continue }
        groups[key, default: []].append(lesson)
    }
    var result: [UUID: Int] = [:]
    for (_, group) in groups {
        for (i, lesson) in group.sorted(by: lessonOrdering).enumerated() {
            result[lesson.id] = i + 1
        }
    }
    return result
}
```

### Task 3.2: 更新所有调用方

**Files:**
- Modify: `TomatoSchedule/Services/CalendarSyncService.swift`
- Modify: `TomatoSchedule/Views/Management/StudentDetailView.swift`

**Why (review Finding 1):** `buildStudentIndexMap` 不仅在 `CalendarSyncService` 内部（line 80 / 98 / 171）调用，也被 `StudentDetailView.swift:229` 直接以 `CalendarSyncService.buildStudentIndexMap(...)` 形式外部调用。删掉 static 方法后，这里会直接编译失败。

- [ ] **Step 1:** 在 `CalendarSyncService.swift` 中删除 `buildStudentIndexMap` 方法（line 243-261）
- [ ] **Step 2:** 将 `CalendarSyncService.swift` 中所有 `Self.buildStudentIndexMap(...)` 调用（line 80 / 98 / 171）改为 `buildStudentIndexMap(...)`（调顶层函数）
- [ ] **Step 3:** 将 `StudentDetailView.swift:229` 的 `CalendarSyncService.buildStudentIndexMap(Array(allLessons))` 改为 `buildStudentIndexMap(Array(allLessons))`
- [ ] **Step 4:** 全局搜索确认无残留调用：

```bash
# 应该返回空结果
grep -rn "CalendarSyncService\.buildStudentIndexMap\|Self\.buildStudentIndexMap" TomatoSchedule/
```

- [ ] **Step 5:** 编译验证

**验证点:**
- CalendarSyncService 不再包含学生业务逻辑
- 所有学生相关函数（`normalizeStudentName` / `studentProgress` / `computeStudentIndex` / `buildStudentIndexMap` / `lessonOrdering`）统一在 `StudentService.swift` 中
- 前三个函数共用 `lessonOrdering` 排序规则，不再各自维护
- **运行时验证：** 打开 `StudentDetailView`，测试学生重命名并触发 `syncAfterRename` 路径，确认日历同步仍正常

---

## Phase 4: 拆分胖 View

> 将超过 300 行的 View 拆出子视图，提升可读性。仅做 `@ViewBuilder` / 子 View 提取，不改逻辑。

### Task 4.1: IncomeView 拆分排行榜子视图

**Files:**
- Create: `TomatoSchedule/Views/Income/IncomeRankingView.swift`
- Modify: `TomatoSchedule/Views/Income/IncomeView.swift`

- [ ] **Step 1:** 新建 `IncomeRankingView.swift`，提取 IncomeView body 中的排行榜渲染部分（line 256-331 的课程排行 + 学生排行），封装为独立子视图：

```swift
struct IncomeRankingView: View {
    let rankingMode: RankingMode
    let courseRanking: [CourseIncome]
    let studentRanking: [StudentIncome]
    let periodLabel: String
    let referenceDate: Date

    var body: some View { ... }
}
```

注意：`IncomeRankingView` 内部的"学生 → StudentIncomeDetailView"的 `NavigationLink` 需要原样保留，不要改跳转结构。

- [ ] **Step 2:** IncomeView body 中替换为 `IncomeRankingView(...)` 调用
- [ ] **Step 3:** 编译验证

**验证点:**
- **运行时验证：** 切换"按课程/按学生"排行 → 点击学生排行项 → 跳转 `StudentIncomeDetailView` 正常

### Task 4.2: BatchLessonFormView 预览区提取为独立文件

**Files:**
- Create: `TomatoSchedule/Views/Lesson/BatchLessonPreviewSection.swift`
- Modify: `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift`

**Why (review Finding 3):** 当前 `BatchLessonFormView` 中**已经**有 `private var previewSection: some View`（line 202-246），因此"提取为 `previewSection`"已是 no-op。要进一步降低 body 负担，需要把这段预览区彻底抽到独立 `struct`：

- [ ] **Step 1:** 新建 `BatchLessonPreviewSection.swift`，定义子 View：

```swift
struct BatchLessonPreviewSection: View {
    let generatedDates: [Date]
    let progressMap: [Date: Int]   // 来自 batchStudentProgress 结果
    let studentName: String
    let onExclude: (Date) -> Void
    let onInclude: (Date) -> Void

    var body: some View { /* 搬移 BatchLessonFormView.previewSection line 202-246 内容 */ }
}
```

- [ ] **Step 2:** 在 `BatchLessonFormView.swift` 中删除 `private var previewSection: some View`，body 中改为调用 `BatchLessonPreviewSection(...)` 并注入所需参数
- [ ] **Step 3:** 确认 `batchStudentProgress` 的调用点（line 208）继续在父 View 中计算后传入子 View
- [ ] **Step 4:** 编译验证

**验证点:**
- BatchLessonFormView.swift 行数明显下降（预览部分约 45 行被移出）
- UI 行为完全不变：批量排课界面、日期勾选切换、学生进度徽章、"最多显示 100 节"提示
- **运行时验证：** 测试批量排课完整流程（选课程 → 选日期范围 → 选星期 → 预览勾选 → 创建）

---

## 改动统计

| 类别 | 文件 | 操作 |
|------|------|------|
| 删除 | `ViewModels/` | 删除空目录 |
| 新建 | `Views/Components/ScrollCalendarFold.swift` | 从 ScheduleView 移出的 UIKit 代码 |
| 新建 | `Helpers/IncomeTypes.swift` | 收入共享类型 / 枚举 |
| 新建 | `Helpers/IncomeAggregator.swift` | 收入聚合纯函数 |
| 新建 | `Views/Income/IncomeRankingView.swift` | 排行榜子视图 |
| 新建 | `Views/Lesson/BatchLessonPreviewSection.swift` | 批量排课预览子视图 |
| 重命名 | `Helpers/StudentProgress.swift` → `StudentService.swift` | 归位 + 抽共享排序 |
| 修改 | `Views/Schedule/ScheduleView.swift` | 移出 ScrollOffsetObserver |
| 修改 | `Views/Income/IncomeView.swift` | 抽取聚合逻辑 + 排行榜子视图 |
| 修改 | `Services/CalendarSyncService.swift` | 移出 buildStudentIndexMap |
| 修改 | `Views/Management/StudentDetailView.swift` | 切到顶层 buildStudentIndexMap |
| 修改 | `Views/Lesson/BatchLessonFormView.swift` | 预览区抽到独立文件 |

**不改动** `project.yml`（已是整目录收录），**不手改** `TomatoSchedule.xcodeproj/project.pbxproj`（由 `xcodegen generate` 产生）。

## 整理前后对比

```
整理前:                              整理后:
TomatoSchedule/                      TomatoSchedule/
├── App/                             ├── App/
│   └── TomatoScheduleApp.swift      │   └── TomatoScheduleApp.swift
├── Models/                          ├── Models/
│   ├── Course.swift                 │   ├── Course.swift
│   └── Lesson.swift                 │   └── Lesson.swift
├── Services/                        ├── Services/
│   └── CalendarSyncService.swift    │   └── CalendarSyncService.swift (−20 行)
├── Helpers/                         ├── Helpers/
│   ├── DateHelper.swift             │   ├── DateHelper.swift
│   ├── StudentProgress.swift  ←──   │   ├── StudentService.swift  ←── 重命名+扩展
│   └── PresetColors.swift           │   ├── IncomeTypes.swift ←── 新增
│                                    │   ├── IncomeAggregator.swift ←── 新增
│                                    │   └── PresetColors.swift
├── ViewModels/ (空) ←── 删除        │
├── Views/                           ├── Views/
│   ├── Schedule/                    │   ├── Schedule/
│   │   └── ScheduleView (288行) ←── │   │   └── ScheduleView (~211行) ←── 瘦身
│   ├── Income/                      │   ├── Income/
│   │   └── IncomeView (407行) ←──   │   │   ├── IncomeView (~250行) ←── 瘦身
│   │                                │   │   ├── IncomeRankingView ←── 新增
│   │                                │   │   └── StudentIncomeDetailView
│   ├── Lesson/                      │   ├── Lesson/
│   │   └── BatchLessonForm (313行)  │   │   ├── BatchLessonForm (~270行) ←── 瘦身
│   │                                │   │   └── BatchLessonPreviewSection ←── 新增
│   ├── Components/                  │   ├── Components/
│   │   └── (4 files)                │   │   ├── ScrollCalendarFold ←── 新增
│   │                                │   │   └── (4 files)
│   └── ...                          │   └── ...
```

## 风险评估

| Phase | 风险 | 缓解措施 |
|-------|------|----------|
| Phase 1 | 极低 — 只移动代码位置 | 编译即可验证 |
| Phase 2 | 低 — 函数签名不变 | 对照原 computed property 逻辑 1:1 搬迁 |
| Phase 3 | 低 — 顶层函数签名不变 | 全局搜索确认所有调用方 |
| Phase 4 | 低 — 纯 View 拆分 | 编译验证 + 目视对比 UI |

## 不做的事

- **不引入 ViewModel 层** — 项目体量 5000 行，SwiftData `@Query` 天然弱化 ViewModel 必要性，引入会增加样板代码
- **不引入协议/依赖注入** — 当前只有 1 个 Service，过早抽象无收益
- **不修改任何功能/UI** — 纯结构调整
- **不动 Model 层** — Course / Lesson 结构合理，无需调整
- **不动 DateHelper / PresetColors** — 职责清晰，体量小
