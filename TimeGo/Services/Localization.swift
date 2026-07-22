import Foundation
import Combine

enum AppLanguagePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    var menuTitleKey: String {
        switch self {
        case .system: return "lang.system"
        case .zhHans: return "lang.zhHans"
        case .english: return "lang.english"
        }
    }
}

final class L10n: ObservableObject {
    // UI singleton; always read/written on the main actor in practice.
    nonisolated(unsafe) static let shared = L10n()

    @Published private(set) var preference: AppLanguagePreference = .system
    /// Effective language code used for lookups: `zh-Hans` or `en`.
    @Published private(set) var code: String = L10n.resolve(.system)

    @MainActor
    func apply(_ preference: AppLanguagePreference) {
        self.preference = preference
        let next = Self.resolve(preference)
        if next != code {
            code = next
        } else {
            objectWillChange.send()
        }
    }

    func t(_ key: String) -> String {
        let table = code == "en" ? Self.en : Self.zh
        return table[key] ?? Self.zh[key] ?? key
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }

    var locale: Locale {
        code == "en" ? Locale(identifier: "en_US") : Locale(identifier: "zh_Hans")
    }

    static func resolve(_ preference: AppLanguagePreference) -> String {
        switch preference {
        case .zhHans: return "zh-Hans"
        case .english: return "en"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    // MARK: - Tables

    private static let zh: [String: String] = [
        "lang.system": "跟随系统",
        "lang.zhHans": "中文",
        "lang.english": "English",

        "common.settings": "设置",
        "common.close": "关闭",
        "common.save": "保存",
        "common.saved": "已保存",
        "common.hours": "小时",
        "common.minutes": "分钟",
        "common.none": "无",
        "common.hoursValue": "%@ 小时",
        "common.hoursInt": "%d 小时",
        "common.dash": "—",
        "common.exit": "退出",
        "common.start": "开始",

        "auth.notDetermined": "尚未请求",
        "auth.authorized": "已允许",
        "auth.denied": "已拒绝",
        "auth.provisional": "临时允许",
        "auth.restricted": "受限制",
        "auth.unknown": "未知",

        "login.enabled": "已开启",
        "login.needsApproval": "待系统批准",
        "login.notRegistered": "未开启",
        "login.notFound": "未找到应用",
        "login.unknown": "未知",
        "login.badge": "登录项 · %@",
        "login.approvalHint": "系统需要你在「登录项」里允许 TimeGo。",
        "login.openSettings": "打开系统登录项设置",
        "login.derivedDataHint": "当前从 Xcode 调试目录运行，开机启动可能失效。建议改用「应用程序」里的稳定版本。",
        "login.useStableApp": "改用「应用程序」中的 TimeGo",

        "notify.badge": "通知权限 · %@",
        "notify.allow": "允许通知",
        "notify.openSettings": "打开系统通知设置",
        "notify.deniedHint": "请在「系统设置 → 通知 → TimeGo」中打开允许通知。",
        "notify.title": "可以下班了",
        "notify.bodyLeave": "%@建议下班时间：%@",
        "notify.bodyReady": "%@可以准备下班了。",
        "notify.earlyTitle": "还有 %d 分钟下班",
        "notify.earlyBody": "建议下班时间：%@",
        "notify.dutyWithLunch": "今天已满 %@ 小时工时（含午休 %@ 小时）。",
        "notify.duty": "今天已满 %@ 小时工时。",

        "location.badge": "定位权限 · %@",
        "location.allow": "允许定位以读取 Wi‑Fi",
        "location.openSettings": "打开系统定位设置",

        "net.wifiOn": "Wi‑Fi 已连接",
        "net.wifiOff": "未连 Wi‑Fi",
        "net.unknownName": "未知名称",
        "net.noIP": "无本地 IP",
        "net.matched": "已匹配公司网",
        "net.unmatched": "未匹配公司网",
        "net.unknownSSID": "未知 SSID",
        "net.noIPShort": "无 IP",
        "net.matchedShort": "已匹配",
        "net.unmatchedShort": "未匹配",
        "net.currentLine": "%@ · %@ · %@",
        "net.summaryLine": "%@ · %@ · %@ · %@",
        "net.needLocationServices": "系统定位服务未开启，macOS 不允许读取 Wi‑Fi 名称",
        "net.needLocationAuth": "需要定位权限才能读取 Wi‑Fi 名称（IP 匹配仍可用）",
        "net.noInterface": "未找到 Wi‑Fi 接口",
        "net.ssidUnavailable": "已授权定位，但仍读不到 SSID（可能未连 Wi‑Fi，或系统仍在脱敏）",

        "menu.notStarted": "未上班",
        "menu.overtime": "加班 %@",
        "menu.remaining": "剩余 %@",
        "menu.helpIdle": "TimeGo：尚未开始计时",
        "menu.helpStarted": "上班 %@",
        "menu.pillDone": "可下班",
        "menu.pillTiming": "计时中",
        "menu.pillIdle": "待开始",
        "menu.heroToday": "今日",
        "menu.heroOvertime": "加班",
        "menu.heroRemaining": "剩余",
        "menu.heroIdleTitle": "还没开始计时",
        "menu.heroDoneTitle": "已经可以下班了",
        "menu.heroBusyTitle": "距离下班还有一会儿",
        "menu.heroIdleSubtitle": "到公司后会自动开始，也可以手动开始。",
        "menu.heroBusySubtitle": "今天 %@ 上班 · 含午休 %@",
        "menu.suggestLeave": "建议 %@ 下班",
        "menu.overview": "今日概览",
        "menu.startTime": "上班时间",
        "menu.editTimeHint": "点击编辑时间",
        "menu.onSite": "已在岗",
        "menu.lunch": "午休",
        "menu.overtimeDuration": "加班时长",
        "menu.remainingDuration": "剩余时长",
        "menu.correctTime": "校正时间",
        "menu.startWork": "开始上班",
        "menu.setNow": "设为现在",
        "menu.clearToday": "清除今天",
        "menu.startNow": "现在开始上班",
        "menu.orPickTime": "或指定时间",
        "menu.network": "网络",
        "menu.statusIdle": "弹性工时 · 公司 Wi‑Fi / IP 可自动开始",
        "menu.statusActive": "今日计时中 · %@",
        "menu.source.manual": "手动开始",
        "menu.source.unlock": "解锁自动开始",
        "menu.source.wake": "唤醒自动开始",
        "menu.source.network": "公司网络自动开始",
        "menu.openOA": "打开考勤",

        "settings.subtitle": "通用、语言、工时、OA、通知与公司网络",
        "settings.general": "通用",
        "settings.generalSubtitle": "登录后自动在菜单栏运行",
        "settings.launchAtLogin": "开机/登录时自动启动",
        "settings.language": "语言",
        "settings.languageSubtitle": "默认跟随电脑语言，也可手动切换",
        "settings.oa": "公司 OA",
        "settings.oaSubtitle": "快速打开考勤系统，查看历史记录",
        "settings.oaURL": "OA 网址",
        "settings.oaPlaceholder": "例如 https://oa.example.com/attendance",
        "settings.oaOpen": "在浏览器中打开",
        "settings.oaHint": "保存后，菜单栏会出现「打开考勤」按钮。可只填域名，会自动补全 https://。",
        "settings.hours": "工时",
        "settings.hoursSubtitle": "建议下班 = 上班 + 工时 + 午休",
        "settings.workHours": "目标工时",
        "settings.lunchHours": "午休时间",
        "settings.hoursHint": "默认 8 + 1 = 在岗 9 小时",
        "settings.notify": "通知",
        "settings.notifySubtitle": "满工时提醒与可选的提前提醒",
        "settings.notifyToggle": "满工时时发送通知",
        "settings.notifyEarlyToggle": "下班前提前提醒",
        "settings.notifyEarlyMinutes": "提前多久",
        "settings.network": "公司网络",
        "settings.networkSubtitle": "用于自动识别上班",
        "settings.requireCompanyNet": "解锁/唤醒仅在公司网下自动上班",
        "settings.networkHint": "多个 Wi‑Fi 或多个 IP 前缀时，请用英文逗号分隔，例如：Office,Office-5G 或 10.8.,192.168.10。连上匹配的公司 Wi‑Fi 或公司 IP 都会自动开始上班。",
        "settings.ssid": "Wi‑Fi 名称（SSID）",
        "settings.ssidPlaceholder": "例如 Office, Office-5G",
        "settings.fillSSID": "填入当前 Wi‑Fi",
        "settings.ip": "IP 前缀",
        "settings.ipPlaceholder": "例如 10.8.,192.168.10.",
        "settings.fillIP": "填入当前 IP 前缀",
        "settings.networkFooter": "连上匹配的公司 Wi‑Fi/IP 会自动开始；配置公司网后，在家解锁默认不会误触发。",
        "settings.panelTitle": "TimeGo 设置",
    ]

    private static let en: [String: String] = [
        "lang.system": "System",
        "lang.zhHans": "中文",
        "lang.english": "English",

        "common.settings": "Settings",
        "common.close": "Close",
        "common.save": "Save",
        "common.saved": "Saved",
        "common.hours": "hours",
        "common.minutes": "min",
        "common.none": "None",
        "common.hoursValue": "%@ h",
        "common.hoursInt": "%d h",
        "common.dash": "—",
        "common.exit": "Quit",
        "common.start": "Start",

        "auth.notDetermined": "Not requested",
        "auth.authorized": "Allowed",
        "auth.denied": "Denied",
        "auth.provisional": "Provisional",
        "auth.restricted": "Restricted",
        "auth.unknown": "Unknown",

        "login.enabled": "On",
        "login.needsApproval": "Needs approval",
        "login.notRegistered": "Off",
        "login.notFound": "App not found",
        "login.unknown": "Unknown",
        "login.badge": "Login item · %@",
        "login.approvalHint": "Allow TimeGo in System Settings → Login Items.",
        "login.openSettings": "Open Login Items Settings",
        "login.derivedDataHint": "You’re running from an Xcode build folder; launch at login may break after clean builds. Prefer the copy in Applications.",
        "login.useStableApp": "Switch to Applications TimeGo",

        "notify.badge": "Notifications · %@",
        "notify.allow": "Allow Notifications",
        "notify.openSettings": "Open Notification Settings",
        "notify.deniedHint": "Enable notifications in System Settings → Notifications → TimeGo.",
        "notify.title": "Time to leave",
        "notify.bodyLeave": "%@Suggested leave time: %@",
        "notify.bodyReady": "%@You can wrap up for the day.",
        "notify.earlyTitle": "%d minutes left",
        "notify.earlyBody": "Suggested leave time: %@",
        "notify.dutyWithLunch": "You've completed %@ hours of work (including %@ hours lunch).",
        "notify.duty": "You've completed %@ hours of work.",

        "location.badge": "Location · %@",
        "location.allow": "Allow Location for Wi‑Fi name",
        "location.openSettings": "Open Location Settings",

        "net.wifiOn": "Wi‑Fi connected",
        "net.wifiOff": "Wi‑Fi off",
        "net.unknownName": "Unknown name",
        "net.noIP": "No local IP",
        "net.matched": "Company network matched",
        "net.unmatched": "Not matched",
        "net.unknownSSID": "Unknown SSID",
        "net.noIPShort": "No IP",
        "net.matchedShort": "Matched",
        "net.unmatchedShort": "Not matched",
        "net.currentLine": "%@ · %@ · %@",
        "net.summaryLine": "%@ · %@ · %@ · %@",
        "net.needLocationServices": "Location Services are off; macOS won't allow reading the Wi‑Fi name",
        "net.needLocationAuth": "Location permission is required to read the Wi‑Fi name (IP matching still works)",
        "net.noInterface": "No Wi‑Fi interface found",
        "net.ssidUnavailable": "Location allowed, but SSID is still unavailable (Wi‑Fi may be off or redacted)",

        "menu.notStarted": "Off",
        "menu.overtime": "OT %@",
        "menu.remaining": "Left %@",
        "menu.helpIdle": "TimeGo: not started",
        "menu.helpStarted": "In %@",
        "menu.pillDone": "Done",
        "menu.pillTiming": "Timing",
        "menu.pillIdle": "Idle",
        "menu.heroToday": "Today",
        "menu.heroOvertime": "Overtime",
        "menu.heroRemaining": "Left",
        "menu.heroIdleTitle": "Not started yet",
        "menu.heroDoneTitle": "You can leave now",
        "menu.heroBusyTitle": "A little more until leave time",
        "menu.heroIdleSubtitle": "Starts automatically at the office, or start manually.",
        "menu.heroBusySubtitle": "Started %@ · lunch %@",
        "menu.suggestLeave": "Leave at %@",
        "menu.overview": "Today",
        "menu.startTime": "Start time",
        "menu.editTimeHint": "Click to edit time",
        "menu.onSite": "On site",
        "menu.lunch": "Lunch",
        "menu.overtimeDuration": "Overtime",
        "menu.remainingDuration": "Remaining",
        "menu.correctTime": "Adjust time",
        "menu.startWork": "Start work",
        "menu.setNow": "Set to now",
        "menu.clearToday": "Clear today",
        "menu.startNow": "Start now",
        "menu.orPickTime": "Or pick a time",
        "menu.network": "Network",
        "menu.statusIdle": "Flex time · company Wi‑Fi / IP can auto-start",
        "menu.statusActive": "Timing today · %@",
        "menu.source.manual": "Manual start",
        "menu.source.unlock": "Started on unlock",
        "menu.source.wake": "Started on wake",
        "menu.source.network": "Started on company network",
        "menu.openOA": "Open OA",

        "settings.subtitle": "General, language, hours, OA, notifications & network",
        "settings.general": "General",
        "settings.generalSubtitle": "Keep TimeGo in the menu bar after login",
        "settings.launchAtLogin": "Launch at login",
        "settings.language": "Language",
        "settings.languageSubtitle": "Follows your Mac by default; you can override it",
        "settings.oa": "Company OA",
        "settings.oaSubtitle": "Quickly open attendance history in your browser",
        "settings.oaURL": "OA URL",
        "settings.oaPlaceholder": "e.g. https://oa.example.com/attendance",
        "settings.oaOpen": "Open in browser",
        "settings.oaHint": "After saving, an “Open OA” button appears in the menu bar. A bare domain gets https:// added automatically.",
        "settings.hours": "Hours",
        "settings.hoursSubtitle": "Leave time = start + work + lunch",
        "settings.workHours": "Work hours",
        "settings.lunchHours": "Lunch break",
        "settings.hoursHint": "Default 8 + 1 = 9 hours on site",
        "settings.notify": "Notifications",
        "settings.notifySubtitle": "Leave-time alert and optional early reminder",
        "settings.notifyToggle": "Notify when work hours are done",
        "settings.notifyEarlyToggle": "Remind me before leave time",
        "settings.notifyEarlyMinutes": "Minutes early",
        "settings.network": "Company network",
        "settings.networkSubtitle": "Used to detect arrival at work",
        "settings.requireCompanyNet": "Unlock/wake auto-start only on company network",
        "settings.networkHint": "Separate multiple Wi‑Fi names or IP prefixes with commas, e.g. Office,Office-5G or 10.8.,192.168.10. Matching company Wi‑Fi or IP will auto-start work.",
        "settings.ssid": "Wi‑Fi name (SSID)",
        "settings.ssidPlaceholder": "e.g. Office, Office-5G",
        "settings.fillSSID": "Use current Wi‑Fi",
        "settings.ip": "IP prefix",
        "settings.ipPlaceholder": "e.g. 10.8.,192.168.10.",
        "settings.fillIP": "Use current IP prefix",
        "settings.networkFooter": "Matching company Wi‑Fi/IP auto-starts work; with network rules set, unlocking at home won't false-trigger.",
        "settings.panelTitle": "TimeGo Settings",
    ]
}
