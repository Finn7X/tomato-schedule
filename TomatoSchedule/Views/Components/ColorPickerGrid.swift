import SwiftUI

struct ColorPickerGrid: View {
    @Binding var selectedHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(PresetColors.all, id: \.hex) { preset in
                Circle()
                    .fill(PresetColors.color(for: preset.hex))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: selectedHex == preset.hex ? 3 : 0)
                            .padding(-3)
                    )
                    .onTapGesture {
                        selectedHex = preset.hex
                    }
                    .accessibilityLabel(preset.name)
            }
        }
    }
}
