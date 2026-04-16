import XCTest
@testable import TomatoSchedule

final class LessonLaneLayoutTests: XCTestCase {
    private let cal = DateHelper.calendar
    private lazy var stubCourse = Course(name: "Test", colorHex: "#FF0000")

    private func makeLessonStub(start: Int, startMin: Int = 0, end: Int, endMin: Int = 0) -> Lesson {
        let today = cal.startOfDay(for: Date())
        let lesson = Lesson(
            course: stubCourse,
            studentName: "Test",
            date: today,
            startTime: cal.date(bySettingHour: start, minute: startMin, second: 0, of: today)!,
            endTime: cal.date(bySettingHour: end, minute: endMin, second: 0, of: today)!
        )
        return lesson
    }

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

    func testCrossDayLessonClipsTrailing() {
        let today = cal.startOfDay(for: Date())
        let startTime = cal.date(bySettingHour: 22, minute: 0, second: 0, of: today)!
        let endTime = cal.date(byAdding: .hour, value: 3, to: startTime)!
        let lesson = Lesson(
            course: stubCourse,
            studentName: "Test",
            date: today,
            startTime: startTime,
            endTime: endTime
        )
        let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: today)!
        let clusters = LessonLaneLayout.buildClusters(
            [lesson], maxLanes: 3, dayRange: (9, 23), dayEnd: dayEnd
        )
        XCTAssertEqual(clusters[0].visibleBlocks[0].clipsTrailing, true)
        XCTAssertEqual(clusters[0].visibleBlocks[0].clipsLeading, false)
    }

    func testEmptyInputProducesEmptyOutput() {
        let clusters = LessonLaneLayout.buildClusters(
            [], maxLanes: 3, dayRange: (9, 21),
            dayEnd: cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
        )
        XCTAssertTrue(clusters.isEmpty)
    }
}
