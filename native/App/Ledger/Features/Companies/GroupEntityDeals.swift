import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

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

    private func ownable(_ cos: [Company]) -> [Company] {
        cos.filter { (c: Company) -> Bool in !engine.isBranch(companyID: c.id) }
    }

    @ViewBuilder private func branchNote(_ cos: [Company]) -> some View {
        let n: Int = cos.filter { (c: Company) -> Bool in engine.isBranch(companyID: c.id) }.count
        if n > 0 {
            Text(n == cos.count ? "A branch has no shares: close or sell it on the chain page." : "\(n) \(n == 1 ? "branch has" : "branches have") no shares: close or sell on the chain page.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func owners(_ cos: [Company]) -> some View {
        let list: [Company] = ownable(cos)
        if list.isEmpty {
            EmptyState(glyph: Glyph.person, title: "You own this outright", message: "Sell shares to bring in owners.", centered: false)
        }
        ForEach(list) { (c: Company) in
            if list.count > 1 { Text(c.name.uppercased()).capsLabel() }
            CompanyOwnershipSection(engine: engine, company: c, mode: .owners)
        }
        branchNote(cos)
    }

    @ViewBuilder private func sell(_ cos: [Company]) -> some View {
        let sellable: [Company] = cos.filter { (c: Company) -> Bool in !engine.isBranch(companyID: c.id) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(sellable) { (c: Company) in
                if sellable.count > 1 { Text(c.name.uppercased()).capsLabel() }
                CompanySaleSection(engine: engine, company: c)
            }
            branchNote(cos)
        }
    }

    @ViewBuilder private func raise(_ cos: [Company]) -> some View {
        let list: [Company] = ownable(cos)
        if list.isEmpty {
            EmptyState(glyph: Glyph.lock, title: "Nothing to raise here", message: "A chain's stores raise money as one company.", centered: false)
        }
        ForEach(list) { (c: Company) in
            if list.count > 1 { Text(c.name.uppercased()).capsLabel() }
            CompanyOwnershipSection(engine: engine, company: c, mode: .raise)
        }
        branchNote(cos)
    }

    @ViewBuilder private func offers(_ cos: [Company]) -> some View {
        let franchisors: [Company] = cos.filter { (c: Company) -> Bool in engine.isFranchisor(companyID: c.id) }
        let ids: Set<Int> = Set(cos.map { (c: Company) -> Int in c.id })
        let asks: [Message] = engine.state.inbox.filter { (m: Message) -> Bool in m.status == "open" && ids.contains(m.companyID) && Self.isOwnerOffer(m) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if asks.isEmpty && franchisors.isEmpty {
                EmptyState(glyph: Glyph.inbox, title: "No offers right now")
            }
            if !asks.isEmpty { bids(asks) }
            if !franchisors.isEmpty { applicants(franchisors) }
            HostingSection(engine: engine)
        }
    }

    static let ownerActions: Set<String> = ["g27bid", "own27"]
    static let ownerDecisions: Set<String> = ["s_acqoffer", "e_merger", "t_pe", "t_auction", "t_activist"]
    static func isOwnerOffer(_ m: Message) -> Bool {
        ownerActions.contains(m.actionID) || (m.actionID == StrategicDecisions.action && ownerDecisions.contains(m.value("data")["id"].string))
    }
    @State private var pending: PendingAction?

    private func bids(_ asks: [Message]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("BIDS AND DEMANDS").capsLabel()
            ForEach(asks) { (m: Message) in
                Card(padding: Theme.Space.m, radius: Theme.Radius.row, fill: Theme.surface) {
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

struct GroupBuyRows: View {
    var engine: GameEngine
    var entity: GroupEntity

    var body: some View {
        let brands = engine.franchiseBrands()
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("FRANCHISE BRANDS").capsLabel()
            NavigationLink { FranchisesView() } label: {
                CardRow(glyph: Glyph.group, title: "Brands that take franchisees",
                        subtitle: brands.isEmpty ? "No brand is looking for franchisees right now." : "\(brands.count) \(brands.count == 1 ? "brand" : "brands") \u{00B7} apply, meet them, agree terms",
                        value: brands.isEmpty ? "" : "\(brands.count)")
            }.buttonStyle(PressableStyle())
        }
    }
}
