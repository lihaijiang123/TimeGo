import Foundation

struct AppSettings: Codable, Equatable {
    /// Target work duration in hours (default 8).
    var workHours: Double = 8
    /// Lunch break duration in hours (default 1). Added on top of work hours for leave time.
    var lunchHours: Double = 1
    /// Company Wi-Fi SSIDs used for auto clock-in.
    var companySSIDs: [String] = []
    /// Local IP prefixes, e.g. "10.8.", "192.168.10."
    var companyIPPrefixes: [String] = []
    /// Notify when the target work duration is reached.
    var notifyWhenDone: Bool = true
    /// Notify a few minutes before leave time.
    var notifyEarlyReminder: Bool = true
    /// Minutes before leave time for the early reminder (default 5).
    var earlyReminderMinutes: Int = 5
    /// If true and network rules are configured, unlock/wake only clocks in while on company network.
    var requireCompanyNetworkForWake: Bool = true
    /// Launch TimeGo automatically when you log in to macOS.
    var launchAtLogin: Bool = true
    /// UI language. Defaults to following the Mac system language.
    var language: AppLanguagePreference = .system
    /// Company OA / attendance URL for quick open from the menu bar.
    var companyOAURL: String = "https://i.mdpi.cn/team/attendance"

    var workDuration: TimeInterval {
        workHours * 3600
    }

    var lunchDuration: TimeInterval {
        max(0, lunchHours) * 3600
    }

    /// Wall-clock time from start until you can leave: work + lunch.
    var requiredOnSiteDuration: TimeInterval {
        workDuration + lunchDuration
    }

    var hasNetworkRules: Bool {
        !companySSIDs.isEmpty || !companyIPPrefixes.isEmpty
    }

    /// Early reminder minutes clamped to a sensible range.
    var clampedEarlyReminderMinutes: Int {
        min(120, max(1, earlyReminderMinutes))
    }

    var notificationsEnabled: Bool {
        notifyWhenDone || notifyEarlyReminder
    }

    /// Normalized browser URL when `companyOAURL` is non-empty.
    var resolvedCompanyOAURL: URL? {
        Self.makeURL(from: companyOAURL)
    }

    static let storageKey = "app.settings"

    init(
        workHours: Double = 8,
        lunchHours: Double = 1,
        companySSIDs: [String] = [],
        companyIPPrefixes: [String] = [],
        notifyWhenDone: Bool = true,
        notifyEarlyReminder: Bool = true,
        earlyReminderMinutes: Int = 5,
        requireCompanyNetworkForWake: Bool = true,
        launchAtLogin: Bool = true,
        language: AppLanguagePreference = .system,
        companyOAURL: String = "https://i.mdpi.cn/team/attendance"
    ) {
        self.workHours = workHours
        self.lunchHours = lunchHours
        self.companySSIDs = companySSIDs
        self.companyIPPrefixes = companyIPPrefixes
        self.notifyWhenDone = notifyWhenDone
        self.notifyEarlyReminder = notifyEarlyReminder
        self.earlyReminderMinutes = earlyReminderMinutes
        self.requireCompanyNetworkForWake = requireCompanyNetworkForWake
        self.launchAtLogin = launchAtLogin
        self.language = language
        self.companyOAURL = companyOAURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workHours = try c.decodeIfPresent(Double.self, forKey: .workHours) ?? 8
        lunchHours = try c.decodeIfPresent(Double.self, forKey: .lunchHours) ?? 1
        companySSIDs = try c.decodeIfPresent([String].self, forKey: .companySSIDs) ?? []
        companyIPPrefixes = try c.decodeIfPresent([String].self, forKey: .companyIPPrefixes) ?? []
        notifyWhenDone = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenDone) ?? true
        notifyEarlyReminder = try c.decodeIfPresent(Bool.self, forKey: .notifyEarlyReminder) ?? true
        earlyReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .earlyReminderMinutes) ?? 5
        requireCompanyNetworkForWake = try c.decodeIfPresent(Bool.self, forKey: .requireCompanyNetworkForWake) ?? true
        // Existing installs: turn on by default when the key is missing.
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        language = try c.decodeIfPresent(AppLanguagePreference.self, forKey: .language) ?? .system
        let decodedOA = try c.decodeIfPresent(String.self, forKey: .companyOAURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedOA, !decodedOA.isEmpty {
            companyOAURL = decodedOA
        } else {
            companyOAURL = "https://i.mdpi.cn/team/attendance"
        }
    }

    /// Accepts full URLs or host/path; adds `https://` when the scheme is missing.
    static func makeURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}

enum ClockInSource: String, Codable {
    case manual
    case unlock
    case wake
    case network
}

struct WorkSession: Codable, Equatable {
    var dayKey: String
    var startTime: Date
    var source: ClockInSource
    var notifiedAtTarget: Bool = false
    var notifiedEarly: Bool = false

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let day = comps.day ?? 0
        let mm = month < 10 ? "0\(month)" : "\(month)"
        let dd = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(mm)-\(dd)"
    }

    init(
        dayKey: String,
        startTime: Date,
        source: ClockInSource,
        notifiedAtTarget: Bool = false,
        notifiedEarly: Bool = false
    ) {
        self.dayKey = dayKey
        self.startTime = startTime
        self.source = source
        self.notifiedAtTarget = notifiedAtTarget
        self.notifiedEarly = notifiedEarly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        startTime = try c.decode(Date.self, forKey: .startTime)
        source = try c.decode(ClockInSource.self, forKey: .source)
        notifiedAtTarget = try c.decodeIfPresent(Bool.self, forKey: .notifiedAtTarget) ?? false
        notifiedEarly = try c.decodeIfPresent(Bool.self, forKey: .notifiedEarly) ?? false
    }
}
