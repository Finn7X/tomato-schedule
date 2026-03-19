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

        // --- Courses ---
        let reading = Course(name: "雅思阅读", colorHex: "#42A5F5", subject: "阅读", totalHours: 36, totalLessons: 48)
        let speaking = Course(name: "雅思口语", colorHex: "#FF6B6B", subject: "口语", totalHours: 20, totalLessons: 20)
        let listening = Course(name: "雅思听力", colorHex: "#66BB6A", subject: "听力", totalHours: 24, totalLessons: 32)
        let writing = Course(name: "雅思写作", colorHex: "#AB47BC", subject: "写作", totalHours: 18, totalLessons: 24)
        let trialReading = Course(name: "阅读试听", colorHex: "#FFA726", notes: "试听课，1小时")
        let vocab = Course(name: "单词默写", colorHex: "#5C6BC0", subject: "词汇", totalHours: 10, totalLessons: 20)

        for c in [reading, speaking, listening, writing, trialReading, vocab] {
            context.insert(c)
        }

        // --- Helper ---
        func make(
            _ course: Course, student: String, offset: Int,
            sh: Int, sm: Int, eh: Int, em: Int,
            num: Int = 0, done: Bool = false, loc: String = ""
        ) {
            let d = cal.date(byAdding: .day, value: offset, to: today)!
            let s = cal.date(bySettingHour: sh, minute: sm, second: 0, of: d)!
            let e = cal.date(bySettingHour: eh, minute: em, second: 0, of: d)!
            context.insert(Lesson(
                course: course, studentName: student,
                date: DateHelper.startOfDay(d), startTime: s, endTime: e,
                lessonNumber: num, isCompleted: done, location: loc
            ))
        }

        let students = ["陈牧崧", "朱宸逸", "李函颖", "王佳琪", "韩双双", "张明远", "刘思雨", "赵晨曦"]

        // --- Past lessons (completed) : day -20 to -1 ---

        // -20
        make(reading, student: students[0], offset: -20, sh: 8, sm: 0, eh: 10, em: 0, num: 1, done: true, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: students[1], offset: -20, sh: 14, sm: 0, eh: 15, em: 0, num: 1, done: true)

        // -18
        make(listening, student: students[2], offset: -18, sh: 9, sm: 0, eh: 11, em: 0, num: 1, done: true, loc: "仙林高科校区VIP804教室")
        make(vocab, student: students[3], offset: -18, sh: 16, sm: 0, eh: 17, em: 0, num: 1, done: true)

        // -16
        make(reading, student: students[0], offset: -16, sh: 8, sm: 0, eh: 10, em: 0, num: 2, done: true, loc: "凯旋城校区VIP3067教室")
        make(writing, student: students[4], offset: -16, sh: 13, sm: 30, eh: 15, em: 30, num: 1, done: true)

        // -14
        make(speaking, student: students[1], offset: -14, sh: 14, sm: 0, eh: 15, em: 0, num: 2, done: true)
        make(listening, student: students[2], offset: -14, sh: 9, sm: 0, eh: 11, em: 0, num: 2, done: true, loc: "仙林高科校区VIP804教室")
        make(vocab, student: students[5], offset: -14, sh: 16, sm: 30, eh: 17, em: 30, num: 2, done: true)

        // -12
        make(reading, student: students[0], offset: -12, sh: 8, sm: 0, eh: 10, em: 0, num: 3, done: true, loc: "凯旋城校区VIP3067教室")
        make(trialReading, student: students[6], offset: -12, sh: 11, sm: 0, eh: 12, em: 0, done: true, loc: "线上")

        // -10
        make(writing, student: students[4], offset: -10, sh: 13, sm: 30, eh: 15, em: 30, num: 2, done: true)
        make(speaking, student: students[1], offset: -10, sh: 10, sm: 0, eh: 11, em: 0, num: 3, done: true)
        make(listening, student: students[7], offset: -10, sh: 15, sm: 30, eh: 17, em: 0, num: 3, done: true)

        // -8
        make(reading, student: students[0], offset: -8, sh: 8, sm: 0, eh: 10, em: 0, num: 4, done: true, loc: "凯旋城校区VIP3067教室")
        make(vocab, student: students[3], offset: -8, sh: 16, sm: 0, eh: 17, em: 0, num: 3, done: true)

        // -6
        make(listening, student: students[2], offset: -6, sh: 9, sm: 0, eh: 11, em: 0, num: 4, done: true, loc: "仙林高科校区VIP804教室")
        make(writing, student: students[4], offset: -6, sh: 14, sm: 0, eh: 16, em: 0, num: 3, done: true)

        // -4
        make(reading, student: students[0], offset: -4, sh: 8, sm: 0, eh: 10, em: 0, num: 5, done: true, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: students[1], offset: -4, sh: 14, sm: 0, eh: 15, em: 0, num: 4, done: true)
        make(vocab, student: students[5], offset: -4, sh: 16, sm: 30, eh: 17, em: 30, num: 4, done: true)

        // -2
        make(listening, student: students[7], offset: -2, sh: 9, sm: 0, eh: 10, em: 30, num: 5, done: true)
        make(writing, student: students[4], offset: -2, sh: 13, sm: 30, eh: 15, em: 30, num: 4, done: true)
        make(trialReading, student: students[3], offset: -2, sh: 16, sm: 0, eh: 17, em: 0, done: true, loc: "线上")

        // -1 yesterday
        make(reading, student: students[0], offset: -1, sh: 8, sm: 0, eh: 10, em: 0, num: 6, done: true, loc: "凯旋城校区VIP3067教室")
        make(speaking, student: students[1], offset: -1, sh: 14, sm: 0, eh: 15, em: 0, num: 5, done: true)

        // --- Today ---
        make(reading, student: students[0], offset: 0, sh: 8, sm: 0, eh: 10, em: 0, num: 7, loc: "凯旋城校区VIP3067教室")
        make(listening, student: students[2], offset: 0, sh: 10, sm: 30, eh: 12, em: 0, num: 6, loc: "仙林高科校区VIP804教室")
        make(speaking, student: students[1], offset: 0, sh: 14, sm: 0, eh: 15, em: 0, num: 6)
        make(vocab, student: students[3], offset: 0, sh: 16, sm: 0, eh: 17, em: 0, num: 5)

        // --- Future: day +1 to +10 ---

        // +1
        make(writing, student: students[4], offset: 1, sh: 9, sm: 0, eh: 11, em: 0, num: 5)
        make(reading, student: students[0], offset: 1, sh: 13, sm: 50, eh: 15, em: 50, num: 8, loc: "凯旋城校区VIP3067教室")
        make(vocab, student: students[5], offset: 1, sh: 16, sm: 30, eh: 17, em: 30, num: 6)

        // +2
        make(speaking, student: students[1], offset: 2, sh: 10, sm: 0, eh: 11, em: 0, num: 7)
        make(listening, student: students[7], offset: 2, sh: 14, sm: 0, eh: 15, em: 30, num: 7)

        // +3
        make(reading, student: students[0], offset: 3, sh: 8, sm: 0, eh: 10, em: 0, num: 9, loc: "凯旋城校区VIP3067教室")
        make(trialReading, student: "新学员小李", offset: 3, sh: 11, sm: 0, eh: 12, em: 0, loc: "线上")
        make(writing, student: students[4], offset: 3, sh: 14, sm: 0, eh: 16, em: 0, num: 6)

        // +5
        make(listening, student: students[2], offset: 5, sh: 9, sm: 0, eh: 11, em: 0, num: 8, loc: "仙林高科校区VIP804教室")
        make(speaking, student: students[1], offset: 5, sh: 14, sm: 0, eh: 15, em: 0, num: 8)
        make(vocab, student: students[3], offset: 5, sh: 16, sm: 0, eh: 17, em: 0, num: 7)

        // +7
        make(reading, student: students[0], offset: 7, sh: 8, sm: 0, eh: 10, em: 0, num: 10, loc: "凯旋城校区VIP3067教室")
        make(writing, student: students[4], offset: 7, sh: 13, sm: 30, eh: 15, em: 30, num: 7)

        // +8
        make(speaking, student: students[1], offset: 8, sh: 10, sm: 0, eh: 11, em: 0, num: 9)
        make(listening, student: students[7], offset: 8, sh: 15, sm: 0, eh: 16, em: 30, num: 9)
        make(vocab, student: students[5], offset: 8, sh: 17, sm: 0, eh: 18, em: 0, num: 8)

        // +10
        make(reading, student: students[0], offset: 10, sh: 8, sm: 0, eh: 10, em: 0, num: 11, loc: "凯旋城校区VIP3067教室")
        make(trialReading, student: "新学员赵琳", offset: 10, sh: 14, sm: 0, eh: 15, em: 0, loc: "线上")

        try? context.save()
    }
}
