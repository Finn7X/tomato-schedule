import XCTest
@testable import TomatoSchedule

final class WeekSnapshotTests: XCTestCase {
    private let cal = DateHelper.calendar
    private lazy var stubCourse = Course(name: "Test", colorHex: "#FF0000")

    func testBuildWithNoLessonsReturnsDefaultRange() {
        let monday = DateHelper.weekStart(for: Date())
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [])
        XCTAssertEqual(snap.days.count, 7)
        XCTAssertEqual(snap.timeRange.start, 9)
        // Default end is 24 — timeline always covers a full day so scrolling never
        // hits a large empty buffer at the bottom (matches Apple Calendar's 0–23).
        XCTAssertEqual(snap.timeRange.end, 24)
    }

    func testBuildExpandsRangeForEarlyLesson() {
        let monday = DateHelper.weekStart(for: Date())
        let lesson = Lesson(
            course: stubCourse,
            studentName: "Test",
            date: monday,
            startTime: cal.date(bySettingHour: 7, minute: 0, second: 0, of: monday)!,
            endTime: cal.date(bySettingHour: 8, minute: 0, second: 0, of: monday)!
        )
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [lesson])
        XCTAssertEqual(snap.timeRange.start, 7)
    }

    func testBuildKeepsDefaultEndForLateLesson() {
        // With default end = 24, a normal late lesson at 21:30-22:30 stays within
        // the default range without further extension (the timeline already covers
        // the full day).
        let monday = DateHelper.weekStart(for: Date())
        let lesson = Lesson(
            course: stubCourse,
            studentName: "Test",
            date: monday,
            startTime: cal.date(bySettingHour: 21, minute: 30, second: 0, of: monday)!,
            endTime: cal.date(bySettingHour: 22, minute: 30, second: 0, of: monday)!
        )
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [lesson])
        XCTAssertEqual(snap.timeRange.end, 24)
    }

    func testDayColumnIsWeekendFlags() {
        let monday = DateHelper.weekStart(for: Date())
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [])
        XCTAssertFalse(snap.days[0].isWeekend)
        XCTAssertFalse(snap.days[4].isWeekend)
        XCTAssertTrue(snap.days[5].isWeekend)
        XCTAssertTrue(snap.days[6].isWeekend)
    }

    func testTwoPassRangeConsistency() {
        let monday = DateHelper.weekStart(for: Date())
        let friday = cal.date(byAdding: .day, value: 4, to: monday)!
        let lesson = Lesson(
            course: stubCourse,
            studentName: "Test",
            date: friday,
            startTime: cal.date(bySettingHour: 7, minute: 0, second: 0, of: friday)!,
            endTime: cal.date(bySettingHour: 8, minute: 0, second: 0, of: friday)!
        )
        let snap = WeekSnapshot.build(weekStart: monday, lessons: [lesson])
        XCTAssertEqual(snap.timeRange.start, 7)
    }

    func testScrollAnchorEquality() {
        XCTAssertEqual(ScrollAnchor.hour(9), ScrollAnchor.hour(9))
        XCTAssertNotEqual(ScrollAnchor.hour(9), ScrollAnchor.hour(10))
        XCTAssertNotEqual(ScrollAnchor.hour(9), ScrollAnchor.nowRounded)
    }
}
