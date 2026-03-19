import SwiftUI

enum PresetColors {
    static let all: [(name: String, hex: String)] = [
        ("番茄红", "#FF6B6B"),
        ("橙子橙", "#FFA726"),
        ("柠檬黄", "#FFEE58"),
        ("薄荷绿", "#66BB6A"),
        ("天空蓝", "#42A5F5"),
        ("薰衣草", "#AB47BC"),
        ("樱花粉", "#F48FB1"),
        ("巧克力", "#8D6E63"),
        ("石墨灰", "#78909C"),
        ("深海蓝", "#5C6BC0"),
    ]

    static func color(for hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6,
              let rgb = UInt64(hex, radix: 16) else {
            return .gray
        }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
