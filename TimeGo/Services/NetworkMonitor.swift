import Foundation
import Network
import CoreWLAN
import Combine

struct NetworkSnapshot: Equatable {
    var ssid: String?
    var localIPv4s: [String]
    var wifiActive: Bool
    var ssidUnavailableReason: String?
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var snapshot = NetworkSnapshot(
        ssid: nil,
        localIPv4s: [],
        wifiActive: false,
        ssidUnavailableReason: nil
    )

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.timego.network")
    private var latestPath: NWPath?
    private var refreshTimer: Timer?

    func start() {
        LocationAuthService.shared.onAuthorized = { [weak self] in
            self?.refreshNow()
        }
        LocationAuthService.shared.refresh()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.latestPath = path
                self?.refresh(path: path)
            }
        }
        monitor.start(queue: queue)
        latestPath = monitor.currentPath
        refresh(path: monitor.currentPath)

        // Path updates cover most changes; rare polling catches SSID/IP drift only.
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refreshNow() {
        refresh(path: latestPath ?? monitor.currentPath)
    }

    func matchesCompanyNetwork(settings: AppSettings) -> Bool {
        CompanyNetworkMatcher.matches(
            ssid: snapshot.ssid,
            localIPv4s: snapshot.localIPv4s,
            settings: settings
        )
    }

    private func refresh(path: NWPath) {
        let ssidResult = currentSSID()
        let wifiActive = path.status == .satisfied && path.usesInterfaceType(.wifi)
        let next = NetworkSnapshot(
            ssid: ssidResult.ssid,
            localIPv4s: localIPv4Addresses(),
            wifiActive: wifiActive,
            ssidUnavailableReason: ssidResult.reason
        )
        guard next != snapshot else { return }
        snapshot = next
    }

    private func currentSSID() -> (ssid: String?, reason: String?) {
        let l10n = L10n.shared
        let location = LocationAuthService.shared
        if !location.systemLocationEnabled {
            return (nil, l10n.t("net.needLocationServices"))
        }
        if !location.authState.isGranted {
            return (nil, l10n.t("net.needLocationAuth"))
        }

        guard let iface = CWWiFiClient.shared().interface() else {
            return (nil, l10n.t("net.noInterface"))
        }

        if let ssid = iface.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty {
            return (ssid, nil)
        }

        return (nil, l10n.t("net.ssidUnavailable"))
    }

    private func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name == "wlan0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let ip = String(cString: hostname)
            if ip.hasPrefix("127.") { continue }
            addresses.append(ip)
        }
        return addresses
    }
}
