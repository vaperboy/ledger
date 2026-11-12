import SwiftUI
import GameCore
import Countries
import Events
import Businesses
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
        let until: String = s.lockAt.map { (t: Double) -> String in JVClock.text(Date(timeIntervalSince1970: t)) } ?? GameCalendar.dateString(week: s.lockUntil)
        let lock: String = s.locked ? "Cannot sell or leave until \(until)" : (s.isYou ? "Votes with \(String(format: "%.1f", s.pct))%" : "Free to sell or leave")
        let id: Int = company.id
        return VStack(alignment: .leading, spacing: 4) {
            ListRow(symbol: s.isYou ? "person.fill" : "person", tint: s.isYou ? Theme.accent : Theme.inkSoft,
                    title: s.isYou ? "\(s.name) (you)" : s.name, subtitle: "\(s.roleTitle) · \(lock)", trailing: String(format: "%.1f%%", s.pct))
            if let offer {
                Text("You offered \(cur.tidyDisplay(offer.price)) for their shares. Waiting for their answer until \(JVClock.text(Date(timeIntervalSince1970: offer.expiresAt))).")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    Task { @MainActor in
                        if let why = await JointVentureCoordinator.shared.withdraw(store, companyID: id, offer: offer) {
                            store.tell("Not withdrawn", why, tone: "warn")
                        } else {
                            store.tell("Offer withdrawn", "\(s.name) keeps their shares. Nothing has changed.")
                        }
                    }
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
    @State private var pctText = "20"
    @State private var priceText = ""
    @State private var editingPct = false
    @State private var editingPrice = false

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
        .onChange(of: pct) { _, v in
            if !editingPct { pctText = Self.pctString(v) }
            syncPriceText()
        }
        .onChange(of: factor) { _, _ in syncPriceText() }
        .task {
            JointVentureCoordinator.shared.attach(online.service)
            syncPriceText()
            friends = await JointVentureCoordinator.shared.invitable()
            loaded = true
        }
    }

    private static let pctRange: ClosedRange<Double> = JVRules.smallestStakePercent...JVRules.largestInvitePercent

    private static func pctString(_ v: Double) -> String {
        abs(v - v.rounded()) < 0.05 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    /// Keeps the price box in step with the slider and the share, unless the player is typing in it.
    private func syncPriceText() {
        guard !editingPrice, let e = store.engine, let co = e.state.company(companyID) else { return }
        let cur: Currency = e.currency(for: co)
        priceText = PriceInput.text(privatePrice(e, fair: e.jvFairPrice(companyID: companyID, pct: pct)), currency: cur)
    }

    private func typedPct() -> Double? {
        let t: String = pctText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let v = Double(t), v.isFinite else { return nil }
        return min(max((v * 10).rounded() / 10, Self.pctRange.lowerBound), Self.pctRange.upperBound)
    }

    private func commitPct() {
        editingPct = false
        if let v = typedPct() { pct = v }
        pctText = Self.pctString(pct)
    }

    private func typedPrice(_ e: GameEngine, _ cur: Currency, fair: Double) -> Double? {
        let b: ClosedRange<Double> = band(e)
        return PriceInput.parse(priceText, currency: cur, range: (fair * b.lowerBound)...(fair * b.upperBound))?.value
    }

    private func commitPrice(_ e: GameEngine, _ cur: Currency, fair: Double) {
        editingPrice = false
        if fair > 0, let v = typedPrice(e, cur, fair: fair) { factor = v / fair }
        syncPriceText()
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
        LedgerField(placeholder: "Share", text: $pctText, suffix: "% of the company", keyboard: .decimalPad, identifier: "jv-pct",
                    onFocusChange: { (f: Bool) in if f { editingPct = true } else { commitPct() } }, onSubmit: { commitPct() })
            .onChange(of: pctText) { _, _ in if editingPct, let v = typedPct() { pct = v } }
        LedgerSlider(value: $pct, in: Self.pctRange, step: 1, valueText: "\(Self.pctString(pct))% of the company")
        Text("From \(Int(Self.pctRange.lowerBound))% to \(Int(Self.pctRange.upperBound))% for each friend.").popupText(.caption)
        Text("Their private price").capsLabel()
        LedgerField(placeholder: "Price", text: $priceText, prefix: cur.country.currencySymbol, keyboard: .decimalPad, identifier: "jv-price",
                    onFocusChange: { (f: Bool) in if f { editingPrice = true } else { commitPrice(e, cur, fair: fair) } }, onSubmit: { commitPrice(e, cur, fair: fair) })
            .onChange(of: priceText) { _, _ in
                if editingPrice, fair > 0, let v = typedPrice(e, cur, fair: fair) { factor = v / fair }
            }
        LedgerSlider(value: $factor, in: band(e), step: 0.05, valueText: cur.tidyDisplay(price))
        Text("Fair value of this share: \(cur.tidyDisplay(fair)). You can ask from \(cur.tidyDisplay((fair * band(e).lowerBound).rounded(.up))) to \(cur.tidyDisplay((fair * band(e).upperBound).rounded(.down))).").popupText(.caption)
        summary(friend: picked, pct: pct, price: price, fair: fair, cur: cur)
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

    private func summary(friend: PlayerProfile?, pct: Double, price: Double, fair: Double, cur: Currency) -> some View {
        let who: String = friend?.displayName ?? "Your friend"
        let diff: Double = fair > 0 ? (price / fair - 1) * 100 : 0
        let note: String = abs(diff) < 0.5 ? "the fair value" : (diff < 0 ? "\(Int(abs(diff).rounded()))% under the fair value, a friendly deal that dilutes you" : "\(Int(diff.rounded()))% over the fair value")
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(who) gets \(Self.pctString(pct))% for \(cur.tidyDisplay(price))").popupText(.rowLabel)
            Text("That is \(note).").popupText(.caption)
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
        let sample: Bool = !JointVentureCoordinator.shared.isReal(friend.id)
        let result = store.act { (g: inout GameEngine) -> JointVenture.InviteResult in
            g.jvInvite(companyID: id, playerID: friend.id, name: friend.displayName, linkKey: friend.id, role: cfo ? "cfo" : "partner", mock: sample, pct: p, price: price, myLinkKeys: mine)
        }
        switch result {
        case .sent(let inviteID)?:
            Haptics.success()
            if !sample {
                Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
            } else if let g = store.engine, let offer = JointVentureCoordinator.shared.offer(engine: g, companyID: id, inviteID: inviteID, friendName: friend.displayName, friendID: friend.id, pct: p, price: price) {
                Task { await JointVentureCoordinator.shared.service.send(offer) }
            }
            dismiss()
            store.tell("Invitation sent", "\(friend.displayName) has the offer: \(Int(p))% of the company for the price you set. They have \(JVRules.inviteWeeks) weeks to answer. Once they accept they pay, and cannot sell for \(JVRules.lockUpWeeks) weeks.", tone: "good")
        case .needsVote(let meetingID)?:
            Haptics.success()
            _ = meetingID
            Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
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
