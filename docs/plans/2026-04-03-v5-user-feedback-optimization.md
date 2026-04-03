# V5 用户反馈优化 实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 6 项用户反馈优化：滑动切月、批量排课、时间段选择器、课次显示优化、价格冻结、预估收入

**Architecture:** 按依赖关系分 6 个 Phase 实施。Phase 1 (F5 价格冻结) 是基础设施层，Phase 2-4 (F4/F3/F1) 相互独立可并行，Phase 5 (F2 批量排课) 依赖前四项，Phase 6 (F6 预估收入) 最后实施。新增 1 个 model 字段 `isManualPrice`，2 个新建文件，修改 16 个现有文件。

**Tech Stack:** Swift 5 / SwiftUI / SwiftData / EventKit / iOS 17+ / XcodeGen

**Spec:** `docs/specs/2026-04-03-v5-user-feedback-optimization.md`

**Build verify:** `cd /Users/xujifeng/dev/TomatoSchedule && xcodegen generate && xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`

---

## Phase 1: F5 价格冻结 + 数据迁移

> 基础设施，F2/F6 依赖此项。包含 schema 变更和存量数据迁移，应最先验证。

### Task 1.1: Lesson model 新增 `isManualPrice` 字段 + 更新 `priceDisplayText`

**Files:**
- Modify: `TomatoSchedule/Models/Lesson.swift`

- [ ] **Step 1:** 在 Lesson 模型中 `// V4 收入` 区域之后新增 V5 字段：

```swift
// V5 价格语义
var isManualPrice: Bool
```

在 `init()` 中新增参数并赋值：

```swift
init(
    ...,
    location: String = ""
) {
    ...
    self.isManualPrice = false   // 新增
}
```

- [ ] **Step 2:** 更新 `priceDisplayText` computed property，区分免费/未定价：

```swift
var priceDisplayText: String? {
    let p = effectivePrice
    if isManualPrice && p == 0 { return "免费" }
    if !isManualPrice && p == 0 { return nil }
    guard p > 0 else { return nil }
    return p == p.rounded() ? "¥\(Int(p))" : String(format: "¥%.1f", p)
}
```

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F5): add isManualPrice field to Lesson model`

### Task 1.2: App 启动迁移逻辑 + scenePhase 监听

**Files:**
- Modify: `TomatoSchedule/App/TomatoScheduleApp.swift`

- [ ] **Step 1:** 新增 `migrateV5PriceFreeze()` 方法。三类旧数据分别处理：
  - 场景 A (`!isPriceOverridden`): 按升级当下费率补快照
  - 场景 B (`isPriceOverridden && !isCompleted`): 标记 `isManualPrice = true`
  - 场景 C (`isPriceOverridden && isCompleted`): 标记 `isManualPrice = false`

```swift
@MainActor
private func migrateV5PriceFreeze() {
    guard !UserDefaults.standard.bool(forKey: "v5PriceMigrationDone") else { return }
    guard let container = try? ModelContainer(for: Course.self, Lesson.self) else { return }
    let context = container.mainContext
    let descriptor = FetchDescriptor<Lesson>()
    guard let lessons = try? context.fetch(descriptor) else { return }

    var changed = false
    for lesson in lessons {
        if lesson.isPriceOverridden && !lesson.isCompleted {
            lesson.isManualPrice = true
            changed = true
        } else if lesson.isPriceOverridden && lesson.isCompleted {
            lesson.isManualPrice = false
            changed = true
        } else if !lesson.isPriceOverridden {
            lesson.priceOverride = lesson.effectivePrice
            lesson.isPriceOverridden = true
            lesson.isManualPrice = false
            changed = true
        }
    }
    if changed { try? context.save() }
    UserDefaults.standard.set(true, forKey: "v5PriceMigrationDone")
}
```

- [ ] **Step 2:** 修改 `body`：在 `.onAppear` 中先调用 `migrateV5PriceFreeze()` 再调用 `autoCompletePastLessons()`。新增 `@Environment(\.scenePhase)` 和 `.onChange` 监听回前台时自动补全：

```swift
@Environment(\.scenePhase) private var scenePhase

var body: some Scene {
    WindowGroup {
        MainTabView()
            .onAppear { migrateV5PriceFreeze(); autoCompletePastLessons() }
    }
    .modelContainer(for: [Course.self, Lesson.self])
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active {
            autoCompletePastLessons()
        }
    }
}
```

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F5): add V5 price migration + scenePhase auto-complete`

### Task 1.3: LessonFormView 价格冻结 + isManualPrice 改造

**Files:**
- Modify: `TomatoSchedule/Views/Lesson/LessonFormView.swift`

- [ ] **Step 1:** 状态变量改造：将 `@State private var isPriceOverridden` 替换为 `@State private var isManualPrice`。保留 `priceOverride`。

- [ ] **Step 2:** 添加 `freezePrice(for:)` 私有方法和 `formatPrice(_:)` 帮助函数。

- [ ] **Step 3:** 更新 `onAppear`：编辑已有课时时用 `lesson.isManualPrice` 初始化。

- [ ] **Step 4:** 更新价格 Section UI：Picker 绑定 `$isManualPrice`。三路分支：手动→输入框，编辑已有+自动→显示 `lesson.priceOverride` 快照，新建+自动→实时试算。使用 `formatPrice()` 避免小数截断。

- [ ] **Step 5:** 更新 `save()` 新建路径：`if isManualPrice` 写入手动价格，`else` 调用 `freezePrice()`。

- [ ] **Step 6:** 更新 `save()` 编辑路径：处理 `wasManual && !isManualPrice`（手动切回自动时重算快照）。

- [ ] **Step 7:** Build verify
- [ ] **Step 8:** Commit: `feat(F5): freeze price at creation + isManualPrice in LessonFormView`

### Task 1.4: CourseFormView 两阶段保存 + 费率变更确认

**Files:**
- Modify: `TomatoSchedule/Views/Course/CourseFormView.swift`

- [ ] **Step 1:** 新增状态：`@State private var showRateChangeConfirmation = false`，`@State private var pendingRate/pendingOldRate`。

- [ ] **Step 2:** 重写 `save()`：检测 `hourlyRate` 变化，有未完成课时弹确认（不立即写入模型），无争议直接保存。

- [ ] **Step 3:** 新增 `applyAllChanges(course:updateFutureLessons:)`：先缓存 `oldTotalLessons`，再赋值。`updateFutureLessons` 时只更新 `!isManualPrice` 的未来课时。`totalLessons` 变化时触发日历重同步。

- [ ] **Step 4:** 添加 `.confirmationDialog` 确认对话框（更新未来课程 / 全部不更新 / 取消）。

- [ ] **Step 5:** Build verify
- [ ] **Step 6:** Commit: `feat(F5): two-phase save + rate change confirmation in CourseFormView`

### Task 1.5: CalendarImportView 导入时冻结价格

**Files:**
- Modify: `TomatoSchedule/Views/Settings/CalendarImportView.swift`

- [ ] **Step 1:** 在 `performImport()` 中，`modelContext.insert(lesson)` 之前添加 `freezePrice(for: lesson)` 调用。添加同样的 `freezePrice` 私有方法。

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat(F5): freeze price on calendar import`

---

## Phase 2: F4 课次显示优化 + CalendarSyncService

> 独立需求 + 为 F2 的课次编号和日历同步做好基础。

### Task 2.1: Course/Lesson model 新增课次计算逻辑

**Files:**
- Modify: `TomatoSchedule/Models/Course.swift`
- Modify: `TomatoSchedule/Models/Lesson.swift`

- [ ] **Step 1:** 在 Course 中新增：

```swift
var sortedLessons: [Lesson] {
    lessons.sorted { $0.startTime < $1.startTime }
}

func autoIndex(for lesson: Lesson) -> Int? {
    guard let idx = sortedLessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }
    return idx + 1
}
```

- [ ] **Step 2:** 在 Lesson 中新增 `displaySequenceText`：

```swift
var displaySequenceText: String? {
    let number: Int
    if lessonNumber > 0 {
        number = lessonNumber
    } else if let auto = course?.autoIndex(for: self) {
        number = auto
    } else {
        return nil
    }
    if let total = course?.totalLessons, total > 0 {
        return "第\(number)/\(total)节"
    }
    return "第\(number)节"
}
```

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F4): add displaySequenceText with auto-derive fallback`

### Task 2.2: 视图层切换到 displaySequenceText

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/LessonTimeGroup.swift`
- Modify: `TomatoSchedule/Views/Schedule/LessonDetailCard.swift`

- [ ] **Step 1:** `LessonTimeGroup.swift`：将 `lesson.headerSequenceText` 替换为 `lesson.displaySequenceText`。

- [ ] **Step 2:** `LessonDetailCard.swift`：从 `progressParts` 中移除课次项（删除 `if let seq = lesson.headerSequenceText` 分支）。

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F4): switch views to displaySequenceText`

### Task 2.3: LessonFormView 课次输入框提升

**Files:**
- Modify: `TomatoSchedule/Views/Lesson/LessonFormView.swift`

- [ ] **Step 1:** 将 `lessonNumber` 输入行从 `DisclosureGroup("更多设置")` 中移出，放到主 Form 的"备注"Section 之后。

- [ ] **Step 2:** 新建时显示 placeholder 提示自动推导值（如 `"自动: 第5节"`）。编辑时显示当前值。

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F4): promote lessonNumber input to main form area`

### Task 2.4: CalendarSyncService 课次同步修复

**Files:**
- Modify: `TomatoSchedule/Services/CalendarSyncService.swift`

- [ ] **Step 1:** 在 `populateEvent(_:from:)` 中替换：

```swift
// 旧代码：
if let seq = lesson.headerSequenceText {
    noteParts.append("第\(seq)")
}

// 新代码：
if let seq = lesson.displaySequenceText {
    noteParts.append(seq)
}
```

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat(F4): fix calendar sync sequence text format`

---

## Phase 3: F3 时间段快速选择器

> 独立 UI 组件，可先开发后集成。

### Task 3.1: 创建 TimeSlotPicker 组件

**Files:**
- Create: `TomatoSchedule/Views/Components/TimeSlotPicker.swift`

- [ ] **Step 1:** 创建 `TimeSlotPicker` 组件，包含：
  - 接口：`@Binding startTime/endTime`，`date`，`slotInterval`，`dayStartHour/dayEndHour`，`forcePickerMode`
  - 双模式切换：`@State private var useGridMode: Bool`（初始化时根据 `forcePickerMode` 和 `canUseGrid` 决定）
  - 网格模式：4 列 LazyVGrid，30 分钟间隔的时间按钮（08:00-21:30）
  - 时长按钮行：1h / 1.5h / 2h / 3h / 自定义，根据起始时间动态禁用溢出选项
  - 精确模式：两个原生 `DatePicker(.hourAndMinute)`
  - `canUseGrid` 判断：使用绝对分钟值比较
  - 摘要行：`已选: 14:00 — 16:00 (2小时)`
  - 模式切换链接：底部"切换到精确输入"/"切换到快速选择"

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat(F3): create TimeSlotPicker component`

### Task 3.2: 集成 TimeSlotPicker 到 LessonFormView

**Files:**
- Modify: `TomatoSchedule/Views/Lesson/LessonFormView.swift`

- [ ] **Step 1:** 在时间 Section 中，替换两个 `DatePicker(.hourAndMinute)` 为 `TimeSlotPicker`。保留日期 DatePicker。添加 `canUseGrid` computed property。

```swift
Section("时间") {
    DatePicker("日期", selection: $date, displayedComponents: .date)
    TimeSlotPicker(
        startTime: $startTime,
        endTime: $endTime,
        date: date,
        forcePickerMode: isEditing && !canUseGrid
    )
}
```

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat(F3): integrate TimeSlotPicker into LessonFormView`

---

## Phase 4: F1 课表左右滑动切换月份

> 独立 UI 优化，无依赖。

### Task 4.1: CalendarHeaderView 添加滑动手势 + transition

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/CalendarHeaderView.swift`
- Modify: `TomatoSchedule/Views/Schedule/MonthGridView.swift`
- Modify: `TomatoSchedule/Views/Schedule/WeekStripView.swift`

- [ ] **Step 1:** 在 `CalendarHeaderView` 中新增状态：

```swift
enum SlideDirection { case backward, forward, none }
@State private var slideDirection: SlideDirection = .none
@State private var isAnimating = false
```

- [ ] **Step 2:** 在日历 body（`MonthGridView` / `WeekStripView` 外层）添加 `.gesture(DragGesture)` ：
  - 水平位移绝对值 > 50pt 且 > 垂直位移绝对值时触发
  - `isAnimating` 防抖
  - 左滑（translation.width < 0）→ 上月（`moveMonth(-1)`）
  - 右滑（translation.width > 0）→ 下月（`moveMonth(1)`）
  - 周视图时调用 `moveWeek` 而非 `moveMonth`

- [ ] **Step 3:** 新增 `moveWeek(_ offset:)` 方法，切周跨月时同步 `displayedMonth`（先缓存 oldMonth 再赋值）。

- [ ] **Step 4:** 给 `MonthGridView` 添加 `.id(displayedMonth)` + `.transition` 基于 `slideDirection`。给 `WeekStripView` 添加 `.id(DateHelper.weekRange(for: selectedDate).start)` + `.transition`。

- [ ] **Step 5:** 更新 `moveMonth` 中也设置 `slideDirection` 以便 chevron 按钮也有方向动画。

- [ ] **Step 6:** Build verify
- [ ] **Step 7:** Commit: `feat(F1): add swipe gesture for month/week navigation`

---

## Phase 5: F2 批量排课

> 依赖 F3（TimeSlotPicker）、F4（课次编号）、F5（价格冻结），最复杂的新功能。

### Task 5.1: 创建 BatchLessonFormView

**Files:**
- Create: `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift`

- [ ] **Step 1:** 创建 `BatchLessonFormView`，包含：
  - 课程选择 Picker、学生名、地点输入
  - 起止日期 DatePicker
  - 星期选择（周一-周日 toggle 按钮，支持多选）
  - `TimeSlotPicker` 时间段选择
  - 备注输入
  - 预览列表（自动生成的课时，含日期、时间、课次）
  - 预览行支持左滑删除
  - 冲突检测（橙色警告图标）
  - 上限保护（> 100 节提示）
  - 课次编号使用 `nextLessonNumber(for:)` 防撞号
  - 创建时每节课调用 `freezePrice`
  - 创建后批量日历同步

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat(F2): create BatchLessonFormView`

### Task 5.2: ScheduleView toolbar 改造

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/ScheduleView.swift`

- [ ] **Step 1:** 新增 `@State private var showingBatchLesson = false`。

- [ ] **Step 2:** 将 toolbar 的 `Button { showingAddLesson = true }` 改为 `Menu`：

```swift
ToolbarItem(placement: .primaryAction) {
    Menu {
        Button { showingAddLesson = true } label: {
            Label("添加单节课时", systemImage: "plus")
        }
        Button { showingBatchLesson = true } label: {
            Label("批量排课", systemImage: "calendar.badge.plus")
        }
    } label: {
        Image(systemName: "plus")
    }
}
```

- [ ] **Step 3:** 新增 `.sheet(isPresented: $showingBatchLesson)` 展示 `BatchLessonFormView`。

- [ ] **Step 4:** Build verify
- [ ] **Step 5:** Commit: `feat(F2): add batch scheduling entry in ScheduleView toolbar`

---

## Phase 6: F6 预估收入

> 依赖 F5（价格冻结后预估才有意义），最后的展示层增强。

### Task 6.1: StatisticsBar 新增预估收入

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/StatisticsBar.swift`
- Modify: `TomatoSchedule/Views/Schedule/ScheduleView.swift`

- [ ] **Step 1:** `StatisticsBar` 新增 `estimatedIncome: Double` 参数。更新 `displayText`：开关开启且 `estimatedIncome > income` 时追加 `（预估¥X）`。

- [ ] **Step 2:** `ScheduleView` 新增 `@AppStorage("showEstimatedIncome") private var showEstimatedIncome = true` 和 `statisticsEstimatedIncome` computed property（`lessonsInRange` 全量求和）。传入 `StatisticsBar`。

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F6): add estimated income to StatisticsBar`

### Task 6.2: IncomeView 预估收入卡片 + 图表

**Files:**
- Modify: `TomatoSchedule/Views/Income/IncomeView.swift`

- [ ] **Step 1:** 新增 `@AppStorage("showEstimatedIncome")` 和 `allLessonsInRange` / `estimatedIncome` computed properties。

- [ ] **Step 2:** 开关开启时：summary cards 从 3 卡横排改为 2x2 `LazyVGrid`，新增"预估收入"卡。开关关闭时保持 3 卡横排。

- [ ] **Step 3:** 图表中叠加未完成部分（半透明）。

- [ ] **Step 4:** Build verify
- [ ] **Step 5:** Commit: `feat(F6): add estimated income card and chart overlay in IncomeView`

### Task 6.3: SettingsView 统一已完成口径 + 预估收入显示

**Files:**
- Modify: `TomatoSchedule/Views/Settings/SettingsView.swift`

- [ ] **Step 1:** 修改 `incomeForToday/Week/Month`：过滤条件从 `$0.isCompleted` 改为 `$0.isCompleted || $0.endTime < .now`。

- [ ] **Step 2:** 新增 `estimatedForToday/Week/Month` computed properties（范围内全量求和）。

- [ ] **Step 3:** 新增 `@AppStorage("showEstimatedIncome")`。开关开启时，收入概览每行追加 `(预估 ¥X)`。

- [ ] **Step 4:** 在"显示" Section 新增 `Toggle("显示预估收入", isOn: $showEstimatedIncome)`。

- [ ] **Step 5:** Build verify
- [ ] **Step 6:** Commit: `feat(F6): unify completion check + estimated income in SettingsView`

---

## 收尾

### Task 7.1: 最终构建验证 + 提交

- [ ] **Step 1:** 运行完整构建验证：

```bash
cd /Users/xujifeng/dev/TomatoSchedule
xcodegen generate
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build
```

- [ ] **Step 2:** 更新 spec 状态为"已实施"。

- [ ] **Step 3:** Commit: `chore: mark V5 spec as implemented`
