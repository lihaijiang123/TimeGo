import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @EnvironmentObject private var store: SessionStore
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var clock = MenuBarClock.shared

    var body: some View {
        // Minute-level clock — title uses `DurationFormat.short` (no seconds).
        let _ = clock.now
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isPastTarget ? TimeGoTheme.overtime : TimeGoTheme.accent)
            Text(menuTitle)
                .font(.body.monospacedDigit().weight(.medium))
        }
        .help(helpText)
    }

    private var iconName: String {
        guard store.hasSessionToday else { return "clock" }
        return store.isPastTarget ? "checkmark.circle.fill" : "clock.fill"
    }

    private var menuTitle: String {
        guard store.hasSessionToday else { return l10n.t("menu.notStarted") }
        if store.isPastTarget {
            return l10n.t("menu.overtime", DurationFormat.short(store.overtimeDuration))
        }
        return l10n.t("menu.remaining", DurationFormat.short(store.remainingDuration))
    }

    private var helpText: String {
        guard let start = store.startTime else {
            return l10n.t("menu.helpIdle")
        }
        return l10n.t("menu.helpStarted", DurationFormat.time.string(from: start))
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var liveClock = PanelLiveClock.shared
    @State private var draftStart = Date()
    @State private var appeared = false
    @State private var ignoreDraftChange = false

    var body: some View {
        // Bind panel refresh to the shared clock (no Timer / AppKit probe in view state).
        let _ = liveClock.now
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)

            hero
                .padding(.bottom, 18)

            SoftDivider()
                .padding(.bottom, 14)

            stats
                .padding(.bottom, 16)

            SoftDivider()
                .padding(.bottom, 14)

            controls
                .padding(.bottom, 16)

            SoftDivider()
                .padding(.bottom, 12)

            networkHint
                .padding(.bottom, 14)

            footer
        }
        .padding(18)
        .frame(width: 360)
        .background(TimeGoTheme.panelBackground)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            PanelLiveClock.shared.retain()
            syncDraftFromStore()
            withAnimation(.easeOut(duration: 0.28)) { appeared = true }
            // Don't leave the caret in the time fields when the panel just opens.
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onDisappear {
            PanelLiveClock.shared.release()
        }
        .onChange(of: store.startTime) { _, newValue in
            guard let newValue else { return }
            syncDraft(newValue)
        }
        .id(l10n.code)
    }

    private func syncDraftFromStore() {
        syncDraft(store.startTime ?? .now)
    }

    private func syncDraft(_ date: Date) {
        ignoreDraftChange = true
        draftStart = date
        DispatchQueue.main.async {
            ignoreDraftChange = false
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TimeGo")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(TimeGoTheme.ink)
                Text(statusLine)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(TimeGoTheme.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Text(
            store.hasSessionToday
            ? (store.isPastTarget ? l10n.t("menu.pillDone") : l10n.t("menu.pillTiming"))
            : l10n.t("menu.pillIdle")
        )
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(TimeGoTheme.statusColor(isActive: store.hasSessionToday, isOvertime: store.isPastTarget))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            TimeGoTheme.statusColor(isActive: store.hasSessionToday, isOvertime: store.isPastTarget).opacity(0.12),
            in: Capsule()
        )
    }

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(TimeGoTheme.line, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        store.isPastTarget ? TimeGoTheme.overtime : TimeGoTheme.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)

                VStack(spacing: 2) {
                    Text(heroEyebrow)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(TimeGoTheme.secondary)
                    Text(heroValue)
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(store.isPastTarget ? TimeGoTheme.overtime : TimeGoTheme.ink)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(width: 88)
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                Text(heroTitle)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(TimeGoTheme.ink)
                Text(heroSubtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(TimeGoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let leave = store.targetLeaveTime {
                    Label(
                        l10n.t("menu.suggestLeave", DurationFormat.time.string(from: leave)),
                        systemImage: "arrow.right.circle"
                    )
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(TimeGoTheme.accent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TimeGoTheme.accent.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TimeGoTheme.line, lineWidth: 1)
                }
        }
    }

    private var heroEyebrow: String {
        guard store.hasSessionToday else { return l10n.t("menu.heroToday") }
        return store.isPastTarget ? l10n.t("menu.heroOvertime") : l10n.t("menu.heroRemaining")
    }

    private var heroValue: String {
        guard store.hasSessionToday else { return l10n.t("common.dash") }
        if store.isPastTarget {
            return DurationFormat.short(store.overtimeDuration)
        }
        return DurationFormat.short(store.remainingDuration)
    }

    private var heroTitle: String {
        guard store.hasSessionToday else { return l10n.t("menu.heroIdleTitle") }
        if store.isPastTarget { return l10n.t("menu.heroDoneTitle") }
        return l10n.t("menu.heroBusyTitle")
    }

    private var heroSubtitle: String {
        guard let start = store.startTime else {
            return l10n.t("menu.heroIdleSubtitle")
        }
        return l10n.t(
            "menu.heroBusySubtitle",
            DurationFormat.time.string(from: start),
            lunchLabel
        )
    }

    private var progress: CGFloat {
        guard store.hasSessionToday else { return 0 }
        let total = max(1, store.settings.requiredOnSiteDuration)
        let done = min(total, store.workedDuration)
        if store.isPastTarget { return 1 }
        return CGFloat(done / total)
    }

    private var stats: some View {
        VStack(spacing: 10) {
            SectionLabel(title: l10n.t("menu.overview"))
            MetaRow(
                title: l10n.t("menu.startTime"),
                value: store.startTime.map { DurationFormat.timeWithSeconds.string(from: $0) } ?? l10n.t("common.dash")
            )
            MetaRow(
                title: l10n.t("menu.onSite"),
                value: store.hasSessionToday ? DurationFormat.clock(store.workedDuration) : l10n.t("common.dash")
            )
            MetaRow(title: l10n.t("menu.lunch"), value: lunchLabel)
            if store.hasSessionToday {
                if store.isPastTarget {
                    MetaRow(
                        title: l10n.t("menu.overtimeDuration"),
                        value: DurationFormat.clock(store.overtimeDuration),
                        emphasize: true,
                        valueColor: TimeGoTheme.overtime
                    )
                } else {
                    MetaRow(
                        title: l10n.t("menu.remainingDuration"),
                        value: DurationFormat.clock(store.remainingDuration),
                        emphasize: true,
                        valueColor: TimeGoTheme.accent
                    )
                }
            }
        }
    }

    private var lunchLabel: String {
        let hours = store.settings.lunchHours
        if hours <= 0 { return l10n.t("common.none") }
        if hours.rounded() == hours {
            return l10n.t("common.hoursInt", Int(hours))
        }
        return l10n.t("common.hoursValue", String(format: "%.1f", hours))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: store.hasSessionToday ? l10n.t("menu.correctTime") : l10n.t("menu.startWork"))

            if store.hasSessionToday {
                HStack {
                    Text(l10n.t("menu.startTime"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(TimeGoTheme.secondary)
                    Spacer()
                    HourMinuteField(date: $draftStart)
                        .onChange(of: draftStart) { _, newValue in
                            guard !ignoreDraftChange else { return }
                            store.setStartTime(mergedToday(newValue), asManualSource: true)
                        }
                }

                HStack(spacing: 8) {
                    Button(l10n.t("menu.setNow")) {
                        store.setStartTime(.now, asManualSource: true)
                        syncDraft(.now)
                    }
                    .buttonStyle(GhostButtonStyle())

                    Button(l10n.t("menu.clearToday")) {
                        store.clearToday()
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            } else {
                Button(l10n.t("menu.startNow")) {
                    store.start(source: .manual)
                    syncDraft(.now)
                }
                .buttonStyle(PrimaryButtonStyle())

                HStack {
                    Text(l10n.t("menu.orPickTime"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(TimeGoTheme.secondary)
                    Spacer()
                    HourMinuteField(date: $draftStart)
                    Button(l10n.t("common.start")) {
                        store.setStartTime(mergedToday(draftStart), asManualSource: true)
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private var networkHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: l10n.t("menu.network"))
            HStack(spacing: 8) {
                Image(systemName: network.matchesCompanyNetwork(settings: store.settings) ? "wifi" : "wifi.exclamationmark")
                    .foregroundStyle(
                        network.matchesCompanyNetwork(settings: store.settings)
                        ? TimeGoTheme.accent
                        : TimeGoTheme.secondary
                    )
                Text(networkSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(TimeGoTheme.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !network.matchesCompanyNetwork(settings: store.settings),
               let reason = network.snapshot.ssidUnavailableReason {
                Text(reason)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(TimeGoTheme.overtime)
            }
        }
    }

    private var networkSummary: String {
        let link = network.snapshot.wifiActive ? l10n.t("net.wifiOn") : l10n.t("net.wifiOff")
        let ssid = network.snapshot.ssid ?? l10n.t("net.unknownName")
        let ip = network.snapshot.localIPv4s.first ?? l10n.t("net.noIP")
        let match = network.matchesCompanyNetwork(settings: store.settings)
            ? l10n.t("net.matched")
            : l10n.t("net.unmatched")
        return l10n.t("net.summaryLine", link, ssid, ip, match)
    }

    private var footer: some View {
        HStack {
            Button(l10n.t("common.settings")) {
                SettingsPanelController.shared.show()
            }
            .buttonStyle(GhostButtonStyle())

            if store.settings.resolvedCompanyOAURL != nil {
                Button(l10n.t("menu.openOA")) {
                    openCompanyOA()
                }
                .buttonStyle(GhostButtonStyle())
            }

            Spacer()

            Button(l10n.t("common.exit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private func openCompanyOA() {
        guard let url = store.settings.resolvedCompanyOAURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var statusLine: String {
        if !store.hasSessionToday {
            return l10n.t("menu.statusIdle")
        }
        let sourceText: String
        switch store.session?.source {
        case .manual: sourceText = l10n.t("menu.source.manual")
        case .unlock: sourceText = l10n.t("menu.source.unlock")
        case .wake: sourceText = l10n.t("menu.source.wake")
        case .network: sourceText = l10n.t("menu.source.network")
        case .none: sourceText = ""
        }
        return l10n.t("menu.statusActive", sourceText)
    }

    private func mergedToday(_ time: Date) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        let hm = cal.dateComponents([.hour, .minute, .second], from: time)
        comps.hour = hm.hour
        comps.minute = hm.minute
        comps.second = hm.second ?? 0
        return cal.date(from: comps) ?? time
    }
}
