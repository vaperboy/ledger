import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// Everything about who owns an entity, behind a small Owners / Sell / Raise / Offers control: the owners and their mood, every way to sell
/// (one route picker, one offers ladder), raising money and issuing shares, and the offers that come to it (franchise applications, bids,
/// owners' demands, hosting). This is the only place in the app where a company is sold or shares are issued or sold.
struct GroupEntityOwnership: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var part: OwnPart = .owners

    enum OwnPart: String, CaseIterable, Hashable { case owners = "Owners", sell = "Sell", raise = "Raise", offers = "Offers" }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SegmentedPill(items: OwnPart.allCases, title: { (p: OwnPart) -> String in p.rawValue }, selection: $part, identifier: { (p: OwnPart) -> String in "group-ownership-\(p.rawValue)" })
            switch part {
            case .owners: owners(cos)
            case .sell: sell(cos)
            case .raise: raise(cos)
            case .offers: offers(cos)
            }
        }
    }

    /// The companies that have owners to show: limited companies and holdings, one block each.
    private func ownable(_ cos: [Company]) -> [Company] { cos.filter { (c: Company) -> Bool in c.form == .limited || c.type == "hold" } }

    // MARK: Owners

    @ViewBuilder private func owners(_ cos: [Company]) -> some View {
        let list: [Company] = ownable(cos)
        if list.isEmpty {
            Text("You own this outright. Turn it into a limited company to bring in owners.").textStyle(.caption, tint: Theme.inkSoft)
        }
        ForEach(list) { (c: Company) in
            if list.count > 1 { Text(c.name.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold) }
            CompanyOwnershipSection(engine: engine, company: c, mode: .owners)
        }
    }

    // MARK: Sell

    @ViewBuilder private func sell(_ cos: [Company]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(cos) { (c: Company) in
                if cos.count > 1 { Text(c.name.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold) }
                CompanySaleSection(engine: engine, company: c, onGoRaise: { part = .raise })
                if c.form == .limited && c.type != "hold" { CompanyOwnershipSection(engine: engine, company: c, mode: .shares) }
            }
        }
    }

    // MARK: Raise

    @ViewBuilder private func raise(_ cos: [Company]) -> some View {
        let list: [Company] = ownable(cos)
        if list.isEmpty {
            Text("Only a limited company or a holding can raise money from investors.").textStyle(.caption, tint: Theme.inkSoft)
        }
        ForEach(list) { (c: Company) in
            if list.count > 1 { Text(c.name.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold) }
            CompanyOwnershipSection(engine: engine, company: c, mode: .raise)
        }
    }

    // MARK: Offers

    @ViewBuilder private func offers(_ cos: [Company]) -> some View {
        let franchisors: [Company] = cos.filter { (c: Company) -> Bool in engine.isFranchisor(companyID: c.id) }
        let ids: Set<Int> = Set(cos.map { (c: Company) -> Int in c.id })
        let asks: [Message] = engine.state.inbox.filter { (m: Message) -> Bool in m.status == "open" && ids.contains(m.companyID) && Self.isOwnerOffer(m) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if asks.isEmpty && franchisors.isEmpty {
                Text("No bids or demands right now. Bids on listed companies show under Sell.").textStyle(.caption, tint: Theme.inkSoft)
            }
            if !asks.isEmpty { bids(asks) }
            if !franchisors.isEmpty { applicants(franchisors) }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("HOSTING").capsLabel()
                HostingSection(engine: engine)
            }
        }
    }

    /// Inbound offers and owners' demands that used to be answered in the Inbox.
    static let ownerActions: Set<String> = ["g27bid", "own27"]
    static let ownerDecisions: Set<String> = ["s_acqoffer", "e_merger", "t_pe", "t_hostile", "t_ipo", "t_auction", "t_activist"]
    static func isOwnerOffer(_ m: Message) -> Bool {
        ownerActions.contains(m.actionID) || (m.actionID == StrategicDecisions.action && ownerDecisions.contains(m.value("data")["id"].string))
    }
    @State private var pending: PendingAction?

    private func bids(_ asks: [Message]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("BIDS AND DEMANDS").capsLabel()
            ForEach(asks) { (m: Message) in
                Card(padding: Theme.Space.m, radius: Theme.Radius.row) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(engine.displayText(m.title, companyID: m.companyID)).textStyle(.body, tint: Theme.ink, weight: .medium).fixedSize(horizontal: false, vertical: true)
                        Text(engine.displayText(m.body, companyID: m.companyID)).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        WrapRow {
                            ForEach(Array(m.options.enumerated()), id: \.offset) { (i: Int, o: JSONValue) in
                                Button(engine.displayText(o["l"].string, companyID: m.companyID)) { ask(m, i) }.buttonStyle(QuietButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    /// An answer that cannot be undone or spends money is confirmed first, as in the Inbox (`DecisionConfirm`).
    private func ask(_ m: Message, _ i: Int) {
        guard m.options.indices.contains(i) else { return }
        let label: String = engine.displayText(m.options[i]["l"].string, companyID: m.companyID)
        let need: DecisionConfirmation = DecisionConfirm.confirmation(for: m, option: i)
        let mid: Int = m.id
        let run: () -> Void = {
            let ok: Bool = store.act { $0.answer(messageID: mid, option: i) } ?? false
            if ok { Haptics.success(); store.show(label + ".", tone: "good") } else { Haptics.warning(); store.show("That offer has already gone.", tone: "warn") }
        }
        if need.needsQuestion {
            pending = PendingAction(title: label, message: engine.displayText(m.title, companyID: m.companyID), button: label, destructive: need.irreversible, run: run)
        } else { run() }
    }

    private func applicants(_ franchisors: [Company]) -> some View {
        let chains = engine.chainSummaries
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("FRANCHISE OFFERS").capsLabel()
            ForEach(franchisors) { (c: Company) in
                let chain = chains.first { (s: Chains.Summary) -> Bool in s.stores.contains { (l: Chains.StoreLine) -> Bool in l.id == c.id } }
                let cur: Currency = engine.currency(for: c)
                ForEach(engine.franchiseApplicants(companyID: c.id)) { a in
                    NavigationLink { FranchiseTalkView(companyID: c.id, applicantID: a.id) } label: {
                        CardRow(glyph: Glyph.person, title: "\(a.name) applies to \(chain?.name ?? c.name)",
                                subtitle: "\(a.experience) yr experience \u{00B7} own money \(cur.tidyShort(a.capital))", value: "Talk")
                    }.buttonStyle(PressableStyle())
                }
            }
        }
    }
}

// MARK: - Buying (Expansion tab)

/// What you could buy: a rival in the market, or a franchise brand to join. Shown under the Expansion tab; selling and owning are under Ownership.
struct GroupBuyRows: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        let open: [Company] = cos.filter { (c: Company) -> Bool in c.status == .open }
        let brands = engine.franchiseBrands()
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("BUY").capsLabel()
            if open.isEmpty {
                Text("Open this company to look at rivals you could buy.").textStyle(.caption, tint: Theme.inkSoft)
            } else {
                Button { Haptics.tap(); store.openMarket(companyID: entity.companyID) } label: {
                    CardRow(glyph: Glyph.market, title: "Rivals you could buy", subtitle: "Pick a rival in the market; the price and what it becomes are agreed there.")
                }.buttonStyle(PressableStyle())
            }
            NavigationLink { FranchisesView() } label: {
                CardRow(glyph: Glyph.group, title: "Brands that take franchisees",
                        subtitle: brands.isEmpty ? "No brand is looking for franchisees right now." : "\(brands.count) \(brands.count == 1 ? "brand" : "brands") \u{00B7} apply, meet them, agree terms",
                        value: brands.isEmpty ? "" : "\(brands.count)")
            }.buttonStyle(PressableStyle())
        }
    }
}
