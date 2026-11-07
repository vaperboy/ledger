import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// The ways to sell a company or part of it, in one place (Group > Ownership > Sell). Every route ends in the same engine sale (`CompanySale`):
/// a handshake, a broker, an auction with a reserve, a management buyout, a merger with a rival, a sale to a rival group, a stake of 10 to 49%,
/// going public (holdings), and the master franchise of a country. A route that is shut says why.
struct SaleRoutePicker: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    /// IPO and share issues live under Raise: the picker points there.
    var onGoRaise: () -> Void = {}
    @State private var pending: PendingAction?
    @State private var sheet: RouteSheet?
    @State private var brokerStake = false

    enum RouteSheet: String, Identifiable { case auction, merger, group, stake, franchise; var id: String { rawValue } }

    var body: some View {
        let routes: [CompanySale.Route] = engine.saleRoutes(companyID: company.id)
        let open: [CompanySale.Route] = routes.filter { (r: CompanySale.Route) -> Bool in r.available }
        let shut: [CompanySale.Route] = routes.filter { (r: CompanySale.Route) -> Bool in !r.available }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("How do you want to sell?").textStyle(.title)
                Text("Listing is not a sale: nothing sells until you accept an offer or hammer a bid.")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            if open.isEmpty {
                EmptyState(glyph: Glyph.lock, title: "No way to sell is open now", message: "Each route below says what it needs.", centered: false)
            } else {
                routeList(open)
            }
            if !shut.isEmpty {
                LedgerSection("Not open now") { routeList(shut) }
            }
        }
        .confirmAction($pending)
        .centerSheet(item: $sheet) { (s: RouteSheet) in sheetContent(s) }
    }

    /// Routes as calm rows under hairlines: an open route opens its step, a shut one says why (its subtitle) and is not a link.
    private func routeList(_ list: [CompanySale.Route]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, r: CompanySale.Route) in
                if n > 0 { Hairline() }
                LedgerRow(leading: .glyph(glyph(r.id)), leadingTint: r.available ? nil : Theme.inkFaint, title: r.title,
                          subtitle: r.available ? r.pitch : r.why, chevron: r.available, lineLimit: 3,
                          identifier: "sell-route-\(r.id)", action: { pick(r) })
            }
        }
    }

    private func glyph(_ id: String) -> String {
        switch id {
        case "auction": return Glyph.achievements
        case "merger", "group": return Glyph.group
        case "ipo": return Glyph.bank
        case "franchise": return Glyph.world
        case "stake": return Glyph.arrowOut
        default: return Glyph.person
        }
    }

    private func pick(_ r: CompanySale.Route) {
        guard r.available else { store.show(r.why, tone: "warn"); return }
        switch r.id {
        case "private", "broker", "mbo": startListing(r.id)
        case "auction": sheet = .auction
        case "merger": sheet = .merger
        case "group": sheet = .group
        case "stake": sheet = .stake
        case "ipo": onGoRaise()
        case "franchise": sheet = .franchise
        default: break
        }
    }

    private func startListing(_ route: String) {
        let id: Int = company.id
        let name: String = company.name
        let ok: Bool = store.act { $0.startSale(companyID: id, route: route) } ?? false
        if ok {
            let how: String = route == "broker" ? "through a broker" : route == "mbo" ? "to your manager" : "quietly"
            store.show("\(name) is on the market \(how). Offers arrive over the coming weeks.", tone: "n")
        } else { Haptics.warning(); store.show("It could not be put on the market now.", tone: "warn") }
    }

    // MARK: The sheets

    @ViewBuilder private func sheetContent(_ s: RouteSheet) -> some View {
        switch s {
        case .auction: auctionSheet
        case .merger: mergerSheet
        case .group: groupSheet
        case .stake: stakeSheet
        case .franchise: franchiseSheet
        }
    }

    private var auctionSheet: some View {
        let cur: Currency = engine.currency(for: company)
        let value: Double = CompanySale.estimatedValue(engine.state, companyID: company.id, data: engine.data)
        let mine: Double = company.ownership / 100
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Worth about " + cur.tidyShort(value * mine)).popupText(.figure)
            Text("Name the lowest price you accept. Three weekly rounds of bids follow: bids rise about 7% a round, but a bidder may drop out. Hammer the top bid at any time, or wait. Fee 4%; staff hear about it.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            ForEach([0.7, 0.85, 1.0], id: \.self) { (f: Double) in
                let reserve: Double = (value * f / 1000).rounded() * 1000
                ChoiceCard(title: "Reserve " + cur.tidyShort(reserve * mine), subtitle: f >= 1 ? "Bold: fewer bidders clear it" : f >= 0.85 ? "Balanced" : "Safe: most bidders clear it", selected: false) {
                    sheet = nil
                    let id: Int = company.id
                    let ok: Bool = store.act { $0.startAuction(companyID: id, reserve: reserve) } ?? false
                    if ok { Haptics.success(); store.show("The auction has opened. Watch the bids come in.", tone: "good") } else { Haptics.warning(); store.show("It could not be put to auction now.", tone: "warn") }
                }
            }
        }
        .centerSheetTitle("Auction")
    }

    private var mergerSheet: some View {
        let rivals: [CompanySale.MergeCandidate] = engine.mergeCandidates(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("The rival joins your company (more size, more customers). Its owner takes a share of the merged company; you keep the rest and the control. Less than 30% may be turned down.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            if rivals.isEmpty { EmptyState(title: "No rival to merge with", message: "No rival in this trade and city is open to a merger now.", centered: false) }
            ForEach(Array(rivals.enumerated()), id: \.element.id) { (n: Int, r: CompanySale.MergeCandidate) in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(r.name).popupText(.rowValue)
                        Text("Owned by \(r.owner)").popupText(.caption)
                    }
                    WrapRow(spacing: Theme.Space.s) {
                        ForEach([20, 25, 30], id: \.self) { (p: Int) in
                            Button("Offer \(p)%") { merge(r, p) }.buttonStyle(SecondaryButtonStyle(size: .compact, tint: p == 30 ? Theme.accent : nil))
                        }
                    }
                }
                .padding(.vertical, Theme.Space.s)
                .overlay(alignment: .top) { if n > 0 { Hairline() } }
            }
        }
        .centerSheetTitle("Merge with a rival")
    }

    private func merge(_ r: CompanySale.MergeCandidate, _ p: Int) {
        let cid: Int = company.id
        let rid: Int = r.id
        let name: String = r.name
        sheet = nil
        pending = PendingAction(title: "Merge with \(name)?", message: "\(r.owner) gets \(p)% of \(company.name). You take over its customers and sites. Gains are not taxed, but you share ownership and the competition authority may look at it. This cannot be undone.",
                                button: "Merge", destructive: true) {
            switch store.act({ $0.mergeWithRival(companyID: cid, rivalID: rid, percent: Double(p)) }) {
            case .merged?: Haptics.success(); store.show("Merged with \(name).", tone: "good")
            case .declined?: Haptics.warning(); store.show("\(p)% was not enough for them. Try again, or offer more.", tone: "warn")
            case .refused(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    private var groupSheet: some View {
        let cur: Currency = engine.currency(for: company)
        let buyers: [CompanySale.GroupBuyer] = engine.groupBuyers(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("A rival group buys at its own quote and the company becomes one of its sites. Quotes move week to week.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            if buyers.isEmpty { EmptyState(title: "No group is buying here", message: "No rival group is active in this country.", centered: false) }
            ForEach(buyers) { (b: CompanySale.GroupBuyer) in
                let mine: Double = b.price * company.ownership / 100
                ChoiceCard(title: b.name, subtitle: "Pays " + cur.tidyShort(mine) + " for your share", selected: false) { sellToGroup(b, mine, cur) }
            }
        }
        .centerSheetTitle("Sell to a rival group")
    }

    private func sellToGroup(_ b: CompanySale.GroupBuyer, _ mine: Double, _ cur: Currency) {
        let cid: Int = company.id
        let gid: String = b.id
        sheet = nil
        pending = PendingAction(title: "Sell \(company.name) to \(b.name)?", message: "\(b.name) pays " + cur.tidyDisplay(mine) + ". The staff (\(company.staff.count.peopleText)) leave your payroll and loans are settled. Gains are taxed. This cannot be undone.",
                                button: "Sell for " + cur.tidyShort(mine), destructive: true) {
            let got: Double? = store.act { $0.sellToGroup(companyID: cid, groupID: gid) } ?? nil
            if got != nil { Haptics.success(); store.show("\(company.name) is sold.", tone: "good") } else { Haptics.warning(); store.show("The sale did not go through: the other owners may be blocking it.", tone: "warn") }
        }
    }

    private var stakeSheet: some View {
        let tiers: [CompanySale.StakeTier] = engine.stakeTiers(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Sell part of your shares and keep running it. Each step gives the buyer more.").popupText(.caption)
            SegmentedPill(items: [false, true], title: { (b: Bool) -> String in b ? "Broker (4%)" : "Quietly" }, selection: $brokerStake)
            ForEach(tiers) { (t: CompanySale.StakeTier) in
                ChoiceCard(title: "\(t.pct)% of your shares", subtitle: "You keep \(Int(t.youKeep.rounded()))%. " + t.unlocks.joined(separator: " "), selected: false) { listStake(t) }
                    .disabled(!t.allowed)
            }
        }
        .centerSheetTitle("Sell a stake")
    }

    private func listStake(_ t: CompanySale.StakeTier) {
        let id: Int = company.id
        let p: Int = t.pct
        let route: String = brokerStake ? "broker" : "private"
        sheet = nil
        let ok: Bool = store.act { $0.startSale(companyID: id, route: route, percent: p) } ?? false
        if ok { store.show("\(p)% listed. Offers arrive over the coming weeks.", tone: "good") } else { Haptics.warning(); store.show("Not possible now: it may already be listed, or would cost you control.", tone: "warn") }
    }

    private var franchiseSheet: some View {
        let masters: [JSONValue] = company.value("fr")["masters"].array
        let countries: [Country] = engine.masterFranchiseCountries(companyID: company.id).filter { (c: Country) -> Bool in !masters.contains { (m: JSONValue) -> Bool in m["c"].string == c.code } }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Sign over the franchise rights of a country to a master franchisee. It costs legal work and cannot be undone.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            if countries.isEmpty { EmptyState(title: "Nothing left to sign", message: "Every country you could sell is already taken.", centered: false) }
            ForEach(countries) { (c: Country) in
                ChoiceCard(title: "\(c.flag) \(c.name)", subtitle: "Master franchise", selected: false) { sellMaster(c) }
            }
        }
        .centerSheetTitle("Master franchise")
    }

    private func sellMaster(_ c: Country) {
        let id: Int = company.id
        let code: String = c.code
        sheet = nil
        pending = PendingAction(title: "Sell the master franchise for \(c.name)?", message: "You sign over the franchise rights for this country. It costs legal work and cannot be undone.", button: "Sell master franchise", destructive: true) {
            switch store.act({ $0.sellMasterFranchise(companyID: id, country: code) }) {
            case .ok?: Haptics.success(); store.show("Master franchise signed.", tone: "good")
            case .cash?: store.show("Not enough cash for the legal work.", tone: "warn")
            case .banned(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            default: Haptics.warning(); store.show("Not possible.", tone: "warn")
            }
        }
    }
}
