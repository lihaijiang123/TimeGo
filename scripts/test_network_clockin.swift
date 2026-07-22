#!/usr/bin/env swift
import Foundation

struct AppSettings {
    var companySSIDs: [String] = []
    var companyIPPrefixes: [String] = []
    var hasNetworkRules: Bool { !companySSIDs.isEmpty || !companyIPPrefixes.isEmpty }
}

enum CompanyNetworkMatcher {
    static func matches(ssid: String?, localIPv4s: [String], settings: AppSettings) -> Bool {
        guard settings.hasNetworkRules else { return false }
        if let ssid = ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty {
            let targets = Set(settings.companySSIDs.map { $0.lowercased() })
            if targets.contains(ssid.lowercased()) { return true }
        }
        for ip in localIPv4s {
            for prefix in settings.companyIPPrefixes where !prefix.isEmpty {
                if ip.hasPrefix(prefix) { return true }
            }
        }
        return false
    }
}

var failed = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("PASS  \(msg)") } else { failed += 1; print("FAIL  \(msg)") }
}

let ipOnly = AppSettings(companySSIDs: [], companyIPPrefixes: ["192.168.124."])
expect(
    CompanyNetworkMatcher.matches(ssid: nil, localIPv4s: ["192.168.124.6"], settings: ipOnly),
    "IP prefix matches without Wi‑Fi SSID"
)
expect(
    !CompanyNetworkMatcher.matches(ssid: nil, localIPv4s: ["10.0.0.1"], settings: ipOnly),
    "wrong IP does not match"
)

let ssidOnly = AppSettings(companySSIDs: ["连我"], companyIPPrefixes: [])
expect(
    CompanyNetworkMatcher.matches(ssid: "连我", localIPv4s: [], settings: ssidOnly),
    "SSID match works"
)
expect(
    CompanyNetworkMatcher.matches(ssid: "连我", localIPv4s: ["10.0.0.1"], settings: AppSettings(companySSIDs: ["连我"], companyIPPrefixes: ["192.168.5."])),
    "SSID or IP: SSID hit is enough"
)
expect(
    CompanyNetworkMatcher.matches(ssid: nil, localIPv4s: ["192.168.5.10"], settings: AppSettings(companySSIDs: ["连我"], companyIPPrefixes: ["192.168.5."])),
    "SSID or IP: IP hit is enough"
)

print(failed == 0 ? "\nAll tests passed." : "\n\(failed) test(s) failed.")
exit(failed == 0 ? 0 : 1)
