import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var notifications = NotificationService.shared
    @ObservedObject private var location = LocationAuthService.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared

    var onClose: (() -> Void)?

    @State private var workHours: Double = 8
    @State private var lunchHours: Double = 1
    @State private var ssidText: String = ""
    @State private var ipText: String = ""
    @State private var notifyWhenDone = true
    @State private var notifyEarlyReminder = true
    @State private var earlyReminderMinutes: Int = 5
    @State private var requireCompanyNetworkForWake = true
    @State private var launchAtLoginEnabled = true
    @State private var language: AppLanguagePreference = .system
    @State private var oaURLText: String = ""
    @State private var savedFlash = false
    @State private var isRequestingNotify = false
    @State private var isRequestingLocation = false

    var body: some View {
        ZStack {
            TimeGoTheme.panelBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                SoftDivider()
                    .padding(.horizontal, 22)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        generalSection
                        languageSection
                        oaSection
                        hoursSection
                        notifySection
                        networkSection
                    }
                    .padding(22)
                }

                SoftDivider()

                footer
                    .padding(16)
            }
        }
        .frame(width: 400, height: 720)
        .id(l10n.code)
        .onAppear {
            load()
            location.refresh()
            network.refreshNow()
            launchAtLogin.refresh()
            Task { await notifications.refreshAuthorizationStatus() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("common.settings"))
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(TimeGoTheme.ink)
                Text(l10n.t("settings.subtitle"))
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(TimeGoTheme.secondary)
            }
            Spacer()
            if savedFlash {
                Text(l10n.t("common.saved"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(TimeGoTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(TimeGoTheme.accentSoft, in: Capsule())
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var generalSection: some View {
        settingsBlock(title: l10n.t("settings.general"), subtitle: l10n.t("settings.generalSubtitle")) {
            Toggle(isOn: $launchAtLoginEnabled) {
                Text(l10n.t("settings.launchAtLogin"))
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(TimeGoTheme.accent)
            .onChange(of: launchAtLoginEnabled) { _, enabled in
                applyLaunchAtLogin(enabled)
            }

            PermissionBadge(
                title: l10n.t("login.badge", launchAtLogin.statusTitle),
                color: launchAtLogin.isEnabled
                    ? TimeGoTheme.accent
                    : (launchAtLogin.needsApproval ? TimeGoTheme.overtime : TimeGoTheme.secondary)
            )

            if launchAtLogin.needsApproval {
                Text(l10n.t("login.approvalHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(TimeGoTheme.secondary)
                Button(l10n.t("login.openSettings")) {
                    launchAtLogin.openSystemLoginItems()
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if NotificationIconRegistrar.isRunningFromDerivedData {
                Text(l10n.t("login.derivedDataHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(TimeGoTheme.secondary)
                Button(l10n.t("login.useStableApp")) {
                    launchAtLogin.migrateToStableApplicationsCopy()
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if let error = launchAtLogin.lastError {
                Text(error)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
    }

    private var languageSection: some View {
        settingsBlock(title: l10n.t("settings.language"), subtitle: l10n.t("settings.languageSubtitle")) {
            Picker("", selection: $language) {
                ForEach(AppLanguagePreference.allCases) { option in
                    Text(l10n.t(option.menuTitleKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: language) { _, newValue in
                applyLanguage(newValue)
            }
        }
    }

    private var oaSection: some View {
        settingsBlock(title: l10n.t("settings.oa"), subtitle: l10n.t("settings.oaSubtitle")) {
            labeledField(
                title: l10n.t("settings.oaURL"),
                placeholder: l10n.t("settings.oaPlaceholder"),
                text: $oaURLText
            ) {
                Button(l10n.t("settings.oaOpen")) {
                    openOAURL(oaURLText)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(AppSettings.makeURL(from: oaURLText) == nil)
            }

            Text(l10n.t("settings.oaHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(TimeGoTheme.secondary)
        }
    }

    private var hoursSection: some View {
        settingsBlock(title: l10n.t("settings.hours"), subtitle: l10n.t("settings.hoursSubtitle")) {
            fieldRow(title: l10n.t("settings.workHours"), unit: l10n.t("common.hours")) {
                TextField("8", value: $workHours, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
            }
            SoftDivider()
            fieldRow(title: l10n.t("settings.lunchHours"), unit: l10n.t("common.hours")) {
                TextField("1", value: $lunchHours, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
            }

            Text(l10n.t("settings.hoursHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(TimeGoTheme.secondary)
                .padding(.top, 2)
        }
    }

    private var notifySection: some View {
        settingsBlock(title: l10n.t("settings.notify"), subtitle: l10n.t("settings.notifySubtitle")) {
            Toggle(isOn: $notifyWhenDone) {
                Text(l10n.t("settings.notifyToggle"))
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(TimeGoTheme.accent)
            .onChange(of: notifyWhenDone) { _, enabled in
                if enabled { Task { await requestNotifications() } }
            }

            SoftDivider()

            Toggle(isOn: $notifyEarlyReminder) {
                Text(l10n.t("settings.notifyEarlyToggle"))
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(TimeGoTheme.accent)
            .onChange(of: notifyEarlyReminder) { _, enabled in
                if enabled { Task { await requestNotifications() } }
            }

            if notifyEarlyReminder {
                fieldRow(title: l10n.t("settings.notifyEarlyMinutes"), unit: l10n.t("common.minutes")) {
                    TextField("5", value: $earlyReminderMinutes, format: .number)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                }
            }

            PermissionBadge(
                title: l10n.t("notify.badge", notifications.authState.title),
                color: notifyStatusColor
            )

            if !notifications.authState.isGranted {
                Button(notifications.authState == .denied ? l10n.t("notify.openSettings") : l10n.t("notify.allow")) {
                    Task { await requestNotifications() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isRequestingNotify)

                if notifications.authState == .denied {
                    Text(l10n.t("notify.deniedHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(TimeGoTheme.secondary)
                }
            }
        }
    }

    private var networkSection: some View {
        settingsBlock(title: l10n.t("settings.network"), subtitle: l10n.t("settings.networkSubtitle")) {
            Toggle(isOn: $requireCompanyNetworkForWake) {
                Text(l10n.t("settings.requireCompanyNet"))
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(TimeGoTheme.accent)

            PermissionBadge(
                title: l10n.t("location.badge", location.authState.title),
                color: locationStatusColor
            )

            if !location.authState.isGranted {
                Button(
                    location.authState == .denied || location.authState == .restricted || !location.systemLocationEnabled
                    ? l10n.t("location.openSettings")
                    : l10n.t("location.allow")
                ) {
                    Task { await requestLocation() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isRequestingLocation)
            }

            if let reason = network.snapshot.ssidUnavailableReason, network.snapshot.ssid == nil {
                Text(reason)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(TimeGoTheme.overtime)
            }

            Text(l10n.t("settings.networkHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(TimeGoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            labeledField(
                title: l10n.t("settings.ssid"),
                placeholder: l10n.t("settings.ssidPlaceholder"),
                text: $ssidText
            ) {
                Button(l10n.t("settings.fillSSID")) {
                    if let ssid = network.snapshot.ssid, !ssid.isEmpty {
                        ssidText = mergeUnique(ssidText, adding: ssid)
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(network.snapshot.ssid?.isEmpty != false)
            }

            labeledField(
                title: l10n.t("settings.ip"),
                placeholder: l10n.t("settings.ipPlaceholder"),
                text: $ipText
            ) {
                Button(l10n.t("settings.fillIP")) {
                    if let ip = network.snapshot.localIPv4s.first,
                       let prefix = Self.suggestedPrefix(from: ip) {
                        ipText = mergeUnique(ipText, adding: prefix)
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(network.snapshot.localIPv4s.isEmpty)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(TimeGoTheme.accent)
                Text(currentNetworkLine)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(TimeGoTheme.secondary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TimeGoTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(l10n.t("settings.networkFooter"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(TimeGoTheme.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(l10n.t("common.close")) { onClose?() }
                .buttonStyle(GhostButtonStyle())
            Button(l10n.t("common.save")) {
                save()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { savedFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation { savedFlash = false }
                    onClose?()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func settingsBlock<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(TimeGoTheme.ink)
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(TimeGoTheme.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(TimeGoTheme.line, lineWidth: 1)
                    )
            )
        }
    }

    private func fieldRow<Content: View>(
        title: String,
        unit: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(TimeGoTheme.ink)
            Spacer()
            content()
            Text(unit)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(TimeGoTheme.secondary)
        }
    }

    private func labeledField<Accessory: View>(
        title: String,
        placeholder: String,
        text: Binding<String>,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(TimeGoTheme.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .font(.system(.body, design: .rounded))
            accessory()
        }
    }

    private var notifyStatusColor: Color {
        switch notifications.authState {
        case .authorized, .provisional, .ephemeral: return TimeGoTheme.accent
        case .denied: return .red
        case .notDetermined, .unknown: return TimeGoTheme.overtime
        }
    }

    private var locationStatusColor: Color {
        switch location.authState {
        case .authorized: return TimeGoTheme.accent
        case .denied, .restricted: return .red
        case .notDetermined, .unknown: return TimeGoTheme.overtime
        }
    }

    private func requestNotifications() async {
        isRequestingNotify = true
        defer { isRequestingNotify = false }
        _ = await notifications.requestAuthorization(forcePrompt: true)
    }

    private func requestLocation() async {
        isRequestingLocation = true
        defer { isRequestingLocation = false }
        _ = await location.requestAuthorization()
        network.refreshNow()
    }

    private var currentNetworkLine: String {
        let ssid = network.snapshot.ssid ?? l10n.t("net.unknownSSID")
        let ips = network.snapshot.localIPv4s.joined(separator: ", ")
        let ipPart = ips.isEmpty ? l10n.t("net.noIPShort") : ips
        let match = network.matchesCompanyNetwork(settings: store.settings)
            ? l10n.t("net.matchedShort")
            : l10n.t("net.unmatchedShort")
        return l10n.t("net.currentLine", ssid, ipPart, match)
    }

    private func load() {
        let s = store.settings
        workHours = s.workHours
        lunchHours = s.lunchHours
        ssidText = s.companySSIDs.joined(separator: ", ")
        ipText = s.companyIPPrefixes.joined(separator: ", ")
        notifyWhenDone = s.notifyWhenDone
        notifyEarlyReminder = s.notifyEarlyReminder
        earlyReminderMinutes = s.clampedEarlyReminderMinutes
        requireCompanyNetworkForWake = s.requireCompanyNetworkForWake
        launchAtLoginEnabled = s.launchAtLogin
        language = s.language
        oaURLText = s.companyOAURL
        l10n.apply(s.language)
        launchAtLogin.refresh()
    }

    private func save() {
        store.updateSettings { s in
            s.workHours = max(0.5, min(24, workHours))
            s.lunchHours = max(0, min(8, lunchHours))
            s.companySSIDs = Self.splitList(ssidText)
            s.companyIPPrefixes = Self.splitList(ipText)
            s.notifyWhenDone = notifyWhenDone
            s.notifyEarlyReminder = notifyEarlyReminder
            s.earlyReminderMinutes = min(120, max(1, earlyReminderMinutes))
            s.requireCompanyNetworkForWake = requireCompanyNetworkForWake
            s.launchAtLogin = launchAtLoginEnabled
            s.language = language
            s.companyOAURL = oaURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        applyLaunchAtLogin(launchAtLoginEnabled)
        applyLanguage(language)
    }

    private func openOAURL(_ raw: String) {
        guard let url = AppSettings.makeURL(from: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        store.updateSettings { $0.launchAtLogin = enabled }
        _ = launchAtLogin.setEnabled(enabled)
        SettingsPanelController.shared.bringToFront()
    }

    private func applyLanguage(_ preference: AppLanguagePreference) {
        store.updateSettings { $0.language = preference }
        l10n.apply(preference)
        launchAtLogin.refresh()
        network.refreshNow()
        SettingsPanelController.shared.updateTitle()
        SettingsPanelController.shared.bringToFront()
    }

    private func mergeUnique(_ existing: String, adding value: String) -> String {
        var items = Self.splitList(existing)
        if !items.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            items.append(value)
        }
        return items.joined(separator: ", ")
    }

    private static func splitList(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func suggestedPrefix(from ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".") + "."
    }
}
