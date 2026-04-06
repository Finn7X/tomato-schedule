# V6 以学生为中心的课次追踪与收入筛选 — 设计规格文档

> 日期：2026-04-06
> 版本：V6 final（经 9 轮 codex review 定稿）
> 状态：已通过评审，待实施

---

## 目录

1. [背景与目标](#1-背景与目标)
2. [用户需求原文](#2-用户需求原文)
3. [需求分析](#3-需求分析)
4. [F7: 收入筛选增强（月份回溯 + 学生维度）](#4-f7-收入筛选增强月份回溯--学生维度)
5. [F8: 以学生为中心的课次与课时追踪](#5-f8-以学生为中心的课次与课时追踪)
6. [数据模型变更](#6-数据模型变更)
7. [涉及文件清单](#7-涉及文件清单)
8. [实现优先级与依赖关系](#8-实现优先级与依赖关系)
9. [数据迁移与兼容性](#9-数据迁移与兼容性)
10. [风险与注意事项](#10-风险与注意事项)
11. [测试要点](#11-测试要点)

---

## 1. 背景与目标

V5 上线后，收入系统和课次系统各自可用，但存在两个核心短板：

- **收入只能看"当前"**：周/月/年三档固定在当前时间，无法回看上个月或去年的收入，也无法按学生维度查看
- **课次以课程为中心**：`displaySequenceText` 按课程内排序计算课次，但教师的核心关注点是"这个学生上了多少节课、多少小时"，而非"这门课的第几节"

本轮迭代的核心目标：

- **收入可回溯、可筛选**：支持按月份前后翻阅，支持按学生/课程两种维度查看排行
- **课次以学生为中心**：课次和累计课时按学生全局计算，跨课程、跨月份，让教师一眼看到学生的学习进度
- **学生姓名必填**：强化学生数据的完整性

### 现有技术栈

| 项目 | 值 |
|------|-----|
| 语言 | Swift 5 / SwiftUI |
| 数据层 | SwiftData |
| 最低版本 | iOS 17.0 |
| 构建 | XcodeGen |

### 现有数据模型关键字段

**Lesson** (`Models/Lesson.swift`)：
- `studentName: String` — 当前为可选输入（空字符串代表未填）
- `lessonNumber: Int` — 手动/批量写入的课次编号，0 代表未填
- `displaySequenceText` — V5 新增，按课程内排序自动推导

**IncomeView** (`Views/Income/IncomeView.swift`)：
- `Period` 枚举：`.week` / `.month` / `.year`
- `currentRange` 固定取当前周/月/年，不可翻页
- `courseRanking` 仅按课程分组

---

## 2. 用户需求原文

1. 收入系统当前只能针对周月年进行选择筛选，但是如果希望以月为粒度查看之前月份的收入就无法实现。希望添加一个机制可以解决这个问题，除了定义查看粒度还可以选择月份
2. 当前以课程划分收入排行，希望也可以选择按学生划分
3. 在增加课时时学生姓名是必选的
4. 显示课次时以学生姓名来计算该学生历史上所有上过的课次数，自动计算这节课是该学生的第几节课
5. 学生姓名是唯一的（同名学生视为同一人）
6. 在课程的详情卡片上还显示学生的第几小时。例如：A 学生历史上上过 10 节 2 小时的课（共 20 小时），新增该学生的 2 小时课，第一节就是第 11 节、第 21-22 小时
7. 在收入中可以选择查看该学生的该月收入，以及历史月份收入

---

## 3. 需求分析

### 3.1 收入筛选增强（F7）

**现状问题：**

当前 `IncomeView` 的 `currentRange` 是 hardcoded 到"当前"周/月/年的：

```swift
// IncomeView.swift:24-37
private var currentRange: (start: Date, end: Date) {
    let cal = DateHelper.calendar
    let now = Date.now  // ← 固定为当前时间
    switch period {
    case .week:  return DateHelper.weekRange(for: now)
    case .month: return DateHelper.monthRange(for: now)
    case .year:  ...
    }
}
```

要做到月份回溯 + 学生筛选，需要：
1. 引入一个可调节的"参考日期"替代固定的 `Date.now`
2. 添加前/后翻页按钮
3. 新增"按学生分组"的排行视图

### 3.2 以学生为中心的课次追踪（F8）

**现状问题：**

当前 `displaySequenceText` 基于 `Course.autoIndex(for:)` 计算——即"这门课的第 N 节"：

```swift
// Course.swift:67-70
func autoIndex(for lesson: Lesson) -> Int? {
    guard let idx = sortedLessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }
    return idx + 1
}
```

用户需求是"这个学生的全局第 N 节、第 X-Y 小时"。这需要跨课程、跨所有历史数据，按 `studentName` 聚合计算。

**关键设计决策：** 学生以 `studentName` 字符串为唯一标识，不新建 Student 实体。理由：
- 当前数据中学生信息只有姓名，没有其他属性（电话、备注等）
- 新建实体需要关系迁移（Lesson → Student），对已有数据风险高
- `studentName` 做聚合查询已够用，且避免 schema 变更

### 3.3 两套编号的关系：学生课次 vs 课程计划节次

V6 引入"学生课次"后，系统中将并存两种编号。必须明确它们的定义、文案和出现位置，避免用户混淆。

| 维度 | 定义 | 计算方式 | 文案 | 出现位置 |
|------|------|----------|------|----------|
| **学生课次**（主叙事） | 该学生跨所有课程按时间排序的全局第 N 节 | `studentProgress(for:allLessons:)` | "第11节 · 第21-22小时" | 课表头部、详情卡片、新建预告 |
| **课程计划节次**（辅助） | 该课程内手动/自动的计划编号 | `lessonNumber` / `displaySequenceText` | "计划节次: 3/48" | LessonFormView 输入框（可选）、日历备注 |

**核心原则：**
- 用户看到的"第 N 节"**始终指学生维度**，这是主叙事
- 课程计划节次降级为辅助信息，仅在表单和日历备注中以"计划节次"文案出现
- 两者绝不使用同一文案，避免歧义

**各页面文案对照：**

| 页面 | 当前文案 | V6 文案 |
|------|----------|---------|
| LessonTimeGroup 头部 | `第3/48节`（课程维度） | `第11节`（学生维度） |
| LessonDetailCard | 无学生课次 | `第11节 · 第21-22小时`（学生维度） |
| LessonFormView 课次输入 | `第几节课`（课程维度） | `计划节次（可选）`（课程维度，降级） |
| BatchLessonFormView 预览 | `第N节`（课程维度） | `第N节`（学生维度）+ 计划节次自动填入但不显示在预览 |
| 日历备注 | `第3/48节`（课程维度） | `学生第11节 · 计划3/48节`（两者都写） |

---

## 4. F7: 收入筛选增强（月份回溯 + 学生维度）

### 4.1 月份/周/年翻页

在 `IncomeView` 中引入 `@State private var referenceDate: Date = .now`，替代 `currentRange` 中的 `Date.now`。

**UI 变更——在 Period Picker 下方添加翻页控件：**

```
┌─────────────────────────────────────┐
│  [周]  [月]  [年]                    │  ← 现有 Period Picker
│                                      │
│  ◀  2026年3月  ▶   [回到本月]        │  ← 新增翻页行
│                                      │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐│
│  │3月收入│ │预估  │ │已完成│ │课均  ││  ← 现有 summary cards
│  │¥12400│ │¥15600│ │ 32节 │ │¥387  ││
│  └──────┘ └──────┘ └──────┘ └──────┘│
│  ...                                 │
└─────────────────────────────────────┘
```

**翻页逻辑：**

```swift
@State private var referenceDate: Date = .now

private func movePeriod(_ offset: Int) {
    let cal = DateHelper.calendar
    switch period {
    case .week:
        referenceDate = cal.date(byAdding: .weekOfYear, value: offset, to: referenceDate) ?? referenceDate
    case .month:
        referenceDate = cal.date(byAdding: .month, value: offset, to: referenceDate) ?? referenceDate
    case .year:
        referenceDate = cal.date(byAdding: .year, value: offset, to: referenceDate) ?? referenceDate
    }
}
```

**翻页标题显示：**

```swift
private var periodTitle: String {
    let cal = DateHelper.calendar
    switch period {
    case .week:
        let range = DateHelper.weekRange(for: referenceDate)
        return "\(DateHelper.dateString(range.start)) - \(DateHelper.dateString(range.end))"
    case .month:
        return DateHelper.monthString(referenceDate)  // "2026年3月"
    case .year:
        return "\(cal.component(.year, from: referenceDate))年"
    }
}
```

**"回到当前"按钮：** 当 `referenceDate` 不在当前周/月/年范围内时显示，点击重置为 `.now`。

**`currentRange` 改造：** 将 `Date.now` 替换为 `referenceDate`：

```swift
private var currentRange: (start: Date, end: Date) {
    let cal = DateHelper.calendar
    switch period {
    case .week:
        return DateHelper.weekRange(for: referenceDate)
    case .month:
        return DateHelper.monthRange(for: referenceDate)
    case .year:
        let start = cal.date(from: cal.dateComponents([.year], from: referenceDate))!
        let end = cal.date(byAdding: .year, value: 1, to: start)!
        return (start, end)
    }
}
```

**`periodLabel` 改造：** 从固定的"本月"改为动态标题：

```swift
private var periodLabel: String {
    let cal = DateHelper.calendar
    let nowRange = currentPeriodRange(for: .now)
    let isCurrentPeriod = referenceDate >= nowRange.start && referenceDate < nowRange.end
    switch period {
    case .week:  return isCurrentPeriod ? "本周" : periodTitle
    case .month: return isCurrentPeriod ? "本月" : "\(cal.component(.month, from: referenceDate))月"
    case .year:  return isCurrentPeriod ? "本年" : "\(cal.component(.year, from: referenceDate))年"
    }
}
```

### 4.2 学生维度排行

在现有的"课程收入排行"旁，新增"按学生"视角。用 Segmented Picker 切换：

```
┌──────────────────────────────────────┐
│  [按课程]  [按学生]                  │  ← 新增维度切换
│                                      │
│  ● 傅褚备    12节  ¥9600    62%      │
│  ● 丹怡       4节  ¥2800    18%      │
│  ● Isabella   3节  ¥1200     8%      │
│  ...                                 │
└──────────────────────────────────────┘
```

**数据结构：**

```swift
@State private var rankingMode: RankingMode = .byCourse
enum RankingMode: String, CaseIterable {
    case byCourse = "按课程"
    case byStudent = "按学生"
}

private struct StudentIncome: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let income: Double
    let percentage: Double
}

private var studentRanking: [StudentIncome] {
    var map: [String: (count: Int, income: Double)] = [:]
    for lesson in lessonsInRange {
        let key = normalizeStudentName(lesson.studentName)
        guard !key.isEmpty else { continue }
        var entry = map[key] ?? (0, 0)
        entry.count += 1
        entry.income += lesson.effectivePrice
        map[key] = entry
    }
    let total = max(totalIncome, 1)
    return map.map { StudentIncome(name: $0.key, count: $0.value.count, income: $0.value.income, percentage: $0.value.income / total * 100) }
        .sorted { $0.income > $1.income }
}
```

**图表也跟随维度切换：** `rankingMode == .byStudent` 时，图表的 `foregroundStyle(by:)` 改为按 `normalizeStudentName(lesson.studentName)` 分组而非 `courseName`。`ChartEntry` 需要新增 `studentKey` 字段：

```swift
private struct ChartEntry: Identifiable {
    let id = UUID()
    let label: String
    let courseName: String
    let courseColor: String
    let studentKey: String    // normalizeStudentName(lesson.studentName)
    let income: Double
}
```

构建 chartData 时（学生维度下过滤空姓名，与排行口径一致）：
```swift
let sKey = normalizeStudentName(lesson.studentName)
// 学生维度时，空姓名课时不参与图表（与 studentRanking 口径一致）
if rankingMode == .byStudent && sKey.isEmpty { continue }

entries.append(ChartEntry(
    label: label,
    courseName: lesson.course?.name ?? "未知",
    courseColor: lesson.course?.colorHex ?? "#78909C",
    studentKey: sKey,
    income: lesson.effectivePrice
))
```

图表渲染时：
```swift
Chart(chartData) { entry in
    BarMark(...)
    .foregroundStyle(by: .value(
        rankingMode == .byCourse ? "课程" : "学生",
        rankingMode == .byCourse ? entry.courseName : entry.studentKey
    ))
}
```

### 4.3 学生月度收入详情

在学生排行中点击某个学生行，跳转到一个 **`StudentIncomeDetailView`**（新建），显示该学生的月度收入明细：

```
┌─ 傅褚备 收入详情 ────────────────────┐
│                                      │
│  ◀  2026年3月  ▶   [回到本月]        │
│                                      │
│  ┌──────────┐  ┌──────────┐          │
│  │ 本月收入 │  │ 已完成   │          │
│  │ ¥9600   │  │ 12 节    │          │
│  └──────────┘  └──────────┘          │
│                                      │
│  3月2日 周一  雅思阅读(线下) ¥800     │
│  3月8日 周六  雅思阅读(线下) ¥800     │
│  3月10日 周一 雅思阅读(线下) ¥800     │
│  ...                                 │
└──────────────────────────────────────┘
```

**统计口径——严格对齐 IncomeView：**

| 指标 | 口径 | 与 IncomeView 对应 |
|------|------|-------------------|
| 本月收入 | 该学生 + 月份范围 + `isCompleted \|\| endTime < .now` | 对齐 `lessonsInRange` |
| 预估收入 | 该学生 + 月份范围 + 全量 | 对齐 `allLessonsInRange` |
| 已完成节数 | 该学生 + 月份范围 + `isCompleted \|\| endTime < .now` | 对齐 `lessonCount` |
| 课时列表 | 该学生 + 月份范围 + 全量（标注完成状态） | 展示全部，方便查看未来课时 |

```swift
// StudentIncomeDetailView 核心数据
private var studentLessons: [Lesson] {
    let key = normalizeStudentName(studentName)
    return allLessons.filter { normalizeStudentName($0.studentName) == key }
}

private var lessonsInMonth: [Lesson] {
    let range = DateHelper.monthRange(for: referenceDate)
    return studentLessons.filter { $0.date >= range.start && $0.date < range.end }
}

private var completedInMonth: [Lesson] {
    lessonsInMonth.filter { $0.isCompleted || $0.endTime < .now }
}

private var actualIncome: Double {
    completedInMonth.reduce(0) { $0 + $1.effectivePrice }
}

private var estimatedIncome: Double {
    lessonsInMonth.reduce(0) { $0 + $1.effectivePrice }
}
```

预估收入受 `@AppStorage("showEstimatedIncome")` 开关控制，与 IncomeView 行为一致。

**从不同 Period 进入时的月份锚定：** 详情页继承父页面的 `referenceDate` 所在月份，而非一律跳回当前月。

```swift
// StudentIncomeDetailView init
init(studentName: String, initialMonth: Date = .now) {
    self.studentName = studentName
    _referenceDate = State(initialValue: initialMonth)
}

// IncomeView 中跳转时传入当前 referenceDate
NavigationLink(value: studentName) { ... }
.navigationDestination(for: String.self) { name in
    StudentIncomeDetailView(studentName: name, initialMonth: referenceDate)
}
```

这样用户在 2026 年 3 月排行中点击学生，详情页直接打开 3 月——不需要再手动翻回去。从周视图进入时，继承 `referenceDate` 所在月份；从年视图进入同理。

### 4.4 涉及文件

| 文件 | 变更 |
|------|------|
| `Views/Income/IncomeView.swift` | 翻页机制 + 学生维度排行 + 图表维度切换 |
| `Views/Income/StudentIncomeDetailView.swift` | **新建** — 学生月度收入详情 |

---

## 5. F8: 以学生为中心的课次与课时追踪

### 5.1 学生姓名：新建必填，编辑宽松

**必填范围严格限定在新建：**

| 场景 | 学生姓名是否必填 | 理由 |
|------|------------------|------|
| LessonFormView 新建 | 必填 | 用户原始需求"增加课时时学生姓名是必选的" |
| BatchLessonFormView 新建 | 必填 | 同上 |
| LessonFormView 编辑已有课时 | 不强制 | 避免旧数据编辑被阻塞，用户可能只想改时间/价格 |

**LessonFormView** 修改：

```swift
// placeholder 区分新建和编辑
TextField(isEditing ? "学生姓名" : "学生姓名（必填）", text: $studentName)

// 保存按钮禁用条件
.disabled(selectedCourse == nil || (!isEditing && normalizeStudentName(studentName).isEmpty))
```

**BatchLessonFormView** 修改：placeholder 改为 `"学生姓名（必填）"`，创建按钮禁用条件增加 `normalizeStudentName(studentName).isEmpty` 检查。

**旧数据兼容：** 已有 `studentName == ""` 的课程可以正常编辑保存（不强制补填），但不参与学生课次计算和学生排行。

### 5.1.1 学生姓名规范化 — 全局统一 key

`studentName` 作为学生聚合的事实主键，必须在**所有路径**（保存、聚合、比较、建议）使用同一套规范化规则，而非只在保存时 normalize。

**规范化函数（放入 `Helpers/StudentProgress.swift`，全局可用）：**

```swift
func normalizeStudentName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
       .components(separatedBy: .whitespaces)
       .filter { !$0.isEmpty }
       .joined(separator: " ")
}
```

效果：`"  张  三  "` → `"张 三"`，`"张三\t"` → `"张三"`。

**统一使用点：**

| 路径 | 使用方式 |
|------|----------|
| LessonFormView / BatchLessonFormView 保存 | `normalizeStudentName(studentName)` |
| `studentProgress(for:allLessons:)` 过滤 | `normalizeStudentName(lesson.studentName)` 比较 |
| 学生收入排行 (`studentRanking`) | 按 `normalizeStudentName` 聚合 |
| `StudentIncomeDetailView` 过滤 | 按 `normalizeStudentName` 匹配 |
| 表单课次预告 | 按 `normalizeStudentName` 查询 |
| 输入建议列表 | 从 `allLessons` 提取时先 normalize 再去重 |

**`studentProgress` 函数更新：**

```swift
func studentProgress(for lesson: Lesson, allLessons: [Lesson]) -> StudentProgress? {
    let key = normalizeStudentName(lesson.studentName)
    guard !key.isEmpty else { return nil }
    let studentLessons = allLessons
        .filter { normalizeStudentName($0.studentName) == key }
        .sorted { $0.startTime < $1.startTime }
    // ...
}
```

**输入时自动建议：**

```swift
private var existingStudentNames: [String] {
    let normalized = allLessons
        .map { normalizeStudentName($0.studentName) }
        .filter { !$0.isEmpty }
    return Array(Set(normalized)).sorted()
}

// 在 TextField 下方
if !studentName.isEmpty {
    let inputKey = normalizeStudentName(studentName)
    let matches = existingStudentNames.filter {
        $0.localizedCaseInsensitiveContains(inputKey) && $0 != inputKey
    }
    if !matches.isEmpty {
        ForEach(matches.prefix(5), id: \.self) { name in
            Button(name) { studentName = name }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

**规范化边界说明：** `normalizeStudentName` 只处理首尾空白和连续空白压缩。`"张三"` 和 `"张 三"` normalize 后仍然不相等（分别是 `"张三"` 和 `"张 三"`），系统会视为两个不同学生。这是刻意取舍——内部空格可能是用户有意区分的（如外国名 "De Silva"）。输入建议列表可以帮助用户发现已有近似名避免误建。如果用户确实把同一个人录成了两种写法，需要手动编辑统一。

### 5.2 学生全局课次计算

新增 Lesson 的 computed property，跨课程按 `studentName` 聚合：

```swift
/// 该学生的全局课次（跨所有课程，按 startTime 排序）
var studentLessonIndex: Int? {
    guard !studentName.isEmpty else { return nil }
    // 需要通过 course 的 modelContext 查询所有同名学生的课
    // 但 SwiftData computed property 无法直接查询全库
    // → 改为在 View 层计算（见 5.3）
}
```

**设计决策：** SwiftData 的 `@Model` computed property 无法执行跨实体的 `FetchDescriptor` 查询。因此学生全局课次不放在 Model 层，而是在 View 层计算。

### 5.3 View 层学生课次计算

新增一个轻量工具函数，在需要显示学生课次的 View 中使用：

```swift
/// 计算某学生在所有课程中按时间排序的课次和累计小时数
struct StudentProgress {
    let lessonIndex: Int      // 第 N 节
    let hourStart: Double     // 第 X 小时开始
    let hourEnd: Double       // 第 Y 小时结束
}

func studentProgress(for lesson: Lesson, allLessons: [Lesson]) -> StudentProgress? {
    let key = normalizeStudentName(lesson.studentName)
    guard !key.isEmpty else { return nil }
    let studentLessons = allLessons
        .filter { normalizeStudentName($0.studentName) == key }
        .sorted {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id.uuidString < $1.id.uuidString  // 稳定 tie-breaker
        }
    
    guard let index = studentLessons.firstIndex(where: { $0.id == lesson.id }) else { return nil }
    
    let lessonIndex = index + 1
    
    // 累计前面所有课的小时数
    let priorHours = studentLessons[..<index].reduce(0.0) { $0 + Double($1.durationMinutes) / 60.0 }
    let thisHours = Double(lesson.durationMinutes) / 60.0
    
    return StudentProgress(
        lessonIndex: lessonIndex,
        hourStart: priorHours,
        hourEnd: priorHours + thisHours
    )
}
```

**示例：** 学生"傅褚备"历史上上过 10 节 2 小时的课（共 20 小时），新增一节 2 小时课：
- `lessonIndex = 11`（第 11 节）
- `hourStart = 20.0`，`hourEnd = 22.0`（第 21-22 小时）

### 5.4 LessonDetailCard 显示学生课次

**当前显示（`LessonDetailCard.swift:30-38`）：**

```
09:00-10:00 · 傅褚备
```

**改为：**

```
09:00-10:00 · 傅褚备
第11节 · 第21-22小时
```

在 `LessonDetailCard` 中，需要注入 `allLessons` 来计算学生进度。修改方式：

```swift
struct LessonDetailCard: View {
    let lesson: Lesson
    let allLessons: [Lesson]  // 新增参数
    @AppStorage("showIncomeInCourseList") private var showIncome = true

    // ...

    // 在 body 中新增学生进度行
    if let progress = studentProgress(for: lesson, allLessons: allLessons) {
        HStack(spacing: 0) {
            Text("第\(progress.lessonIndex)节")
            Text(" · ")
            let startH = Int(progress.hourStart) + 1
            let endH = Int(progress.hourEnd.rounded(.up))
            if startH == endH {
                Text("第\(startH)小时")
            } else {
                Text("第\(startH)-\(endH)小时")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
```

**小时显示规则：**
- `hourStart = 20.0, hourEnd = 22.0` → "第21-22小时"（`Int(20)+1=21`, `ceil(22)=22`）
- `hourStart = 0.0, hourEnd = 1.0` → "第1小时"（`Int(0)+1=1`, `ceil(1)=1`）
- `hourStart = 10.0, hourEnd = 11.5` → "第11-12小时"（`Int(10)+1=11`, `ceil(11.5)=12`）

### 5.5 LessonTimeGroup 头部显示学生课次

当前 `LessonTimeGroup.swift:25-29` 显示 `lesson.displaySequenceText`（按课程的课次）。

**改为显示学生课次（替换课程课次）：**

```swift
// LessonTimeGroup.swift
struct LessonTimeGroup: View {
    let lesson: Lesson
    let allLessons: [Lesson]  // 新增参数
    var onEdit: () -> Void = {}

    // ... header 中：
    if let progress = studentProgress(for: lesson, allLessons: allLessons) {
        Text("第\(progress.lessonIndex)节")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**设计决策：** 头部只显示"第 N 节"（简洁），详情卡片同时显示"第 N 节 · 第 X-Y 小时"（完整）。课程维度的 `displaySequenceText` 仍保留在 Lesson model 上不删除，但 UI 不再主动使用它。

### 5.6 ScheduleView 传递 allLessons

当前 `ScheduleView` 已有 `@Query private var allLessons: [Lesson]`。需要在调用 `LessonTimeGroup` 和 `LessonDetailCard` 时传入：

```swift
// ScheduleView.swift 的 lessonList 中
LessonTimeGroup(lesson: lesson, allLessons: allLessons) {
    editingLesson = lesson
}

// LessonTimeGroup 内部调用 LessonDetailCard 时
LessonDetailCard(lesson: lesson, allLessons: allLessons)
```

### 5.7 LessonFormView 显示学生课次预告

新建课时时，选好学生姓名后，在表单中显示提示信息：

```swift
let inputKey = normalizeStudentName(studentName)
if !inputKey.isEmpty {
    let studentLessons = allLessons.filter { normalizeStudentName($0.studentName) == inputKey }
    let existingCount = studentLessons.count
    let existingHours = studentLessons.reduce(0.0) { $0 + Double($1.durationMinutes) / 60.0 }
    if existingCount > 0 {
        Text("该学生已有 \(existingCount) 节课（\(String(format: "%.1f", existingHours))小时），本节将是第 \(existingCount + 1) 节")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

需要在 LessonFormView 中添加 `@Query private var allLessons: [Lesson]`。

### 5.8 CalendarSyncService 日历备注更新

当前日历备注使用课程维度的 `displaySequenceText`（`CalendarSyncService.swift:216-219`）：

```swift
if let seq = lesson.displaySequenceText {
    noteParts.append(seq)  // "第3/48节"
}
```

**V6 方案：由调用方预计算学生节次，传入 service。** Service 本身保持无状态，不依赖 allLessons。

#### 5.8.1 populateEvent 签名变更

```swift
// CalendarSyncService.swift
private func populateEvent(_ event: EKEvent, from lesson: Lesson, studentIndex: Int? = nil) {
    // ...
    var noteParts: [String] = []
    // 学生维度（主叙事）
    if let idx = studentIndex {
        noteParts.append("学生第\(idx)节")
    }
    // 课程维度（辅助）
    if let seq = lesson.displaySequenceText {
        noteParts.append("计划\(seq)")
    }
    // ...
}
```

#### 5.8.2 syncLesson 签名变更

```swift
func syncLesson(_ lesson: Lesson, studentIndex: Int? = nil) throws {
    // ... 内部调用 populateEvent(event, from: lesson, studentIndex: studentIndex)
}
```

#### 5.8.3 syncAllLessons 预计算

```swift
func syncAllLessons(_ lessons: [Lesson]) throws -> Int {
    // 预计算全局学生节次 index map
    let indexMap = Self.buildStudentIndexMap(lessons)
    // ... 遍历时传入
    populateEvent(event, from: lesson, studentIndex: indexMap[lesson.id])
}

/// 按 normalizeStudentName 分组，每组按 (startTime, id) 稳定排序，输出 [lessonId: studentIndex]
static func buildStudentIndexMap(_ lessons: [Lesson]) -> [UUID: Int] {
    var groups: [String: [Lesson]] = [:]
    for lesson in lessons {
        let key = normalizeStudentName(lesson.studentName)
        guard !key.isEmpty else { continue }
        groups[key, default: []].append(lesson)
    }
    var result: [UUID: Int] = [:]
    for (_, group) in groups {
        let sorted = group.sorted {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id.uuidString < $1.id.uuidString  // 稳定 tie-breaker
        }
        for (i, lesson) in sorted.enumerated() {
            result[lesson.id] = i + 1
        }
    }
    return result
}
```

#### 5.8.4 所有调用方变更清单

| 调用方 | 当前代码 | V6 变更 |
|--------|----------|---------|
| `ScheduleView.swift` swipe 完成/删除 | `syncLesson(lesson)` | 传入 `studentIndex`（从 allLessons 用 `computeStudentIndex` 计算） |
| `LessonFormView.swift` 新建/编辑保存 | `syncLesson(newLesson)` / `syncLesson(lesson)` | 传入 `studentIndex`（用 `computeStudentIndex` 计算，见下文） |
| `BatchLessonFormView.swift` 批量创建 | `syncLesson(lesson)` in loop | 用 `buildStudentIndexMap` 批量预计算后传入 |
| `SettingsView.swift` 全量同步 | `syncAllLessons(Array(allLessons))` | 签名不变（内部已预计算） |
| `CourseFormView.swift` 课程名变更 | `syncLessonsForCourse(course)` | `syncLessonsForCourse` 内部需要 allLessons 参数来预计算学生节次 |

#### 5.8.5 单课场景的 studentIndex 预计算

新建和编辑时 `@Query allLessons` 的快照可能不包含刚创建/刚修改的 lesson。定义一个显式 helper：

```swift
/// 计算目标 lesson 在学生时间线中的位置
/// targetLesson 可以不在 existingLessons 中（新建场景）
func computeStudentIndex(for targetLesson: Lesson, existingLessons: [Lesson]) -> Int? {
    let key = normalizeStudentName(targetLesson.studentName)
    guard !key.isEmpty else { return nil }

    // 构建集合：已有同名学生课时（排除 targetLesson 自身以防重复）+ targetLesson
    var pool = existingLessons.filter {
        normalizeStudentName($0.studentName) == key && $0.id != targetLesson.id
    }
    pool.append(targetLesson)
    pool.sort {
        if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
        return $0.id.uuidString < $1.id.uuidString
    }
    guard let idx = pool.firstIndex(where: { $0.id == targetLesson.id }) else { return nil }
    return idx + 1
}
```

**调用路径：**

| 场景 | 调用方式 |
|------|----------|
| 新建 | `computeStudentIndex(for: newLesson, existingLessons: allLessons)` — newLesson 尚未 insert，通过 helper 显式加入 pool |
| 编辑 | `computeStudentIndex(for: lesson, existingLessons: allLessons)` — lesson 对象已是最新值（SwiftData 同引用），helper 排除旧自身再加回 |
| Swipe 完成 | 同编辑 |

这样无论 `@Query` 快照是否刷新，studentIndex 都是准确的。

**CourseFormView 特殊处理：** `syncLessonsForCourse(_:)` 目前只接收 `Course`，无法拿到全局 allLessons 来计算跨课程的学生节次。V6 改为 `syncLessonsForCourse(_:allLessons:)`：

```swift
func syncLessonsForCourse(_ course: Course, allLessons: [Lesson]) throws {
    guard syncEnabled else { return }
    let indexMap = Self.buildStudentIndexMap(allLessons)
    for lesson in course.lessons {
        try syncLesson(lesson, studentIndex: indexMap[lesson.id])
    }
}
```

CourseFormView 需要新增 `@Query private var allLessons: [Lesson]`，在调用时传入。

**已有事件更新：** 下次手动或自动同步时，备注会被新格式覆盖。不做主动全量重同步，保持"最终一致"策略。

### 5.9 BatchLessonFormView 学生节次算法

批量排课预览和创建时的学生节次不能简单用 `existingCount + index`——因为新课时可能插入到已有课时的时间线中间。

**算法：无 @State 预分配，纯函数计算**

**设计决策：** 去掉 `@State pendingLessonIds`。预览阶段不需要预分配 UUID——因为批量生成的每个日期天然不同，与已有课时 startTime 冲突是极少数（且用户已看到冲突警告的）场景。

```swift
// BatchLessonFormView 中 — 纯函数，无 @State 依赖，可在 body 中安全调用

private func batchStudentProgress(studentName: String) -> [Date: Int] {
    let key = normalizeStudentName(studentName)
    guard !key.isEmpty else { return [:] }

    // 1. 已有课时
    let existing: [(startTime: Date, dateKey: Date?, sortTail: String)] = allLessons
        .filter { normalizeStudentName($0.studentName) == key }
        .map { ($0.startTime, nil, $0.id.uuidString) }

    // 2. 待创建课时（用日期索引字符串作为 sortTail，保证同 startTime 时顺序稳定）
    let pending: [(startTime: Date, dateKey: Date?, sortTail: String)] = generatedDates
        .enumerated()
        .map { i, date in
            let t = DateHelper.combine(date: date, time: startTime)
            return (t, date, "~pending-\(String(format: "%04d", i))")
            // "~" 前缀保证 pending 排在同 startTime 的 existing 之后（ASCII > UUID 字符）
        }

    // 3. 合并排序
    let merged = (existing + pending).sorted {
        if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
        return $0.sortTail < $1.sortTail
    }

    // 4. 提取待创建项的位置
    var result: [Date: Int] = [:]
    for (sortedIdx, item) in merged.enumerated() {
        if let genDate = item.dateKey {
            result[genDate] = sortedIdx + 1
        }
    }
    return result
}
```

**创建时不需要预分配 UUID：**

```swift
private func createLessons() {
    guard let course = selectedCourse else { return }
    var courseNumber = nextLessonNumber(for: course)

    for date in generatedDates {
        let actualStart = DateHelper.combine(date: date, time: startTime)
        let actualEnd = DateHelper.combine(date: date, time: endTime)

        let lesson = Lesson(course: course, ...)
        // lesson.id 由 Lesson.init 自动生成，无需预分配
        // ... 其余赋值
    }
}
```

**预览行显示：**

```swift
let progressMap = batchStudentProgress(studentName: studentName)
// ForEach(generatedDates, ...) { date in
if let studentIdx = progressMap[date] {
    Text("第\(studentIdx)节")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**预览 vs 创建后一致性分析：**

| 场景 | 预览排序 | 创建后排序 | 一致？ |
|------|----------|------------|--------|
| 所有 pending 日期不同（正常情况） | 按 startTime | 按 startTime | 一致 |
| pending 与 existing 同 startTime（冲突） | existing 先（`sortTail` 中 UUID < "~pending"） | 按 `id.uuidString`（新旧 UUID 比较） | 可能 ±1 |

**已接受的边界情况：** 同 startTime 的冲突课时，预览显示的学生节次可能与创建后差 ±1。这只影响用户已明确看到冲突警告的那一节课，且差异仅为相邻序号。这是可接受的产品取舍，远优于引入 @State 预分配带来的 SwiftUI 时序复杂性。

**全局 tie-breaker 规则：**
- `studentProgress` / `buildStudentIndexMap` / `computeStudentIndex`：`(startTime, id.uuidString)`
- `batchStudentProgress`（预览）：`(startTime, sortTail)`，其中 existing 用 `id.uuidString`，pending 用 `"~pending-NNNN"`

**创建时的课程计划节次（`lessonNumber`）：** 仍然按课程维度用 `nextLessonNumber(for:)` 递增写入——这两套编号独立互不干扰。

### 5.10 LessonFormView 课程计划节次降级

当前"第几节课"输入框在主表单区域（V5 从 DisclosureGroup 提升上来的），V6 将其文案和定位调整：

```swift
// 从 Section("课次") 改为放回 DisclosureGroup 内，降低优先级
// 文案从"第几节课"改为"计划节次（可选）"
HStack {
    Text("计划节次")
    Spacer()
    TextField("可选", value: $lessonNumber, format: .number)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(width: 80)
    if let total = selectedCourse?.totalLessons, total > 0 {
        Text("/ \(total)").foregroundStyle(.secondary)
    }
}
```

学生课次预告（5.7 节）成为主表单的课次信息入口。

### 5.10 涉及文件

| 文件 | 变更 |
|------|------|
| `Models/Lesson.swift` | 无 schema 变更（studentName 已存在） |
| `Helpers/StudentProgress.swift` | **新建** — `StudentProgress` 结构体 + `studentProgress(for:allLessons:)` 函数 |
| `Views/Schedule/LessonDetailCard.swift` | 新增 `allLessons` 参数 + 学生课次/小时显示行 |
| `Views/Schedule/LessonTimeGroup.swift` | 新增 `allLessons` 参数 + 头部改为学生课次 |
| `Views/Schedule/ScheduleView.swift` | 传递 `allLessons` 给子组件 |
| `Views/Lesson/LessonFormView.swift` | 学生姓名新建必填+建议+规范化 + 课次输入降级 + 学生课次预告 |
| `Views/Lesson/BatchLessonFormView.swift` | 学生姓名必填+规范化 |
| `Services/CalendarSyncService.swift` | populateEvent 增加 studentIndex 参数 + 双维度备注 |

---

## 6. 数据模型变更

**本轮迭代无 schema 变更。**

| 需求 | 是否需要 schema 变更 | 原因 |
|------|---------------------|------|
| F7 收入翻页 | 否 | 纯 UI 状态（`@State referenceDate`） |
| F7 学生排行 | 否 | 按 `studentName` 聚合计算 |
| F8 学生课次 | 否 | 在 View 层按 `studentName` 跨课程聚合 |
| F8 学生必填 | 否 | `studentName` 字段已存在，仅变更 UI 校验 |

**不新建 Student 实体的理由：**
- 当前数据只有姓名作为学生信息，不值得建立独立实体
- `studentName` 字符串聚合已满足所有需求
- 避免 schema 迁移风险（Lesson ↔ Student 关系）
- 如果未来需要学生详情（电话、备注等），再考虑独立实体

---

## 7. 涉及文件清单

### 新建文件

| 文件 | 用途 |
|------|------|
| `Views/Income/StudentIncomeDetailView.swift` | F7 学生月度收入详情页 |
| `Helpers/StudentProgress.swift` | F8 学生全局课次计算工具 |

### 修改文件

| 文件 | 涉及需求 | 主要变更 |
|------|----------|----------|
| `Views/Income/IncomeView.swift` | F7 | referenceDate 翻页 + 学生维度排行 + 图表维度切换 |
| `Views/Schedule/LessonDetailCard.swift` | F8 | 新增 allLessons 参数 + 学生课次/小时显示 |
| `Views/Schedule/LessonTimeGroup.swift` | F8 | 新增 allLessons 参数 + 头部改为学生课次 |
| `Views/Schedule/ScheduleView.swift` | F8 | 传递 allLessons 给 LessonTimeGroup/LessonDetailCard |
| `Views/Lesson/LessonFormView.swift` | F8 | 学生姓名必填 + 课次预告 + @Query allLessons |
| `Views/Lesson/BatchLessonFormView.swift` | F8 | 学生姓名必填 |
| `Services/CalendarSyncService.swift` | F8 | populateEvent/syncLesson/syncAllLessons 增加 studentIndex + buildStudentIndexMap |
| `Views/Course/CourseFormView.swift` | F8 | 新增 @Query allLessons，syncLessonsForCourse 传入 allLessons |

### 未修改文件

| 文件 | 原因 |
|------|------|
| `Models/Lesson.swift` | 无 schema 变更，displaySequenceText 保留不删 |
| `Models/Course.swift` | 无变更 |
| `App/TomatoScheduleApp.swift` | 无变更 |
| `Views/Schedule/StatisticsBar.swift` | 无变更 |
| `Views/Schedule/CalendarHeaderView.swift` | 无变更 |
| `Views/Settings/SettingsView.swift` | 无变更 |

**注意：`Services/CalendarSyncService.swift` 需要修改**（见下方 5.9 节说明），已列入修改文件清单。

---

## 8. 实现优先级与依赖关系

### 依赖图

```
F8 (学生课次) ─── 无依赖，可先实施
       │
       └──→ F7 (收入筛选) ─── 学生排行点击跳转依赖 StudentIncomeDetailView
                               但翻页功能本身独立
```

F7 和 F8 相互独立，可并行开发。唯一交叉点是 F7 的"学生排行点击 → 学生收入详情"需要学生概念已建立，但这只是 UI 跳转，不影响数据层。

### 推荐实施顺序

| 阶段 | 需求 | 理由 |
|------|------|------|
| Phase 1 | F8 学生课次追踪 | 建立 StudentProgress 工具 + 学生必填，为 F7 提供数据基础 |
| Phase 2 | F7 收入筛选增强 | 在 F8 之上添加学生维度的收入查看 |

---

## 9. 数据迁移与兼容性

### 9.1 旧数据中 studentName 为空的课程

V6 将学生姓名改为**新建时**必填，**编辑已有课时不强制**。旧数据中 `studentName == ""` 的课程：
- 正常显示，不报错
- 不显示学生课次（`studentProgress` 返回 nil）
- 不参与学生排行（`normalizeStudentName(lesson.studentName).isEmpty` 时跳过）
- 编辑时**允许继续保存**（不强制补填），但如果教师主动填了学生名，后续该课时即纳入学生统计

### 9.2 学生姓名唯一性与规范化

学生姓名以字符串精确匹配为准，区分大小写。这是刻意的产品取舍——教师录入的学生名通常是中文或固定英文名，大小写混淆概率极低。

**规范化规则：** 保存时统一执行 `normalizeStudentName()`（trim + 合并连续空格），防止 `"张三"` 和 `"张三 "` 被视为不同学生。

**输入辅助：** 输入学生名时显示已有学生名的匹配建议（最多 5 个），减少拼写不一致。

同名学生视为同一人——这是用户明确提出的规则。如果出现不同学生同名，教师可以在姓名中添加后缀区分（如"张三-A"、"张三-B"）。

### 9.3 性能考虑

`studentProgress(for:allLessons:)` 需要在每个课时卡片渲染时对 `allLessons` 做过滤和排序。对于当前数据量（53 节课），完全无性能问题。

如果未来数据量增长到数百上千节，可以考虑：
- 在 ScheduleView 层预计算当天可见课程的 studentProgress 并传入
- 或在 allLessons 上建索引缓存（`[String: [Lesson]]` 按 studentName 分组）

当前阶段不做优化，保持实现简洁。

---

## 10. 风险与注意事项

| 风险 | 缓解措施 |
|------|----------|
| `allLessons` 传入组件导致接口变更 | LessonDetailCard 和 LessonTimeGroup 的所有调用方需要同步更新 |
| 学生姓名必填仅限新建 | 编辑旧课时时不强制补填，允许空姓名继续保存 |
| studentProgress 计算频率 | 每个可见卡片都会计算一次，当前数据量可接受 |
| 收入翻页到很远的历史月份 | 无性能问题（SwiftData @Query 返回全量，过滤在内存中做） |
| 图表按学生分组颜色 | 学生没有专属颜色，使用 SwiftUI Charts 自动配色 |
| 两套"第几节"文案混淆 | 学生维度用"第N节"，课程维度用"计划节次"，文案严格区分 |
| 日历备注与 app 内不一致 | CalendarSyncService 双写学生课次 + 课程计划节次 |
| studentName 拼写不一致 | normalizeStudentName 规范化 + 输入建议列表 |

---

## 11. 测试要点

| 测试场景 | 覆盖需求 |
|----------|----------|
| IncomeView 左右翻页到上个月，数据正确 | F7 翻页 |
| IncomeView 切换年维度后翻到去年，数据正确 | F7 翻页 |
| IncomeView "回到本月"按钮在当前月份时隐藏 | F7 翻页 |
| IncomeView 切换"按学生"排行，按收入降序显示 | F7 学生排行 |
| 点击学生排行中某个学生，进入该学生月度详情 | F7 学生详情 |
| 学生月度详情支持前后翻页查看历史收入 | F7 学生详情 |
| 新建课时不填学生姓名，保存按钮禁用 | F8 必填 |
| 批量排课不填学生姓名，创建按钮禁用 | F8 必填 |
| 编辑旧课时（studentName 为空），允许不填直接保存 | F8 编辑宽松 |
| 学生"傅褚备"历史 10 节 2h 课，新增 2h 课显示"第11节 · 第21-22小时" | F8 课次计算 |
| 同名学生跨不同课程，课次全局累计 | F8 跨课程 |
| 某学生第 1 节 1h 课，显示"第1节 · 第1小时" | F8 边界 |
| 学生课次在 LessonTimeGroup 头部显示"第N节" | F8 头部显示 |
| LessonFormView 课程计划节次显示为"计划节次（可选）"，非"第几节课" | F8 文案区分 |
| 旧数据 studentName 为空的课时不显示学生课次 | F8 旧数据兼容 |
| 输入学生名时显示已有学生名建议列表 | F8 输入辅助 |
| "张三 " 和 "张三" 保存后视为同一学生 | F8 规范化 |
| 日历备注同时包含"学生第N节"和"计划第M/X节" | F8 日历同步 |
| 批量预览（无冲突）的"第N节"与创建后课表显示一致 | F8 预览一致性 |
| 批量预览（有同 startTime 冲突）允许与创建后差 ±1，且冲突行有警告图标 | F8 预览边界 |
| 学生图表在 byStudent 模式下不显示空姓名旧数据 | F7 图表兼容 |
| 图表按学生维度显示时，颜色按学生区分 | F7 图表 |
| 学生详情页收入金额与 IncomeView 学生排行中的金额一致 | F7 口径对齐 |
| 学生详情页预估收入受 showEstimatedIncome 开关控制 | F7 开关 |
