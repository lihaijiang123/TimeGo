import AppKit
import CoreLocation
import Foundation
import Combine

enum LocationAuthState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown

    var title: String {
        let l10n = L10n.shared
        switch self {
        case .notDetermined: return l10n.t("auth.notDetermined")
        case .authorized: return l10n.t("auth.authorized")
        case .denied: return l10n.t("auth.denied")
        case .restricted: return l10n.t("auth.restricted")
        case .unknown: return l10n.t("auth.unknown")
        }
    }

    var isGranted: Bool {
        self == .authorized
    }
}

/// CoreWLAN SSID requires Location Services on modern macOS.
@MainActor
final class LocationAuthService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationAuthService()

    @Published private(set) var authState: LocationAuthState = .unknown
    @Published private(set) var systemLocationEnabled: Bool = true

    var onAuthorized: (() -> Void)?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    func refresh() {
        systemLocationEnabled = CLLocationManager.locationServicesEnabled()
        authState = Self.map(manager.authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        refresh()

        if !systemLocationEnabled {
            openSystemLocationSettings()
            return false
        }

        if authState.isGranted {
            return true
        }

        if authState == .denied || authState == .restricted {
            openSystemLocationSettings()
            return false
        }

        NSApp.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { continuation in
            // Only one outstanding request at a time.
            self.continuation?.resume(returning: false)
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func openSystemLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refresh()
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(returning: self.authState.isGranted)
            }
            if self.authState.isGranted {
                self.onAuthorized?()
            }
            // Permission sheet steals focus; bring settings back so the user isn't lost.
            SettingsPanelController.shared.bringToFront()
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorized: return .authorized
        @unknown default: return .unknown
        }
    }
}
