import XCTest
@testable import TomatoSchedule

final class DateHelperWeekTests: XCTestCase {
    func testWeekStartReturnsMonday() {
        let wed = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let monday = DateHelper.weekStart(for: wed)
        let weekday = DateHelper.calendar.component(.weekday, from: monday)
        XCTAssertEqual(weekday, 2)
        XCTAssertEqual(DateHelper.calendar.component(.day, from: monday), 13)
    }

    func testWeekStartForMonday() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let result = DateHelper.weekStart(for: mon)
        XCTAssertTrue(DateHelper.isSameDay(result, mon))
    }

    func testWeekStartForSunday() {
        let sun = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let monday = DateHelper.weekStart(for: sun)
        XCTAssertEqual(DateHelper.calendar.component(.day, from: monday), 13)
    }

    func testWeekRangeReturnsSevenDays() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let range = DateHelper.weekRange(for: mon)
        XCTAssertTrue(DateHelper.isSameDay(range.start, mon))
        let endDay = DateHelper.calendar.component(.day, from: range.end)
        XCTAssertEqual(endDay, 20)
    }

    func testWeekRangeTextSameMonth() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let text = DateHelper.weekRangeText(mon)
        XCTAssertTrue(text.contains("4"))
        XCTAssertTrue(text.contains("13"))
        XCTAssertTrue(text.contains("19"))
    }

    func testWeekRangeTextCrossYear() {
        let mon = DateHelper.calendar.date(from: DateComponents(year: 2025, month: 12, day: 29))!
        let text = DateHelper.weekRangeText(mon)
        XCTAssertTrue(text.contains("2025"))
        XCTAssertTrue(text.contains("2026"))
    }
}
