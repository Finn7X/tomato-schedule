# 番茄课表 — 系统日历同步 设计方案

> 修订版 — 根据 code review 反馈修订了：事件标识策略、权限分级申请、同步触发覆盖面、导入课程映射。

## 1. 功能概述

为番茄课表添加与 iOS 系统日历的同步能力：
- **导出**：将 app 内的课时（Lesson）同步到系统日历，在 Apple Calendar、锁屏日程、Siri 中可见
- **导入**：从系统日历读取日程事件，转换为 app 内的课时
- 通过一个专属 "番茄课表" 日历隔离 app 数据，不污染用户个人日历

---

## 2. 技术选型

### 2.1 框架：EventKit

iOS 原生日历框架，直接读写系统日历数据库。与 Apple Calendar、iCloud 日历、第三方 CalDAV 日历共享同一数据源。

### 2.2 权限模型（iOS 17+ 分级）

遵循 Apple WWDC23 最小权限建议：**按功能分级申请，在用户触发对应操作时才请求。**

| 权限级别 | 能力 | 本项目何时申请 |
|---------|------|-------------|
| 仅写入（`requestWriteOnlyAccessToEvents`） | 写入事件到默认日历，不可读取、不可创建日历 | **快速导出**（一次性添加事件到默认日历） |
| **完全访问（`requestFullAccessToEvents`）** | 读写全部事件、创建/管理日历 | **托管同步**（启用同步开关时）和 **导入**（从日历导入时） |

**权限申请时机——绝不提前：**
- 用户首次点击 "快速导出" → 申请 write-only
- 用户首次开启 "同步到系统日历" 开关 → 弹出说明 Dialog → 确认后申请 full access
- 用户首次点击 "从系统日历导入" → 若无 full access 则申请

### 2.3 Info.plist 配置

```
NSCalendarsFullAccessUsageDescription = "番茄课表需要访问您的日历，以便将课程安排同步到系统日历，并从日历导入日程。"
NSCalendarsWriteOnlyAccessUsageDescription = "番茄课表需要添加日程到您的日历，以便在系统日历中查看课程安排。"
```

---

## 3. 事件标识与映射策略

> **核心问题：** `EKEvent.eventIdentifier` 在事件换日历或 iCloud 重新同步后可能变化（Apple 官方头文件明确标注），不可作为唯一长期映射键。

### 3.1 双层标识方案

**原则：** 以 app 自身的稳定 ID（`Lesson.id: UUID`）为主，`eventIdentifier` 为辅。

| 层级 | 存储位置 | 内容 | 作用 |
|------|---------|------|------|
| **主标识** | `EKEvent.url` | `tomatoschedule://lesson/{lesson.id}` | App 的稳定标识，嵌入到系统事件中，不受 EventKit 同步影响 |
| **快速索引** | `Lesson.calendarEventId` | `EKEvent.eventIdentifier` 的缓存 | 快速查找，避免全量扫描；失效时回退到主标识 |

### 3.2 映射查找流程

```
查找 Lesson 对应的 EKEvent:
  1. 快速路径：lesson.calendarEventId 非空
     → store.event(withIdentifier: id)
     → 若找到且 event.url 匹配 lesson.id → 命中 ✅
     → 若找到但 url 不匹配 → 标识错绑，丢弃，走慢速路径
     → 若未找到（已删除或 ID 失效）→ 走慢速路径
  2. 慢速路径：扫描专属日历中所有事件
     → 查找 event.url == "tomatoschedule://lesson/{lesson.id}"
     → 若找到 → 命中 ✅，更新 lesson.calendarEventId 缓存
     → 若未找到 → 该 Lesson 尚未同步，需新建
```

### 3.3 EKEvent 字段映射

| Lesson 字段 | EKEvent 字段 | 格式 |
|------------|-------------|------|
| `course.name` + `studentName` | `title` | `"雅思阅读"` 或 `"雅思阅读 · 陈牧崧"` |
| `startTime` | `startDate` | 直接映射 |
| `endTime` | `endDate` | 直接映射 |
| `location` | `location` | 直接映射 |
| `notes` + 进度信息 | `notes` | `"第7/48次\n备注内容"` |
| `lesson.id` (UUID) | `url` | `URL(string: "tomatoschedule://lesson/{uuid}")` — **主标识** |
| — | `calendar` | 专属 "番茄课表" 日历 |

---

## 4. 用户交互设计

### 4.1 入口：新增 "设置" Tab

当前 Tab 结构为 `课表 | 课程`，新增第三个 Tab：

```
[课表]    [课程]    [设置]
```

### 4.2 设置页

```
┌─────────────────────────────────────────────┐
│  日历同步                                    │
├─────────────────────────────────────────────┤
│  同步到系统日历          [开关]               │  ← 启用后：full access + 专属日历 + 自动同步
│  ↳ 使用专属"番茄课表"日历管理              │  ← 灰色说明
│                                             │
│  [立即同步]                                  │  ← 手动全量同步（同步开关开启时可用）
│  上次同步: 2026-03-22 14:30                  │
├─────────────────────────────────────────────┤
│  快速导出                                    │
├─────────────────────────────────────────────┤
│  [导出全部课时到默认日历]                     │  ← 仅需 write-only 权限，一次性操作
├─────────────────────────────────────────────┤
│  从系统日历导入                               │
├─────────────────────────────────────────────┤
│  [选择日历并导入]                             │  ← 需要 full access
└─────────────────────────────────────────────┘
```

### 4.3 导出分两级

**快速导出（低门槛，write-only）：**
- 用户点击 "导出全部课时到默认日历"
- 仅需 write-only 权限（系统弹窗更温和，通过率高）
- 事件添加到系统默认日历，不创建专属日历
- 一次性操作，不追踪、不更新、不删除
- 适合只想在系统日历看一下课程安排的轻度用户

**托管同步（完整能力，full access）：**
- 用户开启 "同步到系统日历" 开关
- 弹出说明 Dialog："需要完整日历访问权限以创建专属日历并管理同步。" → 确认后申请
- 创建专属 "番茄课表" 日历
- 自动同步：Lesson/Course 的增删改均自动同步到日历
- 手动全量同步：点击 "立即同步"
- 双层标识追踪，支持更新和删除

### 4.4 关闭同步开关时的行为

弹出确认：

```
┌─────────────────────────────────────────────┐
│  关闭日历同步                                │
│                                             │
│  是否同时删除系统日历中的已同步事件？           │
│                                             │
│  [保留事件]    [删除事件]    [取消]            │
└─────────────────────────────────────────────┘
```

- "保留事件"：关闭自动同步，保留系统日历中的事件和专属日历
- "删除事件"：关闭自动同步，删除专属日历（含所有事件），清除所有 `calendarEventId`
- "取消"：不关闭开关

### 4.5 导入流程（系统日历 → App）

**交互流程：**
1. 用户点击 "选择日历并导入" → 检查/申请 full access
2. 使用系统 `EKCalendarChooser`（UIKit 封装）展示日历列表，排除 "番茄课表"
3. 选择后显示时间范围选择器（默认：未来 30 天）
4. 展示事件列表，按 title 分组，每组可勾选
5. **课程映射步骤**（关键——防止污染课程数据）：

```
┌─────────────────────────────────────────────┐
│  课程映射                                    │
├─────────────────────────────────────────────┤
│  "雅思阅读" (5 个事件)                       │
│  → 映射到: [▼ 雅思阅读 (已有)]               │  ← 自动匹配到同名已有课程
│                                             │
│  "家长沟通" (2 个事件)                       │
│  → 映射到: [▼ 请选择课程...]                 │  ← 无匹配，需用户手动选择
│    选项: 雅思阅读 / 雅思口语 / ... /          │
│          ✚ 新建课程 / ⊘ 跳过不导入            │  ← 明确的选项
│                                             │
│  "请假" (1 个事件)                           │
│  → 映射到: [⊘ 跳过不导入]                    │  ← 默认跳过非课程事件
└─────────────────────────────────────────────┘
```

**映射规则：**
- 事件 title 精确匹配已有 Course.name → 自动映射，用户可修改
- 事件 title 无匹配 → 默认 "请选择课程..."，用户选择：映射到已有课程 / 新建 / 跳过
- **绝不自动创建 Course**，所有新建都需用户确认
- 用户可一键 "全部跳过未映射项"

6. 确认导入 → 创建 Lesson
7. Toast 提示 "已导入 N 个日程"

**去重：** 同一天 + 同一开始时间 + 映射到同一课程 → 标记 "已存在"，默认不勾选

### 4.6 权限被拒绝的处理

根据当前操作所需的权限级别给出对应提示：

```
┌─────────────────────────────────────────────┐
│  ⚠️ 需要日历访问权限                         │
│                                             │
│  {具体操作说明}                               │
│  请在系统设置中开启日历权限。                   │
│                                             │
│           [前往设置]                          │
└─────────────────────────────────────────────┘
```

### 4.7 专属日历被用户删除的处理

- 下次同步时：`eventStore.calendar(withIdentifier:)` 返回 nil
- 自动重建日历，清除所有 `calendarEventId`，执行全量重新同步
- 提示用户 "日历已重建并完成同步"

---

## 5. 数据模型变更

### 5.1 Lesson 新增字段

```swift
var calendarEventId: String    // EKEvent.eventIdentifier 的本地缓存，空字符串表示未同步
```

默认值 `""`，SwiftData 自动 lightweight migration。

> 注意：`calendarEventId` 仅作快速索引，主标识是 `lesson.id`（UUID），通过 `EKEvent.url` 嵌入到系统事件中。

### 5.2 新增 UserDefaults 存储

| Key | 类型 | 用途 |
|-----|------|------|
| `calendarSyncEnabled` | `Bool` | 托管同步开关状态 |
| `appCalendarIdentifier` | `String?` | 专属日历的 `calendarIdentifier` |
| `lastSyncDate` | `Date?` | 上次同步时间 |

---

## 6. 架构设计

### 6.1 新增文件

```
TomatoSchedule/
├── Services/
│   └── CalendarSyncService.swift     ← EventKit 操作封装
├── Views/
│   ├── MainTabView.swift             ← 修改：增加设置 Tab
│   └── Settings/
│       ├── SettingsView.swift        ← 设置页主视图
│       └── CalendarImportView.swift  ← 日历导入（EKCalendarChooser + 事件列表 + 课程映射）
```

### 6.2 CalendarSyncService 职责

```swift
@MainActor
final class CalendarSyncService: ObservableObject {
    private let store = EKEventStore()
    @Published var syncEnabled: Bool
    @Published var lastSyncDate: Date?

    // ── 权限（分级申请）──
    func requestWriteOnlyAccess() async -> Bool
    func requestFullAccess() async -> Bool
    var currentAuthStatus: EKAuthorizationStatus

    // ── 专属日历管理（需 full access）──
    func getOrCreateAppCalendar() throws -> EKCalendar
    func deleteAppCalendar() throws

    // ── 快速导出（write-only 即可）──
    func quickExportAll(_ lessons: [Lesson]) throws -> Int

    // ── 托管同步（需 full access + 专属日历）──
    func syncAllLessons(_ lessons: [Lesson]) throws -> Int
    func syncLesson(_ lesson: Lesson) throws
    func removeSyncedEvent(for lesson: Lesson) throws
    func syncLessonsForCourse(_ course: Course) throws   // 课程改名时
    func removeEventsForLessons(_ lessons: [Lesson]) throws  // 课程删除前

    // ── 导入（需 full access）──
    func fetchCalendars() -> [EKCalendar]
    func fetchEvents(from calendars: [EKCalendar], start: Date, end: Date) -> [EKEvent]

    // ── 内部：双层标识查找 ──
    private func findEvent(for lesson: Lesson, in calendar: EKCalendar) -> EKEvent?
    private func buildEventURL(for lesson: Lesson) -> URL
    private func extractLessonId(from event: EKEvent) -> UUID?
}
```

**设计原则：**
- `@MainActor` 隔离：EventKit 不是 Sendable，统一在主线程操作
- 单例 `EKEventStore`：创建一次，整个 app 生命周期复用
- 批量提交：导出时使用 `commit: false` + 最后 `commit()`

### 6.3 同步流程（托管模式）

```
syncAllLessons(lessons):
    1. calendar = getOrCreateAppCalendar()
    2. 获取日历中已有的全部 EKEvent
    3. 构建 urlIndex: [UUID: EKEvent]（按 event.url 中的 lesson.id 索引）
    4. matchedEventIds = Set<String>()
    5. for lesson in lessons:
         event = urlIndex[lesson.id] ?? findEvent(for: lesson, in: calendar)
         if event 存在:
             更新 event 的 title/start/end/location/notes
             lesson.calendarEventId = event.eventIdentifier  // 刷新缓存
             matchedEventIds.insert(event.eventIdentifier)
         else:
             创建新 EKEvent，设置 url = buildEventURL(for: lesson)
             lesson.calendarEventId = event.eventIdentifier
             matchedEventIds.insert(event.eventIdentifier)
    6. for event in 日历中所有事件:
         if event.eventIdentifier 不在 matchedEventIds 中:
             删除该 event（app 中已删除的课时在系统日历的残留）
    7. store.commit()
    8. 更新 lastSyncDate
```

### 6.4 自动同步触发点（完整覆盖）

> **原则：** 同步逻辑通过 CalendarSyncService 统一收口，不散落在各个 View 中。各 View 调用 Service 方法，Service 内部判断 `syncEnabled` 后决定是否执行。

| 变更类型 | 触发位置 | Service 方法 | 说明 |
|---------|---------|-------------|------|
| 新建 Lesson | `LessonFormView.save()` | `syncLesson(_:)` | 创建对应 EKEvent |
| 编辑 Lesson | `LessonFormView.save()` | `syncLesson(_:)` | 更新对应 EKEvent |
| 删除 Lesson | `ScheduleView` swipe delete | `removeSyncedEvent(for:)` | 删除对应 EKEvent |
| 标记完成 | `ScheduleView` swipe complete | `syncLesson(_:)` | 更新 notes |
| **编辑 Course** | `CourseFormView.save()` | `syncLessonsForCourse(_:)` | **批量更新该课程所有 Lesson 的 title** |
| **删除 Course** | `CourseListView` swipe delete | `removeEventsForLessons(_:)` | **在级联删除前，移除所有关联 EKEvent** |

> V1 方案只覆盖了前 4 项，遗漏了后 2 项。课程改名后系统日历标题不更新、课程删除后事件残留，都是已修复的问题。

---

## 7. 实现任务分解

### Task 1: 数据模型 + Info.plist

**Files:**
- Modify: `Models/Lesson.swift` — 增加 `calendarEventId: String`
- Modify: `Info.plist` — 增加 `NSCalendarsFullAccessUsageDescription` 和 `NSCalendarsWriteOnlyAccessUsageDescription`

### Task 2: CalendarSyncService

**Files:**
- Create: `Services/CalendarSyncService.swift`

实现：
- 权限分级申请（write-only / full access）
- 专属日历创建/获取/删除
- 双层标识：`EKEvent.url` 嵌入 `lesson.id`，`calendarEventId` 缓存 `eventIdentifier`
- 双层查找：快速路径（`eventIdentifier`）+ 慢速路径（`url` 扫描）
- 全量同步、单条同步、批量删除
- 快速导出（write-only，不追踪）

### Task 3: SettingsView（设置页）

**Files:**
- Create: `Views/Settings/SettingsView.swift`
- Modify: `Views/MainTabView.swift` — 增加第三个 Tab

实现：
- 托管同步开关（含权限申请 Dialog）
- 快速导出按钮
- 手动同步按钮 + 上次同步时间
- 关闭同步确认（保留/删除/取消）
- 权限拒绝引导
- 导入入口

### Task 4: CalendarImportView（导入页）

**Files:**
- Create: `Views/Settings/CalendarImportView.swift`

实现：
- 使用 `EKCalendarChooser`（UIViewControllerRepresentable 封装）选择日历
- 时间范围选择
- 事件列表（按 title 分组，可勾选）
- **课程映射步骤**：每组事件指定映射到已有课程 / 新建 / 跳过
- 去重标记
- 确认导入

### Task 5: 自动同步集成（全覆盖）

**Files:**
- Modify: `Views/Lesson/LessonFormView.swift` — 保存后调用 `syncLesson`
- Modify: `Views/Schedule/ScheduleView.swift` — 删除/完成时调用 `removeSyncedEvent` / `syncLesson`
- Modify: `Views/Course/CourseFormView.swift` — 保存后调用 `syncLessonsForCourse`
- Modify: `Views/Course/CourseListView.swift` — 删除前调用 `removeEventsForLessons`

### Task 6: 构建验证 + 最终集成

- `xcodegen generate` → `xcodebuild build`
- 在设备上测试：快速导出、托管同步、导入、课程编辑/删除后的同步
- 验证 Apple Calendar 中事件正确

---

## 8. 风险与注意事项

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 用户拒绝日历权限 | 对应功能不可用 | 按操作分级申请减少拒绝率 + 引导跳转设置 |
| 用户删除专属日历 | 已同步事件丢失 | 自动检测 + 重建 + 全量重新同步 |
| `eventIdentifier` 失效 | 快速路径失效 | 回退到 `EKEvent.url` 慢速路径（主标识），自动修复缓存 |
| `EKEvent.url` 被用户手动修改 | 映射丢失 | 极低概率，全量同步时会重建映射 |
| EKEventStore 非 Sendable | Swift 6 并发问题 | 统一 `@MainActor` 隔离 |
| 大量 Lesson 全量同步耗时 | UI 卡顿 | 批量提交 + 显示进度 |
| App Review 质疑 full access | 被拒审 | 分级权限 + 清晰 usage description + 仅操作专属日历 |
| 导入时自动创建大量脏 Course | 课程列表污染 | 课程映射步骤要求用户显式确认，不自动创建 |

---

## 9. V1 范围界定

**本次实现：**
- ✅ 快速导出（write-only，一次性）
- ✅ 托管同步（full access，专属日历，自动同步）
- ✅ 双层标识（`EKEvent.url` 主标识 + `eventIdentifier` 缓存）
- ✅ 全量同步 + 单条自动同步
- ✅ 课程编辑/删除的同步覆盖
- ✅ 从系统日历导入（含课程映射步骤）
- ✅ 设置页 + 权限分级申请
- ✅ 关闭同步确认

**延后实现：**
- ❌ 实时双向同步（监听 `EKEventStoreChangedNotification` 反向同步）
- ❌ 重复事件（EKRecurrenceRule）支持
- ❌ 日历颜色自定义
- ❌ 多日历导出（按课程分日历）
- ❌ Widget 日程显示
