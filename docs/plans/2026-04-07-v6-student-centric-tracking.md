# V6 学生中心课次与收入筛选 实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现以学生为中心的课次追踪（F8）和收入筛选增强（F7）：学生全局课次/小时、学生必填+规范化+建议、收入翻页+学生维度排行+学生详情页

**Architecture:** 按 spec 依赖关系分 2 个 Phase：Phase 1 (F8 学生课次) 建立基础设施，Phase 2 (F7 收入筛选) 在其上添加收入维度。无 schema 变更，新建 2 个文件，修改 8 个现有文件。

**Tech Stack:** Swift 5 / SwiftUI / SwiftData / EventKit / iOS 17+ / XcodeGen

**Spec:** `docs/specs/2026-04-06-v6-student-centric-tracking.md`

**Build verify:** `cd /Users/xujifeng/dev/TomatoSchedule && xcodegen generate && xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`

---

## Phase 1: F8 学生课次追踪

### Task 1: 创建 StudentProgress 工具

**Files:**
- Create: `TomatoSchedule/Helpers/StudentProgress.swift`

- [ ] **Step 1:** 创建文件，包含：
  - `normalizeStudentName(_:)` 全局函数（trim + 合并连续空格）
  - `StudentProgress` 结构体（`lessonIndex: Int`, `hourStart: Double`, `hourEnd: Double`）
  - `studentProgress(for:allLessons:)` 函数：按 normalizeStudentName 过滤同名学生课时，按 `(startTime, id.uuidString)` 稳定排序，计算目标课的 index 和累计小时
  - `computeStudentIndex(for:existingLessons:)` 函数：单课场景预计算 studentIndex（排除自身再加回，适配新建/编辑）

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat(F8): add StudentProgress helper with normalize + progress calculation`

### Task 2: LessonDetailCard + LessonTimeGroup 显示学生课次

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/LessonDetailCard.swift`
- Modify: `TomatoSchedule/Views/Schedule/LessonTimeGroup.swift`
- Modify: `TomatoSchedule/Views/Schedule/ScheduleView.swift`

- [ ] **Step 1:** `LessonDetailCard`：新增 `let allLessons: [Lesson]` 参数。在 body 中 location 行之前添加学生进度行：调用 `studentProgress(for:allLessons:)`，显示"第N节 · 第X-Y小时"。

- [ ] **Step 2:** `LessonTimeGroup`：新增 `let allLessons: [Lesson]` 参数。头部将 `lesson.displaySequenceText` 替换为 `studentProgress` 的 `lessonIndex`。传递 `allLessons` 给内部 `LessonDetailCard`。

- [ ] **Step 3:** `ScheduleView`：在 `lessonList` 中的 `LessonTimeGroup` 调用处传入 `allLessons: allLessons`。

- [ ] **Step 4:** Build verify
- [ ] **Step 5:** Commit: `feat(F8): display student lesson index + hours in schedule cards`

### Task 3: LessonFormView 学生必填 + 建议 + 课次预告 + 计划节次降级

**Files:**
- Modify: `TomatoSchedule/Views/Lesson/LessonFormView.swift`

- [ ] **Step 1:** 新增 `@Query private var allLessons: [Lesson]`。

- [ ] **Step 2:** 学生姓名 Section：placeholder 区分新建/编辑，保存按钮禁用条件新建时要求 `normalizeStudentName(studentName)` 非空。保存时用 `normalizeStudentName()` 规范化。

- [ ] **Step 3:** 学生名输入建议：在 TextField 下方，从 allLessons 提取 normalize 后的去重学生名，匹配输入显示最多 5 个建议按钮。

- [ ] **Step 4:** 学生课次预告：在学生 Section 下方，当 inputKey 非空时显示"该学生已有 N 节课（X小时），本节将是第 N+1 节"。

- [ ] **Step 5:** 课程计划节次降级：将课次输入框从主表单 Section("课次") 移回 DisclosureGroup 内，文案改为"计划节次"、placeholder 改为"可选"。

- [ ] **Step 6:** Build verify
- [ ] **Step 7:** Commit: `feat(F8): student name required + suggestions + progress preview + plan number demoted`

### Task 4: BatchLessonFormView 学生必填 + 学生节次预览

**Files:**
- Modify: `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift`

- [ ] **Step 1:** 学生姓名必填：placeholder 改为 `"学生姓名（必填）"`，创建按钮禁用条件增加 `normalizeStudentName(studentName).isEmpty`。保存时规范化。

- [ ] **Step 2:** 新增 `batchStudentProgress(studentName:)` 纯函数（spec 5.9 的算法）。预览行从课程维度"第N节"改为学生维度（调用 batchStudentProgress）。

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F8): batch form student required + student-centric preview numbering`

### Task 5: CalendarSyncService 双维度备注 + 调用方适配

**Files:**
- Modify: `TomatoSchedule/Services/CalendarSyncService.swift`
- Modify: `TomatoSchedule/Views/Schedule/ScheduleView.swift`
- Modify: `TomatoSchedule/Views/Lesson/LessonFormView.swift`
- Modify: `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift`
- Modify: `TomatoSchedule/Views/Course/CourseFormView.swift`

- [ ] **Step 1:** `CalendarSyncService`：`populateEvent` 新增 `studentIndex: Int?` 参数，写入"学生第N节"（主）+ "计划\(displaySequenceText)"（辅）。`syncLesson` 新增 `studentIndex` 参数。新增 `buildStudentIndexMap` 静态方法。`syncAllLessons` 内部预计算 indexMap。`syncLessonsForCourse` 新增 `allLessons` 参数。

- [ ] **Step 2:** `ScheduleView`：swipe 完成/删除时调用 `syncLesson` 传入 `computeStudentIndex`。

- [ ] **Step 3:** `LessonFormView`：新建/编辑保存后 `syncLesson` 传入 `computeStudentIndex`。

- [ ] **Step 4:** `BatchLessonFormView`：批量创建后用 `buildStudentIndexMap` 预计算再逐条传入。

- [ ] **Step 5:** `CourseFormView`：新增 `@Query private var allLessons: [Lesson]`，`syncLessonsForCourse` 调用传入 allLessons。

- [ ] **Step 6:** Build verify
- [ ] **Step 7:** Commit: `feat(F8): calendar sync with student + plan dual-dimension notes`

---

## Phase 2: F7 收入筛选增强

### Task 6: IncomeView 翻页 + 学生排行 + 图表维度

**Files:**
- Modify: `TomatoSchedule/Views/Income/IncomeView.swift`

- [ ] **Step 1:** 新增 `@State private var referenceDate: Date = .now`。`currentRange` 中 `Date.now` 替换为 `referenceDate`。

- [ ] **Step 2:** 翻页 UI：在 Period Picker 下方新增 HStack（◀ 标题 ▶ + "回到当前"按钮）。`movePeriod(_:)` 方法。`periodTitle` 和 `periodLabel` 改为动态。

- [ ] **Step 3:** 新增 `RankingMode` 枚举和 `@State rankingMode`。新增 `studentRanking` computed property（按 normalizeStudentName 聚合）。排行区域添加 Segmented Picker 切换课程/学生。

- [ ] **Step 4:** `ChartEntry` 新增 `studentKey` 字段。chartData 构建时填入 `normalizeStudentName`，学生维度过滤空姓名。图表渲染按 rankingMode 切换 foregroundStyle。

- [ ] **Step 5:** Build verify
- [ ] **Step 6:** Commit: `feat(F7): income pagination + student ranking + chart dimension toggle`

### Task 7: StudentIncomeDetailView 学生月度收入详情

**Files:**
- Create: `TomatoSchedule/Views/Income/StudentIncomeDetailView.swift`
- Modify: `TomatoSchedule/Views/Income/IncomeView.swift`

- [ ] **Step 1:** 创建 `StudentIncomeDetailView`，包含：
  - `init(studentName:initialMonth:)` 继承父页 referenceDate
  - `@Query private var allLessons: [Lesson]`
  - 月份翻页（◀ 标题 ▶ + 回到本月）
  - Summary cards：本月收入 + 已完成节数（+ 预估收入受开关控制）
  - 课时列表：该学生该月全部课时，按日期排序，标注完成状态和价格
  - 统计口径对齐 IncomeView（`isCompleted || endTime < .now`）

- [ ] **Step 2:** `IncomeView`：在学生排行中添加 `NavigationLink` → `StudentIncomeDetailView(studentName:initialMonth: referenceDate)`。

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat(F7): add StudentIncomeDetailView with month pagination`

---

## 收尾

### Task 8: 最终构建验证

- [ ] **Step 1:** 完整构建验证。
- [ ] **Step 2:** Commit: `chore: mark V6 spec as implemented`
