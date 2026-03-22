import SwiftUI
import SwiftData

@main
struct TomatoScheduleApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    seedSampleDataIfNeeded()
                    autoCompletePastLessons()
                }
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

        let reading = Course(name: "雅思阅读", colorHex: "#42A5F5", subject: "阅读", totalHours: 36, totalLessons: 48, hourlyRate: 200)
        let trial = Course(name: "雅思阅读试听", colorHex: "#FFA726", notes: "试听课1小时", hourlyRate: 100)
        let speaking = Course(name: "雅思口语", colorHex: "#66BB6A", subject: "口语", totalHours: 20, totalLessons: 20, hourlyRate: 250)

        for c in [reading, trial, speaking] { context.insert(c) }

        func make(_ course: Course, student: String, offset: Int,
                   sh: Int, sm: Int, eh: Int, em: Int,
                   num: Int = 0, done: Bool = false, loc: String = "",
                   freeLesson: Bool = false) {
            let d = cal.date(byAdding: .day, value: offset, to: today)!
            let s = cal.date(bySettingHour: sh, minute: sm, second: 0, of: d)!
            let e = cal.date(bySettingHour: eh, minute: em, second: 0, of: d)!
            let lesson = Lesson(
                course: course, studentName: student,
                date: DateHelper.startOfDay(d), startTime: s, endTime: e,
                lessonNumber: num, isCompleted: done, location: loc
            )
            if done {
                if freeLesson {
                    lesson.priceOverride = 0
                    lesson.isPriceOverridden = true
                } else {
                    let price = lesson.effectivePrice  // calculate BEFORE setting isPriceOverridden
                    lesson.priceOverride = price
                    lesson.isPriceOverridden = true
                }
            }
            context.insert(lesson)
        }

        // Past completed
        make(reading, student: "陈牧崧", offset: -14, sh: 8, sm: 0, eh: 10, em: 0, num: 1, done: true, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: "朱宸逸", offset: -14, sh: 14, sm: 0, eh: 15, em: 0, num: 1, done: true)
        make(reading, student: "陈牧崧", offset: -12, sh: 8, sm: 0, eh: 10, em: 0, num: 2, done: true, loc: "凯旋城校区VIP3067教室")
        make(trial, student: "新学员小李", offset: -12, sh: 11, sm: 0, eh: 12, em: 0, done: true, loc: "线上", freeLesson: true)
        make(speaking, student: "朱宸逸", offset: -10, sh: 14, sm: 0, eh: 15, em: 0, num: 2, done: true)
        make(reading, student: "李函颖", offset: -10, sh: 9, sm: 0, eh: 11, em: 0, num: 1, done: true)
        make(reading, student: "陈牧崧", offset: -8, sh: 8, sm: 0, eh: 10, em: 0, num: 3, done: true, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: "王佳琪", offset: -8, sh: 15, sm: 0, eh: 16, em: 0, num: 1, done: true)
        make(reading, student: "李函颖", offset: -6, sh: 9, sm: 0, eh: 11, em: 0, num: 2, done: true)
        make(speaking, student: "朱宸逸", offset: -6, sh: 14, sm: 0, eh: 15, em: 30, num: 3, done: true)
        make(reading, student: "陈牧崧", offset: -4, sh: 8, sm: 0, eh: 10, em: 0, num: 4, done: true, loc: "凯旋城校区VIP3067教室")
        make(trial, student: "新学员赵琳", offset: -4, sh: 11, sm: 0, eh: 12, em: 0, done: true, loc: "线上")
        make(speaking, student: "王佳琪", offset: -3, sh: 15, sm: 0, eh: 16, em: 0, num: 2, done: true)
        make(reading, student: "李函颖", offset: -2, sh: 9, sm: 0, eh: 11, em: 0, num: 3, done: true)
        make(speaking, student: "朱宸逸", offset: -2, sh: 14, sm: 0, eh: 15, em: 0, num: 4, done: true)
        make(reading, student: "陈牧崧", offset: -1, sh: 8, sm: 0, eh: 10, em: 0, num: 5, done: true, loc: "凯旋城校区VIP3067教室")

        // Today
        make(reading, student: "陈牧崧", offset: 0, sh: 8, sm: 0, eh: 10, em: 0, num: 6, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: "朱宸逸", offset: 0, sh: 14, sm: 0, eh: 15, em: 0, num: 5)
        make(trial, student: "新学员张明", offset: 0, sh: 16, sm: 0, eh: 17, em: 0, loc: "线上")

        // Future
        make(reading, student: "李函颖", offset: 1, sh: 9, sm: 0, eh: 11, em: 0, num: 4)
        make(speaking, student: "王佳琪", offset: 1, sh: 15, sm: 0, eh: 16, em: 0, num: 3)
        make(reading, student: "陈牧崧", offset: 3, sh: 8, sm: 0, eh: 10, em: 0, num: 7, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: "朱宸逸", offset: 3, sh: 14, sm: 0, eh: 15, em: 30, num: 6)
        make(reading, student: "李函颖", offset: 5, sh: 9, sm: 0, eh: 11, em: 0, num: 5)
        make(speaking, student: "王佳琪", offset: 5, sh: 15, sm: 0, eh: 16, em: 0, num: 4)
        make(reading, student: "陈牧崧", offset: 7, sh: 8, sm: 0, eh: 10, em: 0, num: 8, loc: "凯旋城校区VIP3067教室")

        try? context.save()
    }

    @MainActor
    private func autoCompletePastLessons() {
        guard let container = try? ModelContainer(for: Course.self, Lesson.self) else { return }
        let context = container.mainContext
        let now = Date.now
        let descriptor = FetchDescriptor<Lesson>()
        guard let lessons = try? context.fetch(descriptor) else { return }
        var changed = false
        for lesson in lessons where !lesson.isCompleted && lesson.endTime < now {
            lesson.isCompleted = true
            if !lesson.isPriceOverridden {
                lesson.priceOverride = lesson.effectivePrice
                lesson.isPriceOverridden = true
            }
            changed = true
        }
        if changed { try? context.save() }
    }
}
