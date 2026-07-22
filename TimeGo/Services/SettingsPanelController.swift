import AppKit
import SwiftUI

/// Dedicated settings panel that survives system permission dialogs.
/// MenuBarExtra windows dismiss on focus loss; this panel does not (`hidesOnDeactivate = false`).
@MainActor
final class SettingsPanelController: NSObject, NSWindowDelegate {
    static let shared = SettingsPanelController()

    private var panel: NSPanel?
    private var store: SessionStore?
    private var network: NetworkMonitor?

    func configure(store: SessionStore, network: NetworkMonitor) {
        self.store = store
        self.network = network
    }

    func show() {
        guard let store, let network else { return }

        L10n.shared.apply(store.settings.language)

        if panel == nil {
            panel = makePanel(store: store, network: network)
        }
        updateTitle()

        // Accessory apps need a brief regular activation policy to show a real window.
        NSApp.setActivationPolicy(.regular)
        centerOnActiveScreen()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI may finalize size after first layout — re-center once more.
        DispatchQueue.main.async { [weak self] in
            self?.centerOnActiveScreen()
            self?.panel?.makeKeyAndOrderFront(nil)
        }
    }

    func updateTitle() {
        panel?.title = L10n.shared.t("settings.panelTitle")
    }

    func bringToFront() {
        guard let panel, panel.isVisible else { return }
        updateTitle()
        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-only mode after settings is dismissed.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Place the panel in the middle of the screen that contains the mouse
    /// (or the main screen), so it never opens behind the menu-bar popover.
    private func centerOnActiveScreen() {
        guard let panel else { return }

        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let screen = mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        // Keep fully inside the visible area (menu bar / Dock safe).
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    private func makePanel(store: SessionStore, network: NetworkMonitor) -> NSPanel {
        let root = SettingsView(onClose: { [weak self] in
            self?.close()
        })
        .environmentObject(store)
        .environmentObject(network)
        .environmentObject(L10n.shared)

        let hosting = NSHostingController(rootView: root)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.shared.t("settings.panelTitle")
        panel.contentViewController = hosting
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 380, height: 520)
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.94, alpha: 1)
        // Do not use frame autosave — a previous near-menu-bar position would
        // open settings behind the menu panel again.
        return panel
    }
}
