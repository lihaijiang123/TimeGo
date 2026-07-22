import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusTitle = "未知"
    @Published private(set) var needsApproval = false
    @Published private(set) var lastError: String?

    func refresh() {
        let l10n = L10n.shared
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            needsApproval = false
            statusTitle = l10n.t("login.enabled")
        case .requiresApproval:
            isEnabled = false
            needsApproval = true
            statusTitle = l10n.t("login.needsApproval")
        case .notRegistered:
            isEnabled = false
            needsApproval = false
            statusTitle = l10n.t("login.notRegistered")
        case .notFound:
            isEnabled = false
            needsApproval = false
            statusTitle = l10n.t("login.notFound")
        @unknown default:
            isEnabled = false
            needsApproval = false
            statusTitle = l10n.t("login.unknown")
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        lastError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            return enabled ? (isEnabled || needsApproval) : !isEnabled
        } catch {
            lastError = error.localizedDescription
            refresh()
            return false
        }
    }

    /// Apply preference from settings; keeps OS login item in sync.
    func sync(withPreferred preferred: Bool) {
        refresh()

        // If a previous login item pointed at a deleted DerivedData build, status is
        // `.notFound` and macOS cannot launch the app at all — clear and re-register.
        if SMAppService.mainApp.status == .notFound {
            try? SMAppService.mainApp.unregister()
            refresh()
        }

        if preferred {
            if !isEnabled || SMAppService.mainApp.status == .notFound {
                _ = setEnabled(true)
            }
        } else if isEnabled {
            _ = setEnabled(false)
        } else {
            refresh()
        }
    }

    func openSystemLoginItems() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Copy to ~/Applications, open that stable app, and quit this Xcode build so login
    /// items point at a path that survives DerivedData cleans.
    func migrateToStableApplicationsCopy() {
        Task { @MainActor in
            _ = await NotificationIconRegistrar.syncForNotificationCenter(force: true)
            // Drop the DerivedData login registration before switching.
            do {
                if SMAppService.mainApp.status != .notRegistered {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = error.localizedDescription
            }
            refresh()

            let dest = NotificationIconRegistrar.installedAppURL
            guard FileManager.default.fileExists(atPath: dest.path) else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
