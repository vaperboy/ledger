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
    @State private var friendsOpen = false
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
        .centerSheet(isPresented: $inviteOpen, title: "Invite a friend", size: .tall, category: .medium) {
            JVInviteSheet(companyID: company.id, onFindFriends: { friendsOpen = true }).environmentObject(store).environment(online)
        }
        .navigationDestination(isPresented: $meetingsOpen) { JointVentureMeetingsView(companyID: company.id) }
        .navigationDestination(isPresented: $friendsOpen) { FriendsScreen().environmentObject(store).environment(online) }
        .task { JointVentureCoordinator.shared.attach(online.service); await JointVentureCoordinator.shared.sync(store) }
        .centerSheet(item: $buyTarget, title: "Offer for their shares") { (t: BuyTarget) in JVBuybackSheet(companyID: company.id, memberID: t.id).environmentObject(store) }
    }

    private func stakeRow(_ s: JointVenture.Stake, offer: JointVenture.Buyback?, cur: Currency) -> some View {
        let until: String = s.lockAt.map { (t: Double) -> String in JVClock.text(Date(timeIntervalSince1970: t)) } ?? GameCalendar.dateString(week: s.lockUntil)
        let lock: String = s.locked ? "Cannot sell or leave until \(until)" : (s.isYou ? "Votes with \(String(format: "%.1f", s.pct))%" : "Free to sell or leave")
        let id: Int = company.id
        return VStack(alignment: .leading, spacing: 4) {
            partnerLink(s) {
                ListRow(symbol: s.isYou ? "person.fill" : "person", tint: s.isYou ? Theme.accent : Theme.inkSoft,
                        title: s.isYou ? "\(s.name) (you)" : s.name, subtitle: "\(s.roleTitle) · \(lock)", trailing: String(format: "%.1f%%", s.pct))
            }
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

    /// A partner's row opens their player card; your own row has nothing to open.
    @ViewBuilder private func partnerLink<C: View>(_ s: JointVenture.Stake, @ViewBuilder content: @escaping () -> C) -> some View {
        if !s.isYou, s.id.hasPrefix("p:") {
            NavigationLink { PlayerProfileView(playerID: String(s.id.dropFirst(2)), knownName: s.name) } label: { content() }
                .buttonStyle(PressableStyle())
        } else {
            content()
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
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var onFindFriends: () -> Void = {}
    @State private var friends: [PlayerProfile] = []
    @State private var loaded = false
    @State private var picked: PlayerProfile?
    @State private var pct: Double = 20
    @State private var factor: Double = 1
    @State private var role: String = "Partner"
    @State private var search = ""
    @State private var pctText = "20"
    @State private var priceText = ""
    @State private var editingPct = false
    @State private var editingPrice = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if let e = store.engine, let co = e.state.company(companyID) {
                    let cur: Currency = e.currency(for: co)
                    let fair: Double = e.jvFairPrice(companyID: companyID, pct: pct)
                    let price: Double = privatePrice(e, fair: fair)
                    form(e, cur, fair: fair, price: price)
                } else {
                    Text("This company no longer exists.").popupText(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .popupFooter { footer }
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
        abs(v - v.rounded()) < 0.05 ? String(Int(saturating: v.rounded())) : String(format: "%.1f", v)
    }

    private static func firstName(_ p: PlayerProfile) -> String {
        p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName
    }

    /// Keeps the typed price in step with the slider and the share, unless the player is typing it.
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

    private var hasFriends: Bool { !loaded || !friends.isEmpty }

    @ViewBuilder private func form(_ e: GameEngine, _ cur: Currency, fair: Double, price: Double) -> some View {
        if !loaded {
            ProgressView().tint(P.inkSoft).frame(maxWidth: .infinity, minHeight: 120)
        } else if friends.isEmpty {
            Text("Add a friend first, then you can share this company with them.")
                .popupText(.body).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            JVSheetSection(title: "Who") { friendPicker }
            shareSection
            priceSection(e, cur, fair: fair, price: price)
            JVSheetSection(title: "Role") {
                SegmentedPill(items: ["Partner", "CFO"], title: { $0 }, selection: $role)
            }
            if (e.jointVenture(companyID: companyID)?.members.count ?? 1) > 1 {
                Text("Your partners vote on it first.").popupText(.risk)
            }
        }
    }

    /// One row of faces; the search box appears only for a long list.
    @ViewBuilder private var friendPicker: some View {
        if friends.count > 8 {
            LedgerField(placeholder: "Search friends", text: $search, keyboard: .default, identifier: "jv-friend-search")
        }
        let q: String = search.trimmingCharacters(in: .whitespaces)
        let shown: [PlayerProfile] = friends.filter { (p: PlayerProfile) -> Bool in q.isEmpty || p.displayName.localizedCaseInsensitiveContains(q) }
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(shown) { (p: PlayerProfile) in friendChip(p) }
            }
            .padding(.vertical, Theme.Space.xxs)
        }
        .scrollIndicators(.hidden)
    }

    private func friendChip(_ p: PlayerProfile) -> some View {
        let on: Bool = picked?.id == p.id
        return Button { Haptics.tap(); picked = p } label: {
            VStack(spacing: Theme.Space.xs) {
                PlayerAvatar(player: p, size: 46)
                    .padding(3)
                    .overlay(Circle().strokeBorder(on ? P.accent : Color.clear, lineWidth: 2))
                Text(Self.firstName(p))
                    .textStyle(.caption, tint: on ? P.accent : P.inkSoft, weight: on ? .semibold : .regular).lineLimit(1)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(p.displayName)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var shareSection: some View {
        JVSheetSection(title: "Share", trailing: {
            TapToTypeValue(shown: "\(Self.pctString(pct))%", text: $pctText, suffix: "%", identifier: "jv-pct",
                           onBegin: { pctText = Self.pctString(pct); editingPct = true }, onCommit: { commitPct() })
                .onChange(of: pctText) { _, _ in if editingPct, let v = typedPct() { pct = v } }
        }) {
            LedgerSlider(value: $pct, in: Self.pctRange, step: 1)
                .accessibilityLabel("Share")
                .accessibilityValue("\(Self.pctString(pct))%")
        }
    }

    private func priceSection(_ e: GameEngine, _ cur: Currency, fair: Double, price: Double) -> some View {
        let b: ClosedRange<Double> = band(e)
        return JVSheetSection(title: "Price", trailing: {
            TapToTypeValue(shown: cur.tidyDisplay(price), text: $priceText, prefix: cur.country.currencySymbol, identifier: "jv-price",
                           onBegin: { editingPrice = true }, onCommit: { commitPrice(e, cur, fair: fair) })
                .onChange(of: priceText) { _, _ in
                    if editingPrice, fair > 0, let v = typedPrice(e, cur, fair: fair) { factor = v / fair }
                }
        }) {
            LedgerSlider(value: $factor, in: b, step: 0.05)
                .overlay { FairTick(range: b) }
                .accessibilityLabel("Price")
                .accessibilityValue(cur.tidyDisplay(price))
        }
    }

    private var summaryLine: String {
        guard let e = store.engine, let f = picked, let co = e.state.company(companyID) else { return "Pick a friend" }
        let fair: Double = e.jvFairPrice(companyID: companyID, pct: pct)
        return "\(Self.firstName(f)) gets \(Self.pctString(pct))% for \(e.currency(for: co).tidyDisplay(privatePrice(e, fair: fair)))"
    }

    @ViewBuilder private var footer: some View {
        if hasFriends {
            Text(summaryLine)
                .textStyle(.body, tint: picked == nil ? P.inkSoft : P.ink, numeric: true, weight: .medium)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            PopupFooter(cancel: "Cancel", action: "Send offer", onCancel: { dismiss() }, onAction: { if let f = picked { send(f) } }, actionEnabled: picked != nil, actionID: "jv-send")
        } else {
            PopupFooter(cancel: "Cancel", action: "Find friends", onCancel: { dismiss() }, onAction: { dismiss(); onFindFriends() }, actionID: "jv-find-friends")
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

/// A rounded inner section with a small caps label; `trailing` holds the section's one value.
private struct JVSheetSection<Trailing: View, Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center) {
                Text(title).capsLabel()
                Spacer(minLength: Theme.Space.s)
                trailing()
            }
            .frame(minHeight: 28)
            content()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PopupRadius.inner, style: .continuous).fill(P.inset))
    }
}

extension JVSheetSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// A value shown once; tapping it turns it into a number field, and leaving the field commits it.
private struct TapToTypeValue: View {
    @Environment(\.outsidePalette) private var P
    var shown: String
    @Binding var text: String
    var prefix: String? = nil
    var suffix: String? = nil
    var identifier: String
    var onBegin: () -> Void
    var onCommit: () -> Void
    @State private var typing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if typing {
                HStack(spacing: Theme.Space.xs) {
                    if let prefix { Text(prefix).textStyle(.headline, tint: P.inkSoft) }
                    TextField("", text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .multilineTextAlignment(.trailing)
                        .textStyle(.headline, numeric: true)
                        .frame(minWidth: 48, maxWidth: 140)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier(identifier)
                        .onAppear { DispatchQueue.main.async { focused = true } }
                    if let suffix { Text(suffix).textStyle(.headline, tint: P.inkSoft) }
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: 36)
                .background(Capsule().fill(P.page))
                .overlay(Capsule().strokeBorder(P.focus, lineWidth: 1))
            } else {
                Button { Haptics.tap(); onBegin(); typing = true } label: {
                    Text(shown)
                        .textStyle(.headline, numeric: true)
                        .padding(.horizontal, Theme.Space.m)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(P.page))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier(identifier)
                .accessibilityHint("Double tap to type a value")
            }
        }
        .onChange(of: focused) { _, f in
            if !f && typing { typing = false; onCommit() }
        }
    }
}

/// A small mark under a LedgerSlider's track where the fair value (factor 1) sits.
private struct FairTick: View {
    @Environment(\.outsidePalette) private var P
    var range: ClosedRange<Double>

    var body: some View {
        let span: Double = range.upperBound - range.lowerBound
        if span > 0, range.contains(1) {
            let f: CGFloat = CGFloat((1 - range.lowerBound) / span)
            GeometryReader { (g: GeometryProxy) in
                let thumb: CGFloat = 22
                Capsule().fill(P.inkSoft)
                    .frame(width: 2, height: 7)
                    .position(x: thumb / 2 + max(1, g.size.width - thumb) * f, y: g.size.height / 2 + 15)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
