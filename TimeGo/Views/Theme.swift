import SwiftUI
import AppKit

enum TimeGoTheme {
    static let accent = Color(red: 0.22, green: 0.45, blue: 0.38)
    static let accentSoft = Color(red: 0.22, green: 0.45, blue: 0.38).opacity(0.14)
    static let overtime = Color(red: 0.86, green: 0.45, blue: 0.22)
    static let line = Color.primary.opacity(0.10)
    static let secondary = Color.primary.opacity(0.58)

    static var ink: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.93, alpha: 1)
                : NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.18, alpha: 1)
        })
    }

    static var panelBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    accent.opacity(0.12),
                    overtime.opacity(0.05),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func statusColor(isActive: Bool, isOvertime: Bool) -> Color {
        if !isActive { return secondary }
        return isOvertime ? overtime : accent
    }
}

struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(TimeGoTheme.line)
            .frame(height: 1)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(TimeGoTheme.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

struct MetaRow: View {
    let title: String
    let value: String
    var emphasize = false
    var valueColor: Color = TimeGoTheme.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(TimeGoTheme.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(emphasize
                      ? .system(.body, design: .rounded).weight(.semibold).monospacedDigit()
                      : .system(.subheadline, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
        }
    }
}

struct PermissionBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(TimeGoTheme.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = TimeGoTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundStyle(TimeGoTheme.ink.opacity(configuration.isPressed ? 0.5 : 0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06), in: Capsule())
    }
}
