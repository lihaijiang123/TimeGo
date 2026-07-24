import Foundation
import Combine

@MainActor
final class AutoClockInService {
    private let store: SessionStore
    private let network: NetworkMonitor
    private let wake: WakeMonitor
    private var cancellables = Set<AnyCancellable>()
    private var gate = NetworkClockInGate()
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
            self?.store.ensureDayBoundaryTimer()
            self?.handlePresence(event)
            // After sleep, scheduled notifications may have been missed.
            self?.checkMissedNotifications()
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
        checkMissedNotifications()
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

    /// Schedule system notifications only — do not also post immediate ones at the
    /// same fire time (that was causing duplicate banners).
    private func performResyncNotifications() {
        let settings = store.settings
        let notifications = NotificationService.shared

        guard settings.notificationsEnabled,
              let leave = store.targetLeaveTime,
              store.hasSessionToday else {
            notifications.cancelPending()
            return
        }

        let wantTarget = settings.notifyWhenDone && store.session?.notifiedAtTarget != true
        let wantEarly = settings.notifyEarlyReminder
            && store.session?.notifiedEarly != true
            && store.session?.notifiedAtTarget != true

        notifications.cancelPending()

        if wantTarget, leave > .now {
            notifications.scheduleTargetNotification(
                at: leave,
                workHours: settings.workHours,
                lunchHours: settings.lunchHours
            )
        }
        if wantEarly {
            let minutes = settings.clampedEarlyReminderMinutes
            let earlyAt = leave.addingTimeInterval(TimeInterval(-minutes * 60))
            if earlyAt > .now {
                notifications.scheduleEarlyNotification(
                    at: earlyAt,
                    leaveTime: leave,
                    minutes: minutes
                )
            }
        }

        // Catch up only when fire time is clearly in the past (e.g. after sleep).
        checkMissedNotifications()
    }

    /// Posts at most one immediate banner when a scheduled notification was missed
    /// (app asleep / terminated). Grace avoids racing the calendar trigger.
    private func checkMissedNotifications() {
        let settings = store.settings
        guard settings.notificationsEnabled else { return }
        guard store.hasSessionToday else { return }
        guard let leave = store.targetLeaveTime else { return }

        let notifications = NotificationService.shared
        let grace: TimeInterval = 3
        let now = Date()

        if settings.notifyEarlyReminder,
           store.session?.notifiedEarly != true,
           store.session?.notifiedAtTarget != true {
            let minutes = settings.clampedEarlyReminderMinutes
            let earlyAt = leave.addingTimeInterval(TimeInterval(-minutes * 60))
            if now >= earlyAt.addingTimeInterval(grace) {
                isMutatingNotifyFlags = true
                store.markNotifiedEarly()
                isMutatingNotifyFlags = false
                notifications.cancelEarlyPending()
                notifications.notifyEarlyReminder(leaveTime: leave, minutes: minutes)
            }
        }

        if settings.notifyWhenDone,
           store.session?.notifiedAtTarget != true,
           now >= leave.addingTimeInterval(grace) {
            isMutatingNotifyFlags = true
            store.markNotifiedAtTarget()
            isMutatingNotifyFlags = false
            notifications.cancelPending()
            notifications.notifyTargetReached(
                leaveTime: leave,
                workHours: settings.workHours,
                lunchHours: settings.lunchHours
            )
        }
    }
}
