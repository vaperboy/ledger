import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// The Partners section of a company page: who co-owns it and what they hold, the lock-up in words, invitations waiting for an answer, the way
/// into the meetings and the Invite a friend flow. Rules: `JVRules`, `JointVenture`.
struct JointVenturePartnersCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    var engine: GameEngine
    var company: Company
    @State private var inviteOpen = false
    @State private var meetingsOpen = false
    @State private var pending: PendingAction?

    /// Shown on an open limited company that is not a holding or a chain branch.
    static func applies(_ co: Company, _ e: GameEngine) -> Bool { e.jvCanStart(companyID: co.id) }

    var body: some View {
        let st: JointVenture.State? = engine.jointVenture(companyID: company.id)
        let stakes: [JointVenture.Stake] = engine.jvStakes(companyID: company.id)
        let cur: Currency = engine.currency(for: company)
        let waiting: Int = st?.meetings.filter { !$0.closed && $0.opened <= engine.state.week && $0.items.contains { $0.votes[JointVenture.Member.me] == nil } }.count ?? 0
        Card(padding: Theme.Space.l, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Partners").capsLabel()
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.group, size: 17, weight: 1.6)
                }
                if stakes.count < 2 && (st?.invites.contains { $0.status == "sent" } != true) {
                    Text("Own this company with friends. Each friend gets a private price of their own, and big decisions go to a vote by shares at a board meeting.")
                        .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(stakes) { (s: JointVenture.Stake) in stakeRow(s) }
                }
                if let st {
                    ForEach(st.invites.filter { $0.status == "sent" }) { (inv: JointVenture.Invite) in
                        ListRow(symbol: "paperplane", tint: Theme.inkSoft, title: inv.name, subtitle: "Invitation sent · \(String(format: "%.0f", inv.pct))% for \(cur.tidyDisplay(inv.price)) · open until \(GameCalendar.dateString(week: inv.expires))",
                                trailing: "Waiting")
                    }
                    meetingsRow(st, waiting: waiting)
                    Text("Decisions go by shares among the votes cast. Money goes out to owners only when a meeting votes for it, and the company is sold only by a vote. A new partner cannot sell or leave for \(JVRules.lockUpWeeks) weeks; after that you can buy them out at what their share is worth.")
                        .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                if stakes.count - 1 + (st?.invites.filter { $0.status == "sent" }.count ?? 0) < JVRules.maxPartners {
                    Button { Haptics.tap(); inviteOpen = true } label: { Text("Invite a friend").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("jv-invite")
                }
            }
        }
        .centerSheet(isPresented: $inviteOpen, title: "Invite a friend", size: .tall) {
            JVInviteSheet(companyID: company.id).environmentObject(store).environment(online)
        }
        .navigationDestination(isPresented: $meetingsOpen) { JointVentureMeetingsView(companyID: company.id) }
        .task { JointVentureCoordinator.shared.attach(online.service); await JointVentureCoordinator.shared.sync(store) }
        .confirmAction($pending)
    }

    private func stakeRow(_ s: JointVenture.Stake) -> some View {
        let lock: String = s.locked ? "Cannot sell or leave until \(GameCalendar.dateString(week: s.lockUntil))" : (s.isYou ? "Votes with \(String(format: "%.1f", s.pct))%" : "Free to sell or leave")
        return VStack(alignment: .leading, spacing: 4) {
            ListRow(symbol: s.isYou ? "person.fill" : "person", tint: s.isYou ? Theme.accent : Theme.inkSoft,
                    title: s.isYou ? "\(s.name) (you)" : s.name, subtitle: "\(s.roleTitle) · \(lock)", trailing: String(format: "%.1f%%", s.pct))
            if !s.isYou && !s.locked {
                Button { askBuyOut(s) } label: { Text("Buy out \(s.name)") }
                    .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
            }
        }
    }

    /// Says what a buy-out does before it happens; nothing moves until the player confirms.
    private func askBuyOut(_ s: JointVenture.Stake) {
        guard let terms: JointVenture.ExitTerms = engine.jvExitTerms(companyID: company.id, memberID: s.id) else { return }
        if let why = terms.problem { Haptics.warning(); store.tell("Not now", why, tone: "warn"); return }
        let id: Int = company.id
        let member: String = s.id
        pending = PendingAction(title: "Buy out \(s.name)?", message: terms.lines.joined(separator: " "), button: "Buy their shares", alwaysAsk: true, tone: .warning, icon: "person.fill.xmark") {
            let problem: String? = store.act { (g: inout GameEngine) -> String? in g.jvBuyOut(companyID: id, memberID: member) } ?? nil
            if let problem { Haptics.warning(); store.tell("Not done", problem, tone: "warn") } else { Haptics.success() }
        }
    }

    private func meetingsRow(_ st: JointVenture.State, waiting: Int) -> some View {
        let next: String = st.nextPlanned.map { "Next planned meeting \(GameCalendar.dateString(week: $0))" } ?? "No planned meeting yet"
        return Button { Haptics.tap(); meetingsOpen = true } label: {
            ListRow(symbol: "calendar", tint: waiting > 0 ? Theme.warn : Theme.accent, title: "Meetings", subtitle: waiting > 0 ? "\(waiting) waiting for your vote" : next,
                    trailing: waiting > 0 ? "Vote" : "", chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jv-meetings")
    }
}

// MARK: - Invite a friend

/// Pick a friend, a stake and a private price, then see in their words what joining does before sending.
struct JVInviteSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    @State private var friends: [PlayerProfile] = []
    @State private var loaded = false
    @State private var picked: PlayerProfile?
    @State private var pct: Double = 20
    @State private var factor: Double = 1
    @State private var role: String = "Partner"
    @State private var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let e = store.engine, let co = e.state.company(companyID) {
                let cur: Currency = e.currency(for: co)
                let fair: Double = e.jvFairPrice(companyID: companyID, pct: pct)
                let price: Double = privatePrice(e, fair: fair)
                if preview, let friend = picked, let terms = e.jvTerms(companyID: companyID, pct: pct, price: price) {
                    consequence(friend: friend, terms: terms, cur: cur)
                } else {
                    form(e, co, cur, fair: fair, price: price)
                }
            } else {
                Text("This company no longer exists.").popupText(.body)
            }
        }
        .task {
            JointVentureCoordinator.shared.attach(online.service)
            friends = await JointVentureCoordinator.shared.service.invitable()
            loaded = true
        }
    }

    private func band(_ e: GameEngine) -> ClosedRange<Double> {
        let wide: ClosedRange<Double> = e.state.worldRules.ventureBand
        return wide.lowerBound...min(1, wide.upperBound)
    }

    private func privatePrice(_ e: GameEngine, fair: Double) -> Double {
        let b: ClosedRange<Double> = band(e)
        return min(max((fair * factor).rounded(), (fair * b.lowerBound).rounded(.up)), (fair * b.upperBound).rounded(.down))
    }

    @ViewBuilder private func form(_ e: GameEngine, _ co: Company, _ cur: Currency, fair: Double, price: Double) -> some View {
        Text("Who").capsLabel()
        if !loaded {
            ProgressView().tint(Theme.inkSoft)
        } else if friends.isEmpty {
            Text("Add friends in the Friends app first. Their profile shows up here.").popupText(.caption)
        } else {
            ForEach(friends) { (p: PlayerProfile) in
                ChoiceCard(title: p.displayName, subtitle: [p.level.map { "Level \($0)" }, p.countryCode].compactMap { $0 }.joined(separator: " · "),
                           selected: picked?.id == p.id) { picked = p }
            }
        }
        Text("Their stake").capsLabel()
        LedgerSlider(value: $pct, in: 5...40, step: 1, valueText: "\(Int(pct))% of the company")
        Text("Their private price").capsLabel()
        LedgerSlider(value: $factor, in: band(e), step: 0.05, valueText: cur.tidyDisplay(price))
        HStack(spacing: 4) {
            if factor == 1 { Text("Fair price: \(cur.tidyDisplay(fair)).") } else {
                StockArrow(up: false, good: false)
                Text("Under the fair price of \(cur.tidyDisplay(fair)): a friendly deal that dilutes you.")
            }
        }
        .popupText(.caption)
        Text("A sample friend pays at most the fair price.").popupText(.caption)
        Text("Only they see this price. Other friends you invite get a price of their own.").popupText(.caption)
        Text("Role").capsLabel()
        SegmentedPill(items: ["Partner", "CFO"], title: { $0 }, selection: $role)
        if (e.jointVenture(companyID: companyID)?.members.count ?? 1) > 1 {
            Text("You have partners, so a meeting votes on this invitation before it goes out.").popupText(.risk)
        }
        Color.clear.frame(height: 0)
            .popupFooter {
                PopupFooter(cancel: "Cancel", action: "See what they will read", onCancel: { dismiss() }, onAction: { Haptics.tap(); preview = true }, actionEnabled: picked != nil, actionID: "jv-preview")
            }
    }

    /// The popup the friend reads: what happens if they join, in plain lines.
    @ViewBuilder private func consequence(friend: PlayerProfile, terms: JointVenture.Terms, cur: Currency) -> some View {
        Text("If you join, this will happen").popupText(.title)
        Text("\(friend.displayName) reads this for \(terms.companyName) before answering.").popupText(.caption)
        ForEach(Array(terms.lines.enumerated()), id: \.offset) { pair in
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
                Text(pair.element).popupText(.body)
            }
        }
        Color.clear.frame(height: 0)
            .popupFooter {
                PopupFooter(cancel: "Back", action: "Send invitation", onCancel: { preview = false }, onAction: { send(friend) }, actionID: "jv-send")
            }
    }

    private func send(_ friend: PlayerProfile) {
        guard let e = store.engine else { return }
        let fair: Double = e.jvFairPrice(companyID: companyID, pct: pct)
        let price: Double = privatePrice(e, fair: fair)
        let id: Int = companyID
        let p: Double = pct
        let cfo: Bool = role == "CFO"
        let mine: Set<String> = Set(["me"] + [online.profile?.id].compactMap { $0 })
        let result = store.act { (g: inout GameEngine) -> JointVenture.InviteResult in
            g.jvInvite(companyID: id, playerID: friend.id, name: friend.displayName, linkKey: friend.id, role: cfo ? "cfo" : "partner", mock: true, pct: p, price: price, myLinkKeys: mine)
        }
        switch result {
        case .sent(let inviteID)?:
            Haptics.success()
            if let g = store.engine, let offer = JointVentureCoordinator.shared.offer(engine: g, companyID: id, inviteID: inviteID, friendName: friend.displayName, friendID: friend.id, pct: p, price: price) {
                Task { await JointVentureCoordinator.shared.service.send(offer) }
            }
            dismiss()
            store.tell("Invitation sent", "\(friend.displayName) has the offer: \(Int(p))% of the company at their own price. They have \(JVRules.inviteWeeks) weeks to answer. Once they accept they pay, and cannot sell for \(JVRules.lockUpWeeks) weeks.", tone: "good")
        case .needsVote(let meetingID)?:
            Haptics.success()
            _ = meetingID
            dismiss()
            store.tell("Put to the partners", "You already have partners, so \(friend.displayName) is invited only if the vote passes. An emergency meeting is open; your partners vote within a week.")
        case .refused(let why)?:
            Haptics.warning()
            store.tell("Not sent", why, tone: "warn")
        case nil:
            break
        }
    }
}
