# 收入系统方案 Review

## 结论

当前方案方向基本对，但还不能直接进入开发。对照现有实现后，至少有 6 个需要先补齐的设计问题，其中前 2 个会直接影响收入数据正确性。

## Findings

### 1. [高] 课程单价变更会改写历史收入，方案没有真正定义“同步策略”

- 方案把 `Lesson.effectivePrice` 定义为纯计算属性：`priceOverride > 0 ? priceOverride : course.hourlyRate × 时长`，并明确“不需要额外存储或同步”。见 `docs/plans/2026-03-22-income-system.md:24-28`、`docs/plans/2026-03-22-income-system.md:69-74`、`docs/plans/2026-03-22-income-system.md:255-275`。
- 现有模型里 `Lesson` 没有任何价格快照字段，只有课程关系、时长、完成状态等字段。见 `TomatoSchedule/Models/Lesson.swift:5-66`。
- 这意味着一旦老师后续修改 `Course.hourlyRate`，所有没有 `priceOverride` 的历史课时收入都会被整体重算，历史月报、周报、课程排行会一起漂移。
- 方案第 5.3 节把“同步”解释成系统日历同步，但用户真正关心的是“课程默认价改了以后，已有课时如何联动”。这部分目前是空白，不是已解决。

建议：

- 至少给 `Lesson` 增加价格来源/快照策略，例如 `pricingMode + rateSnapshot`，或者直接持久化 `finalPrice`。
- 明确课程单价修改时的批量更新策略，例如“仅更新未来未完成课时 / 更新所有未覆盖课时 / 完全不追溯历史”。
- 已完成课时最好默认冻结价格，否则收入统计不可审计。

### 2. [高] 金额精度方案不可接受，`Double + Int(price)` 会导致显示和汇总不一致

- 当前 app 允许老师按分钟编辑开始/结束时间，不是固定 30/60 分钟模板。见 `TomatoSchedule/Views/Lesson/LessonFormView.swift:65-68`。
- 当前时长计算也是分钟级。见 `TomatoSchedule/Models/Lesson.swift:48-54`。
- 方案使用 `Double` 计算价格，并在展示层使用 `Int(price)` 或 `String(format: "%.0f")` 取整。见 `docs/plans/2026-03-22-income-system.md:69-81`、`docs/plans/2026-03-22-income-system.md:334-337`。
- 例如 50 分钟、¥200/h 的课，结果是 166.666...。如果列表显示 166 或 167，但汇总仍按未统一舍入的 `Double` 累加，月收入、排行、卡片展示就会对不上。

建议：

- 不要把金额规则留给 UI 层“显示时取整”。
- 用 `Decimal` 或最小货币单位整数（分）建模，并在模型层统一舍入规则。
- 明确币种精度要求：按元取整、保留 1 位小数，还是保留到分。

### 3. [中] “价格修改不触发日历同步”与现有保存路径矛盾

- 方案写的是“价格变更不触发日历同步”。见 `docs/plans/2026-03-22-income-system.md:273-276`。
- 但当前 `CourseFormView.save()` 在编辑课程时会无条件调用 `syncLessonsForCourse(course)`。见 `TomatoSchedule/Views/Course/CourseFormView.swift:87-97`。
- `syncLessonsForCourse` 会逐条同步该课程下的所有课时事件。见 `TomatoSchedule/Services/CalendarSyncService.swift:167-171`。
- 也就是说，如果直接按现有代码结构加 `hourlyRate`，老师每次改价格都会触发一次整门课程的事件重写，和方案描述相反。

建议：

- 方案里明确写出“哪些字段变化需要同步日历，哪些不需要”。
- 实现上至少要在 `CourseFormView` 里做变更对比，避免价格字段触发 `syncLessonsForCourse`。

### 4. [中] 设置页“查看详细收入统计”缺少可落地的跳转设计

- 方案要求在设置页顶部加“查看详细收入统计 →”，跳转到收入 Tab。见 `docs/plans/2026-03-22-income-system.md:155-168`。
- 但当前 `MainTabView` 只是一个无 `selection` 绑定的 `TabView`。见 `TomatoSchedule/Views/MainTabView.swift:3-20`。
- 当前 `SettingsView` 也没有任何共享的 tab 状态或导航入口。见 `TomatoSchedule/Views/Settings/SettingsView.swift:17-107`。
- 这不是实现细节小问题，而是当前架构里根本没有“从子页切换 tab”的通道。

建议：

- 在方案里补充 tab 选中态设计，例如 `@State selectedTab` + `Tab(value:)`，再把切换能力传给 `SettingsView`。
- 如果不想引入共享 tab 状态，就不要在设置页承诺“跳转收入 Tab”这个交互。

### 5. [中] 删除课程会连同收入历史一起删掉，方案没有给财务数据留存策略

- 当前 `Course` 对 `Lesson` 使用的是 `.cascade` 删除规则。见 `TomatoSchedule/Models/Course.swift:12-18`。
- 当前课程列表里的删除操作也会直接删课程。见 `TomatoSchedule/Views/Course/CourseListView.swift:22-33`。
- 在没有收入模块时，这只是普通排课数据删除；收入系统成为核心模块后，这会直接抹掉历史已完成课时和全部收入记录。
- 方案全文没有提删除策略、归档策略，也没有提“有收入记录时二次确认/禁止删除”。

建议：

- 至少补一个产品决策：课程是“归档”还是“硬删除”。
- 如果仍保留硬删除，应该在有已完成课时/收入时给出更强确认文案，不适合沿用现在的轻量删除交互。

### 6. [中] 用 `0` 作为覆盖价哨兵值，无法表达“这节课免费”

- 方案定义 `priceOverride == 0` 表示使用自动计算，并且表单交互里写了“清空或输入 0 → 恢复自动计算”。见 `docs/plans/2026-03-22-income-system.md:61-80`、`docs/plans/2026-03-22-income-system.md:137-140`。
- 这会让“免费试听课 / 补课免单 / 人情课 0 元”无法被建模；只要课程默认单价大于 0，输入 0 永远会被解释成“继续走自动价”。
- 对独立老师场景，这不是边角情况。

建议：

- 把覆盖价改成可空值，或者单独加一个 `pricingMode`/`isPriceOverridden`。
- `0` 应该是合法价格，不应该被拿来兼任“恢复自动”的控制语义。

## 需要补充到方案里的决策

- 历史课时价格是否冻结：至少要区分“已完成课时”和“未来/未完成课时”。
- 金额精度与舍入规则：按元、角、分中的哪一级统计和展示。
- 删除/归档策略：收入数据是否允许被普通删除操作抹掉。
- 收入页指标定义：文档前文写了“已完成 vs 预计收入”，但 V1 又明确排除了它；摘要卡片也同时出现了“同比”和“与上月同期对比”，口径需要统一。见 `docs/plans/2026-03-22-income-system.md:5-8`、`docs/plans/2026-03-22-income-system.md:183-186`、`docs/plans/2026-03-22-income-system.md:343-358`。

## 审阅范围

- 已审阅方案文档：`docs/plans/2026-03-22-income-system.md`
- 已对照当前实现：`Course` / `Lesson` 模型、`CourseFormView`、`LessonFormView`、`LessonDetailCard`、`MainTabView`、`SettingsView`、`CalendarSyncService`、`CourseListView`
- 本次只输出 review 文档，未做代码实现
