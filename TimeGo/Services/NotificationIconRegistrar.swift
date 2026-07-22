import AppKit
import CoreServices
import Foundation

/// Notification Center resolves the left-side app icon via Launch Services.
/// Apps launched only from Xcode DerivedData often show a gray square; registering a
/// copy under ~/Applications with the same bundle id fixes that lookup.
enum NotificationIconRegistrar {
    static var installedAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/TimeGo.app", isDirectory: true)
    }

    /// Whether the running binary lives under Xcode DerivedData (unstable for login items).
    static var isRunningFromDerivedData: Bool {
        Bundle.main.bundlePath.contains("/DerivedData/")
    }

    /// Safe to call from a background queue: copies the bundle only (no AppKit).
    @discardableResult
    static func installStableCopyIfNeeded(force: Bool = false) -> Bool {
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let dest = installedAppURL.resolvingSymlinksInPath()
        if source.path == dest.path { return true }

        do {
            let fm = FileManager.default
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let versionKey = "notificationIcon.installedToken"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let token = "\(short)-\(build)"
            let needsCopy = force
                || !fm.fileExists(atPath: dest.path)
                || UserDefaults.standard.string(forKey: versionKey) != token

            guard needsCopy else { return true }

            // Atomic replace — never leave ~/Applications without a TimeGo.app
            // (login items / Dock shortcuts may point here).
            let temp = dest.deletingLastPathComponent()
                .appendingPathComponent("TimeGo.installing.app", isDirectory: true)
            try? fm.removeItem(at: temp)
            try fm.copyItem(at: source, to: temp)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: dest)
            }
            try? fm.removeItem(at: temp)
            UserDefaults.standard.set(token, forKey: versionKey)
            return true
        } catch {
            return false
        }
    }

    /// Must run on the main thread (touches `NSApp` / `NSWorkspace`).
    @MainActor
    static func applyIconsAndRegisterLaunchServices() {
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let dest = installedAppURL.resolvingSymlinksInPath()
        let icon = loadAppIcon()
        if let icon {
            NSApp.applicationIconImage = icon
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            let installIcon = loadAppIcon(from: dest) ?? icon
            if let installIcon {
                NSWorkspace.shared.setIcon(installIcon, forFile: dest.path, options: [])
            }
            LSRegisterURL(dest as CFURL, true)
        }
        LSRegisterURL(source as CFURL, true)
    }

    /// Full sync: background-safe file copy, then main-thread icon / LS registration.
    @MainActor
    @discardableResult
    static func syncForNotificationCenter(force: Bool = false) async -> Bool {
        let ok = await Task.detached(priority: .utility) {
            installStableCopyIfNeeded(force: force)
        }.value
        applyIconsAndRegisterLaunchServices()
        return ok
    }

    private static func loadAppIcon(from appURL: URL? = nil) -> NSImage? {
        if let appURL, let bundle = Bundle(url: appURL),
           let icns = bundle.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icns) {
            return image
        }
        if let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icns) {
            return image
        }
        return nil
    }
}
