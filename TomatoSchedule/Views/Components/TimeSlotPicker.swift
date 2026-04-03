import SwiftUI

struct TimeSlotPicker: View {
    @Binding var startTime: Date
    @Binding var endTime: Date
    var date: Date
    var slotInterval: Int = 30
    var dayStartHour: Int = 8
    var dayEndHour: Int = 22
    var forcePickerMode: Bool = false

    @State private var useGridMode: Bool = true
    @State private var hasStartSelection: Bool = false
    @State private var isCustomEndMode: Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 12) {
            if useGridMode {
                gridModeView
            } else {
                pickerModeView
            }
        }
        .onAppear {
            useGridMode = !forcePickerMode
        }
    }

    // MARK: - Grid Mode

    private var gridModeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isCustomEndMode ? "选择结束时间" : "选择开始时间")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(availableSlots, id: \.self) { slot in
                    timeButton(for: slot)
                }
            }

            if hasStartSelection && !isCustomEndMode {
                durationButtonsView
            }

            if hasStartSelection && hasEndSelection {
                summaryLine
            }

            Button(action: { useGridMode = false }) {
                Text("切换到精确输入")
                    .font(.footnote)
                    .foregroundStyle(.teal)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Picker Mode

    private var pickerModeView: some View {
        VStack(spacing: 0) {
            DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
            DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)

            Button(action: { useGridMode = true }) {
                Text("切换到快速选择")
                    .font(.footnote)
                    .foregroundStyle(.teal)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
    }

    // MARK: - Time Button

    private func timeButton(for slot: Date) -> some View {
        let state = buttonState(for: slot)
        return Button {
            handleSlotTap(slot)
        } label: {
            Text(DateHelper.timeString(slot))
                .font(.subheadline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(state.background)
                .foregroundStyle(state.foreground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duration Buttons

    private var durationButtonsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择时长")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                durationButton(label: "1h", minutes: 60)
                durationButton(label: "1.5h", minutes: 90)
                durationButton(label: "2h", minutes: 120)
                durationButton(label: "3h", minutes: 180)

                Button {
                    isCustomEndMode = true
                } label: {
                    Text("自定义")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color.teal.opacity(0.12))
                        .foregroundStyle(.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func durationButton(label: String, minutes: Int) -> some View {
        let disabled = isDurationDisabled(minutes)
        return Button {
            applyDuration(minutes)
        } label: {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(disabled ? Color(.quaternarySystemFill) : Color.teal.opacity(0.12))
                .foregroundStyle(disabled ? Color.secondary : Color.teal)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Summary

    private var summaryLine: some View {
        let cal = DateHelper.calendar
        let minutes = cal.dateComponents([.minute], from: startTime, to: endTime).minute ?? 0
        let durationText: String = {
            if minutes % 60 == 0 {
                return "\(minutes / 60)小时"
            } else {
                let hours = Double(minutes) / 60.0
                return String(format: "%.1f小时", hours)
            }
        }()

        return HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.teal)
            Text("已选: \(DateHelper.timeString(startTime)) — \(DateHelper.timeString(endTime)) (\(durationText))")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Slot Generation

    private var timeSlots: [Date] {
        var slots: [Date] = []
        let cal = DateHelper.calendar
        var hour = dayStartHour
        var minute = 0
        while hour < dayEndHour || (hour == dayEndHour && minute == 0) {
            if let d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                slots.append(d)
            }
            minute += slotInterval
            if minute >= 60 { hour += 1; minute -= 60 }
        }
        // Remove last slot (dayEndHour:00) since it can only be an end time, not a start
        if let last = slots.last,
           cal.component(.hour, from: last) == dayEndHour {
            slots.removeLast()
        }
        return slots
    }

    private var availableSlots: [Date] {
        if isCustomEndMode {
            // Only show slots after start time
            return timeSlots.filter { $0 > startTime }
        }
        return timeSlots
    }

    // MARK: - Button State

    private struct SlotButtonState {
        let background: AnyShapeStyle
        let foreground: Color
    }

    private func buttonState(for slot: Date) -> SlotButtonState {
        let cal = DateHelper.calendar

        if isCustomEndMode {
            // In custom end mode, highlight the selected end time
            if hasEndSelection && cal.isDate(slot, equalTo: endTime, toGranularity: .minute) {
                return SlotButtonState(
                    background: AnyShapeStyle(Color.teal),
                    foreground: .white
                )
            }
            return SlotButtonState(
                background: AnyShapeStyle(Color(.quaternarySystemFill)),
                foreground: .primary
            )
        }

        // Start selected
        if hasStartSelection && cal.isDate(slot, equalTo: startTime, toGranularity: .minute) {
            return SlotButtonState(
                background: AnyShapeStyle(Color.teal),
                foreground: .white
            )
        }

        // In range (between start and end)
        if hasStartSelection && hasEndSelection && slot > startTime && slot < endTime {
            return SlotButtonState(
                background: AnyShapeStyle(Color.teal.opacity(0.15)),
                foreground: .teal
            )
        }

        // Unselected
        return SlotButtonState(
            background: AnyShapeStyle(Color(.quaternarySystemFill)),
            foreground: .primary
        )
    }

    // MARK: - Interaction

    private var hasEndSelection: Bool {
        hasStartSelection && endTime > startTime
    }

    private func handleSlotTap(_ slot: Date) {
        if isCustomEndMode {
            endTime = slot
            isCustomEndMode = false
        } else {
            startTime = slot
            hasStartSelection = true
            // Reset end time when new start is selected
            endTime = slot
            isCustomEndMode = false
        }
    }

    private func isDurationDisabled(_ durationMinutes: Int) -> Bool {
        let cal = DateHelper.calendar
        let startH = cal.component(.hour, from: startTime)
        let startM = cal.component(.minute, from: startTime)
        let startAbsMin = startH * 60 + startM
        let latestEndMin = dayEndHour * 60
        return startAbsMin + durationMinutes > latestEndMin
    }

    private func applyDuration(_ durationMinutes: Int) {
        let cal = DateHelper.calendar
        if let end = cal.date(byAdding: .minute, value: durationMinutes, to: startTime) {
            endTime = end
        }
    }
}
