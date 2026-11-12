import SwiftUI
import GameCore
import Countries
import Events
import Simulation

struct JointVenturePartnersCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    var engine: GameEngine
    var company: Company
    @State private var inviteOpen = false
    @State private var meetingsOpen = false
    @State private var buyTarget: BuyTarget?

    private struct BuyTarget: Identifiable { var id: String }

    static func applies(_ co: Company, _ e: GameEngine) -> Bool { e.jvCanStart(companyID: co.id) }

    var body: some View {
        let st: JointVenture.State? = engine.jointVenture(companyID: company.id)
        let stakes: [JointVenture.Stake] = engine.jvStakes(companyID: company.id)
        let cur: Currency = engine.currency(for: company)
        let waiting: Int = st?.meetings.filter { JVClock.votingOpen($0, week: engine.state.week) && $0.items.contains { $0.votes[JointVenture.Member.me] == nil } }.count ?? 0
        let offers: [JointVenture.Buyback] = engine.jvBuyBackOffers(companyID: company.id)
        Card(padding: Theme.Space.l, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Partners").capsLabel()
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.group, size: 17, weight: 1.6)
                }
                if stakes.count < 2 && (st?.invites.contains { $0.status == "sent" } != true) {
                    Text("Own this company with friends. You set the share and the price each friend is offered; they accept or decline. With co-owners, big decisions go to a vote by shares at a board meeting.")
                        .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(stakes) { (s: JointVenture.Stake) in stakeRow(s, offer: offers.first { $0.memberID == s.id }, cur: cur) }
                }
                if let st {
                    ForEach(st.invites.filter { $0.status == "sent" }) { (inv: JointVenture.Invite) in
                        ListRow(symbol: "paperplane", tint: Theme.inkSoft, title: inv.name, subtitle: "Offered \(String(format: "%.0f", inv.pct))% for \(cur.tidyDisplay(inv.price)) · they accept or decline · open until \(GameCalendar.dateString(week: inv.expires))",
                                trailing: "Waiting")
                    }
                    meetingsRow(st, waiting: waiting)
                    Text("A proposal passes only with yes votes from more than half of all shares; an owner who does not vote abstains. The dividend policy, group rules, payouts and a sale all go to the board. A new partner cannot sell or leave for \(JVRules.lockUpWeeks) weeks; after that you can offer to buy their shares, and they accept or decline.")
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
        .centerSheet(item: $buyTarget, title: "Offer for their shares") { (t: BuyTarget) in JVBuybackSheet(companyID: company.id, memberID: t.id).environmentObject(store) }
    }

    private func stakeRow(_ s: JointVenture.Stake, offer: JointVenture.Buyback?, cur: Currency) -> some View {
        let lock: String = s.locked ? "Cannot sell or leave until \(GameCalendar.dateString(week: s.lockUntil))" : (s.isYou ? "Votes with \(String(format: "%.1f", s.pct))%" : "Free to sell or leave")
        let id: Int = company.id
        return VStack(alignment: .leading, spacing: 4) {
            ListRow(symbol: s.isYou ? "person.fill" : "person", tint: s.isYou ? Theme.accent : Theme.inkSoft,
                    title: s.isYou ? "\(s.name) (you)" : s.name, subtitle: "\(s.roleTitle) · \(lock)", trailing: String(format: "%.1f%%", s.pct))
            if let offer {
                Text("You offered \(cur.tidyDisplay(offer.price)) for their shares. Waiting for their answer until \(JVClock.text(Date(timeIntervalSince1970: offer.expiresAt))).")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    let done: Bool = store.act { (g: inout GameEngine) -> Bool in g.jvWithdrawBuyBack(companyID: id, offerID: offer.id) } ?? false
                    if done { store.tell("Offer withdrawn", "\(s.name) keeps their shares. Nothing has changed.") }
                } label: { Text("Withdraw offer") }
                    .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                    .accessibilityIdentifier("jv-buyback-withdraw")
            } else if !s.isYou && !s.locked {
                Button { askBuyOut(s) } label: { Text("Offer to buy \(s.name)'s shares") }
                    .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                    .accessibilityIdentifier("jv-buyback")
            }
        }
    }

    private func askBuyOut(_ s: JointVenture.Stake) {
        guard let terms: JointVenture.ExitTerms = engine.jvExitTerms(companyID: company.id, memberID: s.id) else { return }
        if let why = terms.problem { Haptics.warning(); store.tell("Not now", why, tone: "warn"); return }
        Haptics.tap()
        buyTarget = BuyTarget(id: s.id)
    }

    private func meetingsRow(_ st: JointVenture.State, waiting: Int) -> some View {
        let next: String = st.members.count > 1 ? "Next board meeting \(JVClock.text(engine.jvNextMeeting()))" : "The board meets weekly once a partner has joined"
        return Button { Haptics.tap(); meetingsOpen = true } label: {
            ListRow(symbol: "calendar", tint: waiting > 0 ? Theme.warn : Theme.accent, title: "Meetings", subtitle: waiting > 0 ? "\(waiting) waiting for your vote" : next,
                    trailing: waiting > 0 ? "Vote" : "", chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jv-meetings")
    }
}

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
        Text("They see this share and this price, and accept or decline. Other friends you invite get a price of their own.").popupText(.caption)
        Text("Role").capsLabel()
        SegmentedPill(items: ["Partner", "CFO"], title: { $0 }, selection: $role)
        if (e.jointVenture(companyID: companyID)?.members.count ?? 1) > 1 {
            Text("You have partners, so the invitation goes out only if more than half of all shares vote for it at an emergency meeting.").popupText(.risk)
        }
        Color.clear.frame(height: 0)
            .popupFooter {
                PopupFooter(cancel: "Cancel", action: "See what they will read", onCancel: { dismiss() }, onAction: { Haptics.tap(); preview = true }, actionEnabled: picked != nil, actionID: "jv-preview")
            }
    }

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
            store.tell("Invitation sent", "\(friend.displayName) has the offer: \(Int(p))% of the company for the price you set. They have \(JVRules.inviteWeeks) weeks to answer. Once they accept they pay, and cannot sell for \(JVRules.lockUpWeeks) weeks.", tone: "good")
        case .needsVote(let meetingID)?:
            Haptics.success()
            _ = meetingID
            dismiss()
            store.tell("Put to the partners", "You already have partners, so \(friend.displayName) is invited only if the vote passes. An emergency meeting is open; your partners have 24 hours to vote.")
        case .refused(let why)?:
            Haptics.warning()
            store.tell("Not sent", why, tone: "warn")
        case nil:
            break
        }
    }
}

struct JVBuybackSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var memberID: String
    @State private var factor: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let e = store.engine, let co = e.state.company(companyID), let terms = e.jvExitTerms(companyID: companyID, memberID: memberID) {
                let cur: Currency = e.currency(for: co)
                let band: ClosedRange<Double> = e.state.worldRules.ventureBand
                let price: Double = offerPrice(terms.price, band)
                ForEach(Array(terms.lines.enumerated()), id: \.offset) { pair in
                    Text(pair.element).popupText(.body)
                }
                Text("Your offer").capsLabel()
                LedgerSlider(value: $factor, in: band, step: 0.05, valueText: cur.tidyDisplay(price))
                Text("Their shares are worth \(cur.tidyDisplay(terms.price)) now. A higher offer is more likely to be accepted. The offer stays open for a week unless you withdraw it.")
                    .popupText(.caption)
                Color.clear.frame(height: 0)
                    .popupFooter {
                        PopupFooter(cancel: "Cancel", action: "Send offer of \(cur.tidyDisplay(price))", onCancel: { dismiss() }, onAction: { send(price, terms.name) }, actionID: "jv-buyback-send")
                    }
            } else {
                Text("That partner is no longer here.").popupText(.body)
            }
        }
    }

    private func offerPrice(_ fair: Double, _ band: ClosedRange<Double>) -> Double {
        min(max((fair * factor).rounded(), (fair * band.lowerBound).rounded(.up)), (fair * band.upperBound).rounded(.down))
    }

    private func send(_ price: Double, _ name: String) {
        let id: Int = companyID
        let member: String = memberID
        let problem: String? = store.act { (g: inout GameEngine) -> String? in g.jvOfferBuyBack(companyID: id, memberID: member, price: price) } ?? nil
        if let problem { Haptics.warning(); store.tell("Not sent", problem, tone: "warn"); return }
        Haptics.success()
        dismiss()
        store.tell("Offer sent", "\(name) has your offer. Nothing moves until they accept; they may also decline.", tone: "good")
        Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
    }
}
