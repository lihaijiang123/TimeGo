import Foundation
import Combine

@MainActor
final class AutoClockInService {
    private let store: SessionStore
    private let network: NetworkMonitor
    private let wake: WakeMonitor
    private var cancellables = Set<AnyCancellable>()
    private var gate = NetworkClockInGate()
    private var notifyCheckTimer: Timer?
    private var resyncTask: Task<Void, Never>?
    /// Blocks session-publisher resync while markNotified* is writing flags.
    private var isMutatingNotifyFlags = false

    init(store: SessionStore, network: NetworkMonitor, wake: WakeMonitor) {
        self.store = store
        self.network = network
        self.wake = wake
    }

    func start() {
        network.start()
        wake.onEvent = { [weak self] event in
            self?.handlePresence(event)
            self?.checkImmediateNotification()
            self?.scheduleNotifyCheckTimer()
        }
        wake.start()

        network.$snapshot
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.evaluateNetworkClockIn()
            }
            .store(in: &cancellables)

        store.$settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.gate.noteSettingsChanged()
                self?.evaluateNetworkClockIn()
                self?.scheduleResyncNotifications()
            }
            .store(in: &cancellables)

        store.$session
            .dropFirst()
            .sink { [weak self] session in
                guard let self else { return }
                if session == nil {
                    self.gate.noteSessionCleared()
                    self.evaluateNetworkClockIn()
                }
                if self.isMutatingNotifyFlags {
                    self.scheduleNotifyCheckTimer()
                    return
                }
                self.scheduleResyncNotifications()
            }
            .store(in: &cancellables)

        NotificationService.shared.onWorkNotificationDelivered = { [weak self] id in
            self?.handleSystemDelivered(id)
        }

        evaluateNetworkClockIn()
        scheduleResyncNotifications()
    }

    private func handleSystemDelivered(_ identifier: String) {
        isMutatingNotifyFlags = true
        defer { isMutatingNotifyFlags = false }

        switch identifier {
        case NotificationService.earlyID:
            if store.session?.notifiedEarly != true {
                store.markNotifiedEarly()
            }
        case NotificationService.targetID:
            if store.session?.notifiedAtTarget != true {
                store.markNotifiedAtTarget()
            }
        default:
            break
        }
        scheduleNotifyCheckTimer()
    }

    private func handlePresence(_ event: PresenceEvent) {
        network.refreshNow()

        guard !store.hasSessionToday else { return }

        let settings = store.settings
        let onCompany = network.matchesCompanyNetwork(settings: settings)

        if settings.hasNetworkRules && settings.requireCompanyNetworkForWake {
            guard onCompany else { return }
        }

        let source: ClockInSource = (event == .wake) ? .wake : .unlock
        store.start(source: source)
    }

    private func evaluateNetworkClockIn() {
        let onCompany = network.matchesCompanyNetwork(settings: store.settings)
        let shouldStart = gate.shouldStart(
            onCompany: onCompany,
            hasSessionToday: store.hasSessionToday,
            hasNetworkRules: store.settings.hasNetworkRules
        )
        if shouldStart {
            store.start(source: .network)
        }
    }

    private func scheduleResyncNotifications() {
        resyncTask?.cancel()
        resyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            self.performResyncNotifications()
        }
    }

    private func performResyncNotifications() {
        let settings = store.settings
        let notifications = NotificationService.shared

        guard settings.notificationsEnabled,
              let leave = store.targetLeaveTime,
              store.hasSessionToday else {
            notifications.cancelPending()
            notifyCheckTimer?.invalidate()
            notifyCheckTimer = nil
            return
        }

        let wantTarget = settings.notifyWhenDone && store.session?.notifiedAtTarget != true
        let wantEarly = settings.notifyEarlyReminder
            && store.session?.notifiedEarly != true
            && store.session?.notifiedAtTarget != true

        notifications.cancelPending()

        if wantTarget {
            notifications.scheduleTargetNotification(
                at: leave,
                workHours: settings.workHours,
                lunchHours: settings.lunchHours
            )
        }
        if wantEarly {
            let minutes = settings.clampedEarlyReminderMinutes
            let earlyAt = leave.addingTimeInterval(TimeInterval(-minutes * 60))
            notifications.scheduleEarlyNotification(
                at: earlyAt,
                leaveTime: leave,
                minutes: minutes
            )
        }

        checkImmediateNotification()
        scheduleNotifyCheckTimer()
    }

    private func scheduleNotifyCheckTimer() {
        notifyCheckTimer?.invalidate()
        notifyCheckTimer = nil

        let settings = store.settings
        guard settings.notificationsEnabled, store.hasSessionToday,
              let leave = store.targetLeaveTime else { return }

        var fireAt: Date?
        if settings.notifyEarlyReminder,
           store.session?.notifiedEarly != true,
           store.session?.notifiedAtTarget != true {
            let earlyAt = leave.addingTimeInterval(
                TimeInterval(-settings.clampedEarlyReminderMinutes * 60)
            )
            if earlyAt > .now {
                fireAt = earlyAt
            }
        }
        if settings.notifyWhenDone, store.session?.notifiedAtTarget != true, leave > .now {
            if let existing = fireAt {
                fireAt = min(existing, leave)
            } else {
                fireAt = leave
            }
        }

        guard let fireAt else { return }
        let delay = max(0.2, fireAt.timeIntervalSinceNow + 0.05)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkImmediateNotification()
                self?.scheduleNotifyCheckTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        notifyCheckTimer = timer
    }

    private func checkImmediateNotification() {
        let settings = store.settings
        guard settings.notificationsEnabled else { return }
        guard store.hasSessionToday else { return }
        guard let leave = store.targetLeaveTime else { return }

        let notifications = NotificationService.shared

        if settings.notifyEarlyReminder,
           store.isInEarlyReminderWindow,
           store.session?.notifiedEarly != true {
            isMutatingNotifyFlags = true
            store.markNotifiedEarly()
            isMutatingNotifyFlags = false
            // Immediate banner replaces any pending early request.
            notifications.notifyEarlyReminder(
                leaveTime: leave,
                minutes: settings.clampedEarlyReminderMinutes
            )
        }

        guard settings.notifyWhenDone else { return }
        guard store.isPastTarget else { return }
        guard store.session?.notifiedAtTarget != true else { return }

        isMutatingNotifyFlags = true
        store.markNotifiedAtTarget()
        isMutatingNotifyFlags = false
        notifications.notifyTargetReached(
            leaveTime: leave,
            workHours: settings.workHours,
            lunchHours: settings.lunchHours
        )
    }
}
