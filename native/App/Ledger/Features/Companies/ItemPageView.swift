import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// An amount to the cent in the company's currency, absolute value. A real figure never shows as zero: below one cent it reads "<0.01".
func itemAmount(_ v: Double, _ cur: Currency) -> String {
    let sym: String = cur.country.currencySymbol
    let shown: String = String(format: "%.2f", abs(v) / cur.rate)
    if shown == "0.00" && v != 0 { return "<" + sym + "0.01" }
    return sym + shown
}

/// "profit 12.40" in green, "loss 3.10" in red, "break-even" in grey: the one reading of a live figure, in the list and on the page.
func itemProfitReading(_ lp: ItemModels.LiveProfit, _ cur: Currency) -> (text: String, tint: Color) {
    switch lp.outcome {
    case .profit: return ("profit " + itemAmount(lp.amount, cur), Theme.gain)
    case .loss: return ("loss " + itemAmount(lp.amount, cur), Theme.loss)
    case .breakEven: return ("break-even", Theme.inkSoft)
    }
}

// MARK: List

/// The items of a company: a titled list with the count and weekly sales at the right, one row per item (price, live profit or loss).
struct ItemsList: View {
    var engine: GameEngine
    var company: Company
    var items: [SalesItem]
    var service: Bool
    var onOpen: (String) -> Void
    var onAdd: () -> Void

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let total: Double = items.reduce(0) { (a: Double, i: SalesItem) -> Double in a + i.weeklyRevenue }
        let noun: String = service ? "service" : "product"
        return LedgerSection(title: "Items", rule: false, trailing: {
            Text("\(items.count) \(items.count == 1 ? "item" : "items") \u{00B7} \(cur.tidyShort(total)) a week").textStyle(.caption)
        }) {
            VStack(spacing: 0) {
                if items.isEmpty {
                    EmptyState(glyph: service ? Glyph.opsWrench : Glyph.opsBox, title: "Nothing is on sale yet",
                               message: company.status == .open ? "Add a \(noun) to start selling." : "", centered: false)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, it: SalesItem) in
                    if i > 0 { Hairline() }
                    row(it, cur)
                }
            }
            if company.status == .open {
                Button("Add \(noun)") { Haptics.tap(); onAdd() }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("sales-add-item")
            }
        }
    }

    private func row(_ it: SalesItem, _ cur: Currency) -> some View {
        let page: ItemPageData? = engine.itemPage(companyID: company.id, itemID: it.id)
        let reading: (text: String, tint: Color) = page.map { (p: ItemPageData) in itemProfitReading(p.live, cur) } ?? ("", Theme.inkSoft)
        let word: String = page?.statusWord ?? "On sale"
        let off: String = it.discountPercent > 0 ? " \u{00B7} \(Int(it.discountPercent))% off" : ""
        let id: String = it.id
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: it.name, glyph: it.isService ? Glyph.opsWrench : Glyph.opsBox)),
                         title: it.name, subtitle: word + off, value: itemAmount(it.price, cur),
                         valueNote: reading.text, valueNoteTint: reading.tint, lineLimit: 1) { onOpen(id) }
    }
}

// MARK: Live profit and loss slider band

/// A thin band under the price slider: red where the price is below the unit cost, green above, with a mark at break-even.
struct ProfitBand: View {
    var lo: Double
    var hi: Double
    var cost: Double
    var price: Double

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let span: Double = max(1e-9, hi - lo)
            let x: CGFloat = CGFloat(min(max((cost - lo) / span, 0), 1)) * g.size.width
            let p: CGFloat = CGFloat(min(max((price - lo) / span, 0), 1)) * g.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.loss.opacity(0.45)).frame(width: x)
                    Rectangle().fill(Theme.gain.opacity(0.45))
                }
                Rectangle().fill(Theme.ink).frame(width: 1.5).offset(x: max(0, x - 0.75))
                Circle().fill(price >= cost ? Theme.gain : Theme.loss).frame(width: 8, height: 8).offset(x: max(0, p - 4))
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: Page

/// One item as a scroll of sections: Price (the one place the price shows), Promotion, Sales and demand, Supply, Plans and promises,
/// History, Documents, Actions. A section with nothing to show is left out; an old titles-only item has no Supply, History or Documents.
struct ItemPageView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    @State private var draftPrice: Double?
    @State private var weeks = 4
    /// The discount being chosen; nil until the player picks one (then the live discount shows).
    @State private var draftPercent: Int?
    @Environment(\.outsidePalette) private var P

    private static let listingTrades: Set<String> = ["webdev", "gamestudio", "startup", "mktg", "furniture", "factory", "hardware", "electrician", "plumber", "handy"]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let base = e.itemPage(companyID: companyID, itemID: itemID) {
            let cur: Currency = e.currency(for: co)
            let price: Double = draftPrice ?? base.item.price
            let pg: ItemPageData = draftPrice == nil ? base : (e.itemPage(companyID: companyID, itemID: itemID, price: price) ?? base)
            let f: ItemForecast = e.itemForecast(companyID: companyID, itemID: itemID, price: price, discountPercent: base.item.discountPercent)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    priceBlock(pg, co, cur, price, f)
                    promotionBlock(co, pg.item)
                    demandBlock(pg, f, cur)
                    supplyBlock(pg, cur)
                    TradeItemBlocks(e: e, companyID: companyID, itemID: itemID, price: price, cur: cur)
                    plansBlock(pg)
                    historyBlock(pg, cur)
                    documentsBlock(pg, cur)
                    actionsBlock(pg, cur)
                    soldBlock(e, co)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .appScreen(title: base.item.name, subtitle: base.modelLabel + " \u{00B7} " + base.statusWord, tab: .company)
        } else {
            EmptyState(glyph: Glyph.opsBox, title: "This item no longer exists")
                .frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    // MARK: Price

    /// The margin is the lead figure; the price itself shows once, in the typed field under the slider (as a figure when it cannot move).
    private func priceBlock(_ p: ItemPageData, _ co: Company, _ cur: Currency, _ price: Double, _ f: ItemForecast) -> some View {
        let lo: Double = p.item.marketPrice * SalesItems.ratioRange.lowerBound
        let hi: Double = p.item.marketPrice * SalesItems.ratioRange.upperBound
        let amount = Binding<Double>(get: { min(max(price, lo), hi) }, set: { (v: Double) in draftPrice = v })
        let reading = itemProfitReading(p.live, cur)
        let margin: String = p.live.outcome == .breakEven ? p.live.word : p.live.word + " " + itemAmount(p.live.amount, cur) + " each"
        let facts: [String] = ["cost " + itemAmount(p.unitCost, cur) + (p.record == nil ? " (typical)" : ""),
                               "market " + itemAmount(p.item.marketPrice, cur),
                               String(format: "about %.0f sold a week", f.units)]
        return LedgerSection("Price", rule: false) {
            Figure(label: "Margin", value: margin, note: facts.joined(separator: " \u{00B7} "), tint: reading.tint, size: .figure)
            if hi > lo {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    LedgerSlider(value: amount, in: lo...hi, onEditingChanged: { (editing: Bool) in
                        if !editing { commitPrice(draftPrice ?? p.item.price) }
                    })
                    .tint(P.accent)
                    .accessibilityIdentifier("sales-item-price")
                    ProfitBand(lo: lo, hi: hi, cost: p.unitCost, price: price)
                }
                TypedPriceField(price: price, range: lo...hi, cur: cur, unit: p.item.isService ? "per service" : "each",
                                hint: { (v: Double) -> String? in
                    let lp = ItemModels.liveProfit(price: v, cost: p.unitCost)
                    return lp.outcome == .breakEven ? "At this price you break even on each one." : "At this price: \(lp.word) \(itemAmount(lp.amount, cur)) on each one."
                }, onSet: { (v: Double) in draftPrice = v; commitPrice(v) })
            } else {
                Figure(label: "Price", value: itemAmount(price, cur), size: .inline)
            }
            listToggle(co, p.item)
        }
    }

    private func commitPrice(_ price: Double) {
        let id: Int = companyID
        let item: String = itemID
        let cur: Currency? = store.engine.flatMap { (e: GameEngine) in e.state.company(id).map { e.currency(for: $0) } }
        let r = store.act { $0.setItemPrice(companyID: id, itemID: item, price: price) }
        draftPrice = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else if r?.didChange == true, let cur { store.saved("price " + itemAmount(price, cur)) }
    }

    // MARK: Promotion

    /// Pick a discount and a length, then one button starts, changes or ends it: nothing reaches the engine before the tap.
    @ViewBuilder private func promotionBlock(_ co: Company, _ it: SalesItem) -> some View {
        let options: [Int] = PriceMoves.discountOptions(co.type)
        if !options.isEmpty {
            let live: Int = Int(it.discountPercent)
            let chosen: Int = draftPercent ?? live
            let pick = Binding<Int>(get: { chosen }, set: { (v: Int) in Haptics.choose(); draftPercent = v })
            let changed: Bool = chosen != live || (chosen > 0 && weeks != it.discountWeeksLeft)
            let title: String = chosen == 0 ? "End promotion" : (live > 0 ? "Change promotion" : "Start promotion")
            let blocked: String? = chosen == 0 && live == 0 ? "Pick a discount to start a promotion." : nil
            LedgerSection(title: "Promotion", trailing: {
                if live > 0 {
                    Text("\(live)% off \u{00B7} \(it.discountWeeksLeft.weeksText) left").textStyle(.caption, tint: P.gain)
                }
            }) {
                SegmentedPill(items: [0] + options, title: { (pc: Int) -> String in pc == 0 ? "None" : "\(pc)%" }, selection: pick)
                if chosen > 0 {
                    Stepper(value: $weeks, in: 1...26) {
                        Text("For \(weeks.weeksText)").textStyle(.body, tint: P.ink)
                    }
                    .frame(minHeight: 44)
                }
                if changed || live == 0 {
                    PrimaryAction(title: title, blockedReason: blocked) { commitDiscount(Double(chosen)) }
                }
            }
            .onAppear { if live > 0 { weeks = max(1, it.discountWeeksLeft) } }
        }
    }

    private func commitDiscount(_ percent: Double) {
        let id: Int = companyID
        let item: String = itemID
        let w: Int = weeks
        let r = store.act { $0.setItemDiscount(companyID: id, itemID: item, percent: percent, weeks: w) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn"); return }
        guard r?.didChange == true else { return }
        draftPercent = nil
        Haptics.success()
        store.show(percent > 0 ? "Promotion: \(Int(percent))% off for \(w.weeksText)" : "Promotion ended")
    }

    @ViewBuilder private func listToggle(_ co: Company, _ it: SalesItem) -> some View {
        if Self.listingTrades.contains(co.type) || it.listedForGroup {
            let on = Binding<Bool>(get: { it.listedForGroup }, set: { (v: Bool) in setListed(v) })
            Toggle(isOn: on) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("List for my other companies").textStyle(.headline)
                    Text("Your other companies in this country can buy it in TechPro. The profit stays with this company.").textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(P.accent)
        }
    }

    private func setListed(_ v: Bool) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemListedForGroup(companyID: id, itemID: item, listed: v) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else if r?.didChange == true { store.saved(v ? "listed for your companies" : "no longer listed") }
    }

    // MARK: Sales and demand

    private func demandBlock(_ p: ItemPageData, _ f: ItemForecast, _ cur: Currency) -> some View {
        let profit: String = (f.profitChange >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(f.profitChange)) + " a week"
        let chance: String = String(format: "%.0f%%", p.saleProbability * 100)
        return LedgerSection("Sales and demand") {
            VStack(spacing: 0) {
                FlatRow(label: "Revenue", value: cur.tidyShort(f.revenue) + " a week", rule: false)
                FlatRow(label: "Profit change", value: profit, tint: f.profitChange >= 0 ? P.gain : P.loss)
                FlatRow(label: "Demand against market price", value: String(format: "%+.0f%%", f.demandChange * 100), tint: f.demandChange >= 0 ? P.gain : P.loss)
                FlatRow(label: "Chance an interested buyer buys this week", value: chance, sub: "Fair value \(itemAmount(p.fairValue, cur))")
            }
        }
    }

    // MARK: Supply

    @ViewBuilder private func supplyBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            LedgerSection("Supply") {
                // The current supplier shows as the "In use" row below when it is one of the offers; otherwise here.
                let listed: Bool = p.offers.prefix(4).contains { $0.vendorID == r.supplierID }
                VStack(spacing: 0) {
                    if !listed {
                        if let s = p.supply {
                            FlatRow(label: "Comes from", value: s.vendorName, sub: s.relationshipWord, rule: false)
                            FlatRow(label: "You pay", value: itemAmount(s.buyPrice, cur), sub: s.discount > 0 ? "\(Int((s.discount * 100).rounded()))% off for the relationship" : "")
                        } else {
                            FlatRow(label: "Comes from", value: "No supplier chosen", rule: false)
                        }
                    }
                    if r.leadDays > 0 { FlatRow(label: "Lead time", value: "\(r.leadDays) days", rule: !listed) }
                    if r.model.holdsStock {
                        FlatRow(label: "In stock", value: "\(r.stock)", sub: r.onOrder > 0 ? "\(r.onOrder) on order" : "")
                    }
                    if r.capacity > 0 { FlatRow(label: "Capacity", value: String(format: "%.0f a week", r.capacity)) }
                }
                if !p.offers.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(p.offers.prefix(4).enumerated()), id: \.element.vendorID) { (n: Int, o: ItemModels.SupplyLine) in
                            let current: Bool = o.vendorID == r.supplierID
                            if n > 0 { Hairline() }
                            SupplierRow(name: o.vendorName, detail: "You pay \(itemAmount(o.buyPrice, cur))" + (o.leadDays > 0 ? " \u{00B7} \(o.leadDays) days" : ""),
                                        badge: o.relationshipWord, current: current, action: current ? nil : { choose(o.vendorID, o.vendorName) })
                        }
                    }
                }
            }
        }
    }

    private func choose(_ vendorID: String, _ name: String) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemSupplier(companyID: id, itemID: item, vendorID: vendorID) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else if r?.didChange == true { store.saved("supplied by " + name) }
    }

    // MARK: Plans and promises

    /// Reservations and plans; a running discount shows under Promotion.
    @ViewBuilder private func plansBlock(_ p: ItemPageData) -> some View {
        let plans: [ItemModels.Plan] = p.record?.plans ?? []
        let reserved: Int = p.record?.reserved ?? 0
        if !plans.isEmpty || reserved > 0 {
            LedgerSection("Plans and promises") {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if reserved > 0 { Text("\(reserved) reserved for customers.").textStyle(.body, tint: P.ink) }
                    ForEach(Array(plans.enumerated()), id: \.offset) { pair in
                        Text(pair.element.text).textStyle(.body, tint: P.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder private func historyBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        let weeksList: [ItemModels.Week] = Array((p.record?.history ?? []).suffix(8).reversed())
        if !weeksList.isEmpty {
            let total: Double = (p.record?.history ?? []).reduce(0) { (a: Double, w: ItemModels.Week) -> Double in a + w.profit }
            LedgerSection(title: "History", trailing: {
                Text("last \(weeksList.count) weeks").textStyle(.caption)
            }) {
                VStack(spacing: 0) {
                    ForEach(Array(weeksList.enumerated()), id: \.offset) { pair in
                        FlatRow(label: "Week \(pair.element.week)", value: String(format: "%.0f sold", pair.element.units),
                                sub: (pair.element.profit >= 0 ? "profit " : "loss ") + itemAmount(pair.element.profit, cur), tint: nil, rule: pair.offset > 0)
                    }
                    FlatRow(label: "Profit or loss so far", value: (total >= 0 ? "profit " : "loss ") + itemAmount(total, cur), tint: total >= 0 ? P.gain : P.loss)
                }
            }
        }
    }

    // MARK: Documents

    @ViewBuilder private func documentsBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            LedgerSection("Documents") {
                VStack(spacing: 0) {
                    FlatRow(label: "Kind", value: r.model.label, rule: false)
                    FlatRow(label: "Cost basis", value: itemAmount(r.cost, cur), sub: r.prep > 0 ? "plus \(itemAmount(r.prep, cur)) preparation" : "")
                }
            }
        }
    }

    // MARK: Actions

    /// Quick prices; a discount is started or ended under Promotion.
    @ViewBuilder private func actionsBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        let cost: Double = p.unitCost
        let fair: Double = p.fairValue
        let lo: Double = p.item.marketPrice * SalesItems.ratioRange.lowerBound
        let hi: Double = p.item.marketPrice * SalesItems.ratioRange.upperBound
        let atCost: Bool = cost >= lo && cost <= hi
        let atFair: Bool = fair >= lo && fair <= hi
        if atCost || atFair {
            LedgerSection("Quick prices") {
                WrapRow {
                    if atCost {
                        Button("Price at cost \u{00B7} \(itemAmount(cost, cur))") { Haptics.tap(); commitPrice(cost) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                    }
                    if atFair {
                        Button("Price at fair value \u{00B7} \(itemAmount(fair, cur))") { Haptics.tap(); commitPrice(fair) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                    }
                }
            }
        }
    }

    // MARK: How it is sold

    @ViewBuilder private func soldBlock(_ e: GameEngine, _ co: Company) -> some View {
        let trade: Trade? = e.tradeInfo(companyID: co.id)
        let hasKnobs: Bool = !(trade?.knobs.isEmpty ?? true)
        let hasWays: Bool = e.waysToSell(companyID: co.id).contains { $0.canSwitch }
        if hasKnobs || hasWays {
            LedgerSection("How it is sold") {
                Text("These choices apply to the whole company, not only this item.").textStyle(.caption)
                HowYouSellSheet(companyID: co.id, embedded: true)
            }
        }
    }
}
