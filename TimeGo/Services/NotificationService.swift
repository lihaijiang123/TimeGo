import AppKit
import Foundation
import UserNotifications
import Combine

enum NotificationAuthState: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
    case unknown

    var title: String {
        let l10n = L10n.shared
        switch self {
        case .notDetermined: return l10n.t("auth.notDetermined")
        case .authorized: return l10n.t("auth.authorized")
        case .denied: return l10n.t("auth.denied")
        case .provisional, .ephemeral: return l10n.t("auth.provisional")
        case .unknown: return l10n.t("auth.unknown")
        }
    }

    var isGranted: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    static let targetID = "timego.target.reached"
    static let earlyID = "timego.target.early"

    @Published private(set) var authState: NotificationAuthState = .unknown

    /// Called when the system delivers a TimeGo work notification (scheduled or immediate).
    var onWorkNotificationDelivered: ((String) -> Void)?

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authState = Self.map(settings.authorizationStatus)
    }

    /// Request permission. Activates the app so the system dialog can appear for menu-bar apps.
    @discardableResult
    func requestAuthorization(forcePrompt: Bool = true) async -> Bool {
        await refreshAuthorizationStatus()

        if authState == .denied {
            if forcePrompt {
                openSystemNotificationSettings()
            }
            return false
        }

        if authState.isGranted {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            SettingsPanelController.shared.bringToFront()
            return granted || authState.isGranted
        } catch {
            await refreshAuthorizationStatus()
            SettingsPanelController.shared.bringToFront()
            return false
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func notifyTargetReached(leaveTime: Date, workHours: Double, lunchHours: Double) {
        guard authState.isGranted || authState == .unknown else { return }

        let l10n = L10n.shared
        let content = UNMutableNotificationContent()
        content.title = l10n.t("notify.title")
        content.body = l10n.t(
            "notify.bodyLeave",
            dutySummary(workHours: workHours, lunchHours: lunchHours),
            Self.timeFormatter.string(from: leaveTime)
        )
        content.sound = .default

        center.add(
            UNNotificationRequest(identifier: Self.targetID, content: content, trigger: nil)
        )
    }

    func notifyEarlyReminder(leaveTime: Date, minutes: Int) {
        guard authState.isGranted || authState == .unknown else { return }

        let l10n = L10n.shared
        let content = UNMutableNotificationContent()
        content.title = l10n.t("notify.earlyTitle", minutes)
        content.body = l10n.t("notify.earlyBody", Self.timeFormatter.string(from: leaveTime))
        content.sound = .default

        center.add(
            UNNotificationRequest(identifier: Self.earlyID, content: content, trigger: nil)
        )
    }

    func scheduleTargetNotification(at date: Date, workHours: Double, lunchHours: Double) {
        guard date > .now else { return }
        guard authState.isGranted || authState == .unknown else { return }

        let l10n = L10n.shared
        let content = UNMutableNotificationContent()
        content.title = l10n.t("notify.title")
        content.body = l10n.t(
            "notify.bodyReady",
            dutySummary(workHours: workHours, lunchHours: lunchHours)
        )
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(
            UNNotificationRequest(identifier: Self.targetID, content: content, trigger: trigger)
        )
    }

    func scheduleEarlyNotification(at date: Date, leaveTime: Date, minutes: Int) {
        guard date > .now else { return }
        guard authState.isGranted || authState == .unknown else { return }

        let l10n = L10n.shared
        let content = UNMutableNotificationContent()
        content.title = l10n.t("notify.earlyTitle", minutes)
        content.body = l10n.t("notify.earlyBody", Self.timeFormatter.string(from: leaveTime))
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(
            UNNotificationRequest(identifier: Self.earlyID, content: content, trigger: trigger)
        )
    }

    func cancelPending() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.targetID, Self.earlyID])
    }

    func noteWorkNotificationDelivered(identifier: String) {
        onWorkNotificationDelivered?(identifier)
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    private func dutySummary(workHours: Double, lunchHours: Double) -> String {
        let l10n = L10n.shared
        let work = formatHours(workHours)
        if lunchHours > 0 {
            return l10n.t("notify.dutyWithLunch", work, formatHours(lunchHours))
        }
        return l10n.t("notify.duty", work)
    }

    private func formatHours(_ hours: Double) -> String {
        if hours.rounded() == hours {
            return String(Int(hours))
        }
        return String(format: "%.1f", hours)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
