import Foundation

/// Chinese lunar calendar helpers, mirroring Apple Calendar's display strings.
/// Examples:
/// - lunarDayLabel(for: 2026-04-15) → "廿八"
/// - lunarDayLabel(for: 2026-04-17) → "三月" (lunar month boundary day)
/// - lunarYearLabel(for: 2026-04-15) → "丙午马年"
enum LunarHelper {
    // 农历日：1=初一 .. 30=三十
    private static let dayNames: [String] = [
        "",
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    // 农历月：1=正月 .. 12=腊月
    private static let monthNames: [String] = [
        "",
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    // 12 生肖（地支顺序：子丑寅卯辰巳午未申酉戌亥）
    private static let zodiacs: [String] = [
        "鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"
    ]

    // 天干地支组合（60 甲子）顺序：甲子(1) → 癸亥(60)
    // Cyclic year mod 12 gives the 地支 index → zodiac
    // (cyclicYear - 1) % 12 maps to:
    //   0=子(鼠), 1=丑(牛), 2=寅(虎), 3=卯(兔), 4=辰(龙), 5=巳(蛇),
    //   6=午(马), 7=未(羊), 8=申(猴), 9=酉(鸡), 10=戌(狗), 11=亥(猪)

    private static let chineseCalendar = Calendar(identifier: .chinese)

    /// 农历"日"：每月初一显示月名（如"三月"），其它日显示日名（如"廿八"）
    static func lunarDayLabel(for date: Date) -> String {
        let day = chineseCalendar.component(.day, from: date)
        if day == 1 {
            let month = chineseCalendar.component(.month, from: date)
            // Detect leap month using DateComponents
            let comps = chineseCalendar.dateComponents([.month], from: date)
            let isLeap = comps.isLeapMonth ?? false
            guard month >= 1, month < monthNames.count else { return "" }
            return (isLeap ? "闰" : "") + monthNames[month]
        }
        guard day >= 1, day < dayNames.count else { return "" }
        return dayNames[day]
    }

    /// 农历年：如"丙午马年"
    static func lunarYearLabel(for date: Date) -> String {
        let cyclicYear = chineseCalendar.component(.year, from: date)  // 1...60
        let zodiacIndex = ((cyclicYear - 1) % 12 + 12) % 12

        let formatter = DateFormatter()
        formatter.calendar = chineseCalendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "U"  // 干支年（如"丙午"）
        let cyclic = formatter.string(from: date)

        return "\(cyclic)\(zodiacs[zodiacIndex])年"
    }
}
