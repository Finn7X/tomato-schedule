# V5 用户反馈优化迭代 — 设计规格文档

> 日期：2026-04-03
> 版本：V5 final（经 7 轮 codex review 定稿）
> 状态：已通过评审，待实施

---

## 目录

1. [背景与目标](#1-背景与目标)
2. [用户原始反馈](#2-用户原始反馈)
3. [F1: 课表左右滑动切换月份](#3-f1-课表左右滑动切换月份)
4. [F2: 批量排课](#4-f2-批量排课)
5. [F3: 时间段快速选择器](#5-f3-时间段快速选择器)
6. [F4: 课次显示优化](#6-f4-课次显示优化)
7. [F5: 排课价格冻结](#7-f5-排课价格冻结)
8. [F6: 预估收入](#8-f6-预估收入)
9. [数据迁移与兼容性](#9-数据迁移与兼容性)
10. [涉及文件清单](#10-涉及文件清单)
11. [实现优先级与依赖关系](#11-实现优先级与依赖关系)
12. [风险与注意事项](#12-风险与注意事项)

---

## 1. 背景与目标

TomatoSchedule（番茄课表）已投入真实用户使用一周。用户在实际排课过程中反馈了 6 个痛点，覆盖操作效率、数据准确性和信息展示三个维度。本轮迭代的核心目标：

- **降低排课操作成本**（F1/F2/F3）
- **提高数据展示准确性与可读性**（F4/F5）
- **增强收入预测能力**（F6）
- **零数据丢失**：用户手机已有真实数据，所有变更必须向后兼容，不丢弃已有字段语义

### 技术栈现状

| 项目 | 值 |
|------|-----|
| 语言 | Swift 5 / SwiftUI |
| 数据层 | SwiftData（非 CoreData） |
| 最低版本 | iOS 17.0 |
| 日历同步 | EventKit |
| 构建 | XcodeGen (project.yml) |

### 现有数据模型概览

**Course** (`Models/Course.swift`)：
- `id`, `name`, `colorHex`, `notes`, `createdAt`
- `subject`, `totalHours`, `totalLessons` (V2)
- `hourlyRate` (V4)
- `lessons: [Lesson]` (cascade 删除)

**Lesson** (`Models/Lesson.swift`)：
- `id`, `course`, `studentName`, `date`, `startTime`, `endTime`, `notes`, `createdAt`
- `lessonNumber`, `isCompleted`, `location` (V2)
- `calendarEventId` (V3)
- `isPriceOverridden`, `priceOverride` (V4)
- `isManualPrice` (V5 新增，见 F5)

---

## 2. 用户原始反馈

| # | 原文 | 分类 |
|---|------|------|
| 1 | 希望课表可以左右滑动，左滑就是上个月，右滑就是下个月 | 操作效率 |
| 2 | 希望可以一次添加多个课程，例如四月的每周五下午14:00-16:00 | 操作效率 |
| 3 | 选课程时间的时候可以直接选时间段，例如从早上8:00到晚上10:00，可以选其中任意一个小时或两个小时或者三个小时，不需要从头选时间 | 操作效率 |
| 4 | 课次显示得有点奇怪 不太方便 | 信息展示 |
| 5 | 排上课的价格就固定，不能因为后面课涨价，把前面课的收入也变动了 | 数据准确性 |
| 6 | 想要有预估收入（和实际收入分开，也可以选择开/关） | 信息展示 |

---

## 3. F1: 课表左右滑动切换月份

### 3.1 问题分析

当前月份切换通过 `CalendarHeaderView` 顶部的 `chevron.left` / `chevron.right` 按钮实现（`CalendarHeaderView.swift:15-33`）。按钮点击区域小，操作需要精确点击，不符合用户在课表页面左右滑动的直觉预期。

### 3.2 滑动方向定义

严格遵循用户原话 **"左滑就是上个月，右滑就是下个月"**：

```
用户向左滑动（手指从右向左） → 切换到上一个月 → MonthGridView 从左侧滑入
用户向右滑动（手指从左向右） → 切换到下一个月 → MonthGridView 从右侧滑入
```

这与当前 chevron 按钮的语义一致（左箭头 = 上月，右箭头 = 下月），属于"翻书"心智模型：手指往左翻 = 回到上一页。

### 3.3 月视图（isExpanded == true）实现

1. **手势识别：** 在 `CalendarHeaderView` 的日历区域（`MonthGridView` 外层）包裹 `.gesture(DragGesture)`
2. **触发阈值：** 水平位移绝对值 > 50pt 且 > 垂直位移绝对值时触发，防止与纵向滚动冲突
3. **方向动画：** 引入 `@State private var slideDirection: SlideDirection`（枚举 `.backward` / `.forward` / `.none`），用于控制 `MonthGridView` 的 `transition`：
   - `.backward`（上月，左滑）：`.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))`
   - `.forward`（下月，右滑）：`.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))`
4. **MonthGridView 标识：** 添加 `.id(displayedMonth)` 使 SwiftUI 在月份变化时创建新视图实例，配合 transition 动画生效
5. **动画时长：** 与现有 chevron 动画保持一致（`easeInOut(duration: 0.2)`）
6. **防抖：** 引入 `@State private var isAnimating = false`，动画进行中忽略新的滑动手势

### 3.4 周视图（isExpanded == false）实现

当日历折叠为周视图时，滑动切换的是**周**而非月：

```
左滑 → 上一周（selectedDate -= 7 天）
右滑 → 下一周（selectedDate += 7 天）
```

**状态同步规则（解决 selectedDate / displayedMonth 失同步问题）：**

当切周导致 `selectedDate` 跨月时，必须同步更新 `displayedMonth`：

```swift
// 在 CalendarHeaderView 中处理周切换
private func moveWeek(_ offset: Int) {
    guard let newDate = DateHelper.calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) else { return }
    // 关键：先缓存旧月份，再赋值，否则 oldMonth/newMonth 永远相等
    let oldMonth = DateHelper.calendar.dateComponents([.year, .month], from: selectedDate)
    let newMonth = DateHelper.calendar.dateComponents([.year, .month], from: newDate)
    let needsMonthSync = oldMonth != newMonth
    withAnimation(.easeInOut(duration: 0.2)) {
        selectedDate = newDate
        if needsMonthSync {
            displayedMonth = newDate
        }
    }
}
```

**展开月视图时的定位：** 用户在周视图滑动到其他月后点击展开，`MonthGridView` 应显示 `displayedMonth` 对应的月份（已通过上述同步保证）。

**WeekStripView 动画：** 与 MonthGridView 同理，添加 `.id(DateHelper.weekRange(for: selectedDate).start)` + transition 实现滑动过渡。

### 3.5 涉及文件

| 文件 | 变更 |
|------|------|
| `Views/Schedule/CalendarHeaderView.swift` | 添加 DragGesture、slideDirection 状态、transition 动画、moveWeek 逻辑 |
| `Views/Schedule/MonthGridView.swift` | 添加 `.id(displayedMonth)` 配合 transition |
| `Views/Schedule/WeekStripView.swift` | 添加 `.id()` 配合周切换 transition |

### 3.6 注意事项

- DragGesture 挂在日历区域（MonthGridView/WeekStripView 外层），不在 List 上，与纵向滚动不冲突
- 与现有 `ScrollCalendarFoldModifier`（纵向滚动折叠日历）交互：两个手势方向正交，不冲突
- 需测试 iOS 17 和 iOS 18 两个路径

---

## 4. F2: 批量排课

### 4.1 问题分析

当前只能通过 `LessonFormView` 逐一添加课时。用户典型场景："四月每周五下午 14:00-16:00"，需要手动添加 4 次，每次都要选日期、时间、课程，操作重复且耗时。

### 4.2 设计方案

新增 `BatchLessonFormView`，从 `ScheduleView` 的 toolbar 进入。

#### 4.2.1 入口

在 `ScheduleView` 的 toolbar `+` 按钮改为 `Menu`：

```
+ (Menu)
├── 添加单节课时    → LessonFormView（现有）
└── 批量排课        → BatchLessonFormView（新增）
```

#### 4.2.2 表单设计

```
┌─ 批量排课 ──────────────────────────┐
│                                      │
│  课程: [课程选择 Picker]             │
│  学生: [可选输入]                    │
│  地点: [可选输入]                    │
│                                      │
│  ── 重复规则 ──                      │
│  起始日期: [2026年4月1日]            │
│  结束日期: [2026年4月30日]           │
│                                      │
│  每周重复:                           │
│  [一] [二] [三] [四] [五] [六] [日]  │
│   ○    ○    ○    ○    ●    ○    ○    │
│                                      │
│  ── 上课时间 ──                      │
│  [TimeSlotPicker 组件 (F3)]          │
│  已选: 14:00 - 16:00                 │
│                                      │
│  ── 预览 (4节课) ──                  │
│  ✓ 4月3日 周五   14:00-16:00  第1节  │
│  ✓ 4月10日 周五  14:00-16:00  第2节  │
│  ✓ 4月17日 周五  14:00-16:00  第3节  │
│  ✓ 4月24日 周五  14:00-16:00  第4节  │
│                                      │
│  [取消]              [创建 4 节课]   │
└──────────────────────────────────────┘
```

（注：2026 年 4 月的周五为 3 日、10 日、17 日、24 日。）

#### 4.2.3 核心逻辑

1. **日期生成：** 根据起止日期和选中的星期几，生成所有匹配日期
2. **课次编号：** 取 `max(course.lessons.count, course.lessons.map(\.lessonNumber).max() ?? 0) + 1` 作为起始编号，逐一递增写入 `lessonNumber` 字段持久化。取两者最大值是为了防止"旧数据 `lessonNumber == 0` 导致自动推导序号与新批量编号撞号"的问题（详见 6.2.1）
3. **价格冻结：** 每节课创建时立即冻结价格（配合 F5 统一冻结规则）
4. **预览列表：** 用户可以通过左滑单独移除不需要的日期（如遇到节假日）
5. **冲突检测：** 创建前检查目标时间段是否与已有课程重叠，有冲突标注警告图标
6. **日历同步：** 批量创建后统一触发 `CalendarSyncService` 同步
7. **备注字段：** 批量创建的课程共享同一备注，或留空
8. **上限保护：** 单次批量创建上限 100 节，超过时提示用户分批操作

#### 4.2.4 冲突检测逻辑

```swift
func hasConflict(date: Date, start: Date, end: Date) -> Bool {
    let dayStart = DateHelper.combine(date: date, time: start)
    let dayEnd = DateHelper.combine(date: date, time: end)
    return allLessons.contains { existing in
        DateHelper.isSameDay(existing.date, date) &&
        existing.startTime < dayEnd &&
        existing.endTime > dayStart
    }
}
```

有冲突时在预览行显示橙色警告图标 `exclamationmark.triangle.fill`，但不阻止创建（用户可能有意让课程重叠）。

#### 4.2.5 涉及文件

| 文件 | 变更 |
|------|------|
| `Views/Lesson/BatchLessonFormView.swift` | **新建** — 批量排课表单 |
| `Views/Schedule/ScheduleView.swift` | toolbar 从 Button 改为 Menu |
| `Views/Components/TimeSlotPicker.swift` | **新建** — 复用 F3 的时间选择器组件 |

---

## 5. F3: 时间段快速选择器

### 5.1 问题分析

当前 `LessonFormView` 使用两个原生 `DatePicker(.hourAndMinute)` 分别选择开始和结束时间（`LessonFormView.swift:69-70`）。问题：

1. 系统滚轮需要多次滑动才能到达目标时间
2. 无法直观看到整体可用时间段
3. 需要先选开始时间再选结束时间，两步操作

### 5.2 设计方案 — "快捷网格 + DatePicker 兜底"

提取为独立组件 `TimeSlotPicker`，在 `LessonFormView` 和 `BatchLessonFormView` 中复用。

**核心原则：时间网格是快捷入口，不是唯一入口。** 系统 DatePicker 保留作为兜底，确保任意时间（包括旧数据中不在网格范围内的时间）都可以无损编辑。

#### 5.2.1 布局

```
┌─ 上课时间 ──────────────────────────┐
│                                      │
│  08:00  08:30  09:00  09:30          │
│  10:00  10:30  11:00  11:30          │
│  12:00  12:30  13:00  13:30          │
│  14:00  14:30  15:00  15:30          │
│  16:00  16:30  17:00  17:30          │
│  18:00  18:30  19:00  19:30          │
│  20:00  20:30  21:00  21:30          │
│                                      │
│  时长: [1h] [1.5h] [2h] [3h] [自定义]│
│                                      │
│  已选: 14:00 — 16:00 (2小时)         │
│                                      │
│  [切换到精确输入]                    │ ← 点击后显示原生 DatePicker
└──────────────────────────────────────┘
```

#### 5.2.2 交互流程

```
状态机:
  idle → 用户点击时间按钮 → startSelected
  startSelected → 用户点击时长按钮 → rangeSelected
  startSelected → 用户点击"自定义" → 显示结束时间网格(只显示起始之后的时段) → rangeSelected
  rangeSelected → 用户重新点击起始 → startSelected (重置)
```

1. **初始状态：** 所有时间按钮未选中，时长按钮禁用
2. **选择起始时间：** 用户点击某个时间按钮（如 14:00），该按钮高亮为主题色
3. **选择时长：** 时长按钮激活，用户点击 `2h`，自动计算结束时间为 16:00
   - 起始到结束的所有半小时块高亮显示（14:00, 14:30, 15:00, 15:30 四个按钮变为浅色范围色）
4. **自定义时长：** 点击"自定义"，结束时间网格只显示起始时间之后的时段，用户直接点选结束时间
5. **结果摘要：** 底部显示 `已选: 14:00 — 16:00 (2小时)`

#### 5.2.3 存量数据兼容策略

**问题：** 当前 `LessonFormView` 用原生 `DatePicker(.hourAndMinute)` 可编辑任意分钟。`CalendarImportView` 会把系统日历事件的原始时间直接落到 Lesson（如 `07:30-09:10`、`21:30-22:30`），不保证整点/半点或落在 8:00-22:00 范围内。

**兼容规则：**

| 场景 | 处理方式 |
|------|----------|
| 新建课时 | 默认显示时间网格 |
| 编辑课时，时间对齐网格（如 14:00-16:00） | 显示时间网格，已选中当前值 |
| 编辑课时，时间不对齐网格（如 09:15-10:45） | 自动切换到精确输入模式（原生 DatePicker） |
| 编辑课时，时间超出 8:00-22:00（如 07:00-08:00） | 自动切换到精确输入模式（原生 DatePicker） |

**判断逻辑（使用绝对分钟值，避免小时边界误判）：**

```swift
private var canUseGrid: Bool {
    let cal = DateHelper.calendar
    let startHour = cal.component(.hour, from: startTime)
    let startMin = cal.component(.minute, from: startTime)
    let endHour = cal.component(.hour, from: endTime)
    let endMin = cal.component(.minute, from: endTime)
    
    let startAbsMin = startHour * 60 + startMin
    let endAbsMin = endHour * 60 + endMin
    let gridStartMin = dayStartHour * 60   // 默认 480 (08:00)
    let gridEndMin = dayEndHour * 60       // 默认 1320 (22:00)
    
    // 分钟必须对齐 slotInterval，时间必须完全落在网格范围内
    return startAbsMin >= gridStartMin &&
           endAbsMin <= gridEndMin &&
           startAbsMin % slotInterval == 0 &&
           endAbsMin % slotInterval == 0
}
```

**注意：** `endAbsMin <= gridEndMin` 使用 `<=` 而非 `<`，因为 22:00 是网格的合法结束时间（如 20:00-22:00）。但 22:30 等超出值会被正确拒绝（`22*60+30 = 1350 > 1320`）。

**时长按钮溢出禁用规则：**

选中起始时间后，时长按钮根据是否超出 `dayEndHour` 动态禁用：

```swift
let latestEndMin = dayEndHour * 60  // 1320
let selectedStartAbsMin = startHour * 60 + startMin

// 各时长按钮的可用性
let durations = [60, 90, 120, 180]  // 1h, 1.5h, 2h, 3h
for d in durations {
    let wouldEnd = selectedStartAbsMin + d
    button.isDisabled = wouldEnd > latestEndMin
}
// 例：起始 21:00 (1260min) → 1h 可用(1320)、1.5h 禁用(1350)、2h 禁用(1380)、3h 禁用(1440)
```

用户在任意模式下可以手动切换：网格模式底部有"切换到精确输入"链接，精确模式底部有"切换到快速选择"链接。

#### 5.2.4 组件接口

```swift
struct TimeSlotPicker: View {
    @Binding var startTime: Date
    @Binding var endTime: Date
    var date: Date                  // 用于 DateHelper.combine
    var slotInterval: Int = 30      // 分钟
    var dayStartHour: Int = 8
    var dayEndHour: Int = 22
    var forcePickerMode: Bool = false  // 强制使用 DatePicker 模式
}
```

#### 5.2.5 视觉设计

- 时间按钮：圆角矩形，大小约 70x36pt，4 列网格
- 未选中：`.quaternary` 背景 + `.primary` 文字
- 起始时间：主题色（teal）填充 + 白色文字
- 范围内：主题色 `opacity(0.2)` 填充 + 主题色文字
- 时长按钮：胶囊形状，水平排列，选中项为主题色

#### 5.2.6 在 LessonFormView 中的集成

替换 `LessonFormView` 时间 Section 中的两个 `DatePicker(.hourAndMinute)`：

```swift
Section("时间") {
    DatePicker("日期", selection: $date, displayedComponents: .date)  // 保留不变
    TimeSlotPicker(
        startTime: $startTime,
        endTime: $endTime,
        date: date,
        forcePickerMode: !canUseGrid  // 旧数据不对齐时自动切到 DatePicker
    )
}
```

日期选择器 `DatePicker("日期", ...)` 保留不变。`BatchLessonFormView` 同样使用此组件。

#### 5.2.7 涉及文件

| 文件 | 变更 |
|------|------|
| `Views/Components/TimeSlotPicker.swift` | **新建** — 时间段选择器组件（含网格 + DatePicker 双模式） |
| `Views/Lesson/LessonFormView.swift` | 替换时间 Section 中的两个 DatePicker |

---

## 6. F4: 课次显示优化

### 6.1 问题分析

当前课次系统存在的问题：

1. **手动维护：** `lessonNumber` 需要在 `LessonFormView` 的"更多设置"中手动输入（`LessonFormView.swift:82-88`），隐藏较深
2. **格式不直观：** 显示为 `3/48次`（`Lesson.headerSequenceText`），缺少语义，用户需要理解分子/分母的含义
3. **位置分散：** 同时出现在 `LessonTimeGroup` 头部和 `LessonDetailCard` 的 progressParts 中，冗余

### 6.2 设计方案

#### 6.2.1 课次来源策略：已有值优先，空值自动推导

**核心原则：** 已有 `lessonNumber` 是用户主动录入的业务语义，升级后不得丢弃或默默改写。

| 场景 | `lessonNumber` 值 | 显示来源 |
|------|-------------------|----------|
| 用户已手动设置 | > 0 | 使用存储的 `lessonNumber`（第一优先级） |
| 新建单节课，用户未填 | 0 | 自动推导（按时间排序在同课程中的位置） |
| 批量排课创建 | 自动递增写入 | 使用存储的 `lessonNumber` |
| 旧数据未设置 | 0 | 自动推导 |

**防撞号规则：**

批量排课的起始编号必须同时考虑存储值和课程总数，取两者最大值：

```swift
/// 计算该课程下一个课次编号的安全起始值
func nextLessonNumber(for course: Course) -> Int {
    let maxStored = course.lessons.map(\.lessonNumber).max() ?? 0
    let totalCount = course.lessons.count
    return max(maxStored, totalCount) + 1
}
```

**为什么需要 max：** 如果课程有 3 节旧课且 `lessonNumber` 都是 0，自动推导会显示为第 1/2/3 节。此时仅取 `maxStored = 0` 会让批量创建从 1 开始，导致两套 1/2/3 撞号。取 `max(0, 3) + 1 = 4` 可安全避开。

**自动推导逻辑：**

```swift
// Course 扩展
var sortedLessons: [Lesson] {
    lessons.sorted { $0.startTime < $1.startTime }
}

/// 返回该课程中该课时的自动推导序号（仅在 lessonNumber == 0 时使用）
func autoIndex(for lesson: Lesson) -> Int? {
    guard let idx = sortedLessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }
    return idx + 1
}
```

**Lesson 展示属性：**

```swift
/// 课次展示文本，已有值优先，空值自动推导
var displaySequenceText: String? {
    let number: Int
    if lessonNumber > 0 {
        number = lessonNumber  // 用户手动设置的值，优先使用
    } else if let auto = course?.autoIndex(for: self) {
        number = auto          // 自动推导
    } else {
        return nil
    }
    
    if let total = course?.totalLessons, total > 0 {
        return "第\(number)/\(total)节"
    }
    return "第\(number)节"
}
```

#### 6.2.2 显示格式改进

| 场景 | 旧格式 | 新格式 |
|------|--------|--------|
| 有 totalLessons | `3/48次` | `第3/48节` |
| 无 totalLessons | 不显示 | `第3节` |

#### 6.2.3 显示位置调整

- **LessonTimeGroup 头部（`LessonTimeGroup.swift:25-29`）：** 保留，使用 `displaySequenceText`
- **LessonDetailCard progressParts（`LessonDetailCard.swift:79`）：** 移除课次（不再和头部重复）
- **LessonFormView：** 保留"第几节课"输入框，但调整为：
  - 新建时：输入框显示自动推导的值作为 placeholder（如 `"自动: 第5节"`），用户可覆盖
  - 编辑时：显示当前值，允许修改
  - 将此输入框从"更多设置"DisclosureGroup 提升到主表单区域，提高可见性

#### 6.2.4 `lessonNumber` 字段处理

- **保留字段**：继续作为持久化存储
- **继续写入**：
  - 用户在 LessonFormView 手动输入的值正常写入
  - BatchLessonFormView 批量创建时自动递增写入
  - LessonFormView 新建时如果用户未修改，写入 0（由 `displaySequenceText` 自动推导）
- **继续读取**：`displaySequenceText` 优先使用 `lessonNumber`（> 0 时）

#### 6.2.5 CalendarSyncService 同步适配

**问题：** 当前 `CalendarSyncService.populateEvent()` 的备注构建（`CalendarSyncService.swift:217-219`）：

```swift
if let seq = lesson.headerSequenceText {
    noteParts.append("第\(seq)")  // 产出 "第3/48次"
}
```

`headerSequenceText` 返回 `"3/48次"`，所以备注中出现 `"第3/48次"`。新格式 `displaySequenceText` 返回 `"第3/48节"`，如果沿用 `"第\(seq)"` 拼法，备注会变成 `"第第3/48节"` —— 双重前缀。

**修复方案：**

```swift
// CalendarSyncService.populateEvent() 中改为：
if let seq = lesson.displaySequenceText {
    noteParts.append(seq)  // 直接使用，不再加"第"前缀
}
```

**批量重同步触发规则：**

| 操作 | 是否触发同课程全量重同步 |
|------|--------------------------|
| 新建/删除课时 | 否（仅同步单节，因为已有值优先策略下其他课次不变） |
| 编辑单节课时的 `lessonNumber` | 否（仅同步该节） |
| 批量排课创建 | 否（新课已写入 `lessonNumber`，不影响已有课） |
| 编辑课程的 `totalLessons` | 是（所有课次的分母变了，需触发 `syncLessonsForCourse`） |

对于 `lessonNumber == 0`（自动推导）的课时：插入/删除其他课时可能改变其推导序号，但这些课本身就没有用户主动设定的序号。此场景下不触发全量重同步，用户下次手动同步或 app 下次执行 `syncAllLessons` 时自然更新。这是可接受的最终一致性。

#### 6.2.6 涉及文件

| 文件 | 变更 |
|------|------|
| `Models/Course.swift` | 新增 `sortedLessons`、`autoIndex(for:)` |
| `Models/Lesson.swift` | 新增 `displaySequenceText`，保留 `headerSequenceText`（被 `displaySequenceText` 替代调用） |
| `Views/Schedule/LessonTimeGroup.swift` | 使用 `displaySequenceText` 替换 `headerSequenceText` |
| `Views/Schedule/LessonDetailCard.swift` | 从 progressParts 移除课次 |
| `Views/Lesson/LessonFormView.swift` | 课次输入框从 DisclosureGroup 提升到主区域 + placeholder 自动推导 |
| `Views/Lesson/BatchLessonFormView.swift` | 批量创建时自动递增写入 `lessonNumber` |
| `Services/CalendarSyncService.swift` | `populateEvent()` 改用 `displaySequenceText`，去掉"第"前缀 |

---

## 7. F5: 排课价格冻结

### 7.1 问题分析

当前定价逻辑（`Lesson.effectivePrice`，`Lesson.swift:54-58`）：

```swift
var effectivePrice: Double {
    if isPriceOverridden { return priceOverride }
    guard let rate = course?.hourlyRate, rate > 0 else { return 0 }
    return rate * Double(durationMinutes) / 60.0  // 实时计算
}
```

价格只在以下两个时机冻结：
1. `TomatoScheduleApp.autoCompletePastLessons()`（app 启动时自动完成过去的课程）
2. `ScheduleView` 的 swipe 完成操作

**问题：** 如果老师在四月排了 20 节课，五月调高了 `hourlyRate`，四月所有未完成课程的价格会追溯性变化。用户认为这不合理——排课时的价格就应该是确定的。

### 7.2 价格模型升级：拆分"自动冻结"与"手动改价"

#### 7.2.1 问题：`isPriceOverridden` 语义冲突

当前 `isPriceOverridden` 同时承担两种含义：
1. **用户手动改价**（如试听价 ¥50、人情价 ¥0 免费）
2. **系统自动冻结**（创建时按 hourlyRate 计算的快照）

V5 要求所有课程创建时都冻结价格，这意味着所有 Lesson 都会变成 `isPriceOverridden = true`，导致：
- 编辑普通课时时，UI 会误显示为"自定义"
- "仅更新未来课程"无法跳过真正的手动特价课
- `hourlyRate == 0` 冻结的 ¥0 和用户主动设的"免费课"无法区分

#### 7.2.2 方案：新增 `isManualPrice` 字段

**Schema 变更：** 在 Lesson 模型中新增一个字段：

```swift
// V5 新增
var isManualPrice: Bool  // 默认 false
```

**三字段协作语义：**

| `isPriceOverridden` | `isManualPrice` | `priceOverride` | 含义 | UI 显示 |
|---------------------|-----------------|-----------------|------|---------|
| `false` | `false` | `0` | 旧数据，未迁移（V5 迁移后不应存在） | 按 hourlyRate 实时计算 |
| `true` | `false` | `≥ 0` | 系统自动冻结的价格快照 | "自动计算" + 显示快照值 |
| `true` | `false` | `0`（且 hourlyRate 当时=0） | 排课时课程尚未定价 | 不显示价格（非"免费"） |
| `true` | `true` | `> 0` | 用户手动设定的特殊价格 | "自定义 ¥X" |
| `true` | `true` | `0` | 用户明确标记为免费 | "免费" |

**`priceDisplayText` 更新：**

```swift
var priceDisplayText: String? {
    let p = effectivePrice
    if isManualPrice && p == 0 { return "免费" }      // 用户明确设为免费
    if !isManualPrice && p == 0 { return nil }         // 未定价，不显示
    guard p > 0 else { return nil }
    return p == p.rounded() ? "¥\(Int(p))" : String(format: "¥%.1f", p)
}
```

**SwiftData 迁移：** `isManualPrice` 是新属性带默认值 `false`，SwiftData 自动处理轻量迁移。旧数据的语义迁移（按三类场景区分处理）详见 9.2 节。

#### 7.2.3 统一冻结规则

**所有 Lesson 创建入口统一执行价格冻结，无论价格是多少（包括 0 元）。**

| 创建入口 | 文件 | 冻结方式 |
|----------|------|----------|
| 单节新建 | `LessonFormView.swift` | 创建后 freezePrice() 或写入手动价格 |
| 批量新建 | `BatchLessonFormView.swift`（新建） | 同上，每节课独立冻结 |
| 日历导入 | `CalendarImportView.swift` | 导入创建后 freezePrice() |
| 自动完成 | `TomatoScheduleApp.swift` | 已有冻结逻辑，保持不变 |
| 手动完成 | `ScheduleView.swift` | 已有冻结逻辑，保持不变 |

#### 7.2.4 创建时冻结实现

**通用冻结逻辑：**

```swift
/// 系统自动冻结价格快照（非手动改价）
private func freezePrice(for lesson: Lesson) {
    guard !lesson.isPriceOverridden else { return }  // 已冻结或已手动设价
    let rate = lesson.course?.hourlyRate ?? 0
    let minutes = DateHelper.calendar.dateComponents(
        [.minute], from: lesson.startTime, to: lesson.endTime
    ).minute ?? 0
    let price = rate > 0 ? (rate * Double(minutes) / 60.0 * 100).rounded() / 100 : 0
    lesson.priceOverride = price
    lesson.isPriceOverridden = true
    lesson.isManualPrice = false  // 明确标记：这是系统冻结，不是手动改价
}
```

**LessonFormView 本地状态改造：**

```swift
// 原 @State private var isPriceOverridden: Bool = false  ← 移除
// 原 @State private var priceOverride: Double = 0        ← 保留
@State private var isManualPrice: Bool = false   // 新增，绑定价格 Picker
@State private var priceOverride: Double = 0     // 保留，绑定手动价格输入

// onAppear 初始化（编辑已有课时）
if let lesson {
    isManualPrice = lesson.isManualPrice
    priceOverride = lesson.priceOverride
    // ...其他字段
}
```

`isManualPrice` 是表单 UI 的唯一源状态，`isPriceOverridden` 只在持久化写入时使用。

**LessonFormView.save()** — 新建路径：

```swift
let newLesson = Lesson(
    course: selectedCourse,
    studentName: ...,
    date: ...,
    startTime: actualStart,
    endTime: actualEnd,
    ...
)
// Lesson.init() 默认 isPriceOverridden = false, isManualPrice = false, priceOverride = 0
if isManualPrice {
    // 用户在表单中选了"自定义"价格
    newLesson.isPriceOverridden = true
    newLesson.isManualPrice = true
    newLesson.priceOverride = priceOverride
} else {
    // 自动定价：冻结当前费率计算的快照
    freezePrice(for: newLesson)
}
modelContext.insert(newLesson)
```

**LessonFormView.save()** — 编辑路径：

```swift
if let lesson {
    // ...其他字段赋值
    let wasManual = lesson.isManualPrice
    lesson.isManualPrice = isManualPrice
    if isManualPrice {
        // 保持或更新手动价格
        lesson.isPriceOverridden = true
        lesson.priceOverride = priceOverride
    } else if wasManual && !isManualPrice {
        // 从"自定义"切回"自动计算"：按当前课程费率和编辑后时长重算快照
        let rate = selectedCourse?.hourlyRate ?? 0
        let minutes = DateHelper.calendar.dateComponents(
            [.minute], from: actualStart, to: actualEnd
        ).minute ?? 0
        let price = rate > 0 ? (rate * Double(minutes) / 60.0 * 100).rounded() / 100 : 0
        lesson.priceOverride = price
        lesson.isPriceOverridden = true
        // lesson.isManualPrice 已经是 false
    }
    // else: 自动保持自动 → 保持原冻结快照不变
}
```

**CalendarImportView.performImport()** — 导入路径：

```swift
let lesson = Lesson(
    course: course,
    studentName: parsed.studentName,
    date: eventDate,
    startTime: event.startDate,
    endTime: event.endDate,
    notes: event.notes ?? "",
    location: event.location ?? ""
)
freezePrice(for: lesson)  // 导入时自动冻结（非手动）
modelContext.insert(lesson)
```

#### 7.2.5 LessonFormView 编辑 UI 适配

当前编辑页的"自动计算 / 自定义" Picker 绑定 `isPriceOverridden`。V5 后需要改为绑定 `isManualPrice`：

**共享价格格式化函数**（与 `priceDisplayText` 规则一致，避免截断小数）：

```swift
/// 整数显示 "¥100"，非整数显示 "¥148.5"
private func formatPrice(_ p: Double) -> String {
    p == p.rounded() ? "¥\(Int(p))" : String(format: "¥%.1f", p)
}
```

```swift
// LessonFormView 中
Picker("课时费用", selection: $isManualPrice) {
    Text("自动计算").tag(false)
    Text("自定义").tag(true)
}
.pickerStyle(.segmented)

if isManualPrice {
    // 手动价格输入
    HStack {
        Text("¥")
        TextField("金额", value: $priceOverride, format: .number)
        Text("(0 = 免费)").font(.caption).foregroundStyle(.secondary)
    }
} else if isEditing, let lesson {
    // 编辑已有课时：显示冻结的 priceOverride 快照（不重算）
    let snapshot = lesson.priceOverride
    if snapshot > 0 {
        Text("\(formatPrice(snapshot)) (已锁定)")
            .font(.caption).foregroundStyle(.secondary)
    } else {
        Text("未定价")
            .font(.caption).foregroundStyle(.secondary)
    }
} else {
    // 新建课时（尚未保存）：按当前费率实时试算
    if let rate = selectedCourse?.hourlyRate, rate > 0 {
        let auto = (rate * Double(durationMinutes) / 60.0 * 100).rounded() / 100
        Text("\(formatPrice(auto)) (\(formatPrice(rate))/h)")
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

**编辑已有课时时的初始化：**
```swift
// onAppear
if let lesson {
    isManualPrice = lesson.isManualPrice  // 而不是 lesson.isPriceOverridden
    priceOverride = lesson.priceOverride
    ...
}
```

这样：
- 自动冻结的普通课时（`isManualPrice = false`）→ 编辑时正确显示"自动计算"
- 用户手动改价的课时（`isManualPrice = true`）→ 编辑时正确显示"自定义"

#### 7.2.6 编辑课程费率时的处理 — 两阶段保存

**两阶段保存设计：**

```swift
private func save() {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    
    if let course {
        // 阶段1：检测费率是否变化
        let rateChanged = course.hourlyRate != hourlyRate && hourlyRate > 0
        let oldRate = course.hourlyRate
        
        if rateChanged && course.lessons.contains(where: { !$0.isCompleted }) {
            pendingRate = hourlyRate
            pendingOldRate = oldRate
            showRateChangeConfirmation = true
            return  // 不 dismiss，等待用户选择
        }
        
        // 阶段2：无争议时直接保存
        applyAllChanges(course: course)
    } else {
        let newCourse = Course(name: trimmedName, ...)
        modelContext.insert(newCourse)
    }
    dismiss()
}

/// 确认对话框选择后调用
private func applyAllChanges(course: Course, updateFutureLessons: Bool = false) {
    let oldTotalLessons = course.totalLessons
    let needsCalendarSync = course.name != trimmedName || course.subject != trimmedSubject
    let needsSequenceResync = oldTotalLessons != totalLessons
    
    course.name = trimmedName
    course.colorHex = colorHex
    course.notes = notes
    course.subject = trimmedSubject
    course.totalHours = totalHours
    course.totalLessons = totalLessons
    course.hourlyRate = hourlyRate
    
    if updateFutureLessons {
        // 只更新自动定价的未来课时，跳过手动改价的
        let futureLessons = course.lessons.filter {
            !$0.isCompleted && $0.startTime > .now && !$0.isManualPrice
        }
        for lesson in futureLessons {
            let minutes = DateHelper.calendar.dateComponents(
                [.minute], from: lesson.startTime, to: lesson.endTime
            ).minute ?? 0
            lesson.priceOverride = (hourlyRate * Double(minutes) / 60.0 * 100).rounded() / 100
        }
    }
    
    if needsCalendarSync || needsSequenceResync {
        try? CalendarSyncService.shared.syncLessonsForCourse(course)
    }
    
    dismiss()
}
```

**确认对话框：**

```
课时单价从 ¥{old}/h 更改为 ¥{new}/h。

[更新未来课程]  — 更新未来自动定价的课程（手动设定过价格的课不受影响）
[全部不更新]    — 只影响之后新建的课程，已排课程保持原价
[取消]          — 放弃费率修改
```

#### 7.2.7 effectivePrice 保留兼容

```swift
var effectivePrice: Double {
    if isPriceOverridden { return priceOverride }
    // Fallback: V5 迁移完成后不应再有数据走到这里
    guard let rate = course?.hourlyRate, rate > 0 else { return 0 }
    let raw = rate * Double(durationMinutes) / 60.0
    return (raw * 100).rounded() / 100
}
```

### 7.3 涉及文件

| 文件 | 变更 |
|------|------|
| `Views/Lesson/LessonFormView.swift` | save() 新建路径添加 `freezePrice()` |
| `Views/Lesson/BatchLessonFormView.swift` | 批量创建时调用 `freezePrice()` |
| `Views/Settings/CalendarImportView.swift` | `performImport()` 中导入课时后调用 `freezePrice()` |
| `Views/Course/CourseFormView.swift` | 两阶段保存 + 费率变更确认对话框 |
| `App/TomatoScheduleApp.swift` | 添加 V5 一次性存量迁移逻辑 |

---

## 8. F6: 预估收入

### 8.1 问题分析

当前只显示已完成课程的收入。用户希望看到"如果这些课都上完了，这个月能挣多少"的预估值，便于财务规划。

### 8.2 统一"已完成"口径

**问题（现状）：** 不同视图对"已完成"的判断标准不一致：

| 视图 | 判断逻辑 | 文件位置 |
|------|----------|----------|
| ScheduleView (statisticsCompleted/Income) | `isCompleted \|\| endTime < .now` | `ScheduleView.swift:62-67` |
| IncomeView (completedLessons) | `isCompleted \|\| endTime < .now` | `IncomeView.swift:19-21` |
| SettingsView (incomeForToday/Week/Month) | 仅 `isCompleted` | `SettingsView.swift:197-213` |

**统一规则：** 全 app 统一使用 **`isCompleted || endTime < .now`** 作为"已完成"判断。

**设计依据：**
- `autoCompletePastLessons()` 在 app 启动和回前台时会将过期课标为 `isCompleted = true`，`isCompleted` 是持久化的权威状态
- `endTime < .now` 是实时补充，覆盖 `autoCompletePastLessons()` 尚未执行的间隙（如 app 持续活跃时课程自然结束，用户直接切到 Income/Settings 页）
- 这两个条件不矛盾：`endTime < .now` 是 `autoCompletePastLessons()` 最终会处理的子集，读路径提前兜底只是让 UI 更及时

**需要修改的位置（仅 SettingsView）：**

```swift
// SettingsView.swift:197 改为：
private var incomeForToday: Double {
    let today = DateHelper.startOfDay(.now)
    let tomorrow = DateHelper.endOfDay(.now)
    return allLessons.filter {
        ($0.isCompleted || $0.endTime < .now) &&
        $0.date >= today && $0.date < tomorrow
    }.reduce(0) { $0 + $1.effectivePrice }
}
// 同理修改 incomeForWeek / incomeForMonth
```

ScheduleView 和 IncomeView 已经使用此口径，保持不变。

**补偿机制：** 在 `TomatoScheduleApp` 中增加 `scenePhase` 监听，回前台时触发 `autoCompletePastLessons()` 将 `isCompleted` 持久化。`ScheduleView.onAppear` 中的调用也保留。这样 `isCompleted` 标记会在合理时机追平 `endTime < .now` 的实时判断。

```swift
@main
struct TomatoScheduleApp: App {
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
}
```

### 8.3 预估收入定义

| 术语 | 定义 | 计算方式 |
|------|------|----------|
| 实际收入 | 已完成课程的确认收入 | `lessons.filter { $0.isCompleted \|\| $0.endTime < .now }.sum { effectivePrice }` |
| 预估收入 | 范围内所有课程（含未完成）的总预期收入 | `lessons.sum { effectivePrice }` |

注：由于 F5 已在创建时冻结价格，所有课程都有确定的 `effectivePrice`，预估收入是确定值而非估算值。

### 8.4 开关控制

新增 `@AppStorage("showEstimatedIncome")`，默认 `true`。

在 `SettingsView` 的"显示"section 添加：

```swift
Toggle("显示预估收入", isOn: $showEstimatedIncome)
```

### 8.5 各视图的展示变更

**StatisticsBar**（`StatisticsBar.swift`）：

当前格式：
```
4月排课48次，已上32次，收入¥2400
```

新格式（开关开启时）：
```
4月排课48次，已上32次，收入¥2400（预估¥4800）
```

新格式（开关关闭时）：
```
4月排课48次，已上32次，收入¥2400
```

新增参数 `estimatedIncome: Double`。

**IncomeView**（`IncomeView.swift`）：

Summary cards 区域从 3 卡变为 4 卡（开关开启时）：

```
┌──────────┐ ┌──────────┐
│ 本月收入 │ │ 预估收入 │
│ ¥2400    │ │ ¥4800    │
├──────────┤ ├──────────┤
│ 已完成   │ │ 课均     │
│ 32 节    │ │ ¥75      │
└──────────┘ └──────────┘
```

布局调整：从 `HStack(spacing: 12)` 改为 2x2 网格 `LazyVGrid(columns: 2)`。开关关闭时不显示"预估收入"卡，恢复 3 卡横排布局。

图表中可选叠加预估部分：已完成用实色柱状图，未完成部分用半透明叠加。

**SettingsView**（`SettingsView.swift`）：

收入概览 section 每行追加预估值（开关开启时）：

```
今日    ¥300   (预估 ¥600)
本周    ¥1200  (预估 ¥2400)
本月    ¥2400  (预估 ¥4800)
```

### 8.6 计算逻辑

在 `ScheduleView` 中新增：

```swift
private var statisticsEstimatedIncome: Double {
    lessonsInRange.reduce(0) { $0 + $1.effectivePrice }
}
```

在 `IncomeView` 中新增：

```swift
private var allLessonsInRange: [Lesson] {
    let range = currentRange
    return allLessons.filter { $0.date >= range.start && $0.date < range.end }
}

private var estimatedIncome: Double {
    allLessonsInRange.reduce(0) { $0 + $1.effectivePrice }
}
```

在 `SettingsView` 中新增（与 incomeForToday/Week/Month 对应）：

```swift
private var estimatedForToday: Double {
    let today = DateHelper.startOfDay(.now)
    let tomorrow = DateHelper.endOfDay(.now)
    return allLessons.filter { $0.date >= today && $0.date < tomorrow }
        .reduce(0) { $0 + $1.effectivePrice }
}
// 同理 estimatedForWeek / estimatedForMonth
```

### 8.7 涉及文件

| 文件 | 变更 |
|------|------|
| `Views/Schedule/StatisticsBar.swift` | 新增 estimatedIncome 参数和显示 |
| `Views/Schedule/ScheduleView.swift` | 统一 isCompleted 口径 + 计算 statisticsEstimatedIncome |
| `Views/Income/IncomeView.swift` | 统一 isCompleted 口径 + 预估收入卡片 + 图表叠加 |
| `Views/Settings/SettingsView.swift` | 收入概览追加预估值 + 新增 showEstimatedIncome Toggle |

---

## 9. 数据迁移与兼容性

### 9.1 Schema 变更评估

| 需求 | 是否需要 schema 变更 | 原因 |
|------|---------------------|------|
| F1 滑动 | 否 | 纯 UI 变更 |
| F2 批量排课 | 否 | 复用现有 Lesson model，`lessonNumber` 自动递增写入 |
| F3 时间选择器 | 否 | 纯 UI 组件，DatePicker 兜底保证旧数据可编辑 |
| F4 课次优化 | 否 | 使用已有 `lessonNumber` + computed property 补充 |
| **F5 价格冻结** | **是** | **新增 `isManualPrice: Bool` 字段（默认 false）** |
| F6 预估收入 | 否 | 使用 `@AppStorage` + computed property |

**结论：** F5 需要一次轻量 schema 变更（新增带默认值的 Bool 属性），SwiftData 自动处理。其他需求无 schema 变更。F4 和 F5 涉及存量数据的语义迁移（见下文），需要谨慎处理。

### 9.2 F5 价格冻结 — 存量数据迁移

需要处理三类存量数据：

**场景 A：** `isPriceOverridden == false` → V4 自动定价、从未冻结。需要按升级当下费率补一份快照。
**场景 B：** `isPriceOverridden == true && isCompleted == false` → V4 时用户手动设了价格（V4 系统冻结只发生在课程完成时，未完成课的 `isPriceOverridden=true` 必定来自用户手动操作）。标记 `isManualPrice = true`。
**场景 C：** `isPriceOverridden == true && isCompleted == true` → 无法确定是用户手动改价还是系统自动冻结（`autoCompletePastLessons()` 和手动完成都会冻结）。默认标记 `isManualPrice = false`。

**场景 C 的取舍：** 将已完成+已冻结课默认视为系统冻结（`isManualPrice = false`），而非手动改价。理由：
- V4 中绝大多数已完成课的 `isPriceOverridden=true` 来自系统自动冻结，用户手动改已完成课价格是极少数场景
- 如果反过来（默认标 `isManualPrice = true`），会导致所有已完成课编辑时误显示"自定义"，且 `priceOverride=0` 的已完成课会被 `priceDisplayText` 误显示为"免费"，影响范围更大
- 已完成课不参与"更新未来课程"逻辑，`isManualPrice` 的值对它们没有业务影响

**迁移逻辑（`TomatoScheduleApp.swift`）：**

```swift
private func migrateV5PriceFreeze() {
    guard !UserDefaults.standard.bool(forKey: "v5PriceMigrationDone") else { return }
    guard let container = try? ModelContainer(for: Course.self, Lesson.self) else { return }
    let context = container.mainContext
    let descriptor = FetchDescriptor<Lesson>()
    guard let lessons = try? context.fetch(descriptor) else { return }
    
    var changed = false
    for lesson in lessons {
        if lesson.isPriceOverridden && !lesson.isCompleted {
            // 场景 B：未完成 + 已冻结 → 必定是用户手动设价
            lesson.isManualPrice = true
            changed = true
        } else if lesson.isPriceOverridden && lesson.isCompleted {
            // 场景 C：已完成 + 已冻结 → 默认视为系统冻结
            lesson.isManualPrice = false
            // (isManualPrice 新字段默认已是 false，这里显式写入以表达意图)
            changed = true
        } else if !lesson.isPriceOverridden {
            // 场景 A：从未冻结 → 按升级当下费率补快照
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

**已知限制（场景 A）：** 对于 V4 中从未冻结过的课程（场景 A），升级时只能按**升级当下的 `course.hourlyRate`** 补快照，无法恢复到**排课当时的费率**（因为 V4 根本没有保存排课时的费率快照）。这是 V4 数据结构决定的上限，不是实现疏漏。

**已知限制（场景 C）：** 极少数 V4 中用户手动改过价格的已完成课，升级后编辑页会显示"自动计算"而非"自定义"。用户可以手动切换回"自定义"。

**执行时机：** `TomatoScheduleApp.body` 的 `.onAppear` 中，在 `autoCompletePastLessons()` 之前调用。

**幂等性保证：** 通过 `UserDefaults` flag 确保只执行一次。

### 9.3 F4 课次 — 旧数据处理

- `lessonNumber` 字段保留，继续作为持久化存储
- 已有 `lessonNumber > 0` 的课程：显示时优先使用存储值，语义不变
- 已有 `lessonNumber == 0` 的课程：通过 `displaySequenceText` 自动推导显示
- 不执行任何批量写入或改写

### 9.4 `@AppStorage` 新增键

| 键名 | 默认值 | 用途 |
|------|--------|------|
| `showEstimatedIncome` | `true` | F6 预估收入开关 |

现有键不变：
| 键名 | 默认值 | 用途 |
|------|--------|------|
| `showIncomeInCourseList` | `true` | 收入显示开关（保持不变） |

---

## 10. 涉及文件清单

### 新建文件

| 文件 | 用途 |
|------|------|
| `Views/Lesson/BatchLessonFormView.swift` | F2 批量排课表单 |
| `Views/Components/TimeSlotPicker.swift` | F3 时间段选择器组件（含网格 + DatePicker 双模式） |

### 修改文件

| 文件 | 涉及需求 | 主要变更 |
|------|----------|----------|
| `Models/Course.swift` | F4 | 新增 `sortedLessons`、`autoIndex(for:)` |
| `Models/Lesson.swift` | F4/F5 | 新增 `isManualPrice` 字段 + `displaySequenceText` + 更新 `priceDisplayText` |
| `App/TomatoScheduleApp.swift` | F5/F6 | 新增 `migrateV5PriceFreeze()` + `scenePhase` 监听自动补全 |
| `Views/Schedule/CalendarHeaderView.swift` | F1 | 添加 DragGesture + transition 动画 + moveWeek 周切换逻辑 |
| `Views/Schedule/MonthGridView.swift` | F1 | 添加 `.id(displayedMonth)` 配合 transition |
| `Views/Schedule/WeekStripView.swift` | F1 | 添加 `.id()` 配合周切换 transition |
| `Views/Schedule/ScheduleView.swift` | F2/F6 | toolbar Menu 改造 + 统一 isCompleted 口径 + 预估收入计算 |
| `Views/Schedule/StatisticsBar.swift` | F6 | 新增 estimatedIncome 参数和显示 |
| `Views/Schedule/LessonTimeGroup.swift` | F4 | 使用 `displaySequenceText` |
| `Views/Schedule/LessonDetailCard.swift` | F4 | progressParts 移除课次（不与头部重复） |
| `Views/Lesson/LessonFormView.swift` | F3/F4/F5 | TimeSlotPicker 替换 + 课次输入框提升 + 创建时冻结价格 + Picker 绑定 isManualPrice |
| `Views/Course/CourseFormView.swift` | F5 | 两阶段保存 + 费率变更确认对话框 |
| `Views/Income/IncomeView.swift` | F6 | 统一 isCompleted 口径 + 预估收入卡片 + 图表叠加 |
| `Views/Settings/SettingsView.swift` | F6 | 统一已完成口径(+endTime兜底) + 预估收入 Toggle + 概览追加预估 |
| `Views/Settings/CalendarImportView.swift` | F5 | performImport() 中导入课时后调用 freezePrice() |
| `Services/CalendarSyncService.swift` | F4 | populateEvent() 改用 displaySequenceText + 去掉"第"前缀 |

### 未修改文件

| 文件 | 原因 |
|------|------|
| `Views/Course/CourseListView.swift` | 本轮无变更 |
| `Views/Components/DotIndicator.swift` | 无变更 |
| `Views/Components/ColorPickerGrid.swift` | 无变更 |
| `Views/Components/EmptyStateView.swift` | 无变更 |
| `Helpers/DateHelper.swift` | 无变更 |
| `Helpers/PresetColors.swift` | 无变更 |

---

## 11. 实现优先级与依赖关系

### 依赖图

```
F5 (价格冻结) ─── 无依赖，最先实施（含数据迁移）
       │
       ├──→ F2 (批量排课) ─── 依赖 F5（创建时冻结价格）+ F3（时间选择器）
       │         │
       │         └──→ F3 (时间选择器) ─── 可独立开发
       │
       └──→ F6 (预估收入) ─── 依赖 F5（价格冻结后预估才有意义）

F1 (滑动切换) ─── 独立，无依赖
F4 (课次优化) ─── 独立，无依赖（但 CalendarSyncService 变更需在 F2 批量排课前完成）
```

### 推荐实施顺序

| 阶段 | 需求 | 理由 |
|------|------|------|
| Phase 1 | F5 价格冻结 + 数据迁移 | 基础设施，F2/F6 依赖此项；包含数据迁移，应最先验证 |
| Phase 2 | F4 课次优化 + CalendarSyncService | 独立 + 为 F2 的课次编号和日历同步做好基础 |
| Phase 3 | F3 时间选择器 | 独立 UI 组件，可先开发后集成 |
| Phase 4 | F1 滑动切换 | 独立 UI 优化 |
| Phase 5 | F2 批量排课 | 依赖 F3、F4、F5，最复杂的新功能 |
| Phase 6 | F6 预估收入 | 依赖 F5，是最后的展示层增强 |

---

## 12. 风险与注意事项

### 12.1 数据安全

| 风险 | 缓解措施 |
|------|----------|
| V5 价格迁移中断 | `UserDefaults` flag 确保幂等，可安全重跑 |
| `lessonNumber` 旧值丢失 | 保留字段、保留读取、保留写入，旧值作为第一优先级显示 |
| 批量创建大量课程 | 单次批量创建上限 100 节，防止误操作 |
| 0 元/未定价课程价格追溯 | 冻结规则覆盖所有价格（含 0 元），无死角 |
| 日历导入课程价格漂移 | CalendarImportView 创建时同步冻结价格 |

### 12.2 性能

| 关注点 | 评估 |
|--------|------|
| `course.autoIndex(for:)` 排序开销 | 仅在 `lessonNumber == 0` 时触发，单课程几十到几百节，O(n log n) 可忽略 |
| 批量创建后日历同步 | 复用现有 `syncLesson` 逐一同步，可优化但非必需 |
| 预估收入计算 | 与实际收入计算逻辑相同，无额外开销 |

### 12.3 UX 注意事项

| 要点 | 说明 |
|------|------|
| 滑动方向 | 严格遵循用户原话：左滑 = 上个月，右滑 = 下个月 |
| 时间选择器兼容 | 旧课时不对齐网格时自动切到 DatePicker，不丢失精度 |
| 课次稳定性 | 已有 `lessonNumber > 0` 的课次不会因增删其他课而变化 |
| 滑动手势 vs 滚动 | DragGesture 挂在日历区域（非 List），与纵向滚动正交 |
| 时间网格高度 | 28 个按钮在 4 列布局下约 280pt，iPhone SE 上可能偏高，考虑 ScrollView 包裹或减少行数 |
| 批量排课预览 | 预览列表支持滚动，最多约 100 行 |
| 月份切换动画 | 动画进行中禁用重复触发，防止快速连续滑动造成状态混乱 |
| 费率变更事务 | 两阶段保存确保用户确认前不写入模型，取消操作无副作用 |

### 12.4 测试要点

| 测试场景 | 覆盖需求 |
|----------|----------|
| 升级后 V4 已冻结课（isPriceOverridden=true）价格不变 | F5 迁移-已冻结 |
| 升级后 V4 未冻结课按升级当下费率补快照（非排课时费率，这是 V4 数据结构上限） | F5 迁移-未冻结 |
| 升级后 V4 未完成+已冻结课标记为 isManualPrice=true | F5 迁移-手动识别 |
| 升级后 V4 已完成+已冻结课标记为 isManualPrice=false | F5 迁移-系统冻结识别 |
| 修改 hourlyRate 后已排课程价格不变 | F5 核心逻辑 |
| 修改 hourlyRate 选择"更新未来课程"后正确更新 | F5 确认流 |
| 修改 hourlyRate 选择"取消"后模型未被修改 | F5 两阶段保存 |
| 从日历导入课程后价格被冻结 | F5 CalendarImportView |
| 批量创建跨月课程（日期正确） | F2 日期生成 |
| 批量创建后课次 lessonNumber 自动递增且持久化，不与旧数据撞号 | F2 + F4 |
| 编辑已有 lessonNumber > 0 的课时，值保持不变 | F4 |
| 新建 lessonNumber == 0 的课时，displaySequenceText 显示正确 | F4 |
| 修改 totalLessons 后触发日历重同步，备注无"第第"双重前缀 | F4 + CalendarSync |
| 编辑 07:30-09:10 的旧课时，自动进入 DatePicker 模式 | F3 兼容性 |
| 编辑 14:00-16:00 的课时，显示网格模式 | F3 正常路径 |
| 时间网格起始 21:00 时 1.5h/2h/3h 按钮禁用 | F3 边界 |
| 编辑 21:30-22:30 的课时，自动进入 DatePicker 模式（不被网格误收） | F3 边界 |
| 新建课时选"自定义价格 ¥200"，isManualPrice=true，freezePrice 不覆盖 | F5 写入顺序 |
| 新建自动定价课时，编辑时 Picker 显示"自动计算"（非"自定义"） | F5 isManualPrice |
| 修改费率后选"全部不更新"，再编辑已冻结课时，编辑页显示旧快照金额（非新费率） | F5 编辑态快照 |
| hourlyRate=99、时长 90 分钟，编辑页和列表页均显示 ¥148.5（非 ¥148） | F5 价格格式化 |
| 已有手动价 ¥50 的课时，编辑切回"自动计算"保存后，价格变为按当前费率和时长计算的冻结价 | F5 手动切自动 |
| hourlyRate=0 时排课，编辑时不显示"免费"（显示为未定价/无价格） | F5 priceDisplayText |
| 用户手动设价 ¥0 的课时，显示"免费" | F5 priceDisplayText |
| 费率更新"更新未来课程"跳过 isManualPrice=true 的试听课 | F5 费率更新 |
| 预估收入 = 实际收入 + 未完成收入 | F6 |
| 关闭预估收入开关后各视图不显示预估 | F6 开关 |
| 用户停留 app 不退出，课程结束后切到 Income 页，实际收入已更新 | F6 scenePhase |
| 某课程有 3 节旧课(lessonNumber=0)，批量排课从第 4 节开始 | F4 防撞号 |
| 左滑上个月、右滑下个月（月视图） | F1 方向验证 |
| 周视图左右滑动跨月后 displayedMonth 同步更新 | F1 状态同步 |
| 周视图滑动跨月后展开月视图，显示正确月份 | F1 状态同步 |
| 左滑到 1 月、右滑到 12 月（跨年） | F1 边界 |
| iOS 17 + iOS 18 兼容性 | F1（ScrollCalendarFoldModifier 分支） |

