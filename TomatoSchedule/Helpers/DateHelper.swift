import Foundation

enum DateHelper {
    private static let cnCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        cal.firstWeekday = 2 // Monday first
        return cal
    }()

    static var calendar: Calendar { cnCalendar }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(date))!
    }

    static func weekRange(for date: Date) -> (start: Date, end: Date) {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        return (start, end)
    }

    static func monthRange(for date: Date) -> (start: Date, end: Date) {
        let interval = calendar.dateInterval(of: .month, for: date)!
        return (interval.start, interval.end)
    }

    static func daysInMonth(for date: Date) -> [Date] {
        let range = monthRange(for: date)
        var days: [Date] = []
        var current = range.start
        while current < range.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }

    static func weekdaySymbol(_ date: Date) -> String {
        let symbols = ["一", "二", "三", "四", "五", "六", "日"]
        let weekday = calendar.component(.weekday, from: date)
        let index = (weekday + 5) % 7
        return "周\(symbols[index])"
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }

    static func monthString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    static func combine(date: Date, time: Date) -> Date {
        let dateComps = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComps = calendar.dateComponents([.hour, .minute], from: time)
        var combined = DateComponents()
        combined.year = dateComps.year
        combined.month = dateComps.month
        combined.day = dateComps.day
        combined.hour = timeComps.hour
        combined.minute = timeComps.minute
        return calendar.date(from: combined) ?? date
    }
}
