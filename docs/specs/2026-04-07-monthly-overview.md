# 月度排课总览 — 设计规格文档

> 日期：2026-04-07
> 版本：final（经 5 轮 codex 评审定稿）
> 状态：已通过评审，待实施

---

## 1. 背景与目标

教师约课时需要向学生展示"这个月哪些时间已经排课了、哪些时间是空闲的"。当前 app 的课表只能逐日查看——点击某天才能看到当天的课时列表，无法总览全月排课密度。教师希望有一个视图可以**快速了解全月忙闲**，并能**导出分享图发给学生**协商约课。

**核心目标：**
- 月网格总览：一屏看到全月每天的忙闲程度（无需滚动）
- 日详情下钻：点击某天查看当天精确的时间块分布
- 导出分享图：生成独立排版的图片，学生无需安装 app 即可读懂

**明确不做的：**
- 不是预约系统（学生不直接在 app 里选课）
- 不改数据模型（完全基于现有 Lesson/Course）

---

## 2. 信息架构：三层分离

| 层级 | 名称 | 目的 | 可截图分享？ |
|------|------|------|------------|
| 第一层 | 月网格总览 | 一屏看全月粗粒度忙闲趋势 | **是（主要分享方式）** |
| 第二层 | 日时间轴详情 | 教师自查某天精确课时（含课程/学生信息） | **否（仅教师自用）** |
| 第三层 | 导出分享图 | 生成详细长图发给学生 | **是（补充分享方式）** |

三层共享同一份聚合数据，但各自独立排版。

**分享责任明确划分：**
- 系统截图 → 月网格（一屏可容纳，主要方式）
- 导出图片 → 详细时间轴长图（补充方式）
- 日详情 → **不用于分享**，仅教师下钻自查，允许滚动

---

## 3. 第一层：月网格总览

### 3.1 布局

复用现有 `MonthGridView` 的 7 列日历网格风格，但每个日期单元格增加一个**垂直忙闲指示条**（mini timeline bar）：

```
┌─ 月度排课总览 ──────────────────────────┐
│                                          │
│  ◀  2026年4月  ▶              [导出图片] │
│                                          │
│  一    二    三    四    五    六    日   │
│ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐
│ │    ││    ││ 1  ││ 2  ││ 3  ││ 4  ││ 5  │
│ │    ││    ││▐  ▐││▐▐ ▐││▐▐▐▐││▐  ▐││    │
│ │    ││    ││ 2节││ 3节││ 5节││ 2节││    │
│ └────┘└────┘└────┘└────┘└────┘└────┘└────┘
│ ...                                      │
│                                          │
│  ■ 已排课    □ 可约时间                   │
└──────────────────────────────────────────┘
```

### 3.2 日期单元格设计

每个单元格约 **50×72pt**（7 列在 iPhone SE 375pt 宽上每列约 50pt）：

```
┌──────┐
│  7   │  ← 日期数字（12pt, bold if today）
│ ▐██▐ │  ← 垂直忙闲条（8×40pt, 1小时离散格子）
│  3节 │  ← 课时数角标（10pt, secondary）
└──────┘
```

**垂直忙闲条（核心组件）— 1 小时 bins 离散格子：**
- 高度 40pt，宽度 8pt，圆角 2pt
- 纵轴按 `timeRange`（动态，见 3.3）切成 N 个 **1 小时**槽位
- 默认 14 小时范围（8-22）= 14 格，每格约 `40/14 ≈ 2.9pt`，满足最小可见性
- 最大范围 24 小时 = 24 格，每格约 `40/24 ≈ 1.7pt`，仍可辨认
- 每个槽位只有两种状态：占用（主题色 teal 填充）或空闲（灰色 `.quaternary.opacity(0.3)`）
- 某小时内只要有任何课时（哪怕只占 10 分钟），该格即标记为占用
- **统一主题色**，不按课程分色（隐私安全）

**为什么用 1 小时而非 30 分钟：** 月网格承担"粗粒度忙闲分布"，不需要精确到半小时。40pt 高度内放 28 个 30 分钟格子每格仅 1.4pt，数学上无法满足最小可见要求。精确分布留给日详情和导出图。

**单元格状态：**

| 状态 | 样式 |
|------|------|
| 今天 | 日期数字用金色圆底高亮（与现有 MonthGridView 一致） |
| 有课 | 显示忙闲条 + 课时数 |
| 无课 | 只显示日期数字，忙闲条为纯灰色 |
| 非当月（补齐天） | 整格 `opacity(0.3)` |
| 过去日期 | 文字 `opacity(0.5)` |

**点击交互：** 点击某天进入第二层（日时间轴详情）。

### 3.3 动态时间轴范围

**不固定 8:00-22:00。** 根据当月实际课时数据动态计算：

```swift
private var timeRange: (start: Int, end: Int) {
    let lessons = lessonsInMonth
    guard !lessons.isEmpty else { return (8, 22) }

    let cal = DateHelper.calendar
    let earliest = lessons.map { cal.component(.hour, from: $0.startTime) }.min() ?? 8
    let latest = lessons.map {
        let h = cal.component(.hour, from: $0.endTime)
        let m = cal.component(.minute, from: $0.endTime)
        return m > 0 ? h + 1 : h
    }.max() ?? 22

    // 向外各补 1 小时安全边距，钳制到 0-24
    return (max(earliest - 1, 0), min(latest + 1, 24))
}
```

这样 7:30 开始的课不会被截断，23:00 结束的课也能正确显示。

### 3.4 隐私安全设计

月网格是教师截图发给学生的主要界面。**忙闲条统一使用主题色（teal）**，不按课程分色——避免泄露课程信息。学生只需知道"哪些时间段被占用了"，不需要知道是什么课。

底部显示简洁说明：

```
■ 已排课    □ 可约时间
月网格为粗粒度忙闲趋势，精确时间以导出图为准
```

**月网格的产品边界：** 月网格按 1 小时粒度标记忙闲——某小时内只要有任何课时（哪怕只占 10 分钟），该格即显示为占用。它用于**快速判断全月忙闲分布**，不是精确可约时间图。精确的时间段分布由导出分享图和日详情承担。

**截图友好验证：** 系统截图可以完整捕获月网格（一屏可容纳），教师无需额外操作即可分享给学生。

### 3.5 屏幕空间验证

- 月份导航栏：44pt
- 星期标题行：20pt
- 5 周 × 72pt/行 = 360pt（最多 6 周 = 432pt）
- 图例说明（两行）：40pt
- **总计：约 464-536pt**
- iPhone SE 安全区内高度约 **600pt**
- **结论：一屏内完全可容纳，无需滚动。**

---

## 4. 第二层：日时间轴详情

### 4.1 定位与入口

**日详情仅供教师自查。** 它是教师下钻查看"某天的精确时间块分布"的工具，允许滚动，直接显示课程和学生信息。日详情一般不发给学生——月网格和导出图承担分享职责。

从月网格点击某天进入。使用 `.sheet` 展示（半屏，detent `.medium` 和 `.large`）。

### 4.2 布局

类似 macOS Calendar 日视图，纵向为时间轴，横向为课时块：

```
┌─ 4月7日 周一 ────────────────────┐
│                                   │
│  08:00 ┃                          │
│  09:00 ┃ ██ 雅思阅读(线上)·石宇 ██│
│  10:00 ┃ █████████████████████    │
│  11:00 ┃                          │
│  12:00 ┃                          │
│  14:00 ┃ ██ 雅思阅读(线下)·傅褚备█│
│  15:00 ┃ █████████████████████    │
│  16:00 ┃ █████████████████████    │
│  17:00 ┃                          │
│  18:00 ┃ ██ 雅思阅读(线上)·Hailey█│
│  19:00 ┃ █████████████████████    │
│  20:00 ┃                          │
└───────────────────────────────────┘
```

### 4.3 课时块渲染规格

每个课时块：
- **颜色：** 课程专属颜色（`course.colorHex`）
- **块内文字：** 课程名 + 学生名，`.caption` 白色
- **高度：** 按时长比例（`1 小时 = 60pt`）
- **位置：** 按 startTime 映射到纵轴

### 4.4 重叠课时分组

如果同一天存在时间重叠的课时，先用 sweep-line 归组：

```swift
// 检测重叠组 — 维护组的 maxEndTime 确保链式重叠正确归组
private func overlapGroups(for lessons: [Lesson]) -> [[Lesson]] {
    let sorted = lessons.sorted { $0.startTime < $1.startTime }
    var groups: [[Lesson]] = []
    var current: [Lesson] = []
    var maxEnd: Date = .distantPast

    for lesson in sorted {
        if lesson.startTime < maxEnd {
            current.append(lesson)
            maxEnd = max(maxEnd, lesson.endTime)
        } else {
            if !current.isEmpty { groups.append(current) }
            current = [lesson]
            maxEnd = lesson.endTime
        }
    }
    if !current.isEmpty { groups.append(current) }
    return groups
}
```

**为什么用 maxEndTime：** 链式重叠（如 A:9-12, B:10-11, C:11:30-13）中，C 与 A 仍然重叠（11:30 < 12:00），但如果只比较 `current.last`（B），C.startTime 11:30 > B.endTime 11:00 会错误地开新组。

### 4.5 重叠组内的 lane 分配

分组后，每组内的课时分配到最多 2 列（lane）中并排显示：

```swift
/// 贪心 lane 分配：按开始时间遍历，放入最早空出的列
private func assignLanes(for group: [Lesson]) -> [(lesson: Lesson, lane: Int)] {
    let sorted = group.sorted { $0.startTime < $1.startTime }
    var laneEndTimes: [Date] = []
    var result: [(Lesson, Int)] = []

    for lesson in sorted {
        if let available = laneEndTimes.firstIndex(where: { $0 <= lesson.startTime }) {
            laneEndTimes[available] = lesson.endTime
            result.append((lesson, available))
        } else if laneEndTimes.count < 2 {
            result.append((lesson, laneEndTimes.count))
            laneEndTimes.append(lesson.endTime)
        } else {
            result.append((lesson, -1))  // 溢出
        }
    }
    return result
}
```

**渲染规则：**
- `lane == 0`：占左半宽度
- `lane == 1`：占右半宽度
- `lane == -1`：不渲染块，在组底部显示 `+N 冲突` badge
- 重叠区域左侧添加 3pt 橙色竖线作为视觉警告

### 4.6 时间轴范围

使用与月网格相同的动态 `timeRange`（该月最早-最晚课时），确保日详情和月总览的时间刻度一致。

### 4.7 底部操作

- "在课表中查看" 按钮：关闭 sheet，跳转到主课表的该日期

---

## 5. 第三层：导出分享图

### 5.1 设计原则

**系统截图是主要分享方式。** 月网格总览一屏可容纳，教师直接用系统截图即可分享给学生。

导出分享图是**补充功能**——生成更详细的"每天一行时间轴"长图卡片，适合需要展示精确时间段的场景。它是独立编排的自包含卡片，不复用交互视图布局。

### 5.2 隐私安全

导出图发给学生，**不得包含任何课程名称或学生姓名**。所有已排课时段统一显示为"已排课"色块（主题色 teal），学生只需关心"哪些时间是空闲的"。

### 5.3 布局

采用"每天一行水平时间轴"，适合长图导出：

```
┌─────────────────────────────────────────────┐
│                                             │
│         番茄课表 · 4月排课总览               │
│                                             │
│    ■ 已排课（不可约）   □ 空闲（可约）       │
│                                             │
│       8    10    12    14    16    18   20   │
│                                             │
│  4/7  一  ░░████████░░░░████████░░████████░░│
│  4/8  二  ░░░░░░░░████████░░░░░░░░████████░░│
│  4/9  三  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│  4/10 四  ░░░░████████░░░░░░░░████████░░░░░░│
│  ...                                        │
│                                             │
│  导出时间：2026年4月7日 21:30                │
│  灰色区域为可约时间，欢迎联系老师预约         │
└─────────────────────────────────────────────┘
```

### 5.4 与交互视图的差异

| 维度 | 交互视图（月网格） | 导出图 |
|------|-------------------|--------|
| 目的 | 浏览 + 点击下钻 | 转发给学生阅读 |
| 密度 | 低（忙闲条 + 课时数） | 中（每天一行时间轴） |
| 隐私 | 无课程/学生信息 | 无课程/学生信息 |
| 背景 | 跟随系统主题 | 固定白色 |
| 字号 | 系统动态字号 | 固定值（确保缩小后可读） |
| 尺寸 | 受屏幕限制（一屏可截） | 固定 390pt 宽，高度按天数动态 |

### 5.5 导出图的自包含信息

必须包含：
- 月份标题（`番茄课表 · 4月排课总览`）
- 图例说明（`■ 已排课 □ 空闲`）
- 导出时间戳
- 引导文案（`灰色区域为可约时间，欢迎联系老师预约`）

**不包含：** 课程名称、学生姓名、课程颜色图例（隐私保护）。

### 5.6 时间轴范围

使用动态 `timeRange`（与月网格一致）。无课时在时间轴范围外的静默截断风险。

### 5.7 重叠课时

导出图中重叠课时用**深色叠加**标记：重叠区域颜色加深（`opacity(1.0)` 而非 `0.85`）。不显示冲突详情（隐私）。

### 5.8 只导出未来日期

导出图默认只包含**今天及以后**的日期行（过去的日期对约课无意义）。如果当月所有日期都已过去，显示提示"本月课程已全部结束"。

### 5.9 渲染与分享

```swift
@MainActor
private func exportImage() {
    let content = MonthlyExportCard(
        month: displayMonth,
        lessonsByDate: lessonsByDate,
        timeRange: timeRange
    )
    .frame(width: 390)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 3
    if let image = renderer.uiImage {
        shareItems = [image]
        showShareSheet = true
    }
}
```

---

## 6. 入口设计

### 6.1 位置

`ScheduleView` toolbar leading 区域，与"今天"按钮并列，icon-only：

```swift
ToolbarItem(placement: .topBarLeading) {
    HStack(spacing: 12) {
        Button("今天") { ... }
            .disabled(DateHelper.isSameDay(selectedDate, .now))

        Button {
            showingOverview = true
        } label: {
            Image(systemName: "rectangle.grid.1x2")
        }
        .accessibilityLabel("月度排课总览")
    }
}
```

### 6.2 展示方式

`.fullScreenCover`（全屏展示，最大化利用空间）。日详情使用内部 `.sheet(detents: [.medium, .large])`。

---

## 7. 数据层

**无 schema 变更。** 完全基于现有 Lesson 字段。

### 7.1 聚合数据结构

```swift
// 日详情用的精确时间块（教师自查页面，含课程/学生信息）
struct TimeBlock: Identifiable {
    let id: UUID
    let startMinutes: Int     // 从 timeRange.start 起的分钟偏移
    let durationMinutes: Int
    let colorHex: String      // 课程颜色，驱动详情页块颜色
    let courseName: String
    let studentName: String
}

// 月数据
private var lessonsInMonth: [Lesson] { ... }
private var lessonsByDate: [Date: [Lesson]] { ... }

// 动态时间轴范围
private var timeRange: (start: Int, end: Int) { ... }
```

### 7.2 忙闲条数据 — 1 小时 bins

月网格忙闲条使用**1 小时粒度的离散槽位数组**：

```swift
/// 某天按 1 小时切成槽位，某小时内只要有课即标记占用
/// bins[i] = true 表示第 i 小时内有课
private func busyBins(for date: Date) -> [Bool] {
    let totalSlots = timeRange.end - timeRange.start  // 1小时一格
    guard totalSlots > 0 else { return [] }
    var bins = Array(repeating: false, count: totalSlots)

    let lessons = lessonsByDate[DateHelper.startOfDay(date)] ?? []
    let cal = DateHelper.calendar
    for lesson in lessons {
        let startH = cal.component(.hour, from: lesson.startTime)
        let startM = cal.component(.minute, from: lesson.startTime)
        let endH = cal.component(.hour, from: lesson.endTime)
        let endM = cal.component(.minute, from: lesson.endTime)

        let startSlot = max(startH - timeRange.start, 0)
        let endSlot = min(endM > 0 ? endH - timeRange.start + 1 : endH - timeRange.start, totalSlots)
        // endM > 0 时向上取整：9:10-10:20 占据 9、10 两个小时格

        for i in startSlot..<endSlot {
            bins[i] = true
        }
    }
    return bins
}
```

**渲染规则：**
- 每格高度 = `40pt / totalSlots`（默认 14 格 ≈ 2.9pt/格，最大 24 格 ≈ 1.7pt/格）
- 占用格：主题色 teal 填充
- 空闲格：`.quaternary.opacity(0.3)`
- 重叠课时不重复累计（bins 是 bool，多节课占同一小时只标记一次）

---

## 8. 文件结构

### 新建文件

| 文件 | 用途 |
|------|------|
| `Views/Schedule/MonthlyOverviewView.swift` | 月度总览容器（月网格 + 导航 + 导出入口） |
| `Views/Schedule/DayAvailabilityCell.swift` | 月网格中的单天单元格（日期 + 忙闲条 + 课时数） |
| `Views/Schedule/DayScheduleDetailView.swift` | 日时间轴详情（小时刻度 + 课时块 + 重叠处理） |
| `Views/Schedule/MonthlyExportCard.swift` | 导出分享图（自包含卡片布局，供 ImageRenderer） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Views/Schedule/ScheduleView.swift` | toolbar 添加总览按钮 + `.fullScreenCover` |

---

## 9. 实现优先级

| 阶段 | 内容 | 理由 |
|------|------|------|
| Phase 1 | MonthlyOverviewView + DayAvailabilityCell | 月网格总览是核心价值 |
| Phase 2 | DayScheduleDetailView | 日详情下钻，支持点击查看 |
| Phase 3 | MonthlyExportCard + 分享功能 | 导出图是分享场景的关键 |
| Phase 4 | ScheduleView 入口 | 最后接入主导航 |

---

## 10. 风险与注意事项

| 风险 | 缓解措施 |
|------|----------|
| 忙闲条在小屏上过窄（iPhone SE 每列约 50pt） | 忙闲条固定 8pt 宽，不随屏幕缩放 |
| 月网格超过 5 周需要 6 行（如 2 月起始周日） | 6 行 × 72pt = 432pt，仍在一屏内 |
| 导出图色块无课程信息 | 统一主题色 + "已排课/可约"图例，隐私安全 |
| 早于 0 点或晚于 24 点的课时 | 钳制到 0-24 范围 |
| 重叠课时导致日详情拥挤 | 双列并排 + 上限 badge |
| ImageRenderer 在后台渲染慢 | 显示 loading indicator |
| 短课时（30 分钟）所在小时格正确标记为占用 | 1 小时 bins 粒度 |

---

## 11. 测试要点

| 测试场景 | 覆盖需求 |
|----------|----------|
| 4 月份（30 天，5 周）月网格正确显示 | 基本布局 |
| 2 月份（28 天，4 周）月网格正确显示 | 边界月份 |
| 6 周月份（如某些月从周六开始）一屏可容纳 | 空间验证 |
| 某天有 3 节课，忙闲条对应槽位显示主题色 | 多课时渲染 |
| 某天无课，忙闲条为纯灰色，课时数不显示 | 空日 |
| 课时在 7:00-8:00，动态时间轴包含该范围 | 动态轴范围 |
| 课时在 22:00-23:30，动态时间轴包含该范围 | 动态轴范围 |
| 无课月份，时间轴默认 8:00-22:00 | 空月份 |
| 今天的单元格有金色圆底高亮 | 今日标记 |
| 过去日期文字降低透明度 | 过去淡化 |
| 点击某天弹出日时间轴详情 sheet | 日详情下钻 |
| 日详情显示课程名+学生名+课程颜色（教师自查） | 日详情内容 |
| 两节课时间重叠，日详情中双列并排+橙色警告线 | 重叠处理 |
| 链式重叠（A:9-12, B:10-11, C:11:30-13）正确归为同一组 | 重叠分组 |
| 月网格系统截图可完整捕获全月信息 | 截图友好 |
| 月网格忙闲条统一主题色，不泄露课程信息 | 隐私安全 |
| 导出图为白色背景，含标题/图例/导出时间/引导文案 | 分享图自包含 |
| 导出图不包含任何课程名称或学生姓名 | 导出隐私 |
| 导出图只包含今天及以后的日期 | 只导出未来 |
| 导出图在深色模式下仍为白底 | 主题一致 |
| 月份前后翻页正确 | 翻页 |
| 默认 14 小时范围忙闲条每格约 2.9pt，视觉可辨认 | 格子尺寸 |
| iPhone SE（375pt 宽）月网格不溢出 | 小屏兼容 |
| 稀疏月份（仅 1-2 节课）正常显示 | 稀疏数据 |
| 高密度月份（每天 3+ 节课）忙闲条不溢出 | 密集数据 |
