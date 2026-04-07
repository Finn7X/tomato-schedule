# 月度排课总览 视觉重设计 实现计划

> **目标：** 修复月度总览的视觉和可用性问题，从"能用"提升到"好看好用"

**用户反馈的 5 个问题：**
1. 入口按钮样式丑，与"今天"按钮捆绑不合理
2. 时间条太窄（8pt），没有时间标注
3. 日历只占屏幕一半，应该充满全屏
4. 日期数字横向没有对齐
5. 整体样式太丑，不像正式应用

**功能变更：**
- 取消导出图片和分享功能（删除 MonthlyExportCard + ShareSheet）
- 右上角改为"显示学生"按钮：点击后忙闲条上显示学生名字

---

## 重设计方案

### 入口按钮

**当前：** `rectangle.grid.1x2` 图标紧贴"今天"按钮
**改为：** 独立的 toolbar item（trailing 位置），使用 `calendar.day.timeline.left` 图标（更贴合"时间轴总览"语义）

```swift
// 将总览按钮从 topBarLeading 移到 topBarTrailing 区域（和 + 菜单同侧）
// 或者放在 navigationTitle 旁边
ToolbarItem(placement: .topBarLeading) {
    Button("今天") { ... }  // 恢复单独
}
ToolbarItem(placement: .primaryAction) {
    HStack(spacing: 16) {
        Button { showingOverview = true } label: {
            Image(systemName: "calendar.day.timeline.left")
        }
        Menu { ... } label: { Image(systemName: "plus") }
    }
}
```

### 月网格页面全面重设计

#### 布局：全屏撑满

**目标：** 日历格子填满整个安全区域，不留大块空白。

```
可用高度计算（iPhone SE，最小屏）：
- 屏幕安全区：~600pt
- inline 导航栏（含月份标题+按钮）：~44pt
- 星期行：~20pt
- 图例行：~24pt
- 可用于网格：~512pt
- 5 周：512 / 5 ≈ 102pt per row
- 6 周：512 / 6 ≈ 85pt per row
```

单元格高度动态计算：`(availableHeight) / weeksCount`，最小 80pt。

#### 单元格重设计

**当前（50×72pt）：**
```
┌──────┐
│  7   │
│ ▐██▐ │  ← 8pt 宽忙闲条，无时间标注
│  3节 │
└──────┘
```

**重设计（~50×85-102pt）：**
```
┌─────────────┐
│ 7        2节 │  ← 日期(左对齐) + 课时数(右对齐)
│              │
│ ┃████░░██░░┃ │  ← 水平时间条(占满宽度，高12pt)
│ 8   12  16 20│  ← 微型时间刻度(仅在首行显示)
│              │
└─────────────┘
```

**核心变更——水平时间条替代垂直忙闲条：**

- 方向从垂直改为**水平**，占满单元格宽度（减去左右 padding 4pt）
- 高度 12pt，圆角 3pt
- 时间范围 8:00-22:00（固定，用于可视化一致性）
- 1 小时 bins → 14 格水平排列
- 占用格：主题色 teal
- 空闲格：`.quaternary.opacity(0.3)`

**时间刻度参考线：**
- 只在**每周第一行**（周一那行）的单元格底部显示微型时间刻度
- 或者在网格顶部（星期行下方）显示一次性的时间轴标注行
- 标注关键小时：8, 10, 12, 14, 16, 18, 20, 22

**推荐方案：** 在星期标题行和网格之间插入一行全局时间轴标签：
```
一    二    三    四    五    六    日
8 10 12 14 16 18 20 22  (每个 cell 宽度内重复，或全局一行)
```

实际上由于每列只有 ~50pt 宽，放不下 8 个数字。改为：只在第一列左下角显示 `8:00` 和右下角显示 `22:00`，中间用灰色竖线标注 12:00 和 18:00 位置。

**最终方案——时间条内部标记：**
- 在每个水平时间条上，用细竖线（0.5pt, 半透明白色）标记 12:00 和 18:00 两个中线位置
- 这样用户一看就知道上午/下午/晚上的分布
- 不需要文字标注，视觉上已经足够传达时间分布

#### 日期数字对齐

**问题：** 当前日期数字用 VStack 居中，不同位数（7 vs 17）导致水平位置不稳定。

**修复：** 日期数字左上角对齐，固定位置：
```swift
Text("\(day)")
    .font(.system(size: 12, weight: isToday ? .bold : .regular))
    .frame(maxWidth: .infinity, alignment: .leading)
```

课时数右上角对齐：
```swift
HStack {
    Text("\(day)")
    Spacer()
    if lessonCount > 0 { Text("\(lessonCount)节").font(.system(size: 9)) }
}
```

#### "显示学生"模式

右上角按钮从"导出"改为"显示学生"（`person.fill` 图标）。

**默认模式：** 时间条显示纯色忙闲（隐私安全，适合截图）
**学生模式：** 时间条上方叠加学生名字标签

```
默认：
│ ┃████░░██████░░░░┃ │

显示学生：
│ ┃石宇░░傅褚备░░░░┃ │
```

实现方式：在每个占用的时间段上叠加一个文字标签，显示该时段的学生名。文字 `.system(size: 7)` 白色，超出截断。

#### 视觉风格提升

**当前问题：** 纯白背景 + 简单矩形格子 = 像调试界面

**改进方向：**
- 月份导航区域使用 CalendarHeaderView 同款 teal 渐变背景
- 单元格之间用细线分隔而非空白
- 今天的单元格用浅 teal 背景高亮（非仅日期数字高亮）
- 有课的日期用微弱的 teal 背景渲染（让忙碌天和空闲天有视觉对比）
- 底部图例使用更紧凑的胶囊样式

**色彩系统：**
```
- 导航栏背景：teal 渐变（与 CalendarHeaderView 一致）
- 今天单元格背景：teal.opacity(0.08)
- 有课单元格背景：teal.opacity(0.03)
- 空闲单元格背景：clear
- 时间条占用：teal
- 时间条空闲：gray.opacity(0.15)
- 网格线：.quaternary
```

---

## 实现任务

### Task 1: 重写 DayAvailabilityCell

**File:** `Views/Schedule/DayAvailabilityCell.swift` (完全重写)

- [ ] 接口改为接受 `cellHeight: CGFloat`（由父视图传入动态高度）
- [ ] 布局改为：顶部 HStack（日期左对齐 + 课时数右对齐），中部水平时间条，底部留空
- [ ] 水平时间条：HStack(spacing:0) 的 14 个 Rectangle，高度 12pt，圆角 3pt
- [ ] 时间条内 12:00 和 18:00 位置加 0.5pt 白色竖线标记
- [ ] 新增 `showStudentNames: Bool` 参数 + `studentNames: [String]` 参数（按时间段的学生名）
- [ ] 学生模式下在占用段上叠加学生名白色文字（.system(size: 7)）
- [ ] 今天单元格整体背景 teal.opacity(0.08)
- [ ] Build verify + commit

### Task 2: 重写 MonthlyOverviewView

**File:** `Views/Schedule/MonthlyOverviewView.swift` (大幅重写)

- [ ] 导航栏使用 teal 渐变背景（复用 CalendarHeaderView 配色）
- [ ] 去掉导出按钮和 ShareSheet，去掉 shareImage/showShareSheet 状态
- [ ] 右上角改为 `@State private var showStudents = false` + `person.fill` / `person` 图标切换
- [ ] 动态计算单元格高度：`(screenHeight - navHeight - weekdayHeight - legendHeight) / weeksCount`
- [ ] 传递 `cellHeight` 和 `showStudents` + 学生名数据给 DayAvailabilityCell
- [ ] 新增 `studentNames(for date:)` 方法：返回每个小时 bin 对应的学生名
- [ ] 网格用细线分隔（`.listRowSeparator` 或 Divider）
- [ ] 底部图例改为紧凑胶囊样式
- [ ] Build verify + commit

### Task 3: 删除 MonthlyExportCard + 清理

**Files:** 删除 `MonthlyExportCard.swift`，清理 MonthlyOverviewView 中的残留引用

- [ ] 删除 `Views/Schedule/MonthlyExportCard.swift`
- [ ] 从 MonthlyOverviewView 移除 `exportImage()`、`ShareSheet`、相关 state
- [ ] Build verify + commit

### Task 4: ScheduleView 入口按钮重设计

**File:** `Views/Schedule/ScheduleView.swift`

- [ ] 将总览按钮从 `topBarLeading` HStack 中移出
- [ ] 恢复"今天"按钮为独立 toolbar item
- [ ] 总览按钮改用 `calendar.day.timeline.left` 图标，放在合适位置
- [ ] Build verify + commit

### Task 5: 日详情保留但优化样式

**File:** `Views/Schedule/DayScheduleDetailView.swift`

- [ ] 保留当前功能（教师自查用）
- [ ] 顶部添加 teal 渐变色块与日期标题
- [ ] Build verify + commit

---

## 不做的事

- 不新增导出/分享功能（用户明确取消）
- 不改数据模型
- 不改日详情的核心逻辑（重叠分组/lane 分配保留）
