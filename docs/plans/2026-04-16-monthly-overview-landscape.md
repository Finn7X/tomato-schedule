# 月度总览横屏周视图 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple Calendar-style landscape week view to MonthlyOverviewView, triggered by device rotation, with a single `focusDate` driving both portrait month grid and landscape week timeline.

**Architecture:** Container + subview pattern. `MonthlyOverviewView` becomes a thin container switching between `MonthCalendarView` (portrait, extracted from current code) and `WeekTimelineView` (landscape, new) based on `verticalSizeClass`. Shared `LessonLaneLayout` helper returns `ConflictCluster` arrays consumed by both week and day views. `AppOrientationCoordinator` (app-scope singleton) manages page-level orientation unlock via `AppDelegate`.

**Tech Stack:** SwiftUI, SwiftData, UIKit (AppDelegate orientation + UIWindowScene geometry), XCTest

**Spec:** `docs/specs/2026-04-15-monthly-overview-landscape.md` (revision-6, 1072 lines)

---

## File Map

### New Files (10)

| File | Responsibility | Lines est. |
|---|---|---|
| `Helpers/AppOrientationCoordinator.swift` | App-scope singleton + AppDelegate + scene helper | ~70 |
| `Helpers/LessonLaneLayout.swift` | Sweep-line cluster builder: `buildClusters(lessons:maxLanes:dayRange:dayEnd:)` | ~100 |
| `Helpers/WeekSnapshot.swift` | `WeekSnapshot`, `DayColumn`, `ConflictCluster`, `PlacedBlock`, `PreviewContext`, `ScrollAnchor` + two-pass builder | ~160 |
| `Helpers/ScrollViewOffsetReader.swift` | UIKit KVO bridge for plain `ScrollView` offset (iOS 17 compat) | ~50 |
| `Views/Schedule/MonthCalendarView.swift` | Extracted portrait month grid (from current MonthlyOverviewView) | ~260 |
| `Views/Schedule/WeekTimeline/WeekTimelineView.swift` | Landscape container: TabView pager + caches + preview sheet + top bar | ~220 |
| `Views/Schedule/WeekTimeline/WeekContentView.swift` | Single week page: 7 columns + scroll + time axis + blocks | ~250 |
| `Views/Schedule/WeekTimeline/WeekHeaderRow.swift` | 7-column day header with today highlight | ~80 |
| `Views/Schedule/WeekTimeline/LessonBlockView.swift` | Course block: color bar + text + "+N" badge + clip arrows | ~120 |
| `Views/Schedule/WeekTimeline/LessonInfoCard.swift` | Preview sheet content (lesson details + overflow list) | ~100 |
| `Views/Schedule/WeekTimeline/NowIndicatorView.swift` | Red current-time line with dot | ~60 |

### Modified Files (5)

| File | Changes |
|---|---|
| `project.yml` | Add landscape orientations + TomatoScheduleTests target |
| `TomatoScheduleApp.swift` | Inject AppDelegate adaptor + AppOrientationCoordinator environment |
| `MonthlyOverviewView.swift` | Rewrite to thin container (~90 lines, down from 306) |
| `DayScheduleDetailView.swift` | Replace inline lane logic with `LessonLaneLayout.buildClusters()`; add "+N" badge |
| `Helpers/DateHelper.swift` | Add `weekStart(for:)`, `weekRange(for:)`, `weekRangeText(_:)` helpers |

### New Test Files (2)

| File | Coverage |
|---|---|
| `TomatoScheduleTests/LessonLaneLayoutTests.swift` | Cluster building, lane assignment, overflow, clipping |
| `TomatoScheduleTests/WeekSnapshotTests.swift` | Time range auto-expansion, day column construction |

---

## Chunk 1: Foundation & Data Layer

### Task 1: Project configuration — orientations + test target

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Update project.yml**

Add landscape orientations and test target:

```yaml
# In targets.TomatoSchedule.settings.base, change line 26:
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"

# Add new target after TomatoSchedule target:
  TomatoScheduleTests:
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

- [ ] **Step 2: Create test directory with placeholder**

```bash
mkdir -p TomatoScheduleTests
```

Create `TomatoScheduleTests/TomatoScheduleTests.swift`:

```swift
import XCTest
@testable import TomatoSchedule

final class TomatoScheduleTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: Regenerate Xcode project and verify build**

```bash
xcodegen generate
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run placeholder test**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test Suite|Executed|FAIL"
```

Expected: `Executed 1 test, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add project.yml TomatoScheduleTests/
git commit -m "chore: add landscape orientations + TomatoScheduleTests target"
```

---

### Task 2: DateHelper extensions for week calculations

**Files:**
- Modify: `TomatoSchedule/Helpers/DateHelper.swift`

Spec §7.1 requires week-start calculation for `focusDate` → week mapping; §4.2 needs week range text for top bar.

- [ ] **Step 1: Write failing tests**

Create `TomatoScheduleTests/DateHelperWeekTests.swift`:

```swift
import XCTest
@testable import TomatoSchedule

final class DateHelperWeekTests: XCTestCase {
    func testWeekStartReturnsMonday() {
        // 2026-04-15 is Wednesday
        let wed = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let monday = DateHelper.weekStart(for: wed)
        let weekday = DateHelper.calendar.component(.weekday, from: monday)
        XCTAssertEqual(weekday, 2) // Monday
        XCTAssertEqual(DateHelper.calendar.component(.day, from: monday), 13)
    }

    func testWeekStartForMonday() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let result = DateHelper.weekStart(for: mon)
        XCTAssertTrue(DateHelper.isSameDay(result, mon))
    }

    func testWeekStartForSunday() {
        // Sunday 2026-04-19 should still return Monday 2026-04-13
        let sun = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let monday = DateHelper.weekStart(for: sun)
        XCTAssertEqual(DateHelper.calendar.component(.day, from: monday), 13)
    }

    func testWeekRangeReturnsSevenDays() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let range = DateHelper.weekRange(for: mon)
        XCTAssertTrue(DateHelper.isSameDay(range.start, mon))
        let endDay = DateHelper.calendar.component(.day, from: range.end)
        XCTAssertEqual(endDay, 20) // next Monday
    }

    func testWeekRangeTextSameMonth() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let text = DateHelper.weekRangeText(mon)
        XCTAssertTrue(text.contains("4"))
        XCTAssertTrue(text.contains("13"))
        XCTAssertTrue(text.contains("19"))
    }

    func testWeekRangeTextCrossYear() {
        // 2025-12-29 (Monday) to 2026-01-04 (Sunday)
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2025, month: 12, day: 29))!
        let text = DateHelper.weekRangeText(mon)
        XCTAssertTrue(text.contains("2025"))
        XCTAssertTrue(text.contains("2026"))
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "FAIL|error:"
```

Expected: compile errors (functions not defined)

- [ ] **Step 3: Implement DateHelper extensions**

Append to `TomatoSchedule/Helpers/DateHelper.swift` before the closing `}`:

```swift
    // MARK: - Week helpers

    static func weekStart(for date: Date) -> Date {
        let cal = calendar
        let weekday = cal.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7 // Monday=0
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -daysFromMonday, to: date)!)
    }

    static func weekRange(for weekStart: Date) -> (start: Date, end: Date) {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        return (calendar.startOfDay(for: weekStart), calendar.startOfDay(for: end))
    }

    static func weekRangeText(_ weekStart: Date) -> String {
        let cal = calendar
        let sunday = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let startYear = cal.component(.year, from: weekStart)
        let endYear = cal.component(.year, from: sunday)
        let startMonth = cal.component(.month, from: weekStart)
        let endMonth = cal.component(.month, from: sunday)
        let startDay = cal.component(.day, from: weekStart)
        let endDay = cal.component(.day, from: sunday)

        if startYear != endYear {
            return "\(startYear) 年 \(startMonth) 月 \(startDay) 日 – \(endYear) 年 \(endMonth) 月 \(endDay) 日"
        } else if startMonth != endMonth {
            return "\(startMonth) 月 \(startDay) 日 – \(endMonth) 月 \(endDay) 日"
        } else {
            return "\(startYear) 年 \(startMonth) 月 \(startDay) – \(endDay) 日"
        }
    }
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test Suite|Executed|FAIL"
```

Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add TomatoSchedule/Helpers/DateHelper.swift TomatoScheduleTests/DateHelperWeekTests.swift
git commit -m "feat: add weekStart/weekRange/weekRangeText to DateHelper"
```

---

### Task 3: Data types + LessonLaneLayout + WeekSnapshot — all data layer with TDD

**Files:**
- Create: `TomatoSchedule/Helpers/WeekSnapshot.swift` (types: `ScrollAnchor`, `PreviewContext`, `PlacedBlock`, `ConflictCluster`, `DayColumn`, `WeekSnapshot` + builder)
- Create: `TomatoSchedule/Helpers/LessonLaneLayout.swift` (cluster builder algorithm)
- Create: `TomatoScheduleTests/LessonLaneLayoutTests.swift`
- Create: `TomatoScheduleTests/WeekSnapshotTests.swift`

**Why merged**: `LessonLaneLayout` returns `ConflictCluster` / `PlacedBlock` which are defined in `WeekSnapshot.swift`. Both files must exist for either to compile. This is the algorithmic core (spec §7.3, §7.4). Pure functions, excellent TDD target.

- [ ] **Step 1: Write failing tests**

Create `TomatoScheduleTests/LessonLaneLayoutTests.swift`:

```swift
import XCTest
@testable import TomatoSchedule

final class LessonLaneLayoutTests: XCTestCase {
    private let cal = DateHelper.calendar

    private func makeLessonStub(start: Int, startMin: Int = 0, end: Int, endMin: Int = 0) -> Lesson {
        let today = cal.startOfDay(for: Date())
        let lesson = Lesson()
        lesson.startTime = cal.date(bySettingHour: start, minute: startMin, second: 0, of: today)!
        lesson.endTime = cal.date(bySettingHour: end, minute: endMin, second: 0, of: today)!
        lesson.studentName = "Test"
        lesson.date = today
        return lesson
    }

    // MARK: - No overlap

    func testSingleLessonProducesSingleCluster() {
        let lesson = makeLessonStub(start: 9, end: 10)
        let clusters = LessonLaneLayout.buildClusters(
            [lesson], maxLanes: 3, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: lesson.date)!
        )
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].visibleBlocks.count, 1)
        XCTAssertEqual(clusters[0].overflowLessons.count, 0)
        XCTAssertEqual(clusters[0].laneCount, 1)
        XCTAssertEqual(clusters[0].visibleBlocks[0].lane, 0)
    }

    func testTwoNonOverlappingLessonsProduceTwoClusters() {
        let a = makeLessonStub(start: 9, end: 10)
        let b = makeLessonStub(start: 11, end: 12)
        let clusters = LessonLaneLayout.buildClusters(
            [b, a], maxLanes: 3, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: a.date)!
        )
        XCTAssertEqual(clusters.count, 2)
    }

    // MARK: - Overlap

    func testTwoOverlappingLessonsShareCluster() {
        let a = makeLessonStub(start: 9, end: 10)
        let b = makeLessonStub(start: 9, startMin: 30, end: 10, endMin: 30)
        let clusters = LessonLaneLayout.buildClusters(
            [a, b], maxLanes: 3, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: a.date)!
        )
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].laneCount, 2)
        XCTAssertEqual(clusters[0].visibleBlocks.count, 2)
        let lanes = Set(clusters[0].visibleBlocks.map(\.lane))
        XCTAssertEqual(lanes, [0, 1])
    }

    // MARK: - Overflow

    func testFourOverlappingWithMaxLanes3ProducesOneOverflow() {
        let lessons = (0..<4).map { _ in makeLessonStub(start: 9, end: 10) }
        let clusters = LessonLaneLayout.buildClusters(
            lessons, maxLanes: 3, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: lessons[0].date)!
        )
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].visibleBlocks.count, 3)
        XCTAssertEqual(clusters[0].overflowLessons.count, 1)
        XCTAssertEqual(clusters[0].laneCount, 3)
    }

    func testFourOverlappingWithMaxLanes2ProducesTwoOverflow() {
        let lessons = (0..<4).map { _ in makeLessonStub(start: 9, end: 10) }
        let clusters = LessonLaneLayout.buildClusters(
            lessons, maxLanes: 2, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: lessons[0].date)!
        )
        XCTAssertEqual(clusters[0].visibleBlocks.count, 2)
        XCTAssertEqual(clusters[0].overflowLessons.count, 2)
    }

    // MARK: - Clipping

    func testCrossDayLessonClipsTrailing() {
        let today = cal.startOfDay(for: Date())
        let lesson = Lesson()
        lesson.startTime = cal.date(bySettingHour: 22, minute: 0, second: 0, of: today)!
        lesson.endTime = cal.date(byAdding: .hour, value: 3, to: lesson.startTime)!
        lesson.studentName = "Test"
        lesson.date = today
        let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: today)!
        let clusters = LessonLaneLayout.buildClusters(
            [lesson], maxLanes: 3, dayRange: (9, 23), dayEnd: dayEnd
        )
        XCTAssertEqual(clusters[0].visibleBlocks[0].clipsTrailing, true)
        XCTAssertEqual(clusters[0].visibleBlocks[0].clipsLeading, false)
    }

    // MARK: - Empty

    func testEmptyInputProducesEmptyOutput() {
        let clusters = LessonLaneLayout.buildClusters(
            [], maxLanes: 3, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
        )
        XCTAssertTrue(clusters.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — verify compile failure**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "error:" | head -3
```

Expected: compile errors (types/functions not defined)

- [ ] **Step 3: Create WeekSnapshot.swift (types)**

Create `TomatoSchedule/Helpers/WeekSnapshot.swift`:

```swift
import SwiftUI

// MARK: - ScrollAnchor

enum ScrollAnchor: Equatable, Hashable {
    case hour(Int)
    case nowRounded
}

// MARK: - PreviewContext

struct PreviewContext: Identifiable {
    let id: UUID
    let lesson: Lesson
    let overflowCompanions: [Lesson]
    let weekStart: Date
}

// MARK: - PlacedBlock

struct PlacedBlock: Identifiable {
    let id: UUID
    let lesson: Lesson
    let lane: Int
    let startMinutesFromRangeStart: Int
    let durationMinutes: Int
    let clipsLeading: Bool
    let clipsTrailing: Bool
}

// MARK: - ConflictCluster

struct ConflictCluster {
    let visibleBlocks: [PlacedBlock]
    let overflowLessons: [Lesson]
    let laneCount: Int
}

// MARK: - DayColumn

struct DayColumn: Identifiable {
    let id: Date
    let date: Date
    let isToday: Bool
    let isWeekend: Bool
    let clusters: [ConflictCluster]
}

// MARK: - WeekSnapshot (two-pass builder)

struct WeekSnapshot {
    let weekStart: Date
    let days: [DayColumn]
    let timeRange: (start: Int, end: Int)

    static func build(weekStart: Date, lessons: [Lesson], maxLanes: Int = 3) -> WeekSnapshot {
        let cal = DateHelper.calendar
        let today = cal.startOfDay(for: Date())

        // Group lessons by day
        var lessonsByDay: [[Lesson]] = Array(repeating: [], count: 7)
        for offset in 0..<7 {
            let dayDate = cal.date(byAdding: .day, value: offset, to: weekStart)!
            let startOfDay = cal.startOfDay(for: dayDate)
            lessonsByDay[offset] = lessons.filter { DateHelper.isSameDay($0.date, startOfDay) }
        }

        // Pass 1: compute global time range across all 7 days
        var earliest = 9
        var latest = 21
        for dayLessons in lessonsByDay {
            for lesson in dayLessons {
                let h = cal.component(.hour, from: lesson.startTime)
                if h < earliest { earliest = h }
                let eComps = cal.dateComponents([.hour, .minute], from: lesson.endTime)
                let endHour = (eComps.minute ?? 0) > 0 ? (eComps.hour ?? 0) + 1 : (eComps.hour ?? 0)
                if endHour > latest { latest = min(endHour, 24) }
            }
        }
        let finalRange = (earliest, latest)

        // Pass 2: build DayColumns with the global range
        let days: [DayColumn] = (0..<7).map { offset in
            let dayDate = cal.date(byAdding: .day, value: offset, to: weekStart)!
            let startOfDay = cal.startOfDay(for: dayDate)
            let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: startOfDay)!
            let weekday = cal.component(.weekday, from: dayDate)
            let isWeekend = weekday == 1 || weekday == 7
            let clusters = LessonLaneLayout.buildClusters(
                lessonsByDay[offset], maxLanes: maxLanes, dayRange: finalRange, dayEnd: dayEnd
            )
            return DayColumn(
                id: startOfDay, date: startOfDay,
                isToday: DateHelper.isSameDay(startOfDay, today),
                isWeekend: isWeekend, clusters: clusters
            )
        }

        return WeekSnapshot(weekStart: weekStart, days: days, timeRange: finalRange)
    }
}
```

- [ ] **Step 4: Implement LessonLaneLayout**

Create `TomatoSchedule/Helpers/LessonLaneLayout.swift`:

```swift
import Foundation

enum LessonLaneLayout {
    static func buildClusters(
        _ lessons: [Lesson],
        maxLanes: Int,
        dayRange: (start: Int, end: Int),
        dayEnd: Date
    ) -> [ConflictCluster] {
        guard !lessons.isEmpty else { return [] }
        let cal = DateHelper.calendar
        let sorted = lessons.sorted { $0.startTime < $1.startTime }
        let rangeStartMinutes = dayRange.start * 60

        // Step 1: group into overlapping clusters
        var rawClusters: [[Lesson]] = []
        var current: [Lesson] = [sorted[0]]
        var maxEnd = sorted[0].endTime

        for lesson in sorted.dropFirst() {
            if lesson.startTime < maxEnd {
                current.append(lesson)
                if lesson.endTime > maxEnd { maxEnd = lesson.endTime }
            } else {
                rawClusters.append(current)
                current = [lesson]
                maxEnd = lesson.endTime
            }
        }
        rawClusters.append(current)

        // Step 2: for each cluster, assign lanes + build PlacedBlocks
        return rawClusters.map { group in
            let clusterSorted = group.sorted { $0.startTime < $1.startTime }
            var laneEndTimes: [Date] = []
            var visible: [PlacedBlock] = []
            var overflow: [Lesson] = []

            for lesson in clusterSorted {
                if let available = laneEndTimes.firstIndex(where: { $0 <= lesson.startTime }) {
                    laneEndTimes[available] = lesson.endTime
                    visible.append(makeBlock(lesson: lesson, lane: available, dayRange: dayRange, dayEnd: dayEnd, rangeStartMinutes: rangeStartMinutes, cal: cal))
                } else if laneEndTimes.count < maxLanes {
                    let lane = laneEndTimes.count
                    laneEndTimes.append(lesson.endTime)
                    visible.append(makeBlock(lesson: lesson, lane: lane, dayRange: dayRange, dayEnd: dayEnd, rangeStartMinutes: rangeStartMinutes, cal: cal))
                } else {
                    overflow.append(lesson)
                }
            }

            return ConflictCluster(
                visibleBlocks: visible,
                overflowLessons: overflow,
                laneCount: max(laneEndTimes.count, 1)
            )
        }
    }

    private static func makeBlock(
        lesson: Lesson, lane: Int,
        dayRange: (start: Int, end: Int), dayEnd: Date,
        rangeStartMinutes: Int, cal: Calendar
    ) -> PlacedBlock {
        let startH = cal.component(.hour, from: lesson.startTime)
        let startM = cal.component(.minute, from: lesson.startTime)
        let rawStart = startH * 60 + startM

        let clipsLeading = rawStart < rangeStartMinutes
        let clipsTrailing = lesson.endTime > dayEnd

        let clippedStart = max(rawStart, rangeStartMinutes) - rangeStartMinutes

        let effectiveEnd: Date = clipsTrailing ? dayEnd : lesson.endTime
        let endH = cal.component(.hour, from: effectiveEnd)
        let endM = cal.component(.minute, from: effectiveEnd)
        let rawEnd = endH * 60 + endM
        let clippedEnd = max(rawEnd - rangeStartMinutes, clippedStart)

        return PlacedBlock(
            id: lesson.id,
            lesson: lesson,
            lane: lane,
            startMinutesFromRangeStart: clippedStart,
            durationMinutes: max(clippedEnd - clippedStart, 1),
            clipsLeading: clipsLeading,
            clipsTrailing: clipsTrailing
        )
    }
}
```

- [ ] **Step 5: Write WeekSnapshot tests**

Create `TomatoScheduleTests/WeekSnapshotTests.swift`:

```swift
import XCTest
@testable import TomatoSchedule

final class WeekSnapshotTests: XCTestCase {
    private let cal = DateHelper.calendar

    func testBuildWithNoLessonsReturnsDefaultRange() {
        let monday = DateHelper.weekStart(for: Date())
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [])
        XCTAssertEqual(snap.days.count, 7)
        XCTAssertEqual(snap.timeRange.start, 9)
        XCTAssertEqual(snap.timeRange.end, 21)
    }

    func testBuildExpandsRangeForEarlyLesson() {
        let monday = DateHelper.weekStart(for: Date())
        let lesson = Lesson()
        lesson.date = monday
        lesson.startTime = cal.date(bySettingHour: 7, minute: 0, second: 0, of: monday)!
        lesson.endTime = cal.date(bySettingHour: 8, minute: 0, second: 0, of: monday)!
        lesson.studentName = "Test"
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [lesson])
        XCTAssertEqual(snap.timeRange.start, 7)
    }

    func testBuildExpandsRangeForLateLesson() {
        let monday = DateHelper.weekStart(for: Date())
        let lesson = Lesson()
        lesson.date = monday
        lesson.startTime = cal.date(bySettingHour: 21, minute: 30, second: 0, of: monday)!
        lesson.endTime = cal.date(bySettingHour: 22, minute: 30, second: 0, of: monday)!
        lesson.studentName = "Test"
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [lesson])
        XCTAssertEqual(snap.timeRange.end, 23)
    }

    func testDayColumnIsWeekendFlags() {
        let monday = DateHelper.weekStart(for: Date())
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [])
        XCTAssertFalse(snap.days[0].isWeekend) // Monday
        XCTAssertFalse(snap.days[4].isWeekend) // Friday
        XCTAssertTrue(snap.days[5].isWeekend)  // Saturday
        XCTAssertTrue(snap.days[6].isWeekend)  // Sunday
    }

    func testTwoPassRangeConsistency() {
        // Friday has 7am lesson; Monday should also use expanded range
        let monday = DateHelper.weekStart(for: Date())
        let friday = cal.date(byAdding: .day, value: 4, to: monday)!
        let lesson = Lesson()
        lesson.date = friday
        lesson.startTime = cal.date(bySettingHour: 7, minute: 0, second: 0, of: friday)!
        lesson.endTime = cal.date(bySettingHour: 8, minute: 0, second: 0, of: friday)!
        lesson.studentName = "Test"
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [lesson])
        // Global range should be (7, 21) even though only Friday has lessons
        XCTAssertEqual(snap.timeRange.start, 7)
    }

    func testScrollAnchorEquality() {
        XCTAssertEqual(ScrollAnchor.hour(9), ScrollAnchor.hour(9))
        XCTAssertNotEqual(ScrollAnchor.hour(9), ScrollAnchor.hour(10))
        XCTAssertNotEqual(ScrollAnchor.hour(9), ScrollAnchor.nowRounded)
    }
}
```

- [ ] **Step 6: Run all tests — verify they pass**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test Suite|Executed|FAIL"
```

Expected: all tests pass (LessonLaneLayout + WeekSnapshot + DateHelper)

- [ ] **Step 7: Commit**

```bash
git add TomatoSchedule/Helpers/WeekSnapshot.swift TomatoSchedule/Helpers/LessonLaneLayout.swift TomatoScheduleTests/LessonLaneLayoutTests.swift TomatoScheduleTests/WeekSnapshotTests.swift
git commit -m "feat: add data layer — WeekSnapshot, ConflictCluster, LessonLaneLayout + tests"
```

---

### Task 4: AppOrientationCoordinator + AppDelegate wiring

**Files:**
- Create: `TomatoSchedule/Helpers/AppOrientationCoordinator.swift`
- Modify: `TomatoSchedule/App/TomatoScheduleApp.swift`

Spec §3.1: app-scope singleton + AppDelegate + environment injection.

- [ ] **Step 1: Create AppOrientationCoordinator**

Create `TomatoSchedule/Helpers/AppOrientationCoordinator.swift`:

```swift
import UIKit

final class AppOrientationCoordinator: ObservableObject {
    static let shared = AppOrientationCoordinator()

    @Published var allowedMask: UIInterfaceOrientationMask = .portrait

    private init() {}

    func requestOrientation(_ target: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.activeWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
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

- [ ] **Step 2: Wire into TomatoScheduleApp**

Modify `TomatoSchedule/App/TomatoScheduleApp.swift`. Add after `@Environment(\.scenePhase)` line:

```swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var orientationCoordinator = AppOrientationCoordinator.shared
```

In the `body`, add `.environmentObject(orientationCoordinator)` to `MainTabView()`:

```swift
    MainTabView()
        .environmentObject(orientationCoordinator)
        .onAppear { ... }
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add TomatoSchedule/Helpers/AppOrientationCoordinator.swift TomatoSchedule/App/TomatoScheduleApp.swift
git commit -m "feat: add AppOrientationCoordinator singleton + AppDelegate orientation control"
```

---

### Task 5: ScrollViewOffsetReader (iOS 17 compat)

**Files:**
- Create: `TomatoSchedule/Helpers/ScrollViewOffsetReader.swift`

Based on existing `ScrollOffsetObserver` pattern but without List/UICollectionViewCell assumption (spec §7.5, §11.1).

- [ ] **Step 1: Create ScrollViewOffsetReader**

Create `TomatoSchedule/Helpers/ScrollViewOffsetReader.swift`:

```swift
import SwiftUI

struct ScrollViewOffsetReader: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = _OffsetIntrospectionView()
        view.onOffsetChange = onOffsetChange
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _OffsetIntrospectionView: UIView {
        var onOffsetChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard observation == nil, window != nil else { return }
            var current: UIView? = superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    observation = scrollView.observe(\.contentOffset, options: .new) { [weak self] sv, _ in
                        DispatchQueue.main.async {
                            self?.onOffsetChange?(sv.contentOffset.y)
                        }
                    }
                    return
                }
                current = view.superview
            }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil { observation?.invalidate(); observation = nil }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TomatoSchedule/Helpers/ScrollViewOffsetReader.swift
git commit -m "feat: add ScrollViewOffsetReader for iOS 17 ScrollView offset compat"
```

---

## Chunk 2: Views

### Task 6: MonthCalendarView extraction

**Files:**
- Create: `TomatoSchedule/Views/Schedule/MonthCalendarView.swift`
- Modify: `TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift` (temporary — full rewrite in Task 12)

Extract the current month grid logic wholesale from `MonthlyOverviewView.swift` into a new `MonthCalendarView.swift`. This is a mechanical move, not a redesign. The view keeps all its current state (`selectedDay`, `showStudents`, `slideForward`, `isAnimating`) and the `DayScheduleDetailView` sheet.

Key changes vs current MonthlyOverviewView:
- Receives `@Binding var focusDate: Date` instead of owning `@State displayMonth`
- Receives `lessons: [Lesson]` as parameter instead of `@Query`
- Receives `onSelectDate: ((Date) -> Void)?` pass-through
- Internal `displayMonth` derived from `focusDate` via computed property
- Month navigation updates `focusDate` (so landscape can pick it up)

- [ ] **Step 1: Create MonthCalendarView.swift**

Copy the entire body of `MonthlyOverviewView.swift` (lines 4-306) into a new file. Then refactor:

1. Rename struct to `MonthCalendarView`
2. Replace `@Query private var allLessons: [Lesson]` with `let lessons: [Lesson]`
3. Replace `@State private var displayMonth: Date = .now` with `@Binding var focusDate: Date`
4. Add computed: `private var displayMonth: Date { DateHelper.calendar.startOfDay(for: focusDate) }`
5. In `moveMonth(_ offset:)`: after computing new month, set `focusDate = newMonth` (keeping same day-of-month if possible, per spec §7.1 rules)
6. Keep `@State selectedDay`, `@State showStudents`, `@State slideForward`, `@State isAnimating` as-is
7. Keep DayScheduleDetailView `.sheet` binding as-is
8. In `buildSnapshot()`, replace `allLessons` with `lessons`

- [ ] **Step 2: Temporarily update MonthlyOverviewView to use MonthCalendarView**

Replace the body of `MonthlyOverviewView` with a simple wrapper that still compiles:

```swift
struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @State private var focusDate: Date = DateHelper.calendar.startOfDay(for: .now)

    var onSelectDate: ((Date) -> Void)?

    var body: some View {
        MonthCalendarView(
            focusDate: $focusDate,
            lessons: allLessons,
            onSelectDate: onSelectDate,
            onDismiss: { dismiss() }
        )
    }
}
```

Adjust `MonthCalendarView` to accept `onDismiss: () -> Void` for the close button.

- [ ] **Step 3: Build and verify portrait still works**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED. Run in simulator to verify month grid looks identical.

- [ ] **Step 4: Commit**

```bash
git add TomatoSchedule/Views/Schedule/MonthCalendarView.swift TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift
git commit -m "refactor: extract MonthCalendarView from MonthlyOverviewView"
```

---

### Task 7: WeekHeaderRow

**Files:**
- Create: `TomatoSchedule/Views/Schedule/WeekTimeline/WeekHeaderRow.swift`

Spec §4.3. Simple view, no external dependencies beyond DateHelper.

- [ ] **Step 1: Create WeekTimeline directory and WeekHeaderRow**

```bash
mkdir -p TomatoSchedule/Views/Schedule/WeekTimeline
```

Create `TomatoSchedule/Views/Schedule/WeekTimeline/WeekHeaderRow.swift`:

```swift
import SwiftUI

struct WeekHeaderRow: View {
    let weekStart: Date
    private let cal = DateHelper.calendar
    private let teal = Color(red: 0.34, green: 0.77, blue: 0.72)
    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: weekStart)!
                let day = cal.component(.day, from: date)
                let isToday = DateHelper.isSameDay(date, Date())
                let weekday = cal.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7

                VStack(spacing: 2) {
                    Text(weekdayLabels[offset])
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    ZStack {
                        if isToday {
                            Circle()
                                .fill(teal)
                                .frame(width: 28, height: 28)
                        }
                        Text("\(day)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isToday ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(isWeekend ? Color.secondary.opacity(0.04) : Color.clear)
            }
        }
        .frame(height: 40)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add TomatoSchedule/Views/Schedule/WeekTimeline/
git commit -m "feat: add WeekHeaderRow — 7-column day header with today highlight"
```

---

### Task 8: NowIndicatorView + LessonBlockView + LessonInfoCard

**Files:**
- Create: `TomatoSchedule/Views/Schedule/WeekTimeline/NowIndicatorView.swift`
- Create: `TomatoSchedule/Views/Schedule/WeekTimeline/LessonBlockView.swift`
- Create: `TomatoSchedule/Views/Schedule/WeekTimeline/LessonInfoCard.swift`

Three leaf views that depend only on data types (already built). Grouping them to reduce commit overhead.

- [ ] **Step 1: Create NowIndicatorView**

Create `TomatoSchedule/Views/Schedule/WeekTimeline/NowIndicatorView.swift`:

```swift
import SwiftUI

struct NowIndicatorView: View {
    let timeRangeStart: Int
    let hourHeight: CGFloat
    let totalColumns: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let cal = DateHelper.calendar
            let hour = cal.component(.hour, from: context.date)
            let minute = cal.component(.minute, from: context.date)
            let minutesFromStart = (hour - timeRangeStart) * 60 + minute
            let yOffset = CGFloat(minutesFromStart) / 60 * hourHeight

            if minutesFromStart >= 0 {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color(.systemRed))
                        .frame(width: 8, height: 8)
                        .offset(x: -4)
                    Rectangle()
                        .fill(Color(.systemRed))
                        .frame(height: 1)
                }
                .offset(y: yOffset)
            }
        }
    }
}
```

- [ ] **Step 2: Create LessonBlockView**

Create `TomatoSchedule/Views/Schedule/WeekTimeline/LessonBlockView.swift`:

```swift
import SwiftUI

struct LessonBlockView: View {
    let block: PlacedBlock
    let cluster: ConflictCluster
    let hourHeight: CGFloat
    let columnWidth: CGFloat
    let weekStart: Date
    let onTap: (PreviewContext) -> Void

    @State private var isPressed = false

    private var blockColor: Color {
        if let hex = block.lesson.course?.colorHex {
            return PresetColors.color(for: hex)
        }
        return PresetColors.color(for: "#94A3B8")
    }

    private var fillOpacity: Double {
        block.lesson.isCompleted ? 0.08 : 0.15
    }

    var body: some View {
        let yOffset = CGFloat(block.startMinutesFromRangeStart) / 60 * hourHeight
        let height = max(CGFloat(block.durationMinutes) / 60 * hourHeight, 18)
        let width = columnWidth / CGFloat(cluster.laneCount)
        let xOffset = width * CGFloat(block.lane)

        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor.opacity(fillOpacity))

            // Left accent bar
            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor)
                .frame(width: 4)
                .padding(.vertical, 1)

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(block.lesson.studentName.isEmpty ? "无学生" : block.lesson.studentName)
                    .font(.system(size: height < 28 ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if height >= 28 {
                    Text(block.lesson.timeRangeText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 2)

            // Clip arrows
            if block.clipsLeading {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if block.clipsTrailing {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)
            }

            // +N badge
            if !cluster.overflowLessons.isEmpty && block.lane == cluster.laneCount - 1 {
                Text("+\(cluster.overflowLessons.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(blockColor.opacity(0.8)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
        }
        .frame(width: width - 2, height: height)
        .offset(x: xOffset + 1, y: yOffset)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isPressed = false }
            onTap(PreviewContext(
                id: block.lesson.id,
                lesson: block.lesson,
                overflowCompanions: cluster.overflowLessons,
                weekStart: weekStart
            ))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("学生 \(block.lesson.studentName)，\(block.lesson.course?.name ?? "课时")，\(block.lesson.timeRangeText)")
    }
}
```

- [ ] **Step 3: Create LessonInfoCard**

Create `TomatoSchedule/Views/Schedule/WeekTimeline/LessonInfoCard.swift`:

```swift
import SwiftUI

struct LessonInfoCard: View {
    let lesson: Lesson
    let overflowCompanions: [Lesson]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let course = lesson.course {
                        LabeledContent("课程", value: course.name)
                    } else {
                        LabeledContent("课程", value: "未关联课程")
                    }
                    LabeledContent("学生", value: lesson.studentName.isEmpty ? "无学生" : lesson.studentName)
                    LabeledContent("时间", value: lesson.timeRangeText)
                    LabeledContent("时长", value: "\(lesson.durationMinutes) 分钟")
                    if !lesson.notes.isEmpty {
                        LabeledContent("备注", value: lesson.notes)
                    }
                    if lesson.effectivePrice > 0 {
                        LabeledContent("价格", value: "¥ \(String(format: "%.0f", lesson.effectivePrice))")
                    }
                }

                if !overflowCompanions.isEmpty {
                    Section("同时段其它课时") {
                        ForEach(overflowCompanions, id: \.id) { companion in
                            HStack {
                                Circle()
                                    .fill(PresetColors.color(for: companion.course?.colorHex ?? "#94A3B8"))
                                    .frame(width: 8, height: 8)
                                Text(companion.studentName)
                                Spacer()
                                Text(companion.timeRangeText)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("课时详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add TomatoSchedule/Views/Schedule/WeekTimeline/NowIndicatorView.swift TomatoSchedule/Views/Schedule/WeekTimeline/LessonBlockView.swift TomatoSchedule/Views/Schedule/WeekTimeline/LessonInfoCard.swift
git commit -m "feat: add NowIndicatorView, LessonBlockView, LessonInfoCard"
```

---

### Task 9: WeekContentView — single week page

**Files:**
- Create: `TomatoSchedule/Views/Schedule/WeekTimeline/WeekContentView.swift`

Spec §4.4-4.7: adaptive hourHeight, 7-column grid, time axis, hour anchors, scroll restore.

- [ ] **Step 1: Create WeekContentView**

Create `TomatoSchedule/Views/Schedule/WeekTimeline/WeekContentView.swift`. This is the largest single view (~250 lines). Key responsibilities:

1. Compute `hourHeight` from GeometryReader (spec §4.4)
2. Render time axis on left (48pt sticky)
3. Render 7 columns with day backgrounds
4. Overlay ConflictCluster blocks via `LessonBlockView`
5. Overlay `NowIndicatorView` on today's column
6. Support `ScrollViewReader` with `.id(hour)` anchors for scroll restore

```swift
import SwiftUI

struct WeekContentView: View {
    let snapshot: WeekSnapshot
    let hourHeight: CGFloat
    let onBlockTap: (PreviewContext) -> Void
    let pendingScrollAnchor: ScrollAnchor?
    let onScrollPositionChanged: (Int) -> Void
    let onScrollRequestHandled: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Anchor views for each hour
                        VStack(spacing: 0) {
                            ForEach(snapshot.timeRange.start...snapshot.timeRange.end, id: \.self) { hour in
                                Color.clear
                                    .frame(height: hourHeight)
                                    .id(hour)
                            }
                        }

                        // Hour grid + time labels
                        hourGridLayer

                        // Day columns with blocks
                        dayColumnsLayer(geo: geo)

                        // Now indicator
                        nowIndicatorLayer(geo: geo)
                    }
                    .frame(height: CGFloat(snapshot.timeRange.end - snapshot.timeRange.start) * hourHeight)
                    .background(scrollOffsetTracker)
                }
                .onAppear {
                    applyScrollAnchor(reader: reader)
                }
                .onChange(of: pendingScrollAnchor) { _, _ in
                    applyScrollAnchor(reader: reader)
                }
            }
        }
    }

    // MARK: - Hour Grid

    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.timeRange.start..<snapshot.timeRange.end, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    // Hour label
                    Text("\(hour)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .offset(y: -7)

                    // Divider line
                    Divider()
                        .opacity(0.25)
                        .padding(.leading, 48)
                }
                .frame(height: hourHeight)
            }
        }
    }

    // MARK: - Day Columns

    private func dayColumnsLayer(geo: GeometryProxy) -> some View {
        let columnWidth = (geo.size.width - 48) / 7
        return HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { _, day in
                ZStack(alignment: .topLeading) {
                    // Day background
                    if day.isToday {
                        Rectangle()
                            .fill(Color(red: 0.34, green: 0.77, blue: 0.72).opacity(0.04))
                    } else if day.isWeekend {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.04))
                    }

                    // Blocks
                    ForEach(day.clusters, id: \.visibleBlocks.first?.id) { cluster in
                        ForEach(cluster.visibleBlocks) { block in
                            LessonBlockView(
                                block: block,
                                cluster: cluster,
                                hourHeight: hourHeight,
                                columnWidth: columnWidth,
                                weekStart: snapshot.weekStart,
                                onTap: onBlockTap
                            )
                        }
                    }
                }
                .frame(width: columnWidth)
            }
        }
    }

    // MARK: - Now Indicator

    private func nowIndicatorLayer(geo: GeometryProxy) -> some View {
        let todayIndex = snapshot.days.firstIndex(where: \.isToday)
        return Group {
            if todayIndex != nil {
                NowIndicatorView(
                    timeRangeStart: snapshot.timeRange.start,
                    hourHeight: hourHeight,
                    totalColumns: 7
                )
                .padding(.leading, 48)
            }
        }
    }

    // MARK: - Scroll Offset Tracking (iOS 17 compat)

    private var scrollOffsetTracker: some View {
        ScrollViewOffsetReader { offsetY in
            let hour = Int(offsetY / hourHeight) + snapshot.timeRange.start
            onScrollPositionChanged(max(snapshot.timeRange.start, min(hour, snapshot.timeRange.end)))
        }
        .frame(width: 0, height: 0)
    }

    // MARK: - Scroll Restore

    private func applyScrollAnchor(reader: ScrollViewProxy) {
        guard let anchor = pendingScrollAnchor else { return }
        let targetHour: Int
        switch anchor {
        case .hour(let h): targetHour = h
        case .nowRounded:
            targetHour = DateHelper.calendar.component(.hour, from: Date())
        }
        let clampedHour = max(snapshot.timeRange.start, min(targetHour, snapshot.timeRange.end))
        withAnimation(.easeOut(duration: 0.3)) {
            reader.scrollTo(clampedHour, anchor: .top)
        }
        onScrollRequestHandled()
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add TomatoSchedule/Views/Schedule/WeekTimeline/WeekContentView.swift
git commit -m "feat: add WeekContentView — single week page with time grid, blocks, scroll anchors"
```

---

### Task 10: WeekTimelineView — pager + caches + sheet

**Files:**
- Create: `TomatoSchedule/Views/Schedule/WeekTimeline/WeekTimelineView.swift`

The landscape container (spec §4.5, §6.1-6.3, §7.5, §7.7, §7.8). Owns TabView pager, snapshot cache, scroll anchor cache, preview sheet, visible weeks window.

- [ ] **Step 1: Create WeekTimelineView**

Create `TomatoSchedule/Views/Schedule/WeekTimeline/WeekTimelineView.swift`:

```swift
import SwiftUI

struct WeekTimelineView: View {
    @Binding var focusDate: Date
    let lessons: [Lesson]
    let onDismiss: () -> Void

    @Environment(\.verticalSizeClass) private var vSize
    @State private var currentWeekStart: Date
    @State private var snapshotCache: [Date: WeekSnapshot] = [:]
    @State private var scrollAnchorByWeek: [Date: ScrollAnchor] = [:]
    @State private var pendingScrollRequest: (week: Date, anchor: ScrollAnchor)?
    @State private var previewingContext: PreviewContext?
    @State private var visibleWeekStarts: [Date] = []
    @State private var hourHeight: CGFloat = 60

    private let teal = Color(red: 0.34, green: 0.77, blue: 0.72)

    init(focusDate: Binding<Date>, lessons: [Lesson], onDismiss: @escaping () -> Void) {
        self._focusDate = focusDate
        self.lessons = lessons
        self.onDismiss = onDismiss
        let ws = DateHelper.weekStart(for: focusDate.wrappedValue)
        self._currentWeekStart = State(initialValue: ws)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                WeekHeaderRow(weekStart: currentWeekStart)
                weekPager
            }
            .onAppear {
                computeHourHeight(landscapeHeight: geo.size.height)
                recenterVisibleWeeks(around: currentWeekStart)
                setInitialScroll()
            }
            .onChange(of: currentWeekStart) { _, newStart in
                previewingContext = nil
                updateFocusDateForWeekChange(newStart)
                extendVisibleWeeksIfNeeded(current: newStart)
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            }
            .onChange(of: lessons.count) { _, _ in
                snapshotCache.removeAll()
            }
            .sheet(item: $previewingContext) { ctx in
                LessonInfoCard(lesson: ctx.lesson, overflowCompanions: ctx.overflowCompanions)
                    .presentationDetents(previewDetents)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.35)))
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
            }
            Spacer()
            Text(DateHelper.weekRangeText(currentWeekStart))
                .font(.body.weight(.semibold))
            Spacer()
            Button {
                let todayWeek = DateHelper.weekStart(for: Date())
                recenterVisibleWeeks(around: todayWeek)
                currentWeekStart = todayWeek
                focusDate = DateHelper.calendar.startOfDay(for: Date())
                pendingScrollRequest = (todayWeek, .nowRounded)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Text("今天")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isTodayWeek ? .secondary : teal)
            }
            .disabled(isTodayWeek)
            .accessibilityLabel("回到本周")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: - Pager

    private var weekPager: some View {
        TabView(selection: $currentWeekStart) {
            ForEach(visibleWeekStarts, id: \.self) { weekStart in
                let snap = snapshotForWeek(weekStart)
                WeekContentView(
                    snapshot: snap,
                    hourHeight: hourHeight,
                    onBlockTap: { ctx in previewingContext = ctx },
                    pendingScrollAnchor: pendingScrollRequest?.week == weekStart
                        ? pendingScrollRequest?.anchor : nil,
                    onScrollPositionChanged: { hour in
                        scrollAnchorByWeek[weekStart] = .hour(hour)
                    },
                    onScrollRequestHandled: { pendingScrollRequest = nil }
                )
                .tag(weekStart)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - Helpers

    private var isTodayWeek: Bool {
        DateHelper.weekStart(for: Date()) == currentWeekStart
    }

    private var previewDetents: Set<PresentationDetent> {
        vSize == .compact
            ? [.fraction(0.35), .large]
            : [.fraction(0.35), .medium]
    }

    private func computeHourHeight(landscapeHeight: CGFloat) {
        let contentArea = landscapeHeight - 56 - 40
        hourHeight = min(80, max(44, contentArea / 6))
    }

    private func snapshotForWeek(_ weekStart: Date) -> WeekSnapshot {
        if let cached = snapshotCache[weekStart] { return cached }
        let snap = WeekSnapshot.build(weekStart: weekStart, lessons: lessons)
        snapshotCache[weekStart] = snap
        return snap
    }

    // MARK: - Visible Weeks Window (§7.8)

    private func recenterVisibleWeeks(around target: Date, radius: Int = 2) {
        let cal = DateHelper.calendar
        visibleWeekStarts = (-radius...radius).compactMap {
            cal.date(byAdding: .weekOfYear, value: $0, to: target)
        }
    }

    private func extendVisibleWeeksIfNeeded(current: Date) {
        let cal = DateHelper.calendar
        if let first = visibleWeekStarts.first, DateHelper.isSameDay(current, first),
           let prev = cal.date(byAdding: .weekOfYear, value: -1, to: first) {
            visibleWeekStarts.insert(prev, at: 0)
        }
        if let last = visibleWeekStarts.last, DateHelper.isSameDay(current, last),
           let next = cal.date(byAdding: .weekOfYear, value: 1, to: last) {
            visibleWeekStarts.append(next)
        }
    }

    // MARK: - State Sync

    private func setInitialScroll() {
        if isTodayWeek {
            pendingScrollRequest = (currentWeekStart, .nowRounded)
        } else {
            pendingScrollRequest = (currentWeekStart, .hour(9))
        }
    }

    private func updateFocusDateForWeekChange(_ newWeekStart: Date) {
        let cal = DateHelper.calendar
        let currentWeekday = cal.component(.weekday, from: focusDate)
        if let adjusted = cal.date(bySetting: .weekday, value: currentWeekday, of: newWeekStart) {
            focusDate = cal.startOfDay(for: adjusted)
        } else {
            focusDate = newWeekStart
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add TomatoSchedule/Views/Schedule/WeekTimeline/WeekTimelineView.swift
git commit -m "feat: add WeekTimelineView — landscape pager with caches, preview sheet, today button"
```

---

## Chunk 3: Integration & Verification

### Task 11: MonthlyOverviewView container rewrite

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift`

Rewrite to thin container: `focusDate` source of truth, orientation lifecycle, size class switch (spec §2, §3.2, §7.1).

- [ ] **Step 1: Rewrite MonthlyOverviewView**

Replace entire content of `MonthlyOverviewView.swift`:

```swift
import SwiftUI
import SwiftData

struct MonthlyOverviewView: View {
    @Query private var allLessons: [Lesson]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSize
    @EnvironmentObject private var coordinator: AppOrientationCoordinator

    @State private var focusDate: Date = DateHelper.calendar.startOfDay(for: .now)

    var onSelectDate: ((Date) -> Void)?

    var body: some View {
        Group {
            if vSize == .compact {
                WeekTimelineView(
                    focusDate: $focusDate,
                    lessons: allLessons,
                    onDismiss: dismissWithOrientationRestore
                )
            } else {
                MonthCalendarView(
                    focusDate: $focusDate,
                    lessons: allLessons,
                    onSelectDate: onSelectDate,
                    onDismiss: dismissWithOrientationRestore
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vSize)
        .onAppear {
            coordinator.allowedMask = .allButUpsideDown
        }
        .onDisappear {
            coordinator.allowedMask = .portrait
        }
        .onChange(of: vSize) { _, _ in
            // Close any preview on rotation
        }
    }

    private func dismissWithOrientationRestore() {
        if let scene = UIApplication.shared.activeWindowScene,
           scene.interfaceOrientation.isLandscape {
            coordinator.requestOrientation(.portrait)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                coordinator.allowedMask = .portrait
                dismiss()
            }
        } else {
            coordinator.allowedMask = .portrait
            dismiss()
        }
    }
}
```

- [ ] **Step 2: Build and test both orientations**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

Launch in simulator. Verify:
- Portrait: month grid visible, same as before
- Rotate to landscape: week timeline appears
- Rotate back: month grid returns

- [ ] **Step 3: Commit**

```bash
git add TomatoSchedule/Views/Schedule/MonthlyOverviewView.swift
git commit -m "feat: rewrite MonthlyOverviewView as thin container with focusDate + orientation lifecycle"
```

---

### Task 12: DayScheduleDetailView +N overflow fix

**Files:**
- Modify: `TomatoSchedule/Views/Schedule/DayScheduleDetailView.swift`

Spec §5.2: replace inline `overlapGroups()` + `assignLanes()` with `LessonLaneLayout.buildClusters()`; add "+N" badge for overflow (previously silently dropped lane=-1 blocks).

- [ ] **Step 1: Rewrite DayScheduleDetailView**

Replace entire content of `DayScheduleDetailView.swift`. The view interface stays the same (`date`, `lessons`, `timeRange`, `onNavigateToSchedule`). Internals switch from `TimeBlock` + flat lane list to `ConflictCluster`-based rendering:

```swift
import SwiftUI
import SwiftData

struct DayScheduleDetailView: View {
    let date: Date
    let lessons: [Lesson]
    let timeRange: (start: Int, end: Int)
    var onNavigateToSchedule: (() -> Void)?

    private let hourHeight: CGFloat = 60

    private var clusters: [ConflictCluster] {
        let cal = DateHelper.calendar
        let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date)!
        return LessonLaneLayout.buildClusters(
            lessons, maxLanes: 2, dayRange: timeRange, dayEnd: dayEnd
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Teal gradient header
            HStack {
                Text("\(DateHelper.dateString(date)) \(DateHelper.weekdaySymbol(date))")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let nav = onNavigateToSchedule {
                    Button {
                        nav()
                    } label: {
                        Label("课表", systemImage: "arrow.right.circle")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.77, blue: 0.72),
                        Color(red: 0.29, green: 0.68, blue: 0.64)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid

                    ForEach(clusters, id: \.visibleBlocks.first?.id) { cluster in
                        ForEach(cluster.visibleBlocks) { block in
                            dayBlockView(block, cluster: cluster)
                        }
                    }
                }
                .frame(height: CGFloat(totalHours) * hourHeight)
                .padding(.leading, 44)
            }
        }
    }

    private var totalHours: Int { timeRange.end - timeRange.start }

    // MARK: - Hour Grid (unchanged)

    private var hourGrid: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...totalHours, id: \.self) { i in
                let y = CGFloat(i) * hourHeight
                Text("\(timeRange.start + i):00")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .offset(x: -44, y: y - 6)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)
                    .offset(y: y)
            }
        }
    }

    // MARK: - Block rendering (uses ConflictCluster)

    @ViewBuilder
    private func dayBlockView(_ block: PlacedBlock, cluster: ConflictCluster) -> some View {
        let y = CGFloat(block.startMinutesFromRangeStart) / 60.0 * hourHeight
        let h = max(CGFloat(block.durationMinutes) / 60.0 * hourHeight, 20)

        GeometryReader { geo in
            let totalWidth = geo.size.width
            let blockWidth = cluster.laneCount > 1 ? totalWidth / CGFloat(cluster.laneCount) : totalWidth
            let xOffset = blockWidth * CGFloat(block.lane)
            let colorHex = block.lesson.course?.colorHex ?? "#78909C"

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if cluster.laneCount > 1 && block.lane == 0 {
                        Rectangle()
                            .fill(.orange)
                            .frame(width: 3)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.lesson.course?.name ?? "未知课程")
                            .font(.system(size: 11, weight: .medium))
                        if !block.lesson.studentName.isEmpty {
                            Text(block.lesson.studentName)
                                .font(.system(size: 10))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    Spacer(minLength: 0)
                }
                .frame(width: blockWidth, height: h)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PresetColors.color(for: colorHex).opacity(0.85))
                )
                .foregroundStyle(.white)

                // +N badge for overflow
                if !cluster.overflowLessons.isEmpty && block.lane == cluster.laneCount - 1 {
                    Text("+\(cluster.overflowLessons.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(PresetColors.color(for: colorHex)))
                        .frame(maxWidth: blockWidth, maxHeight: h, alignment: .bottomTrailing)
                        .padding(2)
                }
            }
            .offset(x: xOffset, y: y)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```

Verify in simulator: open month overview → tap a day → DayScheduleDetailView sheet. If 3+ overlapping lessons exist, "+N" badge should appear on the rightmost visible block.

- [ ] **Step 3: Run all tests**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Executed|FAIL"
```

Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add TomatoSchedule/Views/Schedule/DayScheduleDetailView.swift
git commit -m "fix: DayScheduleDetailView uses LessonLaneLayout + shows +N badge for overflow"
```

---

### Task 13: Clean up & delete old test placeholder

**Files:**
- Delete: `TomatoScheduleTests/TomatoScheduleTests.swift` (placeholder from Task 1)

- [ ] **Step 1: Remove placeholder**

```bash
rm TomatoScheduleTests/TomatoScheduleTests.swift
```

- [ ] **Step 2: Run full test suite**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoScheduleTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test Suite|Executed|FAIL"
```

Expected: all tests pass (DateHelper + LessonLaneLayout + WeekSnapshot)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove test placeholder + verify full test suite"
```

---

### Task 14: Manual verification on iPhone 13 simulator

No code changes. Systematic manual acceptance per spec §10.2.

- [ ] **Step 1: Set up iPhone 13 simulator**

```bash
xcrun simctl list devices | grep "iPhone 13"
```

If not available, create one or use Xcode.

- [ ] **Step 2: Build and install**

```bash
xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'platform=iOS Simulator,name=iPhone 13' build 2>&1 | tail -3
```

- [ ] **Step 3: Walk through acceptance checklist**

Verify every item in spec §10.2 on iPhone 13 simulator:

**Core behavior:**
- Rotate to landscape → week view appears at focusDate's week
- Switch month in portrait → rotate → correct week shown
- Rotate back → correct month shown
- Multiple rapid rotations → no crash/flicker

**iPhone 13 specific:**
- Default ~5-6 hours visible (hourHeight should be ~49pt)
- 30min blocks show student name only (single line)
- Sheet small detent: ≥3h visible above
- Sheet expand: uses `.large` (not `.medium`)

**Interactions:**
- Swipe left/right to change weeks + haptic
- Per-week scroll position preserved
- Today button works from distant week
- Block tap → sheet → content correct
- Block tap while sheet open → content switches

**Data:**
- Empty week → "本周无课时安排"
- Now indicator line (red) on today's column

- [ ] **Step 4: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: address findings from iPhone 13 manual verification"
```

---

## Execution Notes

- **Commit frequency:** Every task produces at least one commit. Never leave uncommitted work overnight.
- **Build verification:** Every commit must pass `xcodebuild build`. Run tests after any helper/model changes.
- **xcodegen:** Run `xcodegen generate` after modifying `project.yml`. The `.xcodeproj` is generated, not hand-edited.
- **Spec reference:** When in doubt about behavior, consult `docs/specs/2026-04-15-monthly-overview-landscape.md` section numbers referenced in each task.
- **Two-pass time range:** `WeekSnapshot.build()` uses a two-pass approach (pass 1: scan all 7 days for global earliest/latest, pass 2: build columns with the final range). This ensures Monday's clusters use the same `dayRange` as Friday's even if Friday has the early-morning lesson.
- **PresetColors.color(for:):** The codebase uses `PresetColors.color(for: hex)` (in `PresetColors.swift`), NOT `Color(hex:)`. All plan code snippets use this API.
