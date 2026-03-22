# 番茄课表 — 收入系统 设计方案

## 1. 功能概述

为独立老师添加完整的收入管理模块：
- **课程定价**：每门课程设置小时单价，单节课费用按时长自动计算，支持单课价格覆盖
- **收入统计**：日/周/月维度的收入汇总，在设置页快速查看
- **收入分析**：独立 Tab 页展示图表统计，含月趋势、课程收入分布、已完成 vs 预计收入

---

## 2. 定价模型设计

### 2.1 核心原则

独立老师的常见定价方式是**按小时计费**，但不同课程时长不同（45分钟、1小时、1.5小时、2小时），因此：

- 以**小时单价**（`hourlyRate`）为基准，存储在 Course 上
- 每节课的实际费用 = `hourlyRate × 实际时长（小时）`，自动计算
- 支持**单课价格覆盖**（`priceOverride`），存储在 Lesson 上，用于特殊定价（试听课折扣、加课调价等）

### 2.2 定价优先级

```
单课收入 = lesson.priceOverride > 0
         ? lesson.priceOverride                              ← 手动覆盖
         : course.hourlyRate × (lesson.durationMinutes / 60) ← 自动计算
```

### 2.3 与现有模型的关系

| 场景 | hourlyRate | priceOverride | 实际收入 |
|------|-----------|---------------|---------|
| 雅思阅读 2h，时薪200 | 200 | 0 | 400 |
| 试听课 1h，半价优惠 | 200 | 100 | 100 |
| 单词默写 0.5h，时薪150 | 150 | 0 | 75 |
| 特殊加课，约定固定价 | 200 | 350 | 350 |

---

## 3. 数据模型变更

### 3.1 Course 新增字段

```swift
var hourlyRate: Double    // 小时单价（元），0 表示未设置定价
```

默认值 `0`，SwiftData lightweight migration。

新增计算属性：
```swift
/// 该课程已完成课时的总收入
var totalIncome: Double {
    completedLessons.reduce(0) { $0 + $1.effectivePrice }
}
```

### 3.2 Lesson 新增字段

```swift
var priceOverride: Double    // 单课价格覆盖（元），0 表示使用课程默认计算
```

默认值 `0`，SwiftData lightweight migration。

新增计算属性：
```swift
/// 本节课的实际收入
var effectivePrice: Double {
    if priceOverride > 0 { return priceOverride }
    guard let rate = course?.hourlyRate, rate > 0 else { return 0 }
    return rate * Double(durationMinutes) / 60.0
}

/// 价格显示文本："¥400" 或 "¥400 (覆盖)" 或 nil
var priceText: String? {
    let price = effectivePrice
    guard price > 0 else { return nil }
    return "¥\(Int(price))"
}
```

---

## 4. 用户交互设计

### 4.1 Tab 结构调整

收入是核心模块，增加独立 Tab：

```
[课表]    [收入]    [课程]    [设置]
```

### 4.2 课程定价入口（CourseFormView）

在现有"高级设置"折叠区域中增加小时单价字段：

```
┌─────────────────────────────────────────────┐
│  课程名称                                    │
│  [雅思阅读]                                  │
├─────────────────────────────────────────────┤
│  课程颜色                                    │
│  ● ● ● ● ●                                 │
├─────────────────────────────────────────────┤
│  高级设置                              ▼     │
│  ┌─────────────────────────────────────┐    │
│  │  小时单价          [200]  元/小时    │    │  ← 新增
│  │  科目类型          [阅读]            │    │
│  │  计划总课时        [36]  小时        │    │
│  │  计划总节数        [48]  节          │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### 4.3 单课价格覆盖（LessonFormView）

在"更多设置"折叠区域中增加价格覆盖：

```
┌─────────────────────────────────────────────┐
│  更多设置                              ▼     │
│  ┌─────────────────────────────────────┐    │
│  │  第几节课          [7]  / 48        │    │
│  │  已完成            [开关]            │    │
│  │  上课地点          [凯旋城校区...]    │    │
│  │  ─────────────────────────          │    │
│  │  课时费用          [自动] ¥400       │    │  ← 新增
│  │  (基于 ¥200/h × 2.0h)              │    │  ← 计算说明
│  │  点击可覆盖为自定义价格              │    │  ← 提示
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

交互细节：
- 默认显示 "自动" + 计算结果 + 计算公式
- 点击后切换为可编辑输入框，用户输入自定义价格
- 清空或输入 0 → 恢复自动计算

### 4.4 课程卡片中显示收入（LessonDetailCard）

在已有的进度信息行中追加价格：

```
┌────┬──────────────────────────────────────────┐
│ ▌  │ 雅思阅读                    ✅            │
│    │ 08:00-10:00 · 陈牧崧                     │
│    │ 阅读 · 4.0/36.0h · 7/48次 · ¥400        │  ← 追加价格
│    │ 凯旋城校区VIP3067教室                      │
└────┴──────────────────────────────────────────┘
```

### 4.5 设置页收入摘要（SettingsView）

在设置页顶部增加收入概览：

```
┌─────────────────────────────────────────────┐
│  收入概览                                    │
├─────────────────────────────────────────────┤
│  今日        ¥400                            │
│  本周        ¥2,800                          │
│  本月        ¥12,600                         │
│  ───                                        │
│  查看详细收入统计 →                            │  ← 跳转收入 Tab
└─────────────────────────────────────────────┘
```

### 4.6 收入 Tab 页（IncomeView）— 独立入口

#### 顶部：摘要卡片

```
┌──────────┬──────────┬──────────┐
│  本月收入  │  已完成   │  课均收入  │
│  ¥12,600 │  31 节   │  ¥406    │
│  ↑12%    │          │          │
└──────────┴──────────┴──────────┘
```

- 本月收入：当月已完成课时的总收入
- 已完成：当月已完成课时数
- 课均收入：本月收入 / 已完成节数
- ↑12%：与上月同期对比

#### 中部：月收入趋势图（Swift Charts）

```
¥
15k ┤                          ██
    │              ██          ██
12k ┤      ██      ██    ██   ██
    │      ██      ██    ██   ██
 9k ┤ ██   ██ ██   ██    ██   ██
    │ ██   ██ ██   ██    ██   ██
 6k ┤ ██   ██ ██   ██    ██   ██
    │ ██   ██ ██   ██    ██   ██
    └──────────────────────────────
      10月  11月  12月  1月   2月  3月
```

- 使用 `BarMark` + `.foregroundStyle(by: courseName)` 堆叠柱状图
- 按课程颜色堆叠，直观看到每门课程的收入占比
- 默认显示近 6 个月

#### 下部：课程收入排行

```
┌─────────────────────────────────────────────┐
│  本月课程收入                                 │
├─────────────────────────────────────────────┤
│  ● 雅思阅读      14节    ¥5,600    44%      │
│  ● 雅思口语       8节    ¥2,400    19%      │
│  ● 雅思听力       5节    ¥2,000    16%      │
│  ● 雅思写作       3节    ¥1,800    14%      │
│  ● 单词默写       1节    ¥800      7%       │
└─────────────────────────────────────────────┘
```

#### 切换维度

顶部分段控件切换时间维度：`周 | 月 | 年`

- **周视图**：7 天柱状图，每天一根柱
- **月视图**：当月每天一根柱（默认）
- **年视图**：12 个月柱状图

---

## 5. 架构设计

### 5.1 新增/修改文件

```
TomatoSchedule/
├── Models/
│   ├── Course.swift              ← 修改：+hourlyRate, +totalIncome
│   └── Lesson.swift              ← 修改：+priceOverride, +effectivePrice, +priceText
├── Views/
│   ├── MainTabView.swift         ← 修改：增加收入 Tab（4 Tab）
│   ├── Income/
│   │   └── IncomeView.swift      ← 新建：收入统计主页（图表 + 排行）
│   ├── Course/
│   │   └── CourseFormView.swift   ← 修改：高级设置中加小时单价
│   ├── Lesson/
│   │   └── LessonFormView.swift  ← 修改：更多设置中加价格覆盖
│   ├── Schedule/
│   │   └── LessonDetailCard.swift ← 修改：进度行追加价格
│   └── Settings/
│       └── SettingsView.swift    ← 修改：顶部加收入概览
```

### 5.2 收入计算逻辑（纯计算属性，无额外 Service）

所有收入数据均从已有的 `@Query allLessons` 实时计算，不需要额外存储或同步：

```swift
// 指定范围内的已完成收入
func income(in range: (Date, Date)) -> Double {
    allLessons
        .filter { $0.isCompleted && $0.date >= range.0 && $0.date < range.1 }
        .reduce(0) { $0 + $1.effectivePrice }
}

// 按课程分组收入
func incomeByCourseName(in range: (Date, Date)) -> [(name: String, color: String, income: Double, count: Int)]
```

不需要后台任务、不需要缓存，SwiftData 的 `@Query` 保证数据实时性。

### 5.3 日历同步联动

课程单价修改后，不需要额外同步动作——价格数据不写入系统日历（EKEvent 无价格字段），仅存在于 app 内部。已有的 `syncLessonsForCourse` 只同步 title/time/location/notes，价格变更不触发日历同步。

---

## 6. 实现任务分解

### Task 1: 数据模型

**Files:**
- Modify: `Models/Course.swift` — 增加 `hourlyRate: Double`、`totalIncome` 计算属性
- Modify: `Models/Lesson.swift` — 增加 `priceOverride: Double`、`effectivePrice`、`priceText` 计算属性

### Task 2: CourseFormView 加小时单价

**Files:**
- Modify: `Views/Course/CourseFormView.swift` — 高级设置中加 `hourlyRate` 输入

### Task 3: LessonFormView 加价格覆盖

**Files:**
- Modify: `Views/Lesson/LessonFormView.swift` — 更多设置中加 `priceOverride` 输入 + 自动计算显示

### Task 4: LessonDetailCard 显示价格

**Files:**
- Modify: `Views/Schedule/LessonDetailCard.swift` — 进度信息行追加 `priceText`

### Task 5: IncomeView（收入统计页）

**Files:**
- Create: `Views/Income/IncomeView.swift`

实现：
- 顶部摘要卡片（本月收入、已完成节数、课均收入、同比变化）
- 维度切换（周/月/年）
- Swift Charts 柱状图（按课程颜色堆叠）
- 课程收入排行列表

### Task 6: SettingsView 加收入概览

**Files:**
- Modify: `Views/Settings/SettingsView.swift` — 顶部加日/周/月收入摘要

### Task 7: MainTabView 加收入 Tab

**Files:**
- Modify: `Views/MainTabView.swift` — 4 Tab：课表 | 收入 | 课程 | 设置

### Task 8: 构建验证

- `xcodegen generate` → `xcodebuild build`
- 验证定价流程：设置课程单价 → 添加课时 → 完成标记 → 收入统计正确

---

## 7. 风险与注意事项

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 浮点精度问题（价格计算） | 显示 ¥399.999 | 使用 `Int(price)` 或 `String(format: "%.0f")` 取整显示 |
| 未设置单价的课程 | 收入为 0，图表中不可见 | 收入页提示"部分课程未设定价格" |
| 大量课时的图表性能 | 年视图可能卡顿 | 仅统计已完成课时，数据量可控（独立老师年 ~1000 节） |
| 价格覆盖与课程单价变更的先后 | 用户可能困惑 | 覆盖优先级明确：有 priceOverride 就用覆盖值，否则用课程单价 × 时长 |

---

## 8. V1 范围界定

**本次实现：**
- ✅ 课程小时单价设置
- ✅ 单课价格覆盖
- ✅ 收入自动计算（effectivePrice）
- ✅ 收入 Tab 页（图表 + 排行）
- ✅ 设置页收入概览
- ✅ 课程卡片显示价格
- ✅ 周/月/年维度切换

**延后实现：**
- ❌ 学生维度收入统计
- ❌ 收入目标/预算设定（RuleMark 目标线）
- ❌ 已完成 vs 预计收入对比（实线 vs 虚线）
- ❌ 导出收入报表（PDF/Excel）
- ❌ 多币种支持
- ❌ 到课率/取消率统计
