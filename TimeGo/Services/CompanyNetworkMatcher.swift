import Foundation

enum CompanyNetworkMatcher {
    /// Matches when SSID is in the company list, or any local IPv4 matches a company prefix.
    /// Wi‑Fi and wired/IP are both valid auto clock-in signals.
    static func matches(
        ssid: String?,
        localIPv4s: [String],
        settings: AppSettings
    ) -> Bool {
        guard settings.hasNetworkRules else { return false }

        if let ssid = ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty {
            let targets = Set(settings.companySSIDs.map { $0.lowercased() })
            if targets.contains(ssid.lowercased()) {
                return true
            }
        }

        for ip in localIPv4s {
            for prefix in settings.companyIPPrefixes where !prefix.isEmpty {
                if ip.hasPrefix(prefix) {
                    return true
                }
            }
        }
        return false
    }
}

/// Rising-edge gate for "joined company network → start session".
struct NetworkClockInGate: Equatable {
    private(set) var wasOnCompanyNetwork = false

    mutating func noteSessionCleared() {
        wasOnCompanyNetwork = false
    }

    mutating func noteSettingsChanged() {
        wasOnCompanyNetwork = false
    }

    /// Returns true when auto clock-in should fire.
    mutating func shouldStart(onCompany: Bool, hasSessionToday: Bool, hasNetworkRules: Bool) -> Bool {
        defer { wasOnCompanyNetwork = onCompany }
        guard !hasSessionToday else { return false }
        guard hasNetworkRules else { return false }
        return onCompany && !wasOnCompanyNetwork
    }
}
