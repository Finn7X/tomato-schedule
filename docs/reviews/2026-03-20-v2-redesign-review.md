# 番茄课表 V2 重构计划 Review

## 范围

- 参考图：`TomatoSchedule/example/7424f0f07240fd43e9c8c7a3dd272de4.JPG`、`TomatoSchedule/example/365bbb518e36d0d74df2992bff44b83c.JPG`
- 当前实现：`TomatoSchedule/Views/MainTabView.swift`、`TomatoSchedule/Views/Calendar/*.swift`、`TomatoSchedule/Views/Lesson/*.swift`、`TomatoSchedule/Models/*.swift`
- 计划文档：`docs/plans/2026-03-20-v2-redesign.md`

## 结论

这份计划的方向是对的：把当前 4 Tab 的日/周/月拆分页，收敛成一个统一课表页，整体上更接近参考应用。

但它还不能直接进入实施。当前版本已经抓住了“统一日历头部 + 下方课程列表”的主结构，但在数据建模、月历细节、统计口径和工程执行顺序上还有几个会直接影响实现正确性的缺口，建议先修订计划，再按修订版落地。

## 我对参考图的理解

- 两张图是同一个页面的两种状态，不是两个独立页面：周模式收起，月模式展开。
- 顶部青绿色区域不是普通导航栏，而是一个承载月份导航、星期头、日期选择、周月切换的复合头部。
- 月视图明确显示了相邻月份的溢出日期。`2026年01月` 图里显示了 `2025-12-29/30/31` 和 `2026-02-01`，不是留空。
- 日课程列表采用“时间轴式列表”表达：左侧时间点/竖线，头部行里除了时间，还有状态文案（如“无考勤数据”），部分项右侧还有序号。
- 同一节课里至少存在两层进度信息：列表头部右侧的总序号，以及卡片内部的阶段/课时进度。这两层不是同一个字段。

## Findings

1. **High:** 计划里的进度模型不足以表达参考图里的两层进度。
   `docs/plans/2026-03-20-v2-redesign.md:121-126`、`docs/plans/2026-03-20-v2-redesign.md:262-277` 只新增了 `Course.totalLessons` 和 `Lesson.lessonNumber` 这一套节次关系；`docs/plans/2026-03-20-v2-redesign.md:406-434` 又把它同时用于时间行右侧序号和详情卡片进度 badge。参考图里这两者不是一个概念：例如同一项同时出现 `1/48次` 和 `1/8次`，另一项则出现 `4.0/10.0h`。按当前计划落地后，数据层无法同时正确驱动这两种展示，最终只能二选一或写死文案。应先把“总课程序号”和“卡片进度”拆成两套字段，或者把卡片进度改成可配置文本模型。

2. **Medium:** 月历网格的设计和参考图不一致，计划把相邻月份日期错误地隐藏掉了。
   `docs/plans/2026-03-20-v2-redesign.md:369-371` 明确写了“上月尾部日期不显示、下月头部日期不显示”，但参考图的月模式正好相反，明确展示了相邻月份日期。这个差异会让最终页面一眼看上去就不像参考应用，也会损失月边界日期的上下文。建议改为“显示相邻月日期但降低强调度”。

3. **Medium:** 计划没有真正覆盖“周/月/日课程统计”这个补充需求，只实现了月统计。
   `docs/plans/2026-03-20-v2-redesign.md:95-99` 把“显示周月日课程统计”映射成了单一 `StatisticsBar`；`docs/plans/2026-03-20-v2-redesign.md:375-385` 和 `docs/plans/2026-03-20-v2-redesign.md:629-630` 也只有 `X月总排课N次，已上M次`。如果需求方的补充要求成立，这里至少要定义清楚三种口径怎么切换，或者明确本次 V2 只做月统计。另一个结构性问题是 `CalendarHeaderView` 把 `isExpanded` 放在内部状态里（`docs/plans/2026-03-20-v2-redesign.md:319-323`），父视图拿不到当前日历模式，后续想让统计栏随模式变化会很别扭。

4. **Medium:** 任务里的“每步 build 验证”在当前工程结构下并不可靠，因为新文件在 Task 10 之前不会进入编译源列表。
   计划把 `xcodegen generate` 放在 `docs/plans/2026-03-20-v2-redesign.md:707`，但前面 Task 2 到 Task 8 都要求“创建新文件后 build 验证”（如 `docs/plans/2026-03-20-v2-redesign.md:588`、`docs/plans/2026-03-20-v2-redesign.md:603`、`docs/plans/2026-03-20-v2-redesign.md:617`、`docs/plans/2026-03-20-v2-redesign.md:644`、`docs/plans/2026-03-20-v2-redesign.md:656`、`docs/plans/2026-03-20-v2-redesign.md:674`）。但当前 `TomatoSchedule.xcodeproj/project.pbxproj` 的 `PBXSourcesBuildPhase` 仍是显式文件列表，见 `TomatoSchedule.xcodeproj/project.pbxproj:231-245`。这意味着这些前置 build 可能根本没有编译到新建文件，验证会失真。应把 `xcodegen generate` 提前到第一次新增源码文件之后，或者每个阶段同步维护项目文件。

## 建议在修订版计划里补充的两点

- 明确 `无考勤数据` 是否属于 V2 范围。参考图里这是时间行的一部分，但当前计划的 `LessonTimeGroup` 规格（`docs/plans/2026-03-20-v2-redesign.md:389-412`）没有任何对应的数据字段或 UI 占位。
- 明确“时间分组”到底是单个 `Lesson` 还是同一时间段的一组 `Lesson`。现在 `LessonTimeGroup` 名字叫分组，但签名仍是单个 `lesson`，`ScheduleView` 也按 `ForEach(lessonsForSelectedDate)` 直接渲染（`docs/plans/2026-03-20-v2-redesign.md:462-475`、`docs/plans/2026-03-20-v2-redesign.md:655`、`docs/plans/2026-03-20-v2-redesign.md:668-673`）。如果未来同一时间段可能挂多条课，这个设计会立刻失真。

## 建议的修订方向

- 把“课程总体进度”和“卡片内部展示进度”拆模，不要复用同一套 `lessonNumber/totalLessons`。
- 月历改成显示前后月份溢出日期，使用弱化样式而不是留空。
- 先决定统计需求是“仅月统计”还是“周/月/日联动统计”，再决定状态归属。
- 调整任务顺序：第一次新增源码文件后就执行 `xcodegen generate`，保证后续 build 真正覆盖新增代码。
- 如果本轮不做考勤，也应在计划里明确写“保留状态文案占位，不做考勤功能”。

## 当前仓库核对结果

- 现有 V1 架构确实是 4 Tab：`日 / 周 / 月 / 课程`。
- 当前仓库在本地可正常构建：我于 2026-03-20 执行了  
  `xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`  
  结果为 `BUILD SUCCEEDED`。
