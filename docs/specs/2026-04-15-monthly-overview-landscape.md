# 月度总览横屏周视图 — 设计规格文档

> 日期：2026-04-15
> 版本：revision-4（修 PreviewContext 编译 blocker、统一全文合同术语、iOS 17 scroll helper 路径明确化、示例代码对齐真实 app 入口）
> 状态：待定稿确认
> 关联：扩展自 `docs/specs/2026-04-07-monthly-overview.md`；review 文档 `docs/reviews/2026-04-15-monthly-overview-landscape-review.md` + `docs/reviews/2026-04-15-monthly-overview-landscape-review-revision-2.md`

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
- 不重构竖屏月视图的视觉分层（Apple Calendar Compact/Stacked/Details 风格 — 见 §13.1 延后说明）

**顺带修复（低风险）：**

- `DayScheduleDetailView` 当同时段 ≥3 节课时现在会静默丢弃第 3+ 节（§5.2）。因本次重构已抽 `LessonLaneLayout` helper，顺手让日视图也支持 "+N" 角标展示被合并项，消除该体验 bug。

---

## 2. 总体架构：容器 + 子视图

`MonthlyOverviewView` 重构为轻薄容器，按 `@Environment(\.verticalSizeClass)` 切换子视图。**所有跨方向状态合并到单一 `focusDate`**：

```
MonthlyOverviewView (容器)
│  @Query allLessons
│  @State focusDate                    ← 单一 source of truth（§7.1）
│  @EnvironmentObject coordinator        ← app-scope 单例 AppOrientationCoordinator.shared（§3.1）
│  @Environment verticalSizeClass
│
├── compact == false (竖屏)
│   └── MonthCalendarView              ← 从现有代码抽离
│        │ @Binding focusDate
│        ├─ 内部 state: selectedDay, showStudents, slideForward, isAnimating
│        └─ DayScheduleDetailView (sheet)
│
└── compact == true (横屏)
    └── WeekTimelineView                ← 新增
         │ @Binding focusDate
         ├─ @State snapshotCache
         ├─ @State scrollAnchorByWeek
         ├─ @State pendingScrollRequest
         ├─ @State previewingContext
         ├─ WeekHeaderRow
         ├─ WeekContentView × N (TabView 分页)
         │   ├─ TimeAxisColumn (私有子视图)
         │   ├─ LessonBlockView × M
         │   └─ NowIndicatorView
         └─ LessonInfoCard (通过 .sheet(item:) 挂载，§6.3)
```

**抽取与职责划分：**

- `MonthlyOverviewView`：状态容器，不含视觉元素；只持有 `focusDate` 和方向协调器，处理方向进入/退出
- `MonthCalendarView`：竖屏月网格（原月视图逻辑整体搬迁，**自己持有**选中日、显示学生 toggle、动画方向等 state 与 `DayScheduleDetailView` sheet）
- `WeekTimelineView`：横屏周视图容器（TabView pager + 顶栏 + 快照缓存 + 滚动锚点 + preview 状态）
- `WeekContentView`：单周页面渲染（含时间轴列私有子视图）
- `WeekHeaderRow`：7 列星期+日期表头
- `LessonBlockView`：单个课时块，含 `+N` 角标渲染与 scaleEffect 点击反馈
- `NowIndicatorView`：红色现在时刻指示线 + Timer
- `LessonInfoCard`：preview 卡片（底部 sheet 内容，非 popover，§6.3）
- `AppOrientationCoordinator`（helper）：`ObservableObject` app-scope 单例，`AppDelegate` 据此动态决定支持方向（§3.1）
- `LessonLaneLayout`（helper）：返回 `ConflictCluster[]`，周视图与 `DayScheduleDetailView` 共用（§7.4）
- `WeekSnapshot` / `ConflictCluster` / `PlacedBlock`（helper）：数据模型层承接 `+N` 合并与跨天截断（§7.3）

该方案与近期 Phase 1-4 重构"抽子视图 + 提 helpers"的方向一致。

---

## 3. 方向策略

### 3.1 方向控制：单 scene 下的闭环所有权

iPhone 版的方向请求是 **`UIWindowScene` 的 API**，不是 `UIApplication` 的。方案采用"Info.plist 全局声明支持 → `AppDelegate` 动态限向 → 进入/退出页面时对当前 scene 请求 geometry update"的三段式。

本 spec 按 **iPhone 单 scene** 落地，`AppOrientationCoordinator` 设计为**应用级单例**（honest singleton），同时注入 SwiftUI environment，保证 AppDelegate 与 View 共享同一实例。未来扩展多 scene（iPad Stage Manager / Split View）时，升级为 `WindowScene → Coordinator` registry（见 §13.4）。

**完整合约**：

```swift
// Helpers/AppOrientationCoordinator.swift
final class AppOrientationCoordinator: ObservableObject {
    static let shared = AppOrientationCoordinator()        // AppDelegate 读取入口
    @Published var allowedMask: UIInterfaceOrientationMask = .portrait

    private init() {}

    /// 请求当前 active window scene 旋转到指定方向
    /// - Parameter target: 目标方向 mask（通常是 .portrait 或 .landscape）
    func requestOrientation(_ target: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.activeWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
            // log-only，不中断 UX
        }
    }
}

// Helpers/AppOrientationCoordinator.swift（续）
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // 单 scene：直接读 shared；未来多 scene 时通过 window.windowScene 查 registry
        AppOrientationCoordinator.shared.allowedMask
    }
}

extension UIApplication {
    var activeWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
```

**注入规则（唯一写法）**：

1. **`project.yml`**：将 `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` 从 `"UIInterfaceOrientationPortrait"` 改为包含 `Portrait + LandscapeLeft + LandscapeRight` 的数组值（xcodegen YAML 支持字符串数组，具体语法在 plan 阶段确认）
2. **`TomatoScheduleApp.swift`**：
   ```swift
   @main
   struct TomatoScheduleApp: App {
       @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
       @StateObject private var orientationCoordinator = AppOrientationCoordinator.shared

       var body: some Scene {
           WindowGroup {
               MainTabView()
                   .environmentObject(orientationCoordinator)
                   .onAppear { migrateV5PriceFreeze(); autoCompletePastLessons() }
           }
           .modelContainer(for: [Course.self, Lesson.self])
       }
   }
   ```
   - `@StateObject` 的初始值就是 `.shared`，不会产生第二个实例；确保 view 树任何 `@EnvironmentObject AppOrientationCoordinator` 读到的与 AppDelegate 读到的是同一对象
3. **`MonthlyOverviewView`**：`@EnvironmentObject private var coordinator: AppOrientationCoordinator`，**不再自建 `@StateObject`**。容器只读/改 `coordinator.allowedMask` 和调 `coordinator.requestOrientation(...)`；读写路径与 AppDelegate 完全一致
4. **AppDelegate 回调**：读取 `AppOrientationCoordinator.shared.allowedMask`，闭环

**为什么这么设计**：
- 过去版本中同时写了 "页面私有 `@StateObject`" + "App 级 environment" + "AppDelegate 直读"，三者不自洽
- 当前方案唯一合同：**app-scope 单例 + SwiftUI environment 注入 + AppDelegate 读 shared**，所有路径读到同一份 `allowedMask`
- 多 scene 的演进路径见 §13.4，本轮不做

### 3.2 进入/退出时机（主路径 + 兜底路径）

**进入 `MonthlyOverviewView`**：

- `onAppear`：`coordinator.allowedMask = .allButUpsideDown`（仅**解锁**，不主动请求旋转）
- **不强制横屏**：若用户进入时已横持手机，系统会在解锁后自然旋转到 landscape；若用户竖持，保持竖屏月视图。这与 Apple Calendar 行为一致

**退出 `MonthlyOverviewView`**：

主路径优先于兜底路径触发，避免"先关闭 → 再旋转"的突兀感。

- **主路径（显式关闭按钮）**：用户点 × 触发 `dismissWithOrientationRestore()`：
  1. 若 scene 当前处于横屏 → `coordinator.requestOrientation(.portrait)` 并 delay 最小动画帧（~200ms，Apple Calendar 实测值）
  2. 再 `coordinator.allowedMask = .portrait`
  3. 最后 `dismiss()`
  4. 用户视觉感受：屏幕先平滑旋回竖屏，再退出 cover
- **兜底路径（`onDisappear`）**：仅负责恢复 mask，不再强行 request geometry：
  1. `coordinator.allowedMask = .portrait`
  2. 不调 `coordinator.requestOrientation(.portrait)`——若用户绕过主路径（如 gesture 下拉、父 view 被销毁），此时 cover 已开始消失动画，强行请求旋转会让底层 ScheduleView（竖屏锁定）瞬间跳转，视觉割裂

**代码要点**：所有 scene 相关调用都通过 `coordinator.requestOrientation(...)` 一个口子走，不在 View 里直接拿 `UIApplication.shared.activeWindowScene`，保持调用路径单一

### 3.3 内部方向感知

- 容器用 `@Environment(\.verticalSizeClass)`（`compact` = 横屏）切换子视图——这是 Apple 推荐的 adaptive UI 机制，响应 size class 变化而非监听硬件方向
- **不监听** `UIDevice.orientationDidChangeNotification`（与 SwiftUI 生命周期冲突概率高，且不响应 Stage Manager / 外接屏幕等 size-class 变化场景）

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
- 每小时高 **80pt**；默认 9–21 共 12h = 960pt 内容高度
- 扩展后最大可能范围（6–23）= 17h = 1360pt 内容高度；`ScrollView` 自然承载，不需特殊处理
- 半点细虚线分隔（可选，增强时间感知）

### 4.5 内容网格（横向翻页 + 纵向滚动）

**分页实现选择**：经评估 `TabView(selection:).tabViewStyle(.page(...))` 无法暴露拖拽手势生命周期（`onChanged`），因此 "preview 在翻页手势开始时关闭" 这条承诺会落不稳。权衡两种方案：

| 方案 | 优点 | 缺点 | 最终选择 |
|---|---|---|---|
| **A. 坚持 TabView(.page)** | 系统原生弹性、减速曲线、无缝对齐 | 无法在 gesture `onChanged` 关 preview；preview 必须延迟到 `selection` 变化后关闭 | 默认选此，preview 规则相应调整（见 §6.3） |
| **B. 自定义 pager**（`HStack` + `DragGesture` + `offset`） | 手势生命周期可控，preview 可在 `onChanged` 第一下拖动时关闭 | 动画曲线需手写、snap 阈值需调、容易与纵向 ScrollView 手势冲突 | 仅当 A 方案实际体验不达标时，退路方案 |

**选定方案 A（`TabView(.page)`）的具体落法**：

```swift
TabView(selection: $currentWeekStart) {
    ForEach(visibleWeekStarts, id: \.self) { weekStart in
        WeekContentView(weekStart: weekStart, ...)
            .tag(weekStart)
    }
}
.tabViewStyle(.page(indexDisplayMode: .never))
.onChange(of: currentWeekStart) { _, newStart in
    previewingContext = nil                   // 翻页完成后立即关闭 preview（§6.3 / §7.7）
    focusDate = adjustedDate(for: newStart)   // 按 "同星期日期" 规则更新 focusDate（§7.1）
    extendVisibleWeeksIfNeeded(current: newStart)  // 预加载下一周（§7.8）
    haptic.impactOccurred(intensity: 0.6)     // 轻触觉
}
```

- 分页 identity = 该周周一 00:00 的 `Date`
- `visibleWeekStarts` 维护规则见 §7.8（相邻翻页增量扩窗口 / 外部跳周重建窗口）
- 每页内容：7 列 × (end - start) 小时 ZStack
- 背景：每小时横线（`Divider().opacity(0.25)`）；今日列轻微 teal tint `opacity(0.04)`
- **`currentWeekStart` 与 `focusDate`**：`currentWeekStart` 由 `focusDate` 推导（`focusDate` 所在周的周一）；切周时 `focusDate` 按"同星期日期"更新（4/15 周三 → 切下周 → 4/22 周三，而非 4/22 周一）

### 4.6 课时块

- 圆角 6pt，左侧 4pt 实心色条 = 课程色（`course?.colorHex`）
- 填充 = 课程色 `opacity(0.15)`（已完成课时降至 `0.08`，左色条保持原强度表示"淡出"）
- 块内文字：
  - 上行：学生姓名（11pt, semibold）
  - 下行：`09:30–10:30`（10pt, regular, `.secondary`）
- 块高 < 28pt（约 ≤25 分钟课时）：单行仅显示学生姓名，缩 10pt 字号
- **重叠宽度规则**：车道数 = 该课时所属"冲突簇"内的最大并发车道数（laneCount）；该簇内**每个**块宽度均 = 列宽 / laneCount（统一除，不按各自并发数变化），避免边界对不齐
- 最多 3 列并排；簇内同时并发 >3 时：lane 0/1/2 正常渲染，第 4 条起不单独渲染，改为在第 3 条块右下角叠加 "+N" 10pt 圆角气泡（点击第 3 条块弹出 `LessonInfoCard` 时顺带显示被合并的条目列表，见 §6.3）

### 4.7 现在时刻指示线

- 仅当视图页包含今天 **且** 当前时刻在可见时间范围内时渲染
- 整条横线横跨 7 列，颜色 `Color(.systemRed)`，线宽 1pt
- 今日列起点处 6pt 红点
- 刷新频率：`TimelineView(.periodic(from: .now, by: 60))`

---

## 5. 竖屏月视图（行为基本不变 + 日视图 +N 修复）

### 5.1 搬迁与 state 下放

- 月网格 + snapshot + MiniBlock + 拖拽切月逻辑整体迁到 `MonthCalendarView.swift`
- 视觉 0 变更
- **State 下放到 `MonthCalendarView`**：`selectedDay`、`showStudents`、`slideForward`、`isAnimating` 本来就是纯竖屏月视图状态，跟随子视图下放
- **`DayScheduleDetailView` sheet 绑定也下放**到 `MonthCalendarView`：竖屏点日期弹出的底部 sheet 由 `MonthCalendarView` 持有与触发
- **容器只保留 `focusDate`**：通过 `@Binding` 传入 `MonthCalendarView`；竖屏切月时子视图更新 `focusDate`（§7.1 同星期日期规则）
- `@Query allLessons` 上移至容器，`MonthCalendarView` 通过参数接收
- "显示学生" toggle 仍在竖屏月视图右上（不影响横屏）

### 5.2 日视图静默丢弃 bug 顺带修复

现有 `DayScheduleDetailView` 在同一时段有 3+ 节课时，第 3 节起直接被过滤（`lane = -1` → `if block.lane >= 0` 不渲染）。这是体验 bug：用户在日详情里完全看不到被丢弃的课时，和 "preview-only 也要如实展示" 的定位冲突。

随 `LessonLaneLayout` 重构一起修：

- 保留 2 车道**视觉上限**（列宽 = 1/2）
- 超出的课时通过 `ConflictCluster.overflowLessons` 回传到 UI 层
- `DayScheduleDetailView` 在 lane=1 的块右下角叠加 "+N" 圆角气泡，点击该块时弹出的信息卡片下方增加 "同时段其它课时" 列表（与横屏周视图一致）
- 验收清单显式覆盖此场景（§10.2）

### 5.3 "竖屏月详情可读性"的权衡（未纳入本 spec）

codex review 提出："用户真正的痛点是竖屏 MiniBlock 过小 → 应该参考 Apple Calendar Compact/Stacked/Details 分层，做竖屏分层视图（如：上半屏月网格 + 下半屏 agenda）"。

**本 spec 不纳入此改动**，原因：

1. 用户原始需求明确是"为这个页面支持横屏"。竖屏 MiniBlock 作为"忙闲密度总览"功能依然成立——用户并未要求竖屏日格内显示完整文案
2. 横屏周视图本身就是 Apple Calendar 分层心智在本 app 的落地（紧凑月 ↔ 详细周）；用户可通过旋转立即进入详细态，不需再塞一层竖屏分层
3. 竖屏分层会引入"上下布局比例"、"选中日 agenda 与 sheet 并存"等新交互决策，属于独立设计命题，应单独 spec

**如果后续用户确认也要做竖屏分层**：另起 spec `YYYY-MM-DD-monthly-overview-portrait-layering.md`，其架构（focusDate 驱动、共享 ConflictCluster 数据层）可直接复用本 spec 的成果，增量成本低。

---

## 6. 交互详述

### 6.1 左右切周

- 滑动 → 系统原生弹性 + snap 动画（`TabView(.page)`）
- **切周完成时**（`onChange(of: currentWeekStart)`）：
  - `previewingContext = nil` 关闭 preview（见 §6.3）
  - `focusDate` 按"同星期日期"更新（§7.1）
  - 轻触觉反馈 `UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)`
- 每页 `WeekContentView` 构建 snapshot 时读 `snapshotCache`；未命中则构建并写回

### 6.2 纵向滚动（每周独立锚点）

- **每周独立 `ScrollView`**，滚动偏移由 `scrollAnchorByWeek[weekStart]` 记录（§7.5）
- **初次进入（本周页）**：`scrollAnchorByWeek[thisWeek] = .nowRounded`，渲染时 `scrollTo(currentHour, anchor: .top)`（§7.5 discrete anchor）
- **切到历史/未来周**（该周无缓存）：`scrollAnchorByWeek[week] = .hour(9)`，滚到 9:00 刻度
- **用户手动滚动**：`onScrollGeometryChange`（iOS 18）或 `ScrollViewOffsetReader`（iOS 17 兼容 helper，见 §7.5 注）回调读 contentOffset.y → 换算最近整点 hour → 写入 `.hour(H)`；用户回翻到该周时恢复
- **"今天"按钮**（必须按此顺序，见 §7.8）：
  1. `recenterVisibleWeeks(around: today.weekStart, radius: 2)`——先重建窗口，避免 TabView selection 落空
  2. `focusDate = Date()`——触发 TabView 切到本周页（此时本周 tag 已在 `visibleWeekStarts` 中）
  3. `pendingScrollRequest = (thisWeekMonday, .nowRounded)`
  4. `WeekContentView` 监听 `pendingScrollRequest`：若 `request.week == self.weekStart` 则 `ScrollViewReader.scrollTo(hour, anchor: .top)` 并把 `pendingScrollRequest` 置 nil
  5. 成功触觉反馈 `UINotificationFeedbackGenerator().notificationOccurred(.success)`

### 6.3 块点击 preview 形态（底部 Sheet，compact 适配）

iPhone landscape 属于 **compact vertical size class**。Apple 的 adaptive interface 指南明确：compact 环境下 `.popover` 默认会被系统适配成全屏 modal，这种默认适配对周视图"轻量预览"场景不合适（遮挡掉正在对比的其它课时）。因此方案显式选用**底部 sheet**：

- 轻点课时块 → `LessonBlockView` 调 `onTap(PreviewContext(...))` → 容器 `previewingContext = ctx` → `.sheet(item: $previewingContext)` 弹出 `LessonInfoCard`
- **sheet 配置**：

```swift
.sheet(item: $previewingContext) { ctx in
    LessonInfoCard(
        lesson: ctx.lesson,
        overflowCompanions: ctx.overflowCompanions  // 来自 PreviewContext（§7.7）
    )
    .presentationDetents([.fraction(0.35), .medium])
    .presentationDragIndicator(.visible)
    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.35)))
}
```

- **`.fraction(0.35)`**：小高度模式，横屏下约 150pt 高，卡片停在底部，上方周网格仍能看见 6-7 小时时间轴，用户可对照 preview 与其它课时
- **`.medium`**：用户上拉可展开到一半屏，看更详细信息
- **`.presentationBackgroundInteraction(.enabled(...))`**：小态下允许与背景交互（滚动时间轴、横滑切周），系统日历 app 标准预览行为
- **内容**：课程名 · 学生 · 完整时间 · 时长 · 备注 · 价格（若 > 0）；若 `cluster.overflowLessons.nonEmpty`（点击的是带 "+N" 角标的块），卡片下方增加 "同时段其它课时" 列表展示被合并项
- **点击瞬间**：块 `scaleEffect(0.97)` 0.1s 微反馈
- **关闭**：上滑外部 / 下拉把手 / 点击另一课时块（自动切换到新 lesson）
- **禁用** 长按、拖拽、空白区新建（与 preview-only 定位一致）

**为什么不用 `.popover` + 自动适配**：系统在 compact 下把 popover 适配成全屏 modal，失去"浮层预览"语义；且不同 iOS 版本适配行为不完全一致。显式 sheet 在所有支持版本上表现一致

### 6.4 旋转过渡

- 容器对 `verticalSizeClass` 变化加 `.animation(.easeInOut(duration: 0.3))`
- 月/周视图间交叉淡入淡出（`.transition(.opacity)`）
- 旋转**不改** `focusDate`（§7.1）；月视图/周视图由同一 `focusDate` 推导各自定位，天然连续

### 6.5 空周态

- 无任何课时的周：不显示空态卡片（会打断横向翻页节奏）
- 时间网格底部居中一行淡灰色 "本周无课时安排"

### 6.6 Preview/翻页/旋转冲突处理

| 场景 | 规则 | 技术落点 |
|---|---|---|
| preview sheet 打开时用户旋转 | 立即关闭 sheet：`previewingContext = nil` | `onChange(of: verticalSizeClass)` |
| preview sheet 打开时用户横滑切周 | 翻页**完成后**关闭 sheet（非 `onChanged`，因 `TabView(.page)` 不暴露手势生命周期） | `onChange(of: currentWeekStart)` |
| sheet 已经是 `.fraction(0.35)` 小态但用户又点另一块 | 不关闭 sheet，直接更新 `previewingContext`（新 id 不同），卡片内容原地切换 | `.sheet(item:)` 的 binding 变化会 smooth transition |
| 旋转时 scene geometry 未完成 | mask 已被 `onDisappear` 重置，主路径已触发旋转；兜底路径静默 | §3.2 主/兜底双路径 |
| 外部跳周（今天按钮）导致 selection 落空 | `recenterVisibleWeeks` 先执行确保 selection 落在 tags 内 | §7.8 |

### 6.7 无障碍

- 每个块 `.accessibilityElement(children: .ignore)` + 合并 label `"学生 小王，课程 数学，9:30 至 10:30"`
- 时间轴列 `.accessibilityHidden(true)`（纯装饰）
- 「今天」按钮 `.accessibilityLabel("回到本周")`

---

## 7. 数据流与共享状态

### 7.1 容器状态 — 单一 `focusDate`

为避免"竖屏 `displayMonth` 与横屏 `selectedWeekStart` 双轨真相"导致的跨月状态断裂（用户从 4 月进入 → 横屏翻到 5 月 → 转回竖屏跳回 4 月），**采用单一 `focusDate`** 作为当前关注日期 source of truth：

```swift
struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSize

    // 单一跨方向 state：当前关注日期（day-precision, startOfDay 归一化）
    @State private var focusDate: Date = DateHelper.calendar.startOfDay(for: .now)

    var onSelectDate: ((Date) -> Void)? = nil
}
```

**推导规则**：
- **竖屏月视图**：当前月份 = `focusDate` 所在月；`MonthCalendarView` 通过 `Binding($focusDate)` 接收
- **横屏周视图**：当前页 = `focusDate` 所在周的周一；`WeekTimelineView` 同样 `Binding($focusDate)`
- **竖屏切月**：更新 `focusDate` 到目标月的代表日（见下方规则）
- **横屏切周**：更新 `focusDate` 到目标周的同星期日期（保持星期对齐）
- **竖屏选某日**：更新 `focusDate` 到该日（竖屏 sheet 弹出 DayScheduleDetailView 时，`focusDate` 即选中日）

**竖屏月切换时 `focusDate` 的具体写法**：
- 若当前 `focusDate` 在新月内（罕见，通常跨月切换）→ 不变
- 若 `focusDate` 日号 ≤ 新月天数 → 新月同日号（如 4/15 切 5 月 → 5/15）
- 否则（如 1/31 切 2 月）→ 新月最后一日
- 这样用户在竖屏连续切月，横屏再打开时看到的周是"自然延续"而非跳回今天

**其它 state 归属**：
- 竖屏专属 state（`selectedDay`、`showStudents`、`slideForward`、`isAnimating`）下放 `MonthCalendarView`
- 横屏 preview state（`previewingContext: PreviewContext?`）升到 `WeekTimelineView`（见 §7.7）
- 每周独立滚动位置见 §7.5
- 可见周窗口（`visibleWeekStarts: [Date]`）的重建规则见 §7.8

### 7.2 方向切换行为（基于 `focusDate`）

- **竖 → 横**：`WeekTimelineView` 定位到 `focusDate` 所在周；用户在竖屏浏览到的月份/日期在横屏上**自然延续**
- **横 → 竖**：`MonthCalendarView` 定位到 `focusDate` 所在月；用户在横屏翻到 5 月第二周后再转回竖屏，看到的是 5 月而非 4 月 ✅
- **旋转本身不改 `focusDate`**：只切 layout，关注日期保持
- **退出**：容器销毁，`focusDate` 清理

### 7.3 核心数据结构

数据结构要承接 §4.6 的 `+N` 合并与 §8.2 的跨天截断，**不能把这些决策留给 UI 层临时扫一遍**。引入 `ConflictCluster` 一等模型、扩展 `PlacedBlock` 附带 clipping 信息：

```swift
// Helpers/WeekSnapshot.swift
struct WeekSnapshot {
    let weekStart: Date                       // Monday 00:00
    let days: [DayColumn]                     // 恰好 7 项
    let timeRange: (start: Int, end: Int)     // 默认 (9, 21)，越界扩展
}

struct DayColumn {
    let date: Date
    let isToday: Bool
    let isWeekend: Bool
    let clusters: [ConflictCluster]           // 按时序排列的冲突簇
}

/// 一段时间内互相重叠的课时集合；同一簇内共享 laneCount、统一计算块宽
struct ConflictCluster {
    let visibleBlocks: [PlacedBlock]          // lane ≥ 0 的块
    let overflowLessons: [Lesson]             // 被合并到"+N"的课时（lane 原本会是 -1）
    let laneCount: Int                        // 可见块的车道数（= visibleBlocks 中 lane 最大值 + 1）
}

struct PlacedBlock: Identifiable {
    let id: UUID                              // = lesson.id
    let lesson: Lesson
    let lane: Int                             // 0 ≤ lane < laneCount
    let startMinutesFromRangeStart: Int       // 渲染起始分钟（可能已被 clipping）
    let durationMinutes: Int                  // 渲染时长（可能已被 clipping）
    let clipsLeading: Bool                    // 实际开始早于 timeRange.start → 顶部加 ↑
    let clipsTrailing: Bool                   // 实际结束晚于当日 23:59（跨天）→ 底部加 ⤓
}
```

**字段消费方**：
- `clusters` 数组让渲染层一次遍历即可处理所有"同时刻"的块，无需 UI 层自己找 cluster 归属
- `overflowLessons` 让 "+N" 气泡能够在 `LessonInfoCard` 中列出被合并条目（§4.6 承诺的"点击第 3 条块显示合并列表"）
- `clipsLeading` / `clipsTrailing` 让 `LessonBlockView` 决定是否在上/下沿加方向箭头（§8.2 跨天截断）

### 7.4 车道分配 helper（返回 ConflictCluster）

`LessonLaneLayout` 不再返回扁平的 `(lesson, lane, laneCount)` 列表，而是直接构建 `ConflictCluster` 数组：

```swift
// Helpers/LessonLaneLayout.swift
enum LessonLaneLayout {
    /// 扫描线识别重叠簇 → 簇内贪心分配车道 → 超出 maxLanes 的课时归入 overflowLessons
    /// - Parameters:
    ///   - lessons: 已按日期过滤到一天的课时（未排序也可）
    ///   - maxLanes: 可见车道上限
    ///   - dayRange: 当日时间轴 (start, end)，用于计算 clipping
    ///   - dayEnd: 当日 23:59:59（`Calendar.date(byAdding: .day, value: 1, to: startOfDay)` 前一秒），用于 endTime 跨天检测
    /// - Returns: 按 startTime 排序的簇数组
    static func buildClusters(
        _ lessons: [Lesson],
        maxLanes: Int,
        dayRange: (start: Int, end: Int),
        dayEnd: Date
    ) -> [ConflictCluster]
}
```

- 算法：① 按 startTime 排序 ② 扫描线分簇（`lesson.startTime < clusterMaxEnd` 入当前簇） ③ 簇内按开始时间再贪心分配车道，超出 `maxLanes` 入 `overflowLessons` ④ 计算每个可见块的 `clipsLeading` / `clipsTrailing` 与裁剪后的 `startMinutesFromRangeStart` / `durationMinutes`
- **`WeekContentView`** 用 `maxLanes: 3`，按 §4.6 在每簇 `lane=2` 的块（最右可见块）右下角叠加 `"+N"` 气泡，N = `overflowLessons.count`
- **`DayScheduleDetailView`** 用 `maxLanes: 2`；**顺带修复**现有的静默丢弃 bug——原本 lane = -1 直接过滤，改为在 `lane=1` 的块右下叠加 `"+N"` 气泡。这是一次低风险的原生感提升（现有实现在 3+ 节冲突时会让用户完全看不到后续课时，属于体验 bug，不是设计取舍）。该改动在 §5-修订 中显式说明，并列入验收清单
- 单元测试覆盖：无重叠 / 2 节重叠 / 3 节簇 maxLanes=2（产生 1 个 overflow）/ 4 节簇 maxLanes=3（产生 1 个 overflow）/ 跨天课时 `clipsTrailing = true` / 早于 timeRange.start 的课时 `clipsLeading = true`

### 7.5 每周独立滚动锚点 + 快照缓存

两个并列的缓存，都位于 `WeekTimelineView`：

```swift
struct WeekTimelineView: View {
    @Binding var focusDate: Date
    let lessons: [Lesson]

    // 按周 Monday 为 key
    @State private var snapshotCache: [Date: WeekSnapshot] = [:]
    @State private var scrollAnchorByWeek: [Date: ScrollAnchor] = [:]
    @State private var pendingScrollRequest: (week: Date, anchor: ScrollAnchor)? = nil
    @State private var previewingContext: PreviewContext? = nil   // §7.7
    @State private var visibleWeekStarts: [Date] = []             // §7.8
}

/// 滚动锚点：**整点粒度 discrete anchor**（不使用 pixel / minute 精度）
/// 选择依据：SwiftUI `ScrollViewReader.scrollTo(id:)` 按视图 id 跳转，不支持任意像素偏移；
/// 整点粒度符合教师使用心智（"我刚才看到 10 点左右"而不是 "pixel 237"），精确到像素无实际意义
enum ScrollAnchor: Equatable, Hashable {
    case hour(Int)                 // 锚点 id = 整点小时（用户滚动时保存为最接近的整点）
    case nowRounded                // 计算派生：当前时刻向下取整到最近整点，等价于 .hour(currentHour)
}
```

**快照缓存**：
- LRU 保留 5 个（当前页 ± 2 周）
- `lessons` 变化 → 整 cache 作废，重算可见周
- 构建频率：切周首次访问时懒构建

**滚动锚点机制（discrete hour anchors）**：

```swift
// WeekContentView 渲染每个整点行时挂 .id(hour)：
ForEach(timeRange.start...timeRange.end, id: \.self) { hour in
    HourRowView(hour: hour)
        .id(hour)                     // ScrollViewReader 跳转的 anchor
}

// 用户手动滚动：通过 onScrollGeometryChange (iOS 18) 或 ScrollOffsetObserver (iOS 17 兼容)
// 读当前 contentOffset.y，反算"最接近顶部的整点行" → 写入 cache
.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offsetY in
    let hour = nearestHourForOffset(offsetY)  // offsetY / hourHeight + timeRange.start
    scrollAnchorByWeek[weekStart] = .hour(hour)
}

// 恢复位置：ScrollViewReader.scrollTo(id: hour, anchor: .top)
ScrollViewReader { reader in
    ...
    .onAppear { restoreScrollIfNeeded(reader: reader) }
    .onChange(of: pendingScrollRequest) { ... reader.scrollTo(targetHour, anchor: .top) ... }
}
```

**恢复规则**：
- 切到某周时查 `scrollAnchorByWeek[week]`：
  - 命中 → `reader.scrollTo(hour, anchor: .top)`
  - 未命中 + 是本周 → `scrollAnchorByWeek[week] = .nowRounded` 并 `reader.scrollTo(currentHour, anchor: .top)`，视觉上当前时刻在顶部附近（"近 30 分钟" 语义由 `.top` 锚加整点入行自然满足——行从整点起，当前时间在该行内偏下 0-60 分钟，呈现"当前时刻刚好在上半屏可见"）
  - 未命中 + 非本周 → `scrollAnchorByWeek[week] = .hour(9)` 并滚到 9 点
- "今天"按钮：① `focusDate = Date()` ② `pendingScrollRequest = (thisWeekMonday, .nowRounded)` ③ `WeekContentView` 观察 request，匹配 weekStart 时 `scrollTo` 并清空 request
- 退出页面时缓存销毁（不持久化）

**关于精度妥协**：
- 用户手动滚动到 10:37，离开该周后再回来：恢复位置是 10:00（整点行顶部）。用户会看到"大致还是上次看的区域"，但非像素精确
- 若未来用户反馈此精度不够，升级路径是在 `ScrollAnchor` 增加 `.halfHour(Int)`（半点粒度，每小时 2 个锚点）并在 `WeekContentView` 为半点行也挂 `.id`，是单点渐进升级，不破坏现有合同

### 7.6 数据流图

```
@Query allLessons ─→ MonthlyOverviewView (container)
                        │
                        └── focusDate ─┬─→ MonthCalendarView (竖屏，月视图)
                                       │
                                       └─→ WeekTimelineView (横屏)
                                             │
                                             ├─ snapshotCache[week]
                                             ├─ scrollAnchorByWeek[week]
                                             ├─ pendingScrollRequest
                                             ├─ visibleWeekStarts[]         ← §7.8
                                             └─ previewingContext           ← §7.7
                                                 │
                                                 ▼ TabView(.page) (见 §4.5)
                                              [week = D] WeekContentView
                                                 │
                                                 ├─ WeekSnapshot (from cache or build)
                                                 │    └─ LessonLaneLayout.buildClusters()
                                                 │         └─ ConflictCluster[]
                                                 │              ├─ visibleBlocks: [PlacedBlock]
                                                 │              └─ overflowLessons: [Lesson]
                                                 └─ 渲染 7 列 + 现在线 + scroll anchor 应用
```

### 7.7 PreviewContext 建模

用 `Lesson?` 作 preview 状态太窄——`LessonInfoCard` 除了 lesson 本身，还需要 overflow 列表（cluster 信息）和出处周（用于 popover 内部的后续操作，例如未来若加"跳到该日"功能）。改用显式 payload：

```swift
// Helpers/WeekSnapshot.swift（或独立文件）
struct PreviewContext: Identifiable {
    let id: UUID                  // = lesson.id，确保 .sheet(item:) 换 lesson 时会触发切换
    let lesson: Lesson
    let overflowCompanions: [Lesson]  // 被合并到 "+N" 的同时段课时；常规块为空数组
    let weekStart: Date               // 来自哪一周的 snapshot
    // 注意：不遵循 Equatable。Lesson 是 @Model class，不自动合成 Equatable。
    // .sheet(item:) 仅依赖 Identifiable（id 变化触发 sheet 内容切换）。
    // 若未来需要 onChange(of:) 等比较，按 id 手动实现。
}
```

**构造路径**：
- `LessonBlockView` 接收一个 `onTap: (PreviewContext) -> Void` 回调；点击时根据自身所属 `ConflictCluster` 构造 `PreviewContext(id: lesson.id, lesson: lesson, overflowCompanions: cluster.overflowLessons, weekStart: contextWeekStart)`
- `WeekTimelineView` 持有 `@State var previewingContext: PreviewContext?`，`LessonBlockView` 通过 closure 设置
- `.sheet(item: $previewingContext)` 的闭包收到 `PreviewContext`，传给 `LessonInfoCard`
- 不再需要 `LessonInfoCard` 二次反查 snapshot，所有信息一次打包

**切换行为**：
- 点击块 A → `previewingContext = CtxA`
- 点击块 B（sheet 已开）→ `previewingContext = CtxB`，因 `.id` 不同 `.sheet(item:)` 平滑切换内容
- 翻页完成 → `previewingContext = nil` 关闭
- 旋转 → `previewingContext = nil` 关闭

### 7.8 visibleWeekStarts 窗口管理

`TabView(selection:)` 需要一个可见 tag 列表。当用户横滑翻页时是"增量扩展"，但外部跳周（今天按钮、初始进入、rotation 驱动的 focusDate 跨越跳变）是"以目标周为中心重建"。

**state**：`@State private var visibleWeekStarts: [Date] = []`（元素为周一 `startOfDay`，按升序排列）

**统一重建 action**：

```swift
/// 以 targetWeekStart 为中心重建窗口
/// - 用于：初始进入、今天按钮、外部跳周、focusDate 非相邻跳变
private func recenterVisibleWeeks(around targetWeekStart: Date, radius: Int = 2) {
    let cal = DateHelper.calendar
    visibleWeekStarts = (-radius...radius).compactMap { offset in
        cal.date(byAdding: .weekOfYear, value: offset, to: targetWeekStart)
    }
}
```

**增量扩展 action**：

```swift
/// 相邻翻页时扩窗口（预加载下一周），避免反复重建
private func extendVisibleWeeksIfNeeded(current: Date, radius: Int = 2) {
    let cal = DateHelper.calendar
    guard let firstVisible = visibleWeekStarts.first,
          let lastVisible = visibleWeekStarts.last else {
        recenterVisibleWeeks(around: current, radius: radius)
        return
    }
    if cal.isDate(current, inSameDayAs: firstVisible),
       let prev = cal.date(byAdding: .weekOfYear, value: -1, to: firstVisible) {
        visibleWeekStarts.insert(prev, at: 0)
    }
    if cal.isDate(current, inSameDayAs: lastVisible),
       let next = cal.date(byAdding: .weekOfYear, value: 1, to: lastVisible) {
        visibleWeekStarts.append(next)
    }
}
```

**触发时机**：

| 触发源 | 动作 | 说明 |
|---|---|---|
| View 首次出现（`onAppear`） | `recenterVisibleWeeks(around: focusDate.weekStart)` | 建立初始窗口 |
| 用户相邻翻页（`onChange(of: currentWeekStart)` 且新周在当前窗口边缘） | `extendVisibleWeeksIfNeeded(current:)` | 预加载下一周 |
| 今天按钮 | ① `recenterVisibleWeeks(around: today.weekStart)` ② `focusDate = Date()` ③ `pendingScrollRequest = (thisWeek, .nowRounded)` | **必须先 recenter 再改 focusDate**，保证 TabView selection 落点在窗口内 |
| 外部跳周（未来 deep link） | 同"今天按钮"流程，`recenterVisibleWeeks(around: targetWeek)` 在前 | — |
| focusDate 非相邻跳变（如竖屏切月跨月后旋转）| 检测 `|focusDate.weekStart - currentWindowCenter| > radius`，若是则 `recenterVisibleWeeks(around: focusDate.weekStart)` | 防 selection 落空 |

**selection 落空兜底**：即使上述触发都错过，`TabView(selection:)` 在 selection 不在 tags 时会保持上一次有效页（SwiftUI 默认行为），不会 crash；但 UI 上会出现"按了今天没反应"的体感。上表规则确保每次外部跳转都在改 `currentWeekStart` 之前就完成 recenter。

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

所有情形都由 `LessonLaneLayout.buildClusters(...)` 产出 `ConflictCluster` 数据层承接，UI 层只负责绘制：

| 情形 | 处理 | 数据载体 |
|---|---|---|
| 两节课完全同时 | lane 0 / lane 1，laneCount=2，簇内每块均占 1/2 列宽 | `ConflictCluster{visibleBlocks: 2, overflowLessons: []}` |
| 3 节同时重叠（周视图 maxLanes=3） | lane 0/1/2，laneCount=3，每块占 1/3 列宽 | `ConflictCluster{visibleBlocks: 3, overflowLessons: []}` |
| 4+ 节同时重叠（周视图 maxLanes=3） | lane 0/1/2 正常渲染；第 4 条起进入 `overflowLessons`，在 lane=2 的块右下角叠加 "+N" 气泡；点击该块时 `LessonInfoCard` 同时展示该 lesson + 被合并项列表 | `ConflictCluster{visibleBlocks: 3, overflowLessons: [N-3]}` |
| 3 节同时重叠（日视图 maxLanes=2） | lane 0/1 + 1 条 overflow；lane=1 的块右下角 "+1" 气泡（修复原静默丢弃 bug，§5.2） | `ConflictCluster{visibleBlocks: 2, overflowLessons: [1]}` |
| 课时 < 15 分钟 | 最小块高 18pt，单行显示学生名，字号 10pt | `PlacedBlock.durationMinutes < 15` |
| 课时 > 8h（异常） | 正常渲染，时间轴自动扩展 | — |
| 早于 timeRange.start（罕见） | 由 `buildClusters` 将 `startMinutesFromRangeStart` 裁剪为 0，`clipsLeading = true`，块顶部绘制 ↑ 箭头 | `PlacedBlock.clipsLeading = true` |
| 跨天课时（endTime 跨日期） | 只在 startTime 当日渲染；`clipsTrailing = true`，块底部绘制 ⤓ 箭头；`durationMinutes` 截到当日 23:59 | `PlacedBlock.clipsTrailing = true` |

### 8.3 课程/颜色缺失

| 情形 | 处理 |
|---|---|
| `lesson.course == nil` | 块色中性灰 `#94A3B8`；`LessonInfoCard` 中课程名显示 "未关联课程" |
| `colorHex` 非法 | `Color(hex:)` 失败回退默认 teal |
| `studentName` 为空 | 块内 "无学生"；`LessonInfoCard` 用 course.name 兜底 |
| `studentName` 过长 | `.lineLimit(1).truncationMode(.tail)` |

### 8.4 课时状态

| 情形 | 处理 |
|---|---|
| `isCompleted == true` | 填充降至 `opacity(0.08)`，左色条保持 |
| 价格为 0 或未设置 | `LessonInfoCard` 价格行隐藏 |

### 8.5 切周与时间边界

| 情形 | 处理 |
|---|---|
| 左右翻页无上限 | 允许任意方向，不做硬限制 |
| 跨年周 | 顶栏显示 "2025 年 12 月 29 日 – 2026 年 1 月 4 日"（含年份） |
| 本周进入时当前时间 < 9:00 | 滚动位置 = 9:00（不能负偏移） |

### 8.6 旋转/翻页/Preview 冲突

见 §6.6 规则表；此处仅列补充边界：

| 情形 | 处理 |
|---|---|
| 退出时 scene 仍为 landscape | 主路径（点 ×）：先 `requestGeometryUpdate(.portrait)` → mask 置 `.portrait` → dismiss；兜底路径（非主动退出）：仅 mask 置回 `.portrait`，不再强行请求 geometry |
| 用户进入时手机已横持 | 不强制旋转，仅解锁 mask；系统按设备姿态自然进入横屏周视图 |
| 多 scene（未来 iPad Split View） | 本 spec 采用 app-scope 单例（§3.1），未来升级为 scene → coordinator registry（§13.4） |

### 8.7 其它

- **Dark Mode**：语义色 + `Color(hex:)` 自适应，不另配色
- **小屏（SE）**：最小列宽 40pt；总宽 48 + 7×40 = 328pt，SE 横屏 667pt 宽绰绰有余
- **Dynamic Type**：表头/时间轴/`LessonInfoCard` respect Dynamic Type；块内文字 `fixedSize(.vertical)` 并限制最大字号，保持网格整齐

---

## 9. 文件结构与规模

### 9.1 新增（10 个）

```
TomatoSchedule/
├── Helpers/
│   ├── AppOrientationCoordinator.swift ← ObservableObject app-scope 单例 + AppDelegate 支持
│   ├── LessonLaneLayout.swift          ← 车道分配 + ConflictCluster 构建
│   ├── WeekSnapshot.swift              ← WeekSnapshot / DayColumn / ConflictCluster / PlacedBlock + builder
│   └── ScrollAnchor.swift              ← 每周滚动锚点类型（小文件，<30 行，也可内联 WeekTimelineView）
└── Views/
    └── Schedule/
        ├── MonthCalendarView.swift     ← 抽离的竖屏月网格
        └── WeekTimeline/
            ├── WeekTimelineView.swift  ← 横屏容器 + TabView pager + 缓存 + 滚动锚点
            ├── WeekContentView.swift   ← 单周页面（含 TimeAxisColumn 私有子视图）
            ├── WeekHeaderRow.swift     ← 7 列星期+日期表头
            ├── LessonBlockView.swift   ← 课时块 + "+N" 气泡 + scale 反馈 + tap 回调
            ├── LessonInfoCard.swift    ← preview 卡片（底部 sheet 内容，非 popover）
            └── NowIndicatorView.swift  ← 现在时刻红线 + Timer
```

### 9.2 修改（4 个 + 1 个 target 扩容）

| 文件 | 改动 |
|---|---|
| `project.yml` | ① `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` 扩展为 Portrait + LandscapeLeft + LandscapeRight 数组值 ② **新增 `TomatoScheduleTests` target**（首次引入，详见 §9.4） |
| `TomatoScheduleApp.swift` | 注入 `@UIApplicationDelegateAdaptor(AppDelegate.self)`；`@StateObject` 持有 `AppOrientationCoordinator.shared`；注入 environment |
| `MonthlyOverviewView.swift` | 降级为容器（~90 行，下降自 306）；持有 `focusDate`；`@EnvironmentObject` 读 `coordinator` |
| `DayScheduleDetailView.swift` | 内联车道逻辑替换为 `LessonLaneLayout.buildClusters(...)`；新增 "+N" 气泡与 overflow 列表展示（§5.2） |

### 9.3 规模估算

| 文件 | 预计行数 | 核心职责 |
|---|---|---|
| `AppOrientationCoordinator.swift` | ~70 | `ObservableObject` + `AppDelegate` + scene 工具方法 |
| `LessonLaneLayout.swift` | ~100 | 扫描线分簇 → 贪心分车道 → 计算 clipping → 构建 `ConflictCluster` |
| `WeekSnapshot.swift` | ~140 | 数据结构（含 `ConflictCluster`/`PlacedBlock` 扩展字段）+ `build(weekStart:lessons:)` |
| `ScrollAnchor.swift` | ~30 | 滚动锚点枚举；若保持独立文件 |
| `MonthCalendarView.swift` | ~260 | 竖屏月网格搬迁 + 接入 `focusDate` binding |
| `WeekTimelineView.swift` | ~200 | TabView pager + 顶栏 + snapshot/scroll anchor 双缓存 + preview sheet 挂载 |
| `WeekContentView.swift` | ~240 | 单周 ScrollView + 网格 + 时间轴 + 块遍历 + 滚动锚点监听 + "+N" 气泡 |
| `WeekHeaderRow.swift` | ~80 | 7 列等宽，today 圆底，周末 tint |
| `LessonBlockView.swift` | ~120 | 块 UI + "+N" 角标 + clipsLeading/Trailing 箭头 + tap 反馈 |
| `LessonInfoCard.swift` | ~100 | 卡片内容（课程、学生、时间、备注、价格、overflow 列表） |
| `NowIndicatorView.swift` | ~60 | `TimelineView(.periodic)` + 红线 + 红点 |
| `DayScheduleDetailView.swift` 增量 | +30 | "+N" 气泡 + overflow 列表 |

**新增代码**：~1400 行；**净增量**：~1100 行（`MonthlyOverviewView` 减 220）。

### 9.4 新增测试 target（本 spec 显式 scope）

当前仓库**无测试 target**（`project.yml` 只有 `TomatoSchedule` 应用 target）。本 spec 提到的 `LessonLaneLayoutTests.swift` 依赖测试 target 的存在，因此把 **target 新增**列为明确 scope：

```yaml
# project.yml 片段（plan 阶段 xcodegen 配置 by example）
targets:
  TomatoSchedule:
    type: application
    # ...既有配置不变...
  TomatoScheduleTests:               # 新增
    type: bundle.unit-test
    platform: iOS
    sources:
      - TomatoScheduleTests
    dependencies:
      - target: TomatoSchedule
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.xujifeng.TomatoScheduleTests
        SWIFT_VERSION: "5"
        GENERATE_INFOPLIST_FILE: YES
```

**新增测试文件**：
```
TomatoScheduleTests/
├── LessonLaneLayoutTests.swift          ~140 行（覆盖 §7.4 的车道 + clipping 场景）
└── WeekSnapshotTests.swift              ~80 行（可选，覆盖时间范围扩展 + 跨天边界）
```

**理由**：
- `LessonLaneLayout` 与 `WeekSnapshot` 是纯函数 + 纯数据结构，单元测试 ROI 高
- `buildClusters` 的扫描线 + 车道贪心 + clipping 混合逻辑 bug 面不小，没有单测则回归靠手工
- 本轮**只新增 target + 算法层测试**，不引入 View 测试 / Snapshot 测试，scope 受控

**若用户反对扩 target**（仅在本轮）：
- 将 §10.1 单元测试降级为"手工验收覆盖同等场景"
- `LessonLaneLayout` 通过在 SwiftUI `#Preview` 中写多种输入 case 并肉眼比对输出渲染结果
- 此为 fallback，不推荐

---

## 10. 测试与验收

### 10.1 单元测试（前置：§9.4 新增 `TomatoScheduleTests` target）

`TomatoScheduleTests/LessonLaneLayoutTests.swift`（~140 行）：

**车道分配**：
- 无重叠：每 lesson 独立 cluster，lane=0，laneCount=1，无 overflow
- 两节完全重叠（maxLanes=3）：1 个 cluster，lane=0/1，laneCount=2，无 overflow
- 三节部分重叠但簇内最大并发=2（如 9-10, 9:30-10:30, 10:30-11）：lane 复用验证
- 三节完全重叠（maxLanes=3）：1 个 cluster，lane=0/1/2，laneCount=3
- 四节完全重叠（maxLanes=3）：lane=0/1/2 + 1 条 overflow
- 四节完全重叠（maxLanes=2）：lane=0/1 + 2 条 overflow（对齐日视图）
- 同起点、不同结束：排序稳定性验证

**Clipping**：
- 课时 7:00-8:00，dayRange=(9,21)（强制不扩展）：`clipsLeading=true`，startMinutesFromRangeStart=0，durationMinutes=0（buildClusters 策略：返回但标记不渲染——实现细节留 plan 阶段，测试验证合同）
- 课时 22:00-次日 01:00（跨天）：`clipsTrailing=true`，durationMinutes 裁到当日 23:59

**边界**：
- 空输入 → []
- 单节课 → 1 cluster，lane=0, laneCount=1

### 10.2 手工验收清单

**核心行为**：
- [ ] 旋转进入横屏：定位到 `focusDate` 所在周
- [ ] 竖屏切月到 5 月 → 旋转横屏：看到 5 月某周（而非 4 月）
- [ ] 横屏翻到 5 月第二周 → 转回竖屏：竖屏月视图显示 5 月（F2 连续性验证）
- [ ] 竖屏选中某日（sheet 打开时）→ 旋转横屏：定位到该日所在周
- [ ] 连续多次旋转不掉帧、不闪烁

**交互**：
- [ ] 横滑切周轻触觉反馈
- [ ] 每周独立滚动位置：滑到 A 周滚到 15:00 → 切到 B 周（滚到 9:00）→ 切回 A 周（恢复 15:00）
- [ ] 点"今天"：recenter 窗口 + 切回本周 + 滚到当前整点行 `.hour(currentHour)` + 成功触觉
- [ ] 本周时"今天"按钮置灰不可点
- [ ] 点击课时块：底部 sheet 小态弹出，时间轴仍可见
- [ ] sheet 小态时横滑切周：sheet 自动关闭（`onChange(of: currentWeekStart)`）
- [ ] sheet 小态时旋转：sheet 立即关闭
- [ ] 点击块 A（sheet 打开）→ 点击块 B：sheet 内容切换，不关闭重开

**数据展示**：
- [ ] 无课周横滑无 crash，底部显示 "本周无课时安排"
- [ ] 重叠 2 节课：车道分配正确，宽度 1/2
- [ ] 重叠 3 节课：lane 0/1/2 + 每块 1/3 宽度
- [ ] 重叠 4 节课（横屏 maxLanes=3）：第 3 块右下角 "+1" 气泡；点击展开 sheet 有 "同时段其它课时" 列表
- [ ] **日视图重叠 3 节课（maxLanes=2）**：第 2 块右下角 "+1" 气泡（§5.2 bug 修复）
- [ ] 越界课时（7:00 / 22:00）触发时间轴扩展至 (7, 22)
- [ ] 跨天课时块底部显示 ⤓ 箭头
- [ ] 已完成课时视觉淡化（opacity 0.08）但仍可辨认

**方向控制**：
- [ ] 退出页面（点 ×）：先旋转回竖屏 → 再关闭 cover（主路径）
- [ ] 退出后其它页面保持竖屏（即使再次旋转手机也不旋）
- [ ] 进入页面时手机已横持：页面直接以横屏周视图显示（不需再旋转一次）

**跨年 / 现在线 / Dark Mode**：
- [ ] 跨年周顶栏含年份（"2025 年 12 月 29 日 – 2026 年 1 月 4 日"）
- [ ] 现在指示线每分钟刷新位置
- [ ] Dark Mode 下颜色对比度满足可读性

### 10.3 不做项

- 不做自动化 UI 测试（与项目现状一致）
- 不做 iPad 专属布局（但容器架构为未来扩展留余地）

---

## 11. 风险与回滚

### 11.1 风险

| 风险 | 缓解 |
|---|---|
| `TabView(.page)` 无法暴露拖拽手势 `onChanged` | 已接受：preview 改为"翻页完成后关闭"（§6.3 / §6.6）；若体验不达标退路方案是自定义 pager（§4.5） |
| `UIWindowScene.requestGeometryUpdate` 在 iOS 16+ 可用 | 项目最低 iOS 17（SwiftData 前提），安全 |
| 主/兜底双路径导致方向切换边界冲突 | 验收清单覆盖"点 × 正常退出"和"非主动退出"两条路径；实现时主路径必须走 `dismissWithOrientationRestore()` |
| `@Query` 全量加载性能 | 当前教师数据量 <数千课时，内存过滤 <10ms；若未来 > 5000 再考虑谓词 |
| `onScrollGeometryChange` 在 iOS 17 不存在（iOS 18 API） | 项目最低 iOS 17；现有 `ScrollOffsetObserver`（`ScrollCalendarFold.swift`）为 List 场景定制（注释 "KVO inside List row"），**不能直接复用于普通 `ScrollView`**。Plan 阶段必须二选一：① 泛化现有 helper 使 `_IntrospectionView.trySetupObservation` 不依赖 UICollectionViewCell 父链 ② 拆出独立 `ScrollViewOffsetReader`。discrete anchor 方案天然兼容两条路（读 offsetY → 换算整点 hour → 写 cache） |
| `focusDate` 语义变化影响 onSelectDate 回调 | `ScheduleView` 调用点同步调整：容器 `onSelectDate?(focusDate)`；验收清单覆盖 |
| 日视图"+N" 气泡改动视觉 | 属于 bug 修复（§5.2）；若用户偏好保留原静默丢弃可在 plan 阶段加开关，但默认展示 |
| 滚动位置精度降到整点粒度 | 用户手动滚到 10:37 离开该周后再回来，会恢复到 10:00。该妥协有明确文字说明（§7.5）；若需半点/分钟精度，plan 阶段渐进升级不破坏合同 |
| 新增测试 target 影响 CI / 构建产物 | `TomatoScheduleTests` 为独立 unit-test target，不打入 release ipa；首次构建时间 +5-10s，可接受；若用户反对扩 target 则降级为手工验收（§9.4 fallback） |
| 单例 `AppOrientationCoordinator.shared` 将来多 scene 时不够用 | 本轮只在 iPhone 单 scene 范围；升级路径见 §13.4 的 registry 设计 |

### 11.2 回滚方案

所有改动集中在：
- `Views/Schedule/` 子树
- 4 个新 helper 文件
- `project.yml` + `TomatoScheduleApp.swift` 的方向改动（可单独 revert）

按文件粒度回退不影响其它功能。`DayScheduleDetailView` 的 "+N" 气泡改动可通过保留原 `overlapGroups` + `assignLanes` 代码路径的方式单独回退（plan 阶段详述）。

---

## 12. 开放问题

- **ⓘ 图例按钮**是否必要？当前倾向保留作为次级入口，若用户验收时觉得冗余可在实施阶段移除
- **半点虚线**在时间轴上是否过密？默认开启，横屏实际渲染后若感觉杂乱可关闭
- **iOS 17 scroll offset 读取**：当前 `ScrollOffsetObserver` 是 List 场景专用（KVO 查 UICollectionViewCell 上层的 UIScrollView），周视图用的是普通 `ScrollView`。Plan 阶段需确认：是否泛化现有 helper 使其也支持非 List 的 `ScrollView` 上层查找，或拆出独立的 `ScrollViewOffsetReader`

这三项留到实施/验收阶段决定，不阻塞设计定稿。

---

## 13. 已考虑但未纳入本 spec（Deferred）

以下改进**方向正确、codex review 中提出**，但经权衡属于独立设计命题，不纳入本次迭代。若后续用户确认需要做，另起 spec：

### 13.1 竖屏月视图分层（Compact / Stacked / Details）

**来源**：codex review F1；Apple iPhone Calendar 月视图提供 Compact / Stacked / Details 三档信息密度切换。

**本 spec 不做的原因**（详见 §5.3）：
- 用户原始需求明确是"为这个页面支持横屏"
- 横屏周视图本身就是紧凑/详细分层的落地
- 独立交互决策较多（上下分栏比例、agenda 与 sheet 并存等），应独立 spec

**未来若做**：新 spec `YYYY-MM-DD-monthly-overview-portrait-layering.md`，复用本 spec 的 `ConflictCluster` 数据层与 `focusDate` 驱动模型，增量成本低。

### 13.2 自定义 pager（替代 TabView(.page)）

**来源**：codex review F4 第 2 条；`TabView(.page)` 不暴露拖拽手势生命周期，导致 "preview 在翻页手势开始时立即关闭" 承诺落不稳。

**本 spec 不做的原因**：
- 已把 preview 关闭规则从 "翻页手势开始" 改为 "翻页完成后"，在 `TabView(.page)` 上稳定可落地
- 自定义 pager 需手写动画曲线、snap 阈值、与纵向 ScrollView 手势冲突处理，增加实现复杂度与 bug 面
- 若实际体验 `TabView(.page)` 不达标（如快速滑动延迟明显），再切换自定义 pager 作为退路方案（§4.5 已记录）

### 13.3 进入页面时直接横屏（"查看周排"专用入口）

**本 spec 不做的原因**：
- 当前用户路径是"点月总览按钮 → 默认竖屏月视图 → 旋转进入周视图"，与 Apple Calendar 一致
- 若后续教师备课场景希望"点某按钮直接横屏进入周视图"，在后续迭代加 `preferredOrientationOnEnter: UIInterfaceOrientation?` 参数，不影响主流程

### 13.4 多 scene Coordinator registry

**本 spec 不做的原因**：
- 当前 iPhone 应用单 scene，`AppOrientationCoordinator.shared` 作为应用级单例足够，读写路径闭环（§3.1）
- 未来若扩 iPad（Stage Manager / Split View 多 scene），`AppDelegate.supportedInterfaceOrientationsFor window:` 需要通过 `window.windowScene` 查回该 scene 对应的 coordinator

**未来升级路径**（不阻塞本 spec 实施）：

```swift
// 演进方向示意，不在本 spec 范围。
// 届时需将 AppOrientationCoordinator.init 从 private 改为 internal，
// 并弃用 .shared 单例改走 registry 查找。
final class AppOrientationRegistry {
    static let shared = AppOrientationRegistry()
    private var map: [UIWindowScene: AppOrientationCoordinator] = [:]

    func coordinator(for scene: UIWindowScene) -> AppOrientationCoordinator {
        map[scene, default: AppOrientationCoordinator(/* internal init */)]
    }

    func remove(scene: UIWindowScene) { map[scene] = nil }
}
```

对应的 SwiftUI 注入在 `WindowGroup` 内通过 `onAppear` 查 `UIWindow.windowScene` 完成。此为独立 spec，本轮不做。

---

**下一步**：本修订版待用户再次确认（或再交 codex review）后，进入 writing-plans 阶段生成实施计划。
