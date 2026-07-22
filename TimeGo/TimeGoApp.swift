import SwiftUI
import AppKit
import UserNotifications

@main
struct TimeGoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: SessionStore
    @StateObject private var network: NetworkMonitor
    @StateObject private var runtime: AppRuntime

    init() {
        let store = SessionStore()
        let network = NetworkMonitor()
        let wake = WakeMonitor()
        _store = StateObject(wrappedValue: store)
        _network = StateObject(wrappedValue: network)
        _runtime = StateObject(wrappedValue: AppRuntime(store: store, network: network, wake: wake))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(network)
                .environmentObject(L10n.shared)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
                .environmentObject(L10n.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppRuntime: ObservableObject {
    private let store: SessionStore
    private let network: NetworkMonitor
    private let wake: WakeMonitor
    private var autoService: AutoClockInService?

    init(store: SessionStore, network: NetworkMonitor, wake: WakeMonitor) {
        self.store = store
        self.network = network
        self.wake = wake
        Task { await self.start() }
    }

    private func start() async {
        guard autoService == nil else { return }
        SettingsPanelController.shared.configure(store: store, network: network)
        L10n.shared.apply(store.settings.language)

        // Install a stable ~/Applications copy first, then repair login items that may
        // still point at a deleted Xcode DerivedData path (app appears not to launch).
        _ = await NotificationIconRegistrar.syncForNotificationCenter()
        LaunchAtLoginService.shared.sync(withPreferred: store.settings.launchAtLogin)
        MenuBarClock.shared.start()

        // Refresh status only; permission prompts are requested from the settings window.
        await NotificationService.shared.refreshAuthorizationStatus()
        let service = AutoClockInService(store: store, network: network, wake: wake)
        autoService = service
        service.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Clicking a banner often launches ~/Applications/TimeGo.app even when another
        // TimeGo (e.g. Xcode build) is already running — that adds a second menu-bar icon.
        // Bail out before SwiftUI installs another MenuBarExtra.
        if Self.activateExistingInstanceIfNeeded() {
            _exit(0)
        }

        // Hide Dock without LSUIElement in Info.plist, so Launch Services still
        // registers a real app icon for Notification Center (left-side logo).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // nonisolated: UNNotification* types are not Sendable; hop to MainActor with a String id.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        await Self.noteDelivered(identifier)
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await Self.noteDelivered(identifier)
    }

    @MainActor
    private static func noteDelivered(_ identifier: String) {
        NotificationService.shared.noteWorkNotificationDelivered(identifier: identifier)
    }

    /// - Returns: `true` when another TimeGo process already owns this bundle id.
    private static func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return false }
        existing.activate()
        return true
    }
}
