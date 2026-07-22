import SwiftUI
import AppKit

/// Compact `HH:mm` control: shows plain text until tapped, then edits with
/// hour → minute autofocus. Avoids stealing first responder when the menu opens.
struct HourMinuteField: View {
    @Binding var date: Date

    @State private var isEditing = false
    @State private var hourText = ""
    @State private var minuteText = ""
    @State private var isPushing = false
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case hour
        case minute
    }

    private var displayText: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                Text(displayText)
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(TimeGoTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onTapGesture {
                        beginEditing()
                    }
                    .help(L10n.shared.t("menu.editTimeHint"))
            }
        }
        .onAppear {
            pullFromDate()
            // Menu bar windows often auto-focus the first text field; keep idle.
            isEditing = false
            focused = nil
            DispatchQueue.main.async {
                focused = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onChange(of: date) { _, _ in
            guard !isPushing else { return }
            pullFromDate()
        }
    }

    private var editor: some View {
        HStack(spacing: 3) {
            digitField(text: $hourText, field: .hour)
            Text(":")
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(TimeGoTheme.secondary)
            digitField(text: $minuteText, field: .minute)
        }
        .onChange(of: hourText) { _, newValue in
            let cleaned = Self.sanitize(newValue, max: 23)
            if cleaned != newValue {
                hourText = cleaned
                return
            }
            if cleaned.count == 2 {
                pushToDate()
                focused = .minute
            }
        }
        .onChange(of: minuteText) { _, newValue in
            let cleaned = Self.sanitize(newValue, max: 59)
            if cleaned != newValue {
                minuteText = cleaned
                return
            }
            if cleaned.count == 2 {
                pushToDate()
            }
        }
        .onChange(of: focused) { old, new in
            if old == .hour, new != .hour {
                normalizeHourText()
                pushToDate()
            }
            if old == .minute, new != .minute {
                normalizeMinuteText()
                pushToDate()
            }
            if new == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    if focused == nil {
                        endEditing()
                    }
                }
            }
        }
        .onExitCommand {
            endEditing()
        }
    }

    private func beginEditing() {
        pullFromDate()
        isEditing = true
        DispatchQueue.main.async {
            focused = .hour
        }
    }

    private func endEditing() {
        normalizeHourText()
        normalizeMinuteText()
        pushToDate()
        focused = nil
        isEditing = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func digitField(text: Binding<String>, field: Field) -> some View {
        TextField("00", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
            .frame(width: 30)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .focused($focused, equals: field)
            .onKeyPress(.upArrow) {
                nudge(field, by: 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                nudge(field, by: -1)
                return .handled
            }
            .onSubmit {
                if field == .hour {
                    normalizeHourText()
                    pushToDate()
                    focused = .minute
                } else {
                    endEditing()
                }
            }
    }

    private func nudge(_ field: Field, by delta: Int) {
        switch field {
        case .hour:
            let current = min(23, max(0, Int(hourText) ?? 0))
            hourText = String(format: "%02d", (current + delta + 24) % 24)
        case .minute:
            let current = min(59, max(0, Int(minuteText) ?? 0))
            minuteText = String(format: "%02d", (current + delta + 60) % 60)
        }
        pushToDate()
    }

    private func pullFromDate() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        hourText = String(format: "%02d", comps.hour ?? 0)
        minuteText = String(format: "%02d", comps.minute ?? 0)
    }

    private func normalizeHourText() {
        let value = min(23, max(0, Int(hourText) ?? 0))
        hourText = String(format: "%02d", value)
    }

    private func normalizeMinuteText() {
        let value = min(59, max(0, Int(minuteText) ?? 0))
        minuteText = String(format: "%02d", value)
    }

    private func pushToDate() {
        guard let hour = Int(hourText), let minute = Int(minuteText) else { return }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }

        var comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let next = Calendar.current.date(from: comps), next != date else { return }

        isPushing = true
        date = next
        isPushing = false
    }

    private static func sanitize(_ raw: String, max: Int) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(2))
        guard digits.count == 2, let value = Int(digits) else { return digits }
        if value > max {
            return String(format: "%02d", max)
        }
        return digits
    }
}
