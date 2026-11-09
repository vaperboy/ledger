import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

extension CompanySourcing {
    static func isAvailable(engine: GameEngine, company: Company) -> Bool {
        engine.hasSupplyLines(companyID: company.id)
    }
}

struct SupplyPick: Identifiable, Equatable, Hashable { var id: String }

struct CompanySupply: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var choosing: SupplyPick?
    @State private var ordering = false
    @State private var showSell = false
    @State private var showAssociation = false
    @State private var showTerms = false

    var body: some View {
        let groups: [SupplyGroup] = engine.supplyLines(companyID: company.id)
        let cur: Currency = engine.currency(for: company)
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("What this company needs each week, and who supplies it.").textStyle(.body, tint: P.inkSoft)
            if groups.isEmpty {
                EmptyState(glyph: Glyph.suppliers, title: "Buys nothing from suppliers", message: "What the business buys shows here once it is open.", centered: false)
            } else {
                ForEach(groups) { (g: SupplyGroup) in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(g.name).textStyle(.label, tint: P.inkFaint)
                        ForEach(g.rows) { (r: SupplyRow) in
                            NeedCard(row: r, currency: cur, contract: market.service.contract(buyerCompanyID: company.id, lineID: r.id),
                                     listing: market.service.contract(buyerCompanyID: company.id, lineID: r.id).flatMap { market.service.listing($0.listingID) }) {
                                choosing = SupplyPick(id: r.id)
                            }
                        }
                    }
                }
                InTransitSection(rows: engine.shipmentsOnTheWay(companyID: company.id), currency: cur)
            }
            more
        }
        .navigationDestination(item: $choosing) { (p: SupplyPick) in SupplierChooserPage(companyID: company.id, lineID: p.id).environmentObject(store) }
        .navigationDestination(isPresented: $ordering) {
            SettingsPage(title: "Order stock", subtitle: company.name) { StockOrderPopup(companyID: company.id, onDone: { ordering = false }).environmentObject(store) }
        }
        .navigationDestination(isPresented: $showSell) { SupplyOtherPlayersScreen(companyID: company.id).environmentObject(store) }
        .navigationDestination(isPresented: $showAssociation) { TradeAssociationScreen(companyID: company.id).environmentObject(store) }
        .navigationDestination(isPresented: $showTerms) {
            SettingsPage(title: "Terms and deals", subtitle: company.name) { CompanySourcing(engine: engine, company: company) }
        }
        .task { market.sync(store) }
        .onChange(of: store.engine?.state.week) { _, _ in market.sync(store) }
    }

    private var more: some View {
        PageGroup("More") {
            if engine.stockOrderBasis(companyID: company.id) != nil {
                LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Order stock once",
                          subtitle: "Compare price and transport, then order", identifier: "suppliers-order") { ordering = true }
                RowRule()
            }
            LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Supply other players",
                      subtitle: "Offer what this company makes", identifier: "suppliers-sell") { showSell = true }
            RowRule()
            LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Trade association",
                      subtitle: TradeAssociations.membership(engine.state, companyID: company.id).map { "Member of \($0.club.name)" } ?? "Join for group buying",
                      identifier: "suppliers-association") { showAssociation = true }
            if CompanySourcing.isAvailable(engine: engine, company: company) {
                RowRule()
                LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Payment terms and deals",
                          subtitle: "How you pay and what you can negotiate", identifier: "suppliers-terms") { showTerms = true }
            }
        }
    }
}

private struct NeedCard: View {
    @Environment(\.outsidePalette) private var P
    var row: SupplyRow
    var currency: Currency
    var contract: SupplyContract?
    var listing: SupplyListing?
    var onChange: () -> Void

    private var late: Bool { row.note != nil }

    private var supplierName: String { contract?.supplierName ?? row.current }

    private var recordText: String {
        if let r = listing?.record {
            return r.ordersTotal == 0 ? "No orders delivered yet" : "Delivered \(SupplyMarketWords.percent(r.deliveredShare)) of orders"
        }
        return "\(row.reliability) supply"
    }

    private var canChange: Bool {
        row.governed == nil && (row.canSwitch || !SupplyMarketCatalogue.tradesSupplying(line: row.id).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(row.title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Chip(text: late ? "Late" : "On time", tint: late ? P.loss : P.gain)
            }
            Hairline()
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(supplierName.tidyText).textStyle(.body).lineLimit(2).multilineTextAlignment(.leading)
                    Text(recordText).textStyle(.caption, tint: P.inkSoft)
                    Text(row.weekly.map { "About " + currency.tidyShort($0) + " a week" } ?? "Billed per job").textStyle(.caption, tint: P.inkFaint, numeric: true)
                }
                Spacer(minLength: Theme.Space.s)
                if canChange {
                    Button("Change") { Haptics.tap(); onChange() }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                        .accessibilityIdentifier("supply-change-\(row.id)")
                }
            }
            if let why = row.governed ?? row.note {
                Text(why.tidyText).textStyle(.caption, tint: row.governed != nil ? P.inkFaint : P.caution).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
        .accessibilityElement(children: .contain)
    }
}

private enum SupplyWay: Int, CaseIterable, Hashable {
    case trusted, cheapest, random
    var title: String { self == .trusted ? "Trusted" : self == .cheapest ? "Cheapest" : "Random pick" }
}

private struct Candidate: Identifiable {
    var id: String
    var name: String
    var record: String
    var trust: Double
    var cost: Double
    var distance: String
    var price: String
    var extra: String
    var isCurrent: Bool
    var note: String?
    var canUse: Bool
    var listing: SupplyListing?
    var offer: SupplyOfferRow?
}

struct SupplierChooserPage: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var lineID: String
    @State private var way: SupplyWay = .trusted
    @State private var opened: String?
    @State private var drawn: String?
    @State private var draws = 0
    @State private var message: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == lineID }) {
            content(e, co, row)
        } else {
            EmptyState(glyph: Glyph.suppliers, title: "This need is gone").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ row: SupplyRow) -> some View {
        let cur: Currency = e.currency(for: co)
        let all: [Candidate] = candidates(e, row, cur)
        let shown: [Candidate] = list(all, way)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("Choose who supplies \(row.title.lowercased()).").textStyle(.body, tint: P.inkSoft)
                if row.id == "goods" { goodsTier(co) }
                if let g = row.governed {
                    Text(g.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true)
                }
                SegmentedPill(items: SupplyWay.allCases, title: { (w: SupplyWay) -> String in w.title }, selection: $way, identifier: { (w: SupplyWay) -> String in "supply-way-\(w.rawValue)" })
                if way == .random { randomBar(e, row, all) }
                if let message { Text(message).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true) }
                if shown.isEmpty {
                    Text(way == .random ? "Draw a supplier to see one." : "No other supplier offers this yet.").textStyle(.body, tint: P.inkFaint)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { (n: Int, c: Candidate) in
                            if n > 0 { Hairline() }
                            candidateRow(c, row, e, co, cur, locked: row.governed != nil)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .appScreen(title: row.title, subtitle: co.name, tab: .company)
        .task { market.sync(store) }
    }

    private func goodsTier(_ co: Company) -> some View {
        let raw: JSONValue = co.value("src")["c"]
        let now: Int = min(2, max(0, raw.isNull ? 1 : raw.int))
        let binding = Binding<Int>(get: { now }, set: { (v: Int) in
            _ = store.act { $0.chooseGoodsClass(companyID: companyID, goodsClass: v) }
            Haptics.tap()
        })
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Quality").textStyle(.label, tint: P.inkFaint)
            SegmentedPill(items: [0, 1, 2], title: { (i: Int) -> String in Suppliers.goodsClassNames[i] }, selection: binding)
        }
    }

    private func randomBar(_ e: GameEngine, _ row: SupplyRow, _ all: [Candidate]) -> some View {
        let pool: [Candidate] = all.filter { $0.canUse && !$0.isCurrent }
        return Button {
            Haptics.tap()
            draw(pool)
        } label: {
            Text(drawn == nil ? "Draw a supplier" : "Draw another")
        }
        .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: P.accent))
        .disabled(pool.isEmpty || draws >= 3)
        .accessibilityIdentifier("supply-draw")
    }

    private func draw(_ pool: [Candidate]) {
        let others: [Candidate] = pool.filter { $0.id != drawn }
        guard let pick = (others.isEmpty ? pool : others).randomElement() else { return }
        drawn = pick.id
        draws += 1
        opened = nil
        message = nil
    }

    private func list(_ all: [Candidate], _ w: SupplyWay) -> [Candidate] {
        switch w {
        case .trusted: return all.sorted { (a: Candidate, b: Candidate) -> Bool in a.trust != b.trust ? a.trust > b.trust : a.name < b.name }
        case .cheapest: return all.sorted { (a: Candidate, b: Candidate) -> Bool in a.cost != b.cost ? a.cost < b.cost : a.name < b.name }
        case .random: return all.filter { $0.id == drawn }
        }
    }

    private func trustScore(_ word: String) -> Double {
        switch word {
        case "Dependable": return 0.95
        case "Steady": return 0.85
        case "Patchy": return 0.6
        default: return 0.5
        }
    }

    private func candidates(_ e: GameEngine, _ row: SupplyRow, _ cur: Currency) -> [Candidate] {
        let today: Int = SupplyMarketStore.today(e)
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: companyID, lineID: lineID)
        var out: [Candidate] = []
        for o in row.offers {
            let current: Bool = o.isCurrent && contract == nil
            var cost: Double = 1
            if let w = o.weekly, let base = row.weekly, base > 0 { cost = w / base }
            out.append(Candidate(id: "o:" + o.id, name: o.name, record: "\(o.reliability) supply", trust: trustScore(o.reliability), cost: cost, distance: "",
                                 price: o.weekly.map { "About " + cur.tidyShort($0) + " a week" } ?? "Billed per job", extra: "\(o.lead) \u{00B7} \(o.terms)",
                                 isCurrent: current, note: o.blocked, canUse: o.blocked == nil && !current, listing: nil, offer: o))
        }
        if row.governed == nil && !SupplyMarketCatalogue.tradesSupplying(line: row.id).isEmpty {
            let wanted: [SupplyListing] = market.service.listings(lineID: row.id).filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
            let landed: [String: SupplyLanded.Row] = SupplyLandedBasis.lookup(SupplyLandedBasis.rows(e, companyID: companyID, listings: wanted, weekly: row.weekly))
            for l in wanted {
                let a: SupplyAvailability = SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: max(l.minOrder, SupplyLandedBasis.compareUnits), today: today)
                let r: SupplyLanded.Row? = landed[l.id]
                let share: Double = l.record.ordersTotal == 0 ? 0.5 : l.record.deliveredShare
                let record: String = l.record.ordersTotal == 0 ? "No orders delivered yet" : "Delivered \(SupplyMarketWords.percent(l.record.deliveredShare)) of orders"
                var price: String = SupplyMarketWords.price(l.priceTier)
                var extra: String = ""
                var distance: String = SupplyMarketWords.place(l)
                let cost: Double = l.priceFactor * (r?.landedFactor ?? 1)
                if let r {
                    price = cur.tidyShort(r.unitPrice) + " a unit"
                    extra = r.mode == nil ? "No transport" : "+ " + cur.tidyShort(r.freightPerUnit + r.customsPerUnit) + " transport"
                    distance = r.mode == nil ? "Delivered as a service" : "\(Int(saturating: r.distanceKm.rounded())) km" + (r.crossesBorder ? " \u{00B7} abroad" : "")
                }
                let current: Bool = contract?.listingID == l.id
                out.append(Candidate(id: "l:" + l.id, name: l.ownerName, record: record, trust: share, cost: cost, distance: distance, price: price, extra: extra,
                                     isCurrent: current, note: a == .available ? nil : a.message, canUse: a == .available && !current, listing: l, offer: nil))
            }
        }
        return out
    }

    private func candidateRow(_ c: Candidate, _ row: SupplyRow, _ e: GameEngine, _ co: Company, _ cur: Currency, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(c.name.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                if c.isCurrent { Chip(text: "In use", tint: P.accent) }
            }
            Text(c.record).textStyle(.caption, tint: P.inkSoft)
            if !c.distance.isEmpty { Text(c.distance).textStyle(.caption, tint: P.inkSoft) }
            HStack(spacing: Theme.Space.s) {
                Text(c.price).textStyle(.body, numeric: true)
                if !c.extra.isEmpty { Text(c.extra).textStyle(.caption, tint: P.inkFaint, numeric: true) }
            }
            if let n = c.note { Text(n.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true) }
            if c.canUse && !locked {
                if let l = c.listing {
                    if opened == c.id {
                        SupplySignBlock(companyID: companyID, lineID: lineID, lineTitle: row.title, listing: l, weeklyMarketSpend: row.weekly ?? 0, currency: cur, onSigned: { dismiss() })
                    } else {
                        Button("Use this supplier") { Haptics.tap(); opened = c.id; message = nil }
                            .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                    }
                } else if let o = c.offer {
                    Button("Use this supplier") { choose(o) }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                        .accessibilityIdentifier("supply-use-\(o.id)")
                }
            }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choose(_ o: SupplyOfferRow) {
        let result: SupplierSwitchResult? = store.act { $0.chooseSupply(companyID: companyID, change: o.change) }
        switch result {
        case .ok?:
            Haptics.success()
            store.saved("supplied by " + o.name)
            dismiss()
        case .notKnownWell?: Haptics.warning(); message = "They do not know you well enough yet. Buy from them or take them to lunch first."
        case .governed?: Haptics.warning(); message = "A chain rule or your franchise agreement fixes this supplier."
        default: Haptics.warning(); message = "That supplier is not available for this company now."
        }
    }
}
