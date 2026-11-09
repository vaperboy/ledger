import SwiftUI

/// The Admin screen: the world rules (each inside limits fixed on the server), the confirmations queue of the government engine and the
/// audit log. Only the server says who is an administrator; every call here is checked there again, and every change leaves an audit row.
struct AdminScreen: View {
    @Environment(OnlineSession.self) private var online
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tab: String, CaseIterable { case rules = "Rules", queue = "Queue", log = "Log" }

    @State private var tab: Tab = .rules
    @State private var snap: AdminSnapshot?
    @State private var failure: String?
    @State private var saved: String?
    @State private var loading = false
    @State private var busy = false
    @State private var editing: String?
    @State private var draft: Double = 0
    @State private var reason = ""
    @State private var decisionReasons: [String: String] = [:]
    @State private var pending: PendingAction?
    @State private var loadingOlder = false
    @State private var noOlder = false

    private let P: OutsidePalette = .control
    private let pageSize = 50

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                if !online.isAdmin {
                    locked
                } else {
                    strip
                    tabs
                    if let failure { banner(failure, tint: P.loss) }
                    if let saved { banner(saved, tint: P.gain) }
                    if snap == nil {
                        HStack {
                            Spacer()
                            if loading { ProgressView().tint(P.accent) } else { Text("Nothing loaded yet.").textStyle(.caption, tint: P.inkFaint) }
                            Spacer()
                        }
                        .padding(.vertical, Theme.Space.xl)
                    } else {
                        switch tab {
                        case .rules: rulesTab
                        case .queue: queueTab
                        case .log: logTab
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xxl)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).noSidewaysDrag()
        .refreshable { await load() }
        .outsideScreen(P)
        .confirmAction($pending)
        .task { if online.isAdmin { await load() } }
        .accessibilityIdentifier("admin-screen")
    }

    // MARK: Frame

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            OutsideBack()
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Administration").textStyle(.title, tint: P.ink).accessibilityAddTraits(.isHeader)
                Text("Every change is logged with your name").textStyle(.caption, tint: P.inkSoft)
            }
            Spacer(minLength: 0)
            Button { Haptics.tap(); Task { await load() } } label: {
                Text("Refresh").textStyle(.caption, tint: P.accent, weight: .medium).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain).disabled(loading || !online.isAdmin)
            .accessibilityIdentifier("admin-refresh")
        }
    }

    private var locked: some View {
        panel {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.large, tint: P.inkFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Administrators only").textStyle(.headline, tint: P.ink)
                    Text("The server does not list this account as an administrator.").textStyle(.caption, tint: P.inkSoft)
                }
            }
        }
    }

    private var strip: some View {
        let rules: [WorldRule] = snap?.rules ?? []
        let changed: Int = rules.filter { !$0.isDefault }.count
        return HStack(spacing: 0) {
            stat("\(changed)", "rules off default", tint: changed > 0 ? P.accent : P.ink)
            Rectangle().fill(P.hairline).frame(width: 0.5, height: 34)
            stat("\(snap?.confirmations.count ?? 0)", "waiting", tint: (snap?.confirmations.isEmpty ?? true) ? P.ink : P.accent2)
            Rectangle().fill(P.hairline).frame(width: 0.5, height: 34)
            stat("\(snap?.audit.count ?? 0)", "log entries", tint: P.ink)
        }
        .padding(.vertical, Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundStyle(tint)
            Text(label).textStyle(.caption, tint: P.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var tabs: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Tab.allCases, id: \.self) { (t: Tab) in
                let on: Bool = tab == t
                Button {
                    Haptics.tap()
                    withAnimation(Motion.quick(reduceMotion)) { tab = t }
                } label: {
                    Text(t.rawValue + (t == .queue && !(snap?.confirmations.isEmpty ?? true) ? " \u{00B7} \(snap?.confirmations.count ?? 0)" : ""))
                        .textStyle(.body, tint: on ? P.onAccent : P.inkSoft, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? P.accent : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
                .accessibilityIdentifier("admin-tab-" + t.rawValue.lowercased())
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.cardDeep))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
    }

    private func banner(_ text: String, tint: Color) -> some View {
        Text(text).textStyle(.caption, tint: tint).fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Rules

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            ForEach(RuleGroup.allCases, id: \.self) { (g: RuleGroup) in
                let rows: [WorldRule] = (snap?.rules ?? []).filter { $0.group == g }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            LedgerGlyph(glyph: g.glyph, size: Theme.Icon.small, tint: P.accent)
                            Text(g.title).capsLabel(P.accent)
                        }
                        Text(g.blurb).textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                        panel {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { (i: Int, r: WorldRule) in
                                    if i > 0 { Hairline() }
                                    ruleRow(r)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ r: WorldRule) -> some View {
        let open: Bool = editing == r.key
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Button {
                Haptics.tap()
                withAnimation(Motion.standard(reduceMotion)) {
                    if open { editing = nil } else { editing = r.key; draft = r.value; reason = "" }
                }
            } label: {
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).textStyle(.body, tint: P.ink).fixedSize(horizontal: false, vertical: true)
                        Text(r.isDefault ? "Default" : "Default was " + r.text(r.defaultValue)).textStyle(.caption, tint: r.isDefault ? P.inkFaint : P.accent)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text(r.valueText).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(P.ink)
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkDim).rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityValue(r.valueText)
            .accessibilityHint(open ? "Close the editor" : "Edit this rule")
            .accessibilityIdentifier("admin-rule-" + r.key)

            if open { editor(r).transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))) }
        }
    }

    private func editor(_ r: WorldRule) -> some View {
        let value: Double = quantised(draft, r)
        let changed: Bool = abs(value - r.value) > 1e-9
        let reasonOK: Bool = reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                nudge("minus", "Lower") { draft = quantised(draft - r.step, r) }.disabled(value <= r.minimum + 1e-9)
                Text(r.text(value)).font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundStyle(changed ? P.accent : P.ink)
                    .frame(maxWidth: .infinity)
                nudge("plus", "Raise") { draft = quantised(draft + r.step, r) }.disabled(value >= r.maximum - 1e-9)
            }
            Slider(value: $draft, in: r.minimum...r.maximum, step: r.step).tint(P.accent)
                .accessibilityLabel(r.label).accessibilityValue(r.text(value))
            HStack {
                Text("Fixed limits").textStyle(.caption, tint: P.inkFaint)
                Spacer()
                Text(r.rangeText).textStyle(.caption, tint: P.inkSoft)
            }
            TextField("Reason for the change (needed)", text: $reason)
                .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(P.ink)
                .padding(.horizontal, Theme.Space.m).frame(minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(P.cardDeep))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
                .submitLabel(.done)
                .accessibilityIdentifier("admin-reason")
            HStack(spacing: Theme.Space.s) {
                Button { Haptics.tap(); draft = r.defaultValue } label: {
                    Text("Use default").textStyle(.body, tint: P.inkSoft, weight: .medium).frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
                }
                .buttonStyle(PressableStyle()).disabled(abs(value - r.defaultValue) < 1e-9)
                Button {
                    Haptics.tap()
                    let why: String = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    pending = PendingAction.online(
                        title: "Change this rule?",
                        effect: "\(r.label.lowercased()) changes from \(r.valueText) to \(r.text(value)) for every player straight away. The change and your reason are written to the audit log, and only another change can reverse it.",
                        button: "Apply change", risk: "Players see the new rule at once.", tone: .warning, icon: "slider.horizontal.3") {
                        apply(r, value: value, reason: why)
                    }
                } label: {
                    Text("Apply change").font(.system(size: 16, weight: .semibold)).foregroundStyle(P.onAccent).frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.accent.opacity(changed && reasonOK ? 1 : 0.35)))
                }
                .buttonStyle(PressableStyle()).disabled(!changed || !reasonOK || busy)
                .accessibilityIdentifier("admin-apply")
            }
        }
        .padding(.bottom, Theme.Space.s)
    }

    private func nudge(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(P.ink)
                .frame(width: 46, height: 46)
                .background(Circle().fill(P.cardDeep)).overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// Clamped into the rule's fixed limits and rounded to four places (what the server stores).
    private func quantised(_ v: Double, _ r: WorldRule) -> Double {
        let clamped: Double = min(max(v, r.minimum), r.maximum)
        return (clamped * 10_000).rounded() / 10_000
    }

    // MARK: Queue

    private var queueTab: some View {
        let items: [PendingConfirmation] = snap?.confirmations ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Changes a president proposed and election results wait here. Nothing takes effect until you confirm it, and you cannot decide a change you proposed yourself.")
                .textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            if items.isEmpty {
                panel {
                    HStack(spacing: Theme.Space.m) {
                        LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.large, tint: P.gain)
                        Text("Nothing is waiting.").textStyle(.headline, tint: P.ink)
                    }
                }
            }
            ForEach(items) { (c: PendingConfirmation) in confirmationCard(c) }
        }
    }

    private func confirmationCard(_ c: PendingConfirmation) -> some View {
        let text: String = decisionReasons[c.id] ?? ""
        let reasonOK: Bool = text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        return panel {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    Text(c.kind.title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(P.accent2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(P.accent2.opacity(0.14)))
                    Text(c.country).textStyle(.caption, tint: P.inkSoft, weight: .medium)
                    Spacer(minLength: 0)
                    Text(c.at.formatted(.relative(presentation: .named))).textStyle(.caption, tint: P.inkFaint)
                }
                Text(c.summary).textStyle(.headline, tint: P.ink).fixedSize(horizontal: false, vertical: true)
                Text("Proposed by " + c.proposer).textStyle(.caption, tint: P.inkSoft)
                TextField("Reason (needed to reject)", text: Binding(get: { decisionReasons[c.id] ?? "" }, set: { decisionReasons[c.id] = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(P.ink)
                    .padding(.horizontal, Theme.Space.m).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(P.cardDeep))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
                HStack(spacing: Theme.Space.s) {
                    Button {
                        Haptics.tap()
                        pending = PendingAction.online(
                            title: "Reject this change?",
                            effect: "\(c.summary.lowercased()) is rejected for \(c.country): " + c.kind.onReject + " Your reason is recorded in the audit log.",
                            button: "Reject", destructive: true, tone: .danger, icon: "xmark.circle") { decide(c, approve: false, reason: text) }
                    } label: {
                        Text("Reject").textStyle(.body, tint: P.loss, weight: .semibold).frame(maxWidth: .infinity, minHeight: 46)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.loss.opacity(reasonOK ? 0.8 : 0.3), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle()).disabled(!reasonOK || busy)
                    .accessibilityIdentifier("admin-reject")
                    Button {
                        Haptics.tap()
                        pending = PendingAction.online(
                            title: "Confirm this change?",
                            effect: "\(c.summary.lowercased()) is confirmed for \(c.country): " + c.kind.onConfirm + " This is recorded in the audit log.",
                            button: "Confirm", tone: .success, icon: "checkmark.circle") { decide(c, approve: true, reason: text) }
                    } label: {
                        Text("Confirm").font(.system(size: 16, weight: .semibold)).foregroundStyle(P.onAccent).frame(maxWidth: .infinity, minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.accent))
                    }
                    .buttonStyle(PressableStyle()).disabled(busy)
                    .accessibilityIdentifier("admin-confirm")
                }
            }
        }
    }

    // MARK: Log

    private var logTab: some View {
        let rows: [AuditEntry] = snap?.audit ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Every change an administrator makes is written here and can never be edited or removed.").textStyle(.caption, tint: P.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if rows.isEmpty {
                panel { Text("No entries yet.").textStyle(.body, tint: P.inkSoft) }
            } else {
                panel {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { (i: Int, e: AuditEntry) in
                            if i > 0 { Hairline() }
                            auditRow(e)
                        }
                    }
                }
                if rows.count >= pageSize && !noOlder {
                    Button { Haptics.tap(); Task { await loadOlder() } } label: {
                        HStack(spacing: Theme.Space.s) {
                            if loadingOlder { ProgressView().tint(P.accent) }
                            Text("Load older entries").textStyle(.body, tint: P.accent, weight: .medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(PressableStyle()).disabled(loadingOlder)
                }
            }
        }
    }

    private func auditRow(_ e: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.title).textStyle(.body, tint: P.ink, weight: .semibold)
                Spacer(minLength: Theme.Space.s)
                Text(e.at.formatted(date: .abbreviated, time: .shortened)).textStyle(.caption, tint: P.inkFaint)
            }
            Text(e.actor + (e.target.isEmpty ? "" : " \u{00B7} " + e.target)).textStyle(.caption, tint: P.inkSoft)
            if e.before != nil || e.after != nil {
                Text((e.before ?? "none") + "  \u{2192}  " + (e.after ?? "none")).font(.system(.caption, design: .monospaced)).foregroundStyle(P.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !e.reason.isEmpty { Text("\u{201C}" + e.reason + "\u{201D}").textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Calls

    private func load() async {
        guard online.isAdmin else { return }
        loading = true
        defer { loading = false }
        do {
            snap = try await online.service.adminSnapshot()
            failure = nil
            noOlder = false
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? "Could not load the administration data."
            if case OnlineError.notAdmin = error { await online.refreshStatus() }
        }
    }

    private func loadOlder() async {
        guard let last = snap?.audit.last?.id else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let more: [AuditEntry] = try await online.service.adminAudit(before: last, limit: pageSize)
            if more.count < pageSize { noOlder = true }
            snap?.audit.append(contentsOf: more)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? "Could not load older entries."
        }
    }

    private func apply(_ r: WorldRule, value: Double, reason why: String) {
        busy = true
        Task {
            do {
                try await online.service.adminSetRule(key: r.key, value: value, reason: why)
                editing = nil
                reason = ""
                saved = "\(r.label) is now \(r.text(value))."
                failure = nil
                await load()
            } catch {
                saved = nil
                failure = (error as? LocalizedError)?.errorDescription ?? "The change was not saved."
            }
            busy = false
        }
    }

    private func decide(_ c: PendingConfirmation, approve: Bool, reason why: String) {
        busy = true
        Task {
            do {
                try await online.service.adminDecide(id: c.id, approve: approve, reason: why.trimmingCharacters(in: .whitespacesAndNewlines))
                decisionReasons[c.id] = nil
                saved = approve ? "Confirmed: \(c.summary)." : "Rejected: \(c.summary)."
                failure = nil
                await load()
            } catch {
                saved = nil
                failure = (error as? LocalizedError)?.errorDescription ?? "The decision was not saved."
            }
            busy = false
        }
    }
}
