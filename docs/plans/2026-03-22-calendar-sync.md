# 番茄课表 — 系统日历同步 设计方案

## 1. 功能概述

为番茄课表添加与 iOS 系统日历的双向同步能力：
- **导出**：将 app 内的课时（Lesson）同步到系统日历，在 Apple Calendar、锁屏日程、Siri 中可见
- **导入**：从系统日历读取日程事件，转换为 app 内的课时
- 通过一个专属 "番茄课表" 日历隔离 app 数据，不污染用户个人日历

---

## 2. 技术选型

### 2.1 框架：EventKit

iOS 原生日历框架，直接读写系统日历数据库。与 Apple Calendar、iCloud 日历、第三方 CalDAV 日历共享同一数据源。

### 2.2 权限模型（iOS 17+）

| 权限级别 | 能力 | 本项目是否需要 |
|---------|------|-------------|
| 无权限（EKEventEditViewController） | 通过系统 UI 添加/编辑单个事件，不可读取 | 不够——无法批量操作 |
| 仅写入（`requestWriteOnlyAccessToEvents`） | 可写入事件，但不可读取、不可创建日历 | 不够——需要读取和创建日历 |
| **完全访问（`requestFullAccessToEvents`）** | 读写全部事件、创建/管理日历 | **需要** |

### 2.3 Info.plist 配置

```
NSCalendarsFullAccessUsageDescription = "番茄课表需要访问您的日历，以便将课程安排同步到系统日历，并从日历导入日程。"
```

---

## 3. 用户交互设计

### 3.1 入口：新增 "设置" Tab

当前 Tab 结构为 `课表 | 课程`，新增第三个 Tab：

```
[课表]    [课程]    [设置]
```

设置页内容（第一版仅日历同步相关）：

```
┌─────────────────────────────────────────────┐
│  日历同步                                    │
├─────────────────────────────────────────────┤
│  同步到系统日历          [开关]               │  ← 主开关
│  ↳ 日历名称              番茄课表             │  ← 专属日历名，灰色说明文字
│                                             │
│  [立即同步]                                  │  ← 手动触发全量同步
│  上次同步: 2026-03-22 14:30                  │  ← 上次同步时间
├─────────────────────────────────────────────┤
│  从系统日历导入                               │
├─────────────────────────────────────────────┤
│  [选择日历并导入]                             │  ← 打开日历选择 → 事件列表 → 勾选导入
└─────────────────────────────────────────────┘
```

### 3.2 导出流程（App → 系统日历）

**首次启用同步开关时：**
1. 检查权限状态
2. 如未授权 → 调用 `requestFullAccessToEvents()` → 系统弹窗
3. 授权成功 → 自动创建 "番茄课表" 专属日历（青绿色，与 app 主色调一致）
4. 执行全量同步：将所有 Lesson 导出为 EKEvent
5. Toast 提示 "已同步 N 个课时到系统日历"

**同步规则：**
- 每个 Lesson 对应一个独立 EKEvent（非重复事件）
- Lesson 的 `calendarEventId` 字段记录 EKEvent 的 `eventIdentifier`
- 有 `calendarEventId` 的 Lesson → 更新已有 EKEvent
- 无 `calendarEventId` 的 Lesson → 创建新 EKEvent
- 系统日历中存在但 app 中已删除的事件 → 从日历中移除

**EKEvent 字段映射：**

| Lesson 字段 | EKEvent 字段 | 格式 |
|------------|-------------|------|
| `course.name` | `title` | `"雅思阅读"` |
| `studentName` | `title` 拼接 | `"雅思阅读 · 陈牧崧"` |
| `startTime` | `startDate` | 直接映射 |
| `endTime` | `endDate` | 直接映射 |
| `location` | `location` | 直接映射 |
| `notes` + 进度信息 | `notes` | `"第7/48次\n备注内容"` |
| — | `calendar` | 专属 "番茄课表" 日历 |

**自动同步触发时机：**
- 同步开关打开的状态下，以下操作自动触发单条同步：
  - 新建 Lesson → 创建对应 EKEvent
  - 编辑 Lesson → 更新对应 EKEvent
  - 删除 Lesson → 移除对应 EKEvent
  - 标记完成 → 更新 EKEvent 的 notes

### 3.3 导入流程（系统日历 → App）

**交互流程：**
1. 用户点击 "选择日历并导入"
2. 显示系统日历列表（排除 "番茄课表" 自身），用户勾选一个或多个日历
3. 显示时间范围选择器（默认：未来 30 天）
4. 展示筛选出的日程事件列表，每条可勾选
5. 用户确认 → 为每个勾选的事件创建 Lesson
6. Toast 提示 "已导入 N 个日程"

**导入映射：**

| EKEvent 字段 | Lesson 字段 | 说明 |
|-------------|------------|------|
| `title` | `course` 匹配或新建 | 按 title 查找已有 Course，无匹配则创建 |
| `startDate` | `startTime` / `date` | 拆分日期和时间 |
| `endDate` | `endTime` | — |
| `location` | `location` | 直接映射 |
| `notes` | `notes` | 直接映射 |

**去重策略：**
- 导入前检查：同一天、同一开始时间、同一课程名 → 视为重复，默认不勾选，显示 "已存在" 标记

### 3.4 权限被拒绝的处理

```
┌─────────────────────────────────────────────┐
│  ⚠️ 无法访问日历                             │
│                                             │
│  番茄课表需要日历权限才能同步课程。             │
│  请在系统设置中开启日历访问权限。               │
│                                             │
│           [前往设置]                          │
└─────────────────────────────────────────────┘
```

点击 "前往设置" → `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`

### 3.5 专属日历被用户删除的处理

- 用户可能在 Apple Calendar 中手动删除 "番茄课表" 日历
- 下次同步时检测：`eventStore.calendar(withIdentifier:)` 返回 nil
- 自动重建日历，清除所有 Lesson 的 `calendarEventId`，执行全量重新同步

---

## 4. 数据模型变更

### 4.1 Lesson 新增字段

```swift
// 在 Lesson 模型中新增
var calendarEventId: String    // EKEvent.eventIdentifier, 空字符串表示未同步
```

默认值 `""`，SwiftData 自动 lightweight migration。

### 4.2 新增 UserDefaults 存储

| Key | 类型 | 用途 |
|-----|------|------|
| `calendarSyncEnabled` | `Bool` | 同步开关状态 |
| `appCalendarIdentifier` | `String?` | 专属日历的 `calendarIdentifier` |
| `lastSyncDate` | `Date?` | 上次同步时间 |

---

## 5. 架构设计

### 5.1 新增文件

```
TomatoSchedule/
├── Services/
│   └── CalendarSyncService.swift     ← EventKit 操作封装
├── Views/
│   ├── MainTabView.swift             ← 修改：增加设置 Tab
│   └── Settings/
│       ├── SettingsView.swift        ← 设置页主视图
│       └── CalendarImportView.swift  ← 日历导入（选择日历 → 事件列表 → 导入）
```

### 5.2 CalendarSyncService 职责

```swift
@MainActor
final class CalendarSyncService: ObservableObject {
    @Published var syncEnabled: Bool
    @Published var lastSyncDate: Date?
    @Published var authorizationStatus: EKAuthorizationStatus

    // 权限
    func requestAccess() async -> Bool
    func checkAuthorizationStatus() -> EKAuthorizationStatus

    // 专属日历管理
    func getOrCreateAppCalendar() throws -> EKCalendar
    private func findAppCalendar() -> EKCalendar?

    // 导出（App → 系统日历）
    func syncAllLessons(_ lessons: [Lesson]) throws -> Int
    func syncSingleLesson(_ lesson: Lesson) throws
    func removeSyncedEvent(for lesson: Lesson) throws

    // 导入（系统日历 → App）
    func fetchCalendars() -> [EKCalendar]
    func fetchEvents(from calendars: [EKCalendar], start: Date, end: Date) -> [EKEvent]

    // 监听外部变更
    func startObservingChanges()
    func stopObservingChanges()
}
```

**设计原则：**
- `@MainActor` 隔离：EventKit 不是 Sendable，统一在主线程操作
- 单例 `EKEventStore`：创建一次，整个 app 生命周期复用
- 批量提交：导出时使用 `commit: false` + 最后 `commit()`，减少磁盘写入

### 5.3 同步流程伪代码

```
syncAllLessons(lessons):
    1. calendar = getOrCreateAppCalendar()
    2. 获取日历中已有的全部 EKEvent
    3. 构建 existingEvents 字典: [eventIdentifier: EKEvent]
    4. syncedIds = Set<String>()
    5. for lesson in lessons:
         if lesson.calendarEventId 非空 && existingEvents[id] 存在:
             更新 EKEvent 字段
             syncedIds.insert(id)
         else:
             创建新 EKEvent
             lesson.calendarEventId = event.eventIdentifier
             syncedIds.insert(event.eventIdentifier)
    6. for (id, event) in existingEvents where !syncedIds.contains(id):
         删除该 EKEvent（app 中已删除的课时）
    7. store.commit()
    8. 更新 lastSyncDate
```

---

## 6. 交互对标：主流 App 实践参考

| 特性 | 本方案 | 课程表类 App | Fantastical | Google Calendar |
|------|--------|-------------|-------------|-----------------|
| 专属日历 | ✅ "番茄课表" | ✅ 常见做法 | ❌ 用现有日历 | ❌ 服务端管理 |
| 手动同步 | ✅ "立即同步" 按钮 | ✅ "导出" 按钮 | — | — |
| 自动同步 | ✅ CRUD 时触发 | ❌ 大多仅手动 | ✅ 实时 | ✅ 实时 |
| 导入日程 | ✅ 选择日历+时间范围 | ❌ 通常不支持 | — | — |
| 设置开关 | ✅ | ✅ | — | — |
| 权限引导 | ✅ 跳转系统设置 | ✅ | ✅ | ✅ |

---

## 7. 实现任务分解

### Task 1: 数据模型 + Info.plist

**Files:**
- Modify: `Models/Lesson.swift` — 增加 `calendarEventId: String`
- Modify: `Info.plist` — 增加 `NSCalendarsFullAccessUsageDescription`

### Task 2: CalendarSyncService

**Files:**
- Create: `Services/CalendarSyncService.swift`

实现：权限请求、专属日历创建/获取、全量同步、单条同步、删除事件、外部变更监听。

### Task 3: SettingsView（设置页）

**Files:**
- Create: `Views/Settings/SettingsView.swift`
- Modify: `Views/MainTabView.swift` — 增加第三个 Tab

实现：同步开关、手动同步按钮、上次同步时间、权限拒绝引导。

### Task 4: CalendarImportView（导入页）

**Files:**
- Create: `Views/Settings/CalendarImportView.swift`

实现：日历选择列表、时间范围选择、事件列表（可勾选 + 去重标记）、确认导入。

### Task 5: 自动同步集成

**Files:**
- Modify: `Views/Lesson/LessonFormView.swift` — 保存后触发 `syncSingleLesson`
- Modify: `Views/Schedule/ScheduleView.swift` — 删除/完成时触发同步

### Task 6: 构建验证 + 最终集成

- `xcodegen generate` → `xcodebuild build`
- 在设备上测试完整同步流程
- 验证 Apple Calendar 中事件显示正确

---

## 8. 风险与注意事项

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 用户拒绝日历权限 | 同步功能不可用 | 清晰的权限说明 + 引导跳转设置 |
| 用户删除 "番茄课表" 日历 | 所有已同步事件丢失 | 自动检测并重建日历 + 全量重新同步 |
| `eventIdentifier` 在 iCloud 重新同步后失效 | 产生重复事件 | Fallback 策略：按 title + startDate 匹配 |
| EKEventStore 非 Sendable | Swift 6 严格并发下编译警告 | 统一 `@MainActor` 隔离 |
| 大量 Lesson 全量同步耗时 | UI 卡顿 | 批量提交 + 显示进度提示 |
| App Review 质疑完全日历访问权限 | 被拒审 | Info.plist 说明清晰描述用途，仅操作专属日历 |

---

## 9. V1 范围界定

**本次实现：**
- ✅ 专属日历创建与管理
- ✅ 全量同步（App → 系统日历）
- ✅ 单条自动同步（CRUD 触发）
- ✅ 手动 "立即同步" 按钮
- ✅ 从系统日历导入日程
- ✅ 设置页 UI
- ✅ 权限请求与引导

**延后实现：**
- ❌ 实时双向同步（监听 `EKEventStoreChangedNotification` 反向同步修改）
- ❌ 重复事件（EKRecurrenceRule）支持
- ❌ 日历颜色自定义
- ❌ 多日历导出（按课程分日历）
- ❌ Widget 日程显示
