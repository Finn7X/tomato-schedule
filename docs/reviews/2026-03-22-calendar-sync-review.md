# 番茄课表 系统日历同步方案 Review

## 范围

- 方案文档：`docs/plans/2026-03-22-calendar-sync.md`
- 当前实现：`TomatoSchedule/Models/Lesson.swift`、`TomatoSchedule/Views/Lesson/LessonFormView.swift`、`TomatoSchedule/Views/Schedule/ScheduleView.swift`、`TomatoSchedule/Views/Course/CourseFormView.swift`、`TomatoSchedule/Views/Course/CourseListView.swift`
- 官方依据：
  - Apple WWDC23《Discover Calendar and EventKit》
  - Xcode 26.2 SDK 中的 `EventKit.framework` / `EventKitUI.framework` 头文件

## 结论

这份方案的大方向是成立的。`EventKit + 专属日历 + 导入/导出分流` 是可行路线，也符合这个 App 的产品定位。

但方案还不能直接进入实现。当前版本已经把主要能力点列出来了，不过在“标识稳定性、权限申请时机、同步触发覆盖面、导入后的数据质量”四个地方还存在明显缺口。它们不是边角优化，而是会直接影响功能是否稳定、是否符合 iOS 常见交互预期的关键问题。

## Findings

1. **High:** 方案把 `eventIdentifier` 当作唯一映射键，可靠性不够，后续很容易出现重复事件或错绑事件。
   方案在 `docs/plans/2026-03-22-calendar-sync.md:71-76`、`docs/plans/2026-03-22-calendar-sync.md:145-152`、`docs/plans/2026-03-22-calendar-sync.md:218-235` 中都以 `Lesson.calendarEventId = EKEvent.eventIdentifier` 作为主映射关系。问题是 Apple 官方头文件已经明确写了：`eventIdentifier` 在事件换日历时“很可能变化”，同步操作后“也可能变化”；`calendarItemIdentifier` 也不是 sync-proof。当前风险表虽然在 `docs/plans/2026-03-22-calendar-sync.md:303-304` 提到了这一点，但给出的 `title + startDate` fallback 仍然过弱，无法区分同名同时间的课时。更稳的方案应该是：
   - 本地仍可缓存 `eventIdentifier` 作为快速索引；
   - 但导出到系统日历时，要把 app 自己的稳定 ID 一并写入事件，例如把 `lesson.id` 放进 `EKEvent.url` 或结构化 notes 标记；
   - 恢复映射时优先按 app 自己的稳定 ID 查，而不是只靠标题和时间。

2. **Medium:** 权限流设计过于“一刀切”，和 Apple 对 EventKit 的最小权限建议不完全一致。
   方案在 `docs/plans/2026-03-22-calendar-sync.md:20-24` 和 `docs/plans/2026-03-22-calendar-sync.md:64-69` 里，把首次开启同步直接绑定到 `requestFullAccessToEvents()`。但 Apple 在 WWDC23 里明确建议：添加事件优先考虑 `EventKitUI` 或 write-only access，只有在“确实需要读取、更新、删除现有事件”时才申请 full access，而且要在用户真正触发该能力时再申请。对这个 App 来说，“导出到系统日历”和“从系统日历导入”并不是同一种权限强度。当前方案会让只想导出的用户也被迫接受完整读取权限，既增加拒绝率，也不算通用 iOS 的最佳体验。建议把权限拆成两层：
   - 导出功能优先使用 write-only 或最小化的添加事件流；
   - 只有用户进入“导入系统日历”或“管理专属日历”时，再解释并申请 full access。

3. **Medium:** 自动同步的触发点设计得太靠 View 层，而且覆盖不完整，当前代码里至少有两类变更会漏同步。
   方案 Task 5 只计划在 `LessonFormView` 保存后、`ScheduleView` 删除/完成时触发同步，见 `docs/plans/2026-03-22-calendar-sync.md:283-288`。但当前实现中，导出的事件内容依赖课程字段，见 `docs/plans/2026-03-22-calendar-sync.md:80-88`；而课程名称、备注、总节数等都可以在 [CourseFormView.swift](/Users/xujifeng/dev/TomatoSchedule/TomatoSchedule/Views/Course/CourseFormView.swift#L87) 里修改，课程删除也会在 [CourseListView.swift](/Users/xujifeng/dev/TomatoSchedule/TomatoSchedule/Views/Course/CourseListView.swift#L27) 触发级联删除。当前计划没有覆盖这些路径，结果会是：
   - 改课程名后，系统日历里的事件标题不更新；
   - 删课程后，系统日历里旧事件可能残留到下次全量同步才清掉。
   这说明同步逻辑不应该只挂在两个具体 View 上，而应该提升到统一的数据变更协调层，至少要覆盖 lesson CRUD、course rename、course delete/cascade delete、手动全量同步四类入口。

4. **Medium:** 导入映射里的“按 title 查找或新建 Course”过于粗糙，会直接污染现有课程数据。
   方案在 `docs/plans/2026-03-22-calendar-sync.md:107-118` 里规定：导入事件时按 `title` 匹配 `Course`，匹配不到就自动新建。对当前产品来说，这个默认太冒进了。因为 `Lesson` 目前创建时需要一个 `Course`，见 [Lesson.swift](/Users/xujifeng/dev/TomatoSchedule/TomatoSchedule/Models/Lesson.swift#L20)，而系统日历里的标题很可能是“家长沟通”“请假”“试听”“医院”等一次性事务。按当前方案导一次就可能生成一批一次性 Course，把“课程”列表变脏。更稳妥的交互应该是：
   - 导入前给用户选择“映射到现有课程 / 创建新课程 / 导入到统一的‘外部日程’课程”；
   - 或至少把“自动新建课程”改成显式确认，而不是默认行为。

## 建议补充到修订版方案里的点

- 明确“关闭同步开关”时的语义：是仅停止后续同步，还是同时询问是否删除已导出的系统日历事件。当前 `docs/plans/2026-03-22-calendar-sync.md:44-59` 只定义了打开后的设置页，没有定义关闭后的行为。
- 如果目标是更接近 iOS 通用交互，日历选择环节可以优先评估 `EKCalendarChooser`，而不是完全自定义列表。SDK 里已有系统 chooser，可减少一段自建选择 UI。
- `startObservingChanges()` / `stopObservingChanges()` 当前写进了服务接口（`docs/plans/2026-03-22-calendar-sync.md:205-207`），但 `V1` 范围又明确说“实时双向同步延后”（`docs/plans/2026-03-22-calendar-sync.md:321-323`）。这里建议二选一：要么本轮不实现监听，要么把监听限定为“检测专属日历被删并提示重建”，不要半做。

## 推荐的修订方向

- 把“系统事件映射”从单一 `eventIdentifier` 升级为“双层标识”：本地缓存 ID + app 自己的稳定外部 ID。
- 权限拆分为“导出最小权限”和“导入/管理时 full access”的按需申请。
- 不要把自动同步只挂在某两个 View 上，应该按数据变更类型统一收口。
- 导入时增加课程映射步骤，避免自动创建大量脏 Course。

## 官方参考

- Apple WWDC23《Discover Calendar and EventKit》：<https://developer.apple.com/videos/play/wwdc2023/10052/>
- 本地 SDK 头文件：
  - `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk/System/Library/Frameworks/EventKit.framework/Headers/EKEvent.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk/System/Library/Frameworks/EventKit.framework/Headers/EKCalendarItem.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk/System/Library/Frameworks/EventKit.framework/Headers/EKEventStore.h`
  - `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk/System/Library/Frameworks/EventKitUI.framework/Headers/EKCalendarChooser.h`

## 当前仓库核对结果

- 当前主结构是 `课表 | 课程` 两个 Tab；方案中的第三个 `设置` Tab 会直接改主导航。
- 当前仓库在本地可正常构建：我于 2026-03-22 执行了  
  `xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`  
  结果为 `BUILD SUCCEEDED`。
