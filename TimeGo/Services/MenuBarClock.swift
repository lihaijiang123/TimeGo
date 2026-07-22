import Foundation
import Combine

/// Minute-level clock for the menu-bar title (`DurationFormat.short`).
@MainActor
final class MenuBarClock: ObservableObject {
    static let shared = MenuBarClock()

    @Published private(set) var now = Date()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        fireAndReschedule()
    }

    private func fireAndReschedule() {
        now = Date()
        timer?.invalidate()

        let cal = Calendar.current
        let nextMinute = cal.nextDate(
            after: Date(),
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60)
        let delay = min(60, max(2, nextMinute.timeIntervalSinceNow + 0.15))

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fireAndReschedule()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// 1 Hz clock while the menu panel is open.
@MainActor
final class PanelLiveClock: ObservableObject {
    static let shared = PanelLiveClock()

    @Published private(set) var now = Date()
    private var timer: Timer?
    private var retainCount = 0

    func retain() {
        retainCount += 1
        guard timer == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func release() {
        retainCount = max(0, retainCount - 1)
        guard retainCount == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}
