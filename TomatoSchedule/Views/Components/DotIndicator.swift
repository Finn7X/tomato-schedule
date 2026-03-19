import SwiftUI

struct DotIndicator: View {
    let count: Int
    var isSelected: Bool = false
    var isOnTintedBackground: Bool = true

    private var dotColor: Color {
        if isOnTintedBackground {
            return isSelected ? .white : .white.opacity(0.7)
        } else {
            return .secondary
        }
    }

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                ForEach(0..<min(count, 4), id: \.self) { _ in
                    Circle()
                        .fill(dotColor)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 6)
        }
    }
}
