# 月度排课总览 实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现月度排课总览功能：月网格（一屏截图分享）+ 日时间轴详情（教师自查）+ 导出分享图（长图卡片）

**Architecture:** 4 个新建文件 + 1 个修改文件。Phase 1 月网格（核心），Phase 2 日详情，Phase 3 导出图，Phase 4 接入入口。无 schema 变更。

**Tech Stack:** Swift 5 / SwiftUI / SwiftData / iOS 17+ / XcodeGen

**Spec:** `docs/specs/2026-04-07-monthly-overview.md`

**Build verify:** `cd /Users/xujifeng/dev/TomatoSchedule && xcodegen generate && xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`

---

## Phase 1: 月网格总览

### Task 1: 创建 DayAvailabilityCell 单元格组件

**Files:**
- Create: `TomatoSchedule/Views/Schedule/DayAvailabilityCell.swift`

- [ ] **Step 1:** 创建单天单元格组件，包含：
  - 输入：`date: Date`、`busyBins: [Bool]`、`lessonCount: Int`、`isCurrentMonth: Bool`、`isToday: Bool`
  - 布局：日期数字（顶部）+ 垂直忙闲条（中部 8×40pt）+ 课时数角标（底部）
  - 忙闲条：遍历 `busyBins`，每格高度 = `40 / bins.count`，占用格填 teal，空闲格填 `.quaternary.opacity(0.3)`，圆角 2pt
  - 状态样式：今天金色圆底、过去日期 opacity(0.5)、非当月 opacity(0.3)、无课不显示课时数
  - 单元格约 50×72pt

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat: add DayAvailabilityCell for monthly overview grid`

### Task 2: 创建 MonthlyOverviewView 月网格主视图

**Files:**
- Create: `TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift`

- [ ] **Step 1:** 创建月度总览主视图，包含：
  - `@Query private var allLessons: [Lesson]`
  - `@State private var displayMonth: Date = .now`
  - 月份导航栏（◀ 标题 ▶）
  - 星期标题行（一-日）
  - 7 列 LazyVGrid，每格一个 `DayAvailabilityCell`
  - 底部图例说明（两行：■ 已排课 □ 可约 + 粗粒度提示）
  - 计算属性：`lessonsInMonth`、`lessonsByDate`、`timeRange`（动态）、`busyBins(for:)`、`weeksInMonth`
  - 月份翻页 `moveMonth(_:)` + "回到本月"按钮
  - 点击日期格子暂时只打印（日详情在 Task 3 接入）

- [ ] **Step 2:** Build verify
- [ ] **Step 3:** Commit: `feat: add MonthlyOverviewView with busy grid + month navigation`

---

## Phase 2: 日时间轴详情

### Task 3: 创建 DayScheduleDetailView 日详情

**Files:**
- Create: `TomatoSchedule/Views/Schedule/DayScheduleDetailView.swift`
- Modify: `TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift`

- [ ] **Step 1:** 创建日时间轴详情视图，包含：
  - 输入：`date: Date`、`allLessons: [Lesson]`、`timeRange: (start: Int, end: Int)`
  - 可选 `onNavigateToSchedule: ((Date) -> Void)?` 回调
  - 纵向 ScrollView 时间轴：每小时 60pt 高，左侧小时刻度标签
  - 课时块渲染：课程颜色 + 块内课程名/学生名
  - `TimeBlock` 数据结构（id、startMinutes、durationMinutes、colorHex、courseName、studentName）
  - 重叠分组 `overlapGroups(for:)` — sweep-line + maxEndTime
  - lane 分配 `assignLanes(for:)` — 贪心最多 2 列 + 溢出 badge
  - 重叠区域橙色竖线标记
  - 底部"在课表中查看"按钮

- [ ] **Step 2:** 在 `MonthlyOverviewView` 中接入日详情：
  - `@State private var selectedDay: Date?`
  - 点击 `DayAvailabilityCell` 设置 `selectedDay`
  - `.sheet(item:)` 展示 `DayScheduleDetailView`，detents `.medium` 和 `.large`

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat: add DayScheduleDetailView with time axis + overlap handling`

---

## Phase 3: 导出分享图

### Task 4: 创建 MonthlyExportCard 导出图 + 分享功能

**Files:**
- Create: `TomatoSchedule/Views/Schedule/MonthlyExportCard.swift`
- Modify: `TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift`

- [ ] **Step 1:** 创建导出分享图视图，包含：
  - 输入：`month: Date`、`lessonsByDate: [Date: [Lesson]]`、`timeRange: (start: Int, end: Int)`
  - 固定宽度 390pt，白色背景
  - 标题：`番茄课表 · M月排课总览`
  - 图例：`■ 已排课（不可约） □ 空闲（可约）`
  - 时间轴标签行（按 timeRange 动态）
  - 每天一行水平时间条：左侧日期+星期，右侧时间条（占用=teal，空闲=灰）
  - 只包含今天及以后的日期行
  - 重叠区域颜色加深（opacity 1.0 vs 0.85）
  - 底部：导出时间戳 + 引导文案
  - 隐私安全：无课程名/学生名/课程图例

- [ ] **Step 2:** 在 `MonthlyOverviewView` 中接入分享功能：
  - toolbar 添加"导出图片"按钮（`square.and.arrow.up` 图标）
  - `ImageRenderer` 渲染 `MonthlyExportCard`，scale=3
  - `UIActivityViewController` 包装的 `ShareSheet` 弹出分享面板
  - 渲染时显示 loading indicator

- [ ] **Step 3:** Build verify
- [ ] **Step 4:** Commit: `feat: add MonthlyExportCard + share functionality`

---

## Phase 4: 接入主导航

### Task 5: ScheduleView 入口

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/ScheduleView.swift`

- [ ] **Step 1:** 添加状态：`@State private var showingOverview = false`

- [ ] **Step 2:** 修改 toolbar leading 区域，与"今天"按钮并列添加总览按钮（icon-only）：
  ```swift
  HStack(spacing: 12) {
      Button("今天") { ... }
      Button { showingOverview = true } label: {
          Image(systemName: "rectangle.grid.1x2")
      }
      .accessibilityLabel("月度排课总览")
  }
  ```

- [ ] **Step 3:** 添加 `.fullScreenCover(isPresented: $showingOverview)` 展示 `MonthlyOverviewView`，传入 `onSelectDate` 回调跳转到主课表对应日期。

- [ ] **Step 4:** Build verify
- [ ] **Step 5:** Commit: `feat: add monthly overview entry in ScheduleView toolbar`

---

## 收尾

### Task 6: 最终构建验证

- [ ] **Step 1:** 完整构建验证
- [ ] **Step 2:** Commit: `chore: mark monthly overview spec as implemented`
