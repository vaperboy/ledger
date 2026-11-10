import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum SupplierSubject: Identifiable, Hashable {
    case item(String)
    case line(String)

    var id: String {
        switch self {
        case .item(let i): return "item:" + i
        case .line(let l): return "line:" + l
        }
    }

    init(_ ask: SupplyAsk, itemID: String) {
        switch ask {
        case .item: self = .item(itemID)
        case .line(let l): self = .line(l)
        }
    }
}

private enum SupplierRank: Int, CaseIterable, Hashable {
    case cheapest, reliable

    var title: String { self == .cheapest ? "Cheapest" : "Most reliable" }
}

private enum SupplierAction {
    case vendor(String)
    case offer(SupplyOfferRow)
    case listing(SupplyListing)
}

private struct SupplierChoice: Identifiable {
    var id: String
    var name: String
    var badge: String
    var price: String
    var trust: Double?
    var delivery: String
    var cost: Double
    var current: Bool
    var blocked: String?
    var action: SupplierAction
}

private struct SupplierSheet {
    var title: String
    var subtitle: String
    var currency: Currency
    var choices: [SupplierChoice]
    var governed: String?
    var weekly: Double
    var lineID: String?
    var lineTitle: String
    var goodsTier: Bool
}

struct SupplierPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var subject: SupplierSubject
    var asking: Bool = false
    var onClose: () -> Void
    @State private var rank: SupplierRank = .cheapest
    @State private var opened: String?
    @State private var message: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let sheet = makeSheet(e, co) {
            content(sheet, co)
        } else {
            Text("This is gone.").popupText(.subtitle)
                .centerSheetTitle("Supplier")
                .popupFooter { PopupOptionButton(title: "Done", identifier: "item-supplier-done") { onClose() } }
        }
    }

    private func makeSheet(_ e: GameEngine, _ co: Company) -> SupplierSheet? {
        switch subject {
        case .item(let id): return itemSheet(e, co, id)
        case .line(let id): return lineSheet(e, co, id)
        }
    }

    private func itemSheet(_ e: GameEngine, _ co: Company, _ id: String) -> SupplierSheet? {
        guard let p = e.itemPage(companyID: companyID, itemID: id), !p.offers.isEmpty else { return nil }
        let cur: Currency = e.currency(for: co)
        let currentID: String? = p.record?.supplierID
        let choices: [SupplierChoice] = p.offers.map { (o: ItemModels.SupplyLine) -> SupplierChoice in
            SupplierChoice(id: o.vendorID, name: o.vendorName, badge: "Company", price: itemAmount(o.buyPrice, cur) + " a unit", trust: o.reliability,
                           delivery: o.leadDays > 0 ? "Delivery: \(o.leadDays) days" : "", cost: o.buyPrice, current: o.vendorID == currentID, blocked: nil,
                           action: .vendor(o.vendorID))
        }
        return SupplierSheet(title: "Who supplies \(p.item.name.tidyText)?", subtitle: "Pick who you buy it from.", currency: cur, choices: choices, governed: nil,
                             weekly: 0, lineID: nil, lineTitle: p.item.name, goodsTier: false)
    }

    private func lineSheet(_ e: GameEngine, _ co: Company, _ id: String) -> SupplierSheet? {
        guard let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == id }) else { return nil }
        let cur: Currency = e.currency(for: co)
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: companyID, lineID: id)
        var choices: [SupplierChoice] = row.offers.map { (o: SupplyOfferRow) -> SupplierChoice in
            var cost: Double = 1
            if let w = o.weekly, let base = row.weekly, base > 0 { cost = w / base }
            return SupplierChoice(id: "o:" + o.id, name: o.name, badge: o.source, price: o.weekly.map { cur.tidyShort($0) + " a week" } ?? "Paid per job", trust: o.trust,
                                  delivery: Self.leadText(o.lead), cost: cost, current: o.isCurrent && contract == nil, blocked: o.blocked.map { Self.short($0) },
                                  action: .offer(o))
        }
        if row.governed == nil && !SupplyMarketCatalogue.tradesSupplying(line: id).isEmpty {
            choices.append(contentsOf: listingChoices(e, row, cur, contract))
        }
        return SupplierSheet(title: "Who supplies \(row.title.lowercased())?", subtitle: "Pick who you buy it from.", currency: cur, choices: choices, governed: row.governed,
                             weekly: row.weekly ?? 0, lineID: id, lineTitle: row.title, goodsTier: id == "goods")
    }

    private func listingChoices(_ e: GameEngine, _ row: SupplyRow, _ cur: Currency, _ contract: SupplyContract?) -> [SupplierChoice] {
        let today: Int = SupplyMarketStore.today(e)
        let wanted: [SupplyListing] = market.service.listings(lineID: row.id).filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
        let landed: [String: SupplyLanded.Row] = SupplyLandedBasis.lookup(SupplyLandedBasis.rows(e, companyID: companyID, listings: wanted, weekly: row.weekly))
        return wanted.map { (l: SupplyListing) -> SupplierChoice in
            let a: SupplyAvailability = SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: max(l.minOrder, SupplyLandedBasis.compareUnits), today: today)
            let r: SupplyLanded.Row? = landed[l.id]
            var price: String = SupplyMarketWords.price(l.priceTier)
            var delivery: [String] = []
            if let r {
                price = cur.tidyShort(r.unitPrice) + " a unit"
                if r.mode != nil {
                    price += " + " + cur.tidyShort(r.freightPerUnit + r.customsPerUnit) + " delivery"
                    delivery.append("\(Int(saturating: r.distanceKm.rounded())) km" + (r.crossesBorder ? " abroad" : ""))
                }
            }
            if l.leadDays > 0 { delivery.append("\(l.leadDays) days") }
            return SupplierChoice(id: "l:" + l.id, name: l.ownerName, badge: "Player", price: price, trust: l.record.ordersTotal == 0 ? nil : l.record.deliveredShare,
                                  delivery: delivery.isEmpty ? "" : "Delivery: " + delivery.joined(separator: " \u{00B7} "), cost: l.priceFactor * (r?.landedFactor ?? 1),
                                  current: contract?.listingID == l.id, blocked: a.message.map { Self.short($0) }, action: .listing(l))
        }
    }

    private static func short(_ text: String) -> String {
        let t: String = text.replacingOccurrences(of: "Not available: ", with: "")
        return t.prefix(1).uppercased() + String(t.dropFirst())
    }

    private static func leadText(_ lead: String) -> String {
        ["Continuous", "As needed", "Same week"].contains(lead) ? "" : "Delivery: " + lead.lowercased()
    }

    private func ranked(_ list: [SupplierChoice]) -> [SupplierChoice] {
        list.sorted { (a: SupplierChoice, b: SupplierChoice) -> Bool in
            switch rank {
            case .cheapest: return a.cost != b.cost ? a.cost < b.cost : a.name < b.name
            case .reliable: return (a.trust ?? 0.5) != (b.trust ?? 0.5) ? (a.trust ?? 0.5) > (b.trust ?? 0.5) : a.name < b.name
            }
        }
    }

    private func content(_ sheet: SupplierSheet, _ co: Company) -> some View {
        let now: SupplierChoice? = sheet.choices.first { (c: SupplierChoice) -> Bool in c.current }
        let others: [SupplierChoice] = sheet.choices.filter { (c: SupplierChoice) -> Bool in !c.current }
        let usable: [SupplierChoice] = ranked(others.filter { (c: SupplierChoice) -> Bool in c.blocked == nil })
        let unavailable: [SupplierChoice] = others.filter { (c: SupplierChoice) -> Bool in c.blocked != nil }
        let suggested: SupplierChoice? = now ?? usable.first { (c: SupplierChoice) -> Bool in if case .listing = c.action { return false } else { return true } }
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(sheet.subtitle).popupText(.subtitle)
            if let g = sheet.governed { Text(g.tidyText).popupText(.risk) }
            if sheet.goodsTier { goodsTier(co) }
            if let now {
                heading("Your supplier now")
                row(now, sheet, locked: true)
            } else {
                Text("No supplier chosen yet.").popupText(.risk)
            }
            if !usable.isEmpty {
                heading("Other suppliers")
                if usable.count > 1 {
                    SegmentedPill(items: SupplierRank.allCases, title: { (r: SupplierRank) -> String in r.title }, selection: $rank,
                                  identifier: { (r: SupplierRank) -> String in "supply-rank-\(r.rawValue)" })
                }
                ForEach(Array(usable.enumerated()), id: \.element.id) { (n: Int, c: SupplierChoice) in
                    if n > 0 { Hairline() }
                    row(c, sheet, locked: sheet.governed != nil)
                }
            }
            if !unavailable.isEmpty {
                heading("Not available")
                ForEach(Array(unavailable.enumerated()), id: \.element.id) { (n: Int, c: SupplierChoice) in
                    if n > 0 { Hairline() }
                    row(c, sheet, locked: true).opacity(0.5)
                }
            }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(sheet.title)
        .popupFooter { footer(suggested, now: now != nil) }
        .accessibilityIdentifier("item-supplier-chooser")
        .task { market.sync(store) }
    }

    private func heading(_ text: String) -> some View {
        Text(text).popupText(.rowLabel).padding(.top, Theme.Space.xs)
    }

    @ViewBuilder private func footer(_ suggested: SupplierChoice?, now: Bool) -> some View {
        if asking, let s = suggested {
            PopupFooter(cancel: "Decide later", action: now ? "Keep \(s.name.tidyText)" : "Use \(s.name.tidyText)", onCancel: { onClose() },
                        onAction: { if now { keepCurrent() } else { choose(s) } }, cancelID: "item-supplier-done", actionID: "item-supplier-keep")
        } else {
            PopupOptionButton(title: asking ? "Decide later" : "Done", identifier: "item-supplier-done") { onClose() }
        }
    }

    private func row(_ c: SupplierChoice, _ sheet: SupplierSheet, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(c.name.tidyText).popupText(.body).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text(c.badge).popupText(.caption)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                    .background(Capsule().fill(P.ink.opacity(0.1)))
            }
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Text(c.price).popupText(.rowValue).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: Theme.Space.s)
                if c.current {
                    Chip(text: "In use", tint: P.accent)
                } else if c.blocked == nil && !locked {
                    Button("Use") { Haptics.tap(); choose(c) }
                        .buttonStyle(PrimaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("supply-use-\(c.id)")
                }
            }
            HStack(alignment: .center, spacing: Theme.Space.s) {
                TrustBar(trust: c.trust)
                Spacer(minLength: Theme.Space.s)
                if !c.delivery.isEmpty { Text(c.delivery).popupText(.caption).lineLimit(1).minimumScaleFactor(0.8) }
            }
            if let why = c.blocked { Text(why).popupText(.caption).lineLimit(2) }
            if opened == c.id, case .listing(let l) = c.action, let lineID = sheet.lineID {
                SupplySignBlock(companyID: companyID, lineID: lineID, lineTitle: sheet.lineTitle, listing: l, weeklyMarketSpend: sheet.weekly, currency: sheet.currency,
                                onSigned: { onClose() })
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func goodsTier(_ co: Company) -> some View {
        let raw: JSONValue = co.value("src")["c"]
        let now: Int = min(2, max(0, raw.isNull ? 1 : raw.int))
        let binding = Binding<Int>(get: { now }, set: { (v: Int) in
            _ = store.act { $0.chooseGoodsClass(companyID: companyID, goodsClass: v) }
            Haptics.tap()
        })
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Quality").popupText(.rowLabel)
            SegmentedPill(items: [0, 1, 2], title: { (i: Int) -> String in Suppliers.goodsClassNames[i] }, selection: binding)
        }
    }

    private func keepCurrent() {
        Haptics.tap()
        store.tutorialAdvance(from: .pickSupplier)
        onClose()
    }

    private func choose(_ c: SupplierChoice) {
        switch c.action {
        case .vendor(let vendor): chooseVendor(vendor, c.name)
        case .offer(let o): chooseOffer(o)
        case .listing: opened = opened == c.id ? nil : c.id; message = nil
        }
    }

    private func chooseVendor(_ vendor: String, _ name: String) {
        guard case .item(let item) = subject else { return }
        let id: Int = companyID
        let r = store.act { $0.setItemSupplier(companyID: id, itemID: item, vendorID: vendor) }
        if case .refused(let why)? = r { Haptics.warning(); message = why; return }
        if r?.didChange == true { Haptics.success(); store.saved("supplied by " + name) }
        if asking { store.tutorialAdvance(from: .pickSupplier) }
        onClose()
    }

    private func chooseOffer(_ o: SupplyOfferRow) {
        let id: Int = companyID
        let result: SupplierSwitchResult? = store.act { $0.chooseSupply(companyID: id, change: o.change) }
        switch result {
        case .ok?:
            Haptics.success()
            store.saved("supplied by " + o.name)
            if asking { store.tutorialAdvance(from: .pickSupplier) }
            onClose()
        case .notKnownWell?: Haptics.warning(); message = "They do not know you well enough yet. Buy from them for a while first."
        case .governed?: Haptics.warning(); message = "A chain rule or your franchise agreement fixes this supplier."
        default: Haptics.warning(); message = "That supplier is not available for this company now."
        }
    }
}

private struct TrustBar: View {
    @Environment(\.outsidePalette) private var P
    var trust: Double?

    var body: some View {
        if let t = trust {
            let share: Double = min(1, max(0, t))
            HStack(spacing: Theme.Space.xs) {
                ZStack(alignment: .leading) {
                    Capsule().fill(P.ink.opacity(0.12))
                    Capsule().fill(share >= 0.95 ? P.gain : share >= 0.88 ? P.accent : P.caution).frame(width: 48 * CGFloat(share))
                }
                .frame(width: 48, height: 5)
                Text("\(Int((share * 100).rounded()))% reliable").popupText(.caption)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Not tested yet").popupText(.caption)
        }
    }
}
