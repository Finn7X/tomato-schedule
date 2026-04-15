# 轻量级项目整理方案 Review

## 范围

- 方案文档：`docs/plans/2026-04-08-lightweight-refactor.md`
- 对照实现：
  - `TomatoSchedule/Views/Schedule/ScheduleView.swift`
  - `TomatoSchedule/Views/Income/IncomeView.swift`
  - `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift`
  - `TomatoSchedule/Helpers/StudentProgress.swift`
  - `TomatoSchedule/Services/CalendarSyncService.swift`
  - `TomatoSchedule/Views/Management/StudentDetailView.swift`
  - `project.yml`

## 结论

方案方向是对的，整体也符合“轻量整理、不改功能”的边界。Phase 1 和 Phase 2 基本可以继续保留，Phase 3 和 Phase 4 需要先修正文案后再交给执行 agent，否则会出现步骤不完整或任务实际上已经做过的情况。

当前我确认到 4 个需要先修的点，其中前 2 个会直接影响执行时的完整性。

## Findings

### 1. [中] Phase 3 的调用方清单不完整，`buildStudentIndexMap` 并不只在 `CalendarSyncService` 内部使用

- 方案在 `docs/plans/2026-04-08-lightweight-refactor.md:176-188` 里把 Phase 3 描述成“把 `CalendarSyncService.buildStudentIndexMap` 移出去，并把所有 `Self.buildStudentIndexMap(...)` 调用改掉”。
- 但当前仓库里还有一个直接外部调用：`TomatoSchedule/Views/Management/StudentDetailView.swift:227-233`。
- 也就是说，如果执行时只按文档里列出的 service 内部调用去改，Phase 3 会留下漏改点；删掉 static 方法后，这里会直接编译失败。

建议：

- 把 `StudentDetailView.swift` 明确加入 Phase 3 的 `Files` 列表。
- Step 4 不要只搜 `CalendarSyncService.buildStudentIndexMap`，还要明确全局确认所有调用方都已切到新入口。

### 2. [中] Phase 3 目前更像“换文件名 + 挪函数”，还没有真正统一学生逻辑入口

- 方案的目标写的是“统一学生逻辑”，见 `docs/plans/2026-04-08-lightweight-refactor.md:165-190`。
- 但当前重复的排序/索引规则不只存在于 `CalendarSyncService.buildStudentIndexMap`：
  - `TomatoSchedule/Helpers/StudentProgress.swift:26-66`
  - `TomatoSchedule/Services/CalendarSyncService.swift:243-260`
  - `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift:252-282`
- 按现方案执行后，只是把 `buildStudentIndexMap` 搬到 `StudentService.swift`，其余逻辑仍是多个顶层函数和局部函数分散存在。这样“文件归位”能做到，但“统一接口”其实还没有做到。

建议：

- 二选一，先把目标写清楚：
  - 如果只想轻量收拢，就把目标改成“学生相关 helper 归位到同一模块”，不要写成“统一学生逻辑”。
  - 如果确实想统一，就补一个极小的共享内部 helper，至少把学生维度的排序/分组规则集中起来，避免 `studentProgress` / `computeStudentIndex` / `buildStudentIndexMap` 继续各自维护。
- `BatchLessonFormView.batchStudentProgress` 是否故意留在 Phase 4，也建议在文档里写明，不然目前的问题定义和实施范围是不对齐的。

### 3. [中] Phase 4.2 和当前代码现状不符，按文档执行几乎是 no-op

- 方案在 `docs/plans/2026-04-08-lightweight-refactor.md:221-229` 里要求“把 `BatchLessonFormView` 的预览区提取为 `private var previewSection: some View`”。
- 但当前代码已经是这个形态了，见 `TomatoSchedule/Views/Lesson/BatchLessonFormView.swift:202-246`。
- 当前文件总长度仍是 313 行，所以照着现文档执行不会真正减少复杂度，也达不到文档写的“拆分后每个文件不超过 300 行”。

建议：

- 直接重写 Task 4.2，不要再写成“提取为 `previewSection`”。
- 如果目标真的是把文件压到 300 行以内，应该明确为：
  - 提取 `BatchLessonPreviewSection.swift` 子视图，或
  - 至少提取 `previewRow(...)` / `PreviewListContent` 级别的子组件。
- 如果只是想降低 body 负担，那验证点也应该改成“预览区渲染逻辑继续下沉”，而不是 `<300 行` 这种当前步骤达不到的结果。

### 4. [低] Phase 2 里共享类型的落点还需要再明确一下

- 方案在 `docs/plans/2026-04-08-lightweight-refactor.md:79-128` 里把 `ChartEntry` / `CourseIncome` / `StudentIncome` / `Period` / `RankingMode` 一起塞进 `Helpers/IncomeAggregator.swift`。
- 这在实现上可行，但 `Period` 和 `RankingMode` 同时承担了 view state / UI 文案职责，而 `IncomeAggregator` 名字看起来更像纯聚合 helper。
- 后续再加 `IncomeRankingView` 后，这个文件会同时承载“共享 UI 类型 + 聚合逻辑”，命名上会有一点歧义。

建议：

- 要么把这个文件在文档里明确成“收入共享类型 + 聚合逻辑”。
- 要么拆成更清楚的边界，例如 `IncomeTypes.swift` + `IncomeAggregator.swift`。
- 这不是 blocker，但先写清楚能减少后续继续重构时的方向摇摆。

## 建议补充到修订版方案里的点

- Phase 1.1 可以明确写成“当前不需要改 `project.yml`”。因为仓库现在是 `sources: - TomatoSchedule` 的整目录收录方式，且 `project.yml` 里没有任何 `ViewModels` 引用，见 `project.yml:14-20`。
- 执行时应以 `project.yml + xcodegen generate` 为准，不建议手改 `TomatoSchedule.xcodeproj/project.pbxproj`。
- 如果保留“每个 Phase 后编译验证”，文档最好顺手补一句：Phase 3 完成后要覆盖学生详情重命名路径；Phase 4 完成后要覆盖批量排课预览区和收入页排行跳转。

## 基线核对结果

- `TomatoSchedule/ViewModels/` 当前确实是空目录。
- `ScheduleView.swift` 当前 288 行，`IncomeView.swift` 407 行，`BatchLessonFormView.swift` 313 行。
- 我在 2026-04-08 本地执行了：
  - `xcodegen generate`
  - `xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`
- 结果：`BUILD SUCCEEDED`

## 审阅结论摘要

- 可以继续推进这个轻量整理方向。
- 但在交给执行 agent 前，至少先修正 Phase 3 的调用方范围、Phase 3 的目标表述，以及 Phase 4.2 的任务定义。
- 修完这几处后，这份方案就更适合直接进入实施。
