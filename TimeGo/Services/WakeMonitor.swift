import AppKit

enum PresenceEvent: Sendable {
    case wake
    case unlock
}

@MainActor
final class WakeMonitor {
    private var observers: [NSObjectProtocol] = []
    var onEvent: ((PresenceEvent) -> Void)?

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onEvent?(.wake)
                }
            }
        )

        observers.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onEvent?(.unlock)
                }
            }
        )
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
    }
}
