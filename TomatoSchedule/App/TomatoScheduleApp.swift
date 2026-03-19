import SwiftUI
import SwiftData

@main
struct TomatoScheduleApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear { seedSampleDataIfNeeded() }
        }
        .modelContainer(for: [Course.self, Lesson.self])
    }

    @MainActor
    private func seedSampleDataIfNeeded() {
        guard let container = try? ModelContainer(for: Course.self, Lesson.self) else { return }
        let context = container.mainContext

        let descriptor = FetchDescriptor<Course>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }

        let cal = DateHelper.calendar
        let today = DateHelper.startOfDay(.now)

        // Courses
        let piano = Course(name: "钢琴课", colorHex: "#42A5F5", subject: "钢琴", totalHours: 20, totalLessons: 20)
        let math = Course(name: "数学辅导", colorHex: "#FF6B6B", subject: "数学", totalHours: 36, totalLessons: 48)
        let english = Course(name: "英语口语", colorHex: "#66BB6A", subject: "口语", totalHours: 10, totalLessons: 10)
        let art = Course(name: "美术启蒙", colorHex: "#FFA726", notes: "水彩为主")

        for c in [piano, math, english, art] { context.insert(c) }

        // Helper to make a lesson
        func makeLesson(
            course: Course, student: String, dayOffset: Int,
            startHour: Int, startMin: Int, endHour: Int, endMin: Int,
            num: Int = 0, completed: Bool = false, location: String = ""
        ) {
            let date = cal.date(byAdding: .day, value: dayOffset, to: today)!
            let start = cal.date(bySettingHour: startHour, minute: startMin, second: 0, of: date)!
            let end = cal.date(bySettingHour: endHour, minute: endMin, second: 0, of: date)!
            let lesson = Lesson(
                course: course, studentName: student,
                date: DateHelper.startOfDay(date), startTime: start, endTime: end,
                lessonNumber: num, isCompleted: completed, location: location
            )
            context.insert(lesson)
        }

        // Today
        makeLesson(course: piano, student: "王小明", dayOffset: 0, startHour: 9, startMin: 0, endHour: 10, endMin: 0, num: 3, completed: false, location: "琴房A")
        makeLesson(course: math, student: "李华", dayOffset: 0, startHour: 14, startMin: 0, endHour: 15, endMin: 30, num: 5, completed: false)
        makeLesson(course: english, student: "张三", dayOffset: 0, startHour: 16, startMin: 0, endHour: 17, endMin: 0, num: 2, completed: false)

        // Tomorrow
        makeLesson(course: math, student: "陈晓", dayOffset: 1, startHour: 10, startMin: 0, endHour: 11, endMin: 30, num: 6)
        makeLesson(course: art, student: "小美", dayOffset: 1, startHour: 14, startMin: 0, endHour: 15, endMin: 30)

        // Yesterday (completed)
        makeLesson(course: piano, student: "王小明", dayOffset: -1, startHour: 9, startMin: 0, endHour: 10, endMin: 0, num: 2, completed: true, location: "琴房A")
        makeLesson(course: english, student: "张三", dayOffset: -1, startHour: 15, startMin: 0, endHour: 16, endMin: 0, num: 1, completed: true)

        // Day after tomorrow
        makeLesson(course: piano, student: "刘洋", dayOffset: 2, startHour: 10, startMin: 0, endHour: 11, endMin: 0, num: 4, location: "琴房B")
        makeLesson(course: math, student: "李华", dayOffset: 2, startHour: 13, startMin: 30, endHour: 15, endMin: 0, num: 7)

        // 3 days ago (completed)
        makeLesson(course: math, student: "李华", dayOffset: -3, startHour: 14, startMin: 0, endHour: 15, endMin: 30, num: 4, completed: true)
        makeLesson(course: art, student: "小美", dayOffset: -3, startHour: 16, startMin: 0, endHour: 17, endMin: 30, completed: true)

        // Next week
        makeLesson(course: english, student: "张三", dayOffset: 5, startHour: 16, startMin: 0, endHour: 17, endMin: 0, num: 3)
        makeLesson(course: piano, student: "王小明", dayOffset: 6, startHour: 9, startMin: 0, endHour: 10, endMin: 0, num: 5, location: "琴房A")

        try? context.save()
    }
}
