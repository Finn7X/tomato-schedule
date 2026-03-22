# 番茄课表 — 收入系统 设计方案

> 修订版 — 根据 code review 修订了：价格冻结策略、金额精度、日历同步条件、Tab 跳转、删除保护、免费课建模。

## 1. 功能概述

为独立老师添加完整的收入管理模块：
- **课程定价**：每门课程设置小时单价，单节课费用按时长自动计算，支持单课价格覆盖（含免费课）
- **价格冻结**：课时完成时自动冻结价格，课程调价不影响历史收入
- **收入统计**：日/周/月维度的收入汇总，设置页快速查看
- **收入分析**：独立 Tab 页展示图表统计，含月趋势、课程收入分布

---

## 2. 定价模型设计

### 2.1 核心原则

- 以**小时单价**（`hourlyRate`）为基准，存储在 Course 上
- 每节课的费用 = `hourlyRate × 实际时长（小时）`，自动计算
- 支持**单课价格覆盖**（`isPriceOverridden` + `priceOverride`），可设为 0 表示免费课
- **完成即冻结**：课时标记完成时，自动将当前计算价格写入覆盖字段，后续课程调价不影响

### 2.2 定价优先级

```
单课收入:
  if lesson.isPriceOverridden:
      return lesson.priceOverride              ← 已冻结或手动覆盖（含 0 = 免费）
  else:
      return course.hourlyRate × 时长(h)       ← 动态计算（未完成课时）
      → 结果在模型层统一四舍五入到分（0.01 精度）
```

### 2.3 价格冻结策略

> **核心决策：已完成课时价格必须冻结，课程调价不可回写历史收入。**

| 操作 | 行为 |
|------|------|
| 标记课时为"已完成" | 若 `isPriceOverridden == false`，自动将 `effectivePrice` 写入 `priceOverride`，设 `isPriceOverridden = true` |
| 取消"已完成"标记 | 不自动解冻（保留冻结价格），用户可在"更多设置"中手动清除覆盖 |
| 修改课程小时单价 | 仅影响 `isPriceOverridden == false` 的课时（即未完成且未手动覆盖的） |
| 手动设置课时价格 | 设 `isPriceOverridden = true`，值为用户输入（含 0 = 免费） |
| 手动清除课时价格 | 设 `isPriceOverridden = false`，恢复动态计算 |

### 2.4 场景示例

| 场景 | hourlyRate | isPriceOverridden | priceOverride | effectivePrice |
|------|-----------|-------------------|---------------|---------------|
| 雅思阅读 2h | 200 | false | 0 | 400.00 |
| 上述课时完成后 | 200 | true | 400.00 | 400.00 |
| 课程后来调价到 250 | 250 | true | 400.00 | 400.00（不变） |
| 免费试听课 1h | 200 | true | 0.00 | 0.00 |
| 特殊约定固定价 | 200 | true | 350.00 | 350.00 |

### 2.5 金额精度规则

> **在模型层统一舍入，不留给 UI 层。**

- 存储类型：`Double`（SwiftData 兼容）
- 舍入精度：四舍五入到分（0.01），在 `effectivePrice` 计算时执行
- 显示规则：整数部分显示（`¥400`），有小数时保留到角（`¥166.7`）
- 汇总规则：所有汇总基于 `effectivePrice`（已舍入值），不会出现显示 vs 汇总不一致

```swift
var effectivePrice: Double {
    if isPriceOverridden { return priceOverride }
    guard let rate = course?.hourlyRate, rate > 0 else { return 0 }
    let raw = rate * Double(durationMinutes) / 60.0
    return (raw * 100).rounded() / 100   // 统一舍入到分
}

var priceDisplayText: String? {
    let p = effectivePrice
    guard p > 0 || isPriceOverridden else { return nil }
    return p == p.rounded() ? "¥\(Int(p))" : String(format: "¥%.1f", p)
}
```

---

## 3. 数据模型变更

### 3.1 Course 新增字段

```swift
var hourlyRate: Double = 0    // 小时单价（元），0 = 未设置定价
```

新增计算属性：
```swift
var totalIncome: Double {
    completedLessons.reduce(0) { $0 + $1.effectivePrice }
}
```

### 3.2 Lesson 新增字段

```swift
var isPriceOverridden: Bool = false   // 是否已覆盖/冻结价格
var priceOverride: Double = 0         // 覆盖价格（仅 isPriceOverridden 时生效，0 = 免费）
```

新增计算属性：`effectivePrice`、`priceDisplayText`（见 2.5 节）。

---

## 4. 用户交互设计

### 4.1 Tab 结构

```
[课表]    [收入]    [课程]    [设置]
```

`MainTabView` 增加 `@State selectedTab` 绑定，支持程序化切换。

### 4.2 CourseFormView — 高级设置加小时单价

```
  高级设置                              ▼
  ┌─────────────────────────────────────┐
  │  小时单价          [200]  元/小时    │  ← 新增
  │  科目类型          [阅读]            │
  │  ...                                │
  └─────────────────────────────────────┘
```

### 4.3 LessonFormView — 更多设置加价格

```
  更多设置                              ▼
  ┌─────────────────────────────────────┐
  │  课时费用                            │
  │  ○ 自动计算  ¥400 (¥200/h × 2.0h)  │  ← 默认选中
  │  ○ 自定义    [    ] 元               │  ← 选中后可输入（含 0 = 免费）
  │  ...                                │
  └─────────────────────────────────────┘
```

- 切换到"自定义"时 `isPriceOverridden = true`
- 切换回"自动计算"时 `isPriceOverridden = false`
- 0 是合法的自定义价格（免费课）

### 4.4 LessonDetailCard — 显示价格

进度行追加价格显示：
```
  阅读 · 4.0/36.0h · 7/48次 · ¥400
```

已冻结的完成课时不额外标记（价格已含在 ✅ 语境中）。

### 4.5 SettingsView — 收入概览

```
┌─────────────────────────────────────────────┐
│  收入概览                                    │
├─────────────────────────────────────────────┤
│  今日        ¥400                            │
│  本周        ¥2,800                          │
│  本月        ¥12,600                         │
└─────────────────────────────────────────────┘
```

点击该 Section → NavigationLink 推入 IncomeView（非 Tab 切换，避免跨 Tab 状态耦合）。

### 4.6 IncomeView — 收入 Tab

**顶部摘要卡片：**
- 本月收入 / 已完成节数 / 课均收入

**中部图表（Swift Charts）：**
- `BarMark` + `.foregroundStyle(by: courseName)` 堆叠柱状图
- 维度切换：`周 | 月 | 年`
  - 周：7 天，每天一柱
  - 月：当月每天一柱（默认）
  - 年：12 个月柱状图

**下部课程收入排行：**
- 按当前维度统计每门课程的收入 + 节数 + 占比

### 4.7 删除课程保护

当课程下有已完成课时（即有收入记录）时，删除前弹出强确认：

```
┌─────────────────────────────────────────────┐
│  确认删除课程                                │
│                                             │
│  「雅思阅读」下有 14 节已完成课时，             │
│  总收入 ¥5,600。删除后相关收入记录             │
│  将一并移除且不可恢复。                        │
│                                             │
│  [取消]              [确认删除]               │
└─────────────────────────────────────────────┘
```

无已完成课时的课程保持原有轻量删除交互。

---

## 5. 日历同步联动

### 5.1 价格变更不触发日历同步

价格数据不写入系统日历（EKEvent 无价格字段）。

### 5.2 CourseFormView 保存时的同步条件

当前 `CourseFormView.save()` 无条件调用 `syncLessonsForCourse`。修改为**仅在同步相关字段变更时触发**：

```swift
// 仅当 name 或 subject 变化时才同步日历
let needsCalendarSync = course.name != trimmedName || course.subject != trimmedSubject
// ... 保存字段 ...
if needsCalendarSync {
    try? CalendarSyncService.shared.syncLessonsForCourse(course)
}
```

`hourlyRate`、`totalHours`、`totalLessons`、`notes` 的变更不触发日历同步。

---

## 6. 架构设计

### 6.1 文件变更

```
修改（7 文件）：
  Models/Course.swift            +hourlyRate, +totalIncome
  Models/Lesson.swift            +isPriceOverridden, +priceOverride, +effectivePrice, +priceDisplayText
  Views/MainTabView.swift        4 Tab + selectedTab 绑定
  Views/Course/CourseFormView.swift   +小时单价 + 条件同步
  Views/Course/CourseListView.swift   +删除保护确认
  Views/Lesson/LessonFormView.swift   +价格覆盖（自动/自定义切换）
  Views/Schedule/LessonDetailCard.swift  +价格显示
  Views/Schedule/ScheduleView.swift      标记完成时冻结价格
  Views/Settings/SettingsView.swift      +收入概览 + NavigationLink

新建（1 文件）：
  Views/Income/IncomeView.swift     收入统计页（图表 + 排行）
```

### 6.2 完成时冻结价格的集成点

ScheduleView 中滑动标记完成的逻辑需增加冻结：

```swift
Button {
    withAnimation { lesson.isCompleted.toggle() }
    // 完成时冻结价格
    if lesson.isCompleted && !lesson.isPriceOverridden {
        lesson.priceOverride = lesson.effectivePrice
        lesson.isPriceOverridden = true
    }
    try? CalendarSyncService.shared.syncLesson(lesson)
} label: { ... }
```

---

## 7. 实现任务分解

### Task 1: 数据模型
- Modify: `Course.swift` — +`hourlyRate`, +`totalIncome`
- Modify: `Lesson.swift` — +`isPriceOverridden`, +`priceOverride`, +`effectivePrice`, +`priceDisplayText`

### Task 2: CourseFormView + 条件同步
- Modify: `CourseFormView.swift` — 高级设置加 `hourlyRate`，保存时仅在 name/subject 变化时同步日历

### Task 3: LessonFormView + 价格覆盖
- Modify: `LessonFormView.swift` — 更多设置加"自动计算/自定义"价格切换

### Task 4: LessonDetailCard + 价格显示
- Modify: `LessonDetailCard.swift` — 进度行追加 `priceDisplayText`

### Task 5: ScheduleView + 完成冻结
- Modify: `ScheduleView.swift` — 滑动完成时冻结价格

### Task 6: CourseListView + 删除保护
- Modify: `CourseListView.swift` — 有已完成课时时弹出强确认

### Task 7: IncomeView（收入统计页）
- Create: `Views/Income/IncomeView.swift` — 摘要卡片 + Swift Charts + 课程排行 + 维度切换

### Task 8: SettingsView + 收入概览
- Modify: `SettingsView.swift` — 顶部加日/周/月收入 + NavigationLink 到 IncomeView

### Task 9: MainTabView 4 Tab
- Modify: `MainTabView.swift` — 加收入 Tab + `@State selectedTab`

### Task 10: 构建验证

---

## 8. 风险与注意事项

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 历史课时无冻结价格（迁移） | 存量已完成课时用当前 hourlyRate 计算 | 文档说明；教师首次设价后历史收入基于当前价，后续新完成课时自动冻结 |
| 金额精度 | 非整数时长产生小数 | 模型层统一 `(raw * 100).rounded() / 100`，汇总和显示一致 |
| 删除课程丢失收入 | 历史数据不可恢复 | 有已完成课时时弹出强确认，显示收入总额 |
| 价格变更误触发日历同步 | 不必要的 EKEvent 重写 | CourseFormView 比较 name/subject 变化才触发 |
| 0 价格的语义 | 免费课 vs 未定价 | `isPriceOverridden` 区分：true+0=免费，false+0=未定价 |

---

## 9. V1 范围界定

**本次实现：**
- ✅ 课程小时单价
- ✅ 单课价格覆盖（含免费课 ¥0）
- ✅ 完成时自动冻结价格
- ✅ 模型层统一金额精度
- ✅ 收入 Tab（图表 + 排行 + 摘要）
- ✅ 设置页收入概览
- ✅ 删除课程收入保护
- ✅ 条件性日历同步

**延后实现：**
- ❌ 课程归档（软删除）
- ❌ 学生维度收入统计
- ❌ 收入目标/预算
- ❌ 已完成 vs 预计收入对比
- ❌ 导出收入报表
- ❌ 到课率/取消率统计
