# 月度总览横屏周视图 — 设计规格文档

> 日期：2026-04-15
> 版本：draft
> 状态：待评审
> 关联：扩展自 `docs/specs/2026-04-07-monthly-overview.md`

---

## 1. 背景与目标

现有 `MonthlyOverviewView`（月度总览）在竖屏下以月网格形式一屏呈现全月忙闲趋势。用户反馈：**竖屏状态下每个日期单元格内的时间块过小**，难以辨认单节课的起止时间与持续时长。

用户希望在旋转至横屏时，页面自动切换到参考 **Apple Calendar 周视图**的布局，以便看清一周内每节课的精确时间分布。

**核心目标：**

- 横屏进入**周视图**：横轴 7 天、纵轴时间轴，与 Apple Calendar 周视图交互心智一致
- 左右滑动切换相邻周，上下滚动查看更多时间段
- 时间轴默认展示 9:00–21:00（约 6 小时可视 + 上下滚动），必要时自动扩展
- 旋转回竖屏自动回到月视图，页面状态连续
- 点击课时块弹出**信息卡片**（preview-only），与竖屏交互一致
- **仅月度总览页面**支持横屏，App 其它页面保持竖屏

**明确不做的：**

- 不引入编辑能力（长按 resize / 拖拽 move / 空白新建）— 延续"月度总览即预览"定位
- 不改动 `Lesson` / `Course` 数据模型
- 不做 iPad 多列适配（iPhone 为主，架构为未来扩展留余地即可）
- 不做自动化 UI 测试（与现有项目风格一致）

---

## 2. 总体架构：容器 + 子视图

`MonthlyOverviewView` 重构为轻薄容器，按 `@Environment(\.verticalSizeClass)` 切换子视图：

```
MonthlyOverviewView (容器)
│  @Query allLessons
│  @State displayedMonth, selectedWeekStart, selectedLesson
│  @Environment verticalSizeClass
│
├── compact == false (竖屏)
│   └── MonthCalendarView     ← 从现有代码抽离
│
└── compact == true (横屏)
    └── WeekTimelineView       ← 新增
```

**抽取与职责划分：**

- `MonthlyOverviewView`：状态容器，不含视觉元素；处理方向锁解除/恢复、方向切换时的状态桥接
- `MonthCalendarView`：竖屏月网格（原 `MonthlyOverviewView` 的月视图逻辑整体搬迁）
- `WeekTimelineView`：横屏周视图容器（TabView pager + 顶栏 + 缓存）
- `WeekContentView`：单周页面渲染
- `LessonLaneLayout`（helper）：车道分配公共算法，周视图与 `DayScheduleDetailView` 共用
- `WeekSnapshot`（helper）：一周的数据聚合结构

该方案与近期 Phase 1-4 重构"抽子视图 + 提 helpers"的方向一致。

---

## 3. 方向策略

### 3.1 全局解锁 + 页面级锁定

1. **`project.yml`**：将 `UISupportedInterfaceOrientations_iPhone` 改为 `[Portrait, LandscapeLeft, LandscapeRight]`
2. **`TomatoScheduleApp.swift`**：注入 `UIApplicationDelegateAdaptor(AppDelegate.self)`
3. **`AppOrientationLock`（新）**：`ObservableObject` 单例，持有 `allowed: UIInterfaceOrientationMask`，默认 `.portrait`
4. **`AppDelegate`**：`application(_:supportedInterfaceOrientationsFor:)` 返回 `AppOrientationLock.shared.allowed`

### 3.2 MonthlyOverviewView 生命周期

- `onAppear`：`AppOrientationLock.shared.allowed = .allButUpsideDown`
- `onDisappear`：
  - `AppOrientationLock.shared.allowed = .portrait`
  - `UIApplication.shared.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))` 强制锁回

### 3.3 内部方向感知

- 容器用 `@Environment(\.verticalSizeClass)`（`compact` = 横屏）切换子视图
- **不监听** `UIDevice.orientationDidChangeNotification`（与 SwiftUI 生命周期冲突概率高）

---

## 4. 横屏视觉结构

### 4.1 整体布局

```
┌──────────────────────────────────────────────────┐
│  ×    2026 年 4 月 13 – 19 日      今天  ⓘ      │ ← 顶栏 56pt
├────┬────────┬────────┬────────┬────────┬────┬───┤
│    │ 一 13  │ 二 14  │ 三 15  │ 四 16  │ …  │日 │ ← 表头 40pt
├────┼────────┴────────┴────────┴────────┴────┴───┤
│ 9  │ ╭──────╮                                      │
│    │ │小王  │                                      │
│10  │ │09:30 │    ╭──────╮                          │
│    │ ╰──────╯    │小李  │                          │
│11  │             │10:30 │                          │
│    │ ═══════════╪══════╪════════════════   ← 现在 │
│12  │             ╰──────╯                          │
│ ..                                                 │
│21  │                                               │
└────┴──────────────────────────────────────────────┘
   48pt           每列等宽                上下滚动 · 左右翻页切周
```

### 4.2 顶栏（固定 56pt）

| 元素 | 位置 | 行为 |
|---|---|---|
| 关闭 × | 左 | 退出 MonthlyOverviewView（等同竖屏） |
| 周范围标题 | 居中 | `"2026 年 4 月 13 – 19 日"`；跨年周带年份前缀 |
| 今天按钮 | 右 | 非本周时激活（teal 填充）；点击 → 切回本周页 + 滚到当前时刻 + success 触觉 |
| ⓘ 图例按钮 | 右 | 可选；弹出课程颜色图例（复用 `PresetColors`） |

### 4.3 星期表头（固定 40pt）

- 7 列 `GridItem(.flexible())`，每列：上行 `一/二/.../日`（12pt footnote）、下行日期数字（20pt semibold）
- **今日**：数字外套 teal 圆底（复用 `Color(red: 0.34, green: 0.77, blue: 0.72)`）
- **周末**（六、日）：背景 `.secondary.opacity(0.04)` 色调区分

### 4.4 时间轴列（sticky 左 48pt）

- 整点标签右对齐，13pt caption，`.secondary`
- 每小时高 **80pt**；默认 9–21 共 12h = 960pt
- 半点细虚线分隔（可选，增强时间感知）

### 4.5 内容网格（横向翻页 + 纵向滚动）

- 一周一"页"，`TabView(selection:).tabViewStyle(.page(indexDisplayMode: .never))`
- 分页 identity = 该周周一 00:00 的 `Date`
- 每页内容：7 列 × (end - start) 小时 ZStack
- 背景：每小时横线（`Divider().opacity(0.25)`）；今日列轻微 teal tint `opacity(0.04)`

### 4.6 课时块

- 圆角 6pt，左侧 4pt 实心色条 = 课程色（`course?.colorHex`）
- 填充 = 课程色 `opacity(0.15)`（已完成课时降至 `0.08`，左色条保持原强度表示"淡出"）
- 块内文字：
  - 上行：学生姓名（11pt, semibold）
  - 下行：`09:30–10:30`（10pt, regular, `.secondary`）
- 块高 < 28pt（约 ≤25 分钟课时）：单行仅显示学生姓名，缩 10pt 字号
- 重叠：车道平分宽度，最多 3 列并排，第 4 条以后以 "+N 更多" 角标合并（右下角 10pt 气泡）

### 4.7 现在时刻指示线

- 仅当视图页包含今天 **且** 当前时刻在可见时间范围内时渲染
- 整条横线横跨 7 列，颜色 `Color(.systemRed)`，线宽 1pt
- 今日列起点处 6pt 红点
- 刷新频率：`TimelineView(.periodic(from: .now, by: 60))`

---

## 5. 竖屏月视图（不变）

竖屏延续当前 `MonthlyOverviewView` 行为，改动仅为**文件搬迁**：

- 月网格 + snapshot + MiniBlock + 拖拽切月逻辑整体迁到 `MonthCalendarView.swift`
- 视觉与行为 0 变更
- `@Query allLessons` 上移至容器
- "显示学生" toggle 仍在竖屏月视图右上（不影响横屏）

---

## 6. 交互详述

### 6.1 左右切周

- 滑动 → 系统原生弹性 + snap 动画
- 切周瞬间轻触觉反馈（`UIImpactFeedbackGenerator(style: .light)`）
- 预加载前后各 1 周数据；更远周懒加载

### 6.2 纵向滚动

- **每周独立 `ScrollView`**，滚动位置互相独立
- 初次进入（本周）：自动滚到当前时间前 30 分钟，"现在"在视图上部约 1/3 处
- 切到历史/未来周：起始位置 = 9:00
- 点"今天"：切回本周页 + 立即滚到当前时刻 + success 触觉

### 6.3 块点击（preview 弹窗）

- 轻点 → `LessonInfoPopover`
  - 内容：课程名 · 学生 · 完整时间 · 时长 · 备注 · 价格（若 > 0）
  - 形态：iOS 原生 `.popover`（iPhone 自动回退 `.sheet(.medium)`）
  - 关闭：点击外部 / 下拉
- 点击瞬间 `scaleEffect(0.97)` 0.1s 微反馈
- **禁用** 长按、拖拽、空白区新建（与 preview-only 定位一致）

### 6.4 旋转过渡

- 容器对 `verticalSizeClass` 变化加 `.animation(.easeInOut(duration: 0.3))`
- 月/周视图间交叉淡入淡出（`.transition(.opacity)`）
- 旋转保持 `selectedWeekStart`（见 §7.2）

### 6.5 空周态

- 无任何课时的周：不显示空态卡片（会打断横向翻页节奏）
- 时间网格底部居中一行淡灰色 "本周无课时安排"

### 6.6 Popover/旋转冲突

- popover 打开时用户旋转：`onChange(of: verticalSizeClass)` 立即 `selectedLesson = nil`
- popover 打开时切周：翻页 gesture `onChanged` 立即关闭 popover

### 6.7 无障碍

- 每个块 `.accessibilityElement(children: .ignore)` + 合并 label `"学生 小王，课程 数学，9:30 至 10:30"`
- 时间轴列 `.accessibilityHidden(true)`（纯装饰）
- 「今天」按钮 `.accessibilityLabel("回到本周")`

---

## 7. 数据流与共享状态

### 7.1 容器状态

```swift
struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @State private var displayedMonth: Date
    @State private var selectedWeekStart: Date?   // 懒初始化
    @State private var selectedLesson: Lesson?
    @Environment(\.verticalSizeClass) private var vSize
    let onSelectDate: (Date) -> Void
}
```

### 7.2 方向切换的 state 约定

- **竖 → 横**：若 `selectedWeekStart == nil` 或不属于 `displayedMonth`，重新推导：
  - `displayedMonth` 包含今天 → 本周周一
  - 否则 → `displayedMonth` 第一周的周一
- **横 → 竖**：`displayedMonth` 保持不变
- **退出**：容器销毁自动清理

### 7.3 核心数据结构

```swift
// Helpers/WeekSnapshot.swift
struct WeekSnapshot {
    let weekStart: Date            // Monday 00:00
    let days: [DayColumn]          // 恰好 7 项
    let timeRange: (start: Int, end: Int)  // 默认 (9, 21)
}

struct DayColumn {
    let date: Date
    let isToday: Bool
    let isWeekend: Bool
    let blocks: [PlacedBlock]      // 已完成车道分配
}

struct PlacedBlock: Identifiable {
    let id: UUID                   // = lesson.id
    let lesson: Lesson
    let lane: Int
    let laneCount: Int
    let startMinutesFromRangeStart: Int
    let durationMinutes: Int
}
```

### 7.4 车道分配 helper

```swift
// Helpers/LessonLaneLayout.swift
enum LessonLaneLayout {
    /// 经典扫描线算法：按 startTime 排序，贪心分配到最早空闲车道
    /// 返回 (lesson, lane, laneCount)，laneCount 是课时所在"冲突簇"的最大并发数
    static func assignLanes(_ lessons: [Lesson]) -> [(Lesson, lane: Int, laneCount: Int)]
}
```

从 `DayScheduleDetailView` 内联车道逻辑提取，同时重构 `DayScheduleDetailView` 使用该 helper，单元测试覆盖。

### 7.5 快照缓存

- `WeekTimelineView` 内 `@State cache: [Date: WeekSnapshot]`
- LRU 保留 5 个（当前页 ± 2 周）
- `allLessons` 变化 → 整 cache 作废，重算可见周

### 7.6 数据流图

```
@Query allLessons ─→ MonthlyOverviewView (container)
                        │
                        ├─ displayedMonth ────→ MonthCalendarView (竖屏)
                        │
                        └─ selectedWeekStart ─→ WeekTimelineView (横屏)
                                                   │ TabView pager
                                                   ▼
                                              [week = D] WeekContentView
                                                   │
                                                   ├─ 从 allLessons 筛 7 日
                                                   ├─ WeekSnapshot.build()
                                                   │    └─ LessonLaneLayout.assignLanes()
                                                   └─ 渲染 7 列网格 + 现在线
```

---

## 8. 边界情况

### 8.1 时间范围

| 情形 | 处理 |
|---|---|
| 周内存在 8:00 课时 | timeRange 扩展至 (8, 21) |
| 周内存在 22:00 结束课时 | timeRange 扩展至 (9, 22) |
| 极端：6:00–23:00 跨度 | 扩展至 (6, 23)，一次性 snapshot |
| 某周无课时 | timeRange = (9, 21)，底部一行 "本周无课时安排" |
| 今天时刻在扩展范围之外 | 不绘制现在指示线 |

### 8.2 重叠与块形状

| 情形 | 处理 |
|---|---|
| 两节课完全同时 | lane 0 / lane 1，各 1/2 宽度 |
| 3+ 节同时重叠 | 车道最多 3 列；第 4 条起以 "+N 更多" 角标合并 |
| 课时 < 15 分钟 | 最小块高 18pt，单行显示学生名，字号 10pt |
| 课时 > 8h（异常） | 正常渲染，时间轴自动扩展 |
| 跨天课时（endTime 跨日期） | 只在 startTime 当日渲染，截断至 23:59，右下箭头 ⤓ 提示 |

### 8.3 课程/颜色缺失

| 情形 | 处理 |
|---|---|
| `lesson.course == nil` | 块色中性灰 `#94A3B8`；popover 课程名显示 "未关联课程" |
| `colorHex` 非法 | `Color(hex:)` 失败回退默认 teal |
| `studentName` 为空 | 块内 "无学生"；popover 用 course.name 兜底 |
| `studentName` 过长 | `.lineLimit(1).truncationMode(.tail)` |

### 8.4 课时状态

| 情形 | 处理 |
|---|---|
| `isCompleted == true` | 填充降至 `opacity(0.08)`，左色条保持 |
| 价格为 0 或未设置 | popover 价格行隐藏 |

### 8.5 切周与时间边界

| 情形 | 处理 |
|---|---|
| 左右翻页无上限 | 允许任意方向，不做硬限制 |
| 跨年周 | 顶栏显示 "2025 年 12 月 29 日 – 2026 年 1 月 4 日"（含年份） |
| 本周进入时当前时间 < 9:00 | 滚动位置 = 9:00（不能负偏移） |

### 8.6 旋转/弹窗冲突

| 情形 | 处理 |
|---|---|
| popover 打开时旋转 | 立即 `selectedLesson = nil` |
| popover 打开时切周 | 翻页手势触发时关闭 popover |
| 退出时方向未解锁 | 双保险：`AppOrientationLock = .portrait` + `requestGeometryUpdate` |

### 8.7 其它

- **Dark Mode**：语义色 + `Color(hex:)` 自适应，不另配色
- **小屏（SE）**：最小列宽 40pt；总宽 48 + 7×40 = 328pt，SE 横屏 667pt 宽绰绰有余
- **Dynamic Type**：表头/时间轴/popover respect Dynamic Type；块内文字 `fixedSize(.vertical)` 并限制最大字号，保持网格整齐

---

## 9. 文件结构与规模

### 9.1 新增（9 个）

```
TomatoSchedule/
├── Helpers/
│   ├── AppOrientationLock.swift        ← ObservableObject + AppDelegate 支持
│   ├── LessonLaneLayout.swift          ← 车道分配算法
│   └── WeekSnapshot.swift              ← 快照结构 + builder
└── Views/
    └── Schedule/
        ├── MonthCalendarView.swift     ← 抽离的竖屏月网格
        └── WeekTimeline/
            ├── WeekTimelineView.swift  ← 横屏容器 + TabView 分页
            ├── WeekContentView.swift   ← 单周页面（含 TimeAxisColumn 私有子视图）
            ├── WeekHeaderRow.swift     ← 7 列星期+日期表头
            ├── LessonBlockView.swift   ← 课时块 + popover 绑定
            └── NowIndicatorView.swift  ← 现在时刻红线 + Timer
```

### 9.2 修改（4 个）

| 文件 | 改动 |
|---|---|
| `project.yml` | `UISupportedInterfaceOrientations_iPhone` → `[Portrait, LandscapeLeft, LandscapeRight]` |
| `TomatoScheduleApp.swift` | 注入 `UIApplicationDelegateAdaptor(AppDelegate.self)` |
| `MonthlyOverviewView.swift` | 降级为容器（80-100 行，下降自 306） |
| `DayScheduleDetailView.swift` | 内联车道逻辑替换为 `LessonLaneLayout.assignLanes(...)` |

### 9.3 规模估算

| 文件 | 预计行数 | 核心职责 |
|---|---|---|
| `AppOrientationLock.swift` | ~60 | `ObservableObject` 单例 + `AppDelegate` 读 allowed mask |
| `LessonLaneLayout.swift` | ~70 | 纯函数，扫描线分配车道 |
| `WeekSnapshot.swift` | ~100 | 数据结构 + `build(weekStart:lessons:)` |
| `MonthCalendarView.swift` | ~250 | 竖屏月网格（原样搬迁） |
| `WeekTimelineView.swift` | ~150 | TabView pager + 顶栏 + 缓存 |
| `WeekContentView.swift` | ~220 | 单周 ScrollView + 网格 + 时间轴 + 块遍历 |
| `WeekHeaderRow.swift` | ~80 | 7 列等宽，today 圆底，周末 tint |
| `LessonBlockView.swift` | ~100 | 块 UI + tap gesture + popover |
| `NowIndicatorView.swift` | ~60 | `TimelineView(.periodic)` + 红线 + 红点 |

**新增代码**：~1090 行；**净增量**：~800 行（`MonthlyOverviewView` 减 220，`DayScheduleDetailView` 瘦 30）。

---

## 10. 测试与验收

### 10.1 单元测试

`TomatoScheduleTests/LessonLaneLayoutTests.swift`（~80 行）：

- 无重叠：全部 lane=0, laneCount=1
- 两节完全重叠：lane=0/1, laneCount=2
- 三节部分重叠但簇大小=2：两条车道复用
- 同起点、不同结束：按排序稳定性验证
- 边界：空输入、单节课

### 10.2 手工验收清单

- [ ] 竖屏 → 横屏：定位到当月今天所在周（若今天不在该月则定位第一周）
- [ ] 横屏 → 竖屏：`displayedMonth` 保持
- [ ] 无课周横滑无 crash
- [ ] 重叠 2-3 节课车道分配正确
- [ ] 越界课时（8:00 / 22:00）触发时间轴扩展
- [ ] popover 在切周/旋转时立即关闭
- [ ] "今天"按钮本周时置灰不可点
- [ ] 跨年周顶栏含年份
- [ ] 退出页面后其它页面保持竖屏
- [ ] 现在指示线每分钟刷新位置
- [ ] Dark Mode 下颜色对比度满足可读性
- [ ] 已完成课时视觉淡化但仍可辨认

### 10.3 不做项

- 不做自动化 UI 测试（与项目现状一致）
- 不做 iPad 专属布局（但容器架构为未来扩展留余地）

---

## 11. 风险与回滚

### 11.1 风险

| 风险 | 缓解 |
|---|---|
| `AppOrientationLock` API 版本兼容 | 项目最低 iOS 17（SwiftData 前提），`requestGeometryUpdate` 在 iOS 16+ 可用，安全 |
| `TabView(.page)` 快速滑动偶发渲染延迟 | SwiftUI 已知表现；可接受，后续观察 |
| `@Query` 全量加载性能 | 当前教师数据量 <数千课时，内存过滤 <10ms；若未来 > 5000 再考虑谓词 |
| 方向解锁影响其它页面 | 页面级 `onAppear/onDisappear` 双重保险 + `AppDelegate` 动态读取 |

### 11.2 回滚方案

所有改动集中在：
- `Views/Schedule/` 子树
- 3 个新 helper 文件
- `project.yml` + `TomatoScheduleApp.swift` 的方向改动（可单独 revert）

按文件粒度回退不影响其它功能。

---

## 12. 开放问题

- **ⓘ 图例按钮**是否必要？当前倾向保留作为次级入口，若用户验收时觉得冗余可在实施阶段移除
- **半点虚线**在时间轴上是否过密？默认开启，横屏实际渲染后若感觉杂乱可关闭

这两项留到实施/验收阶段决定，不阻塞设计定稿。

---

**下一步**：本设计待 codex review 与用户确认后，进入 writing-plans 阶段生成实施计划。
