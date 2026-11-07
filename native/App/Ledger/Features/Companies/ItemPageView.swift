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

/// The items of a company: "Products" (or "Services") with Add at the right, one row per item (price, live profit or loss) that opens its
/// item page. The weekly total is the Sales hero, so it is not repeated here.
struct ItemsList: View {
    var engine: GameEngine
    var company: Company
    var items: [SalesItem]
    var service: Bool
    var onOpen: (String) -> Void
    var onAdd: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let noun: String = service ? "service" : "product"
        return PageGroup(service ? "Services" : "Products") {
            if items.isEmpty && company.status == .open && engine.needsFirstItemChoice(companyID: company.id) {
                FirstItemPicker(engine: engine, company: company, noun: noun, onAddOwn: onAdd)
            } else if items.isEmpty {
                EmptyState(glyph: service ? Glyph.opsWrench : Glyph.opsBox, title: "Nothing is on sale yet",
                           message: company.status == .open ? "Add what you sell." : "", centered: false)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, it: SalesItem) in
                    if i > 0 { RowRule(inset: 52) }
                    row(it, cur)
                }
            }
            if company.status == .open && !items.isEmpty {
                Hairline()
                Button { Haptics.tap(); onAdd() } label: {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(P.accent).frame(width: 40)
                        Text("Add a \(noun)").textStyle(.headline, tint: P.accent)
                        Spacer()
                    }
                    .frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(AcctPressStyle())
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
                         valueNote: reading.text, valueNoteTint: reading.tint, lineLimit: 1, identifier: "sales-item-\(id)") { onOpen(id) }
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

/// One item: the price as the hero with what each one earns at it, the price slider right under it (an exact price can be typed), then what
/// the price does to sales, the promotion, supply, the trade's own blocks, plans, history and how the company sells. A part with nothing to
/// show is left out; an old titles-only item has no Supply, History or Details.
struct ItemPageView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    @State private var draftPrice: Double?
    @State private var weeks = 4
    /// The discount being chosen; nil until the player picks one (then the live discount shows).
    @State private var draftPercent: Int?
    @State private var typing = false
    @State private var showWeeks = false
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
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    priceBlock(pg, co, cur, price, f, setBy: pg.item.priceSetter.isOwner ? nil : pg.item.priceSetter.label)
                    demandBlock(pg, f, cur)
                    promotionBlock(co, pg.item)
                    supplyBlock(pg, cur)
                    TradeItemBlocks(e: e, companyID: companyID, itemID: itemID, price: price, cur: cur)
                    plansBlock(pg)
                    historyBlock(pg, cur)
                    detailsBlock(pg, cur)
                    soldBlock(e, co)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
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

    /// The price is the hero and follows the slider; the line under it says what each one earns and how many sell. The slider and its
    /// profit band sit right under it; quick prices and the typed price are text actions under the slider.
    /// `setBy`: who sets this price when it is not the owner (a manager within the owner's price position); nil: the owner sets it here.
    private func priceBlock(_ p: ItemPageData, _ co: Company, _ cur: Currency, _ price: Double, _ f: ItemForecast, setBy: String? = nil) -> some View {
        let lo: Double = p.item.marketPrice * SalesItems.priceRange.lowerBound
        let hi: Double = p.item.marketPrice * SalesItems.priceRange.upperBound
        let amount = Binding<Double>(get: { min(max(price, lo), hi) }, set: { (v: Double) in draftPrice = v })
        let reading = itemProfitReading(p.live, cur)
        let each: String = p.live.outcome == .breakEven ? "break-even on each" : reading.text + " each"
        let facts: String = String(format: "about %.0f sold a week", f.units)
        let costLine: String = "cost " + itemAmount(p.unitCost, cur) + (p.record == nil ? " (typical)" : "") + "  \u{00B7}  market " + itemAmount(p.item.marketPrice, cur)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button {
                guard hi > lo, setBy == nil else { return }
                Haptics.tap()
                Motion.animate(Motion.quickAnimation) { typing.toggle() }
            } label: {
                CompanyHero(label: "Price " + (p.item.isService ? "per service" : "each"), value: itemAmount(price, cur), change: each, changeTint: reading.tint, context: facts)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Type an exact price")
            if let who = setBy {
                Text("Set by \(who)").textStyle(.caption, tint: P.inkFaint)
            } else if hi > lo {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    LedgerSlider(value: amount, in: lo...hi, onEditingChanged: { (editing: Bool) in
                        if !editing { commitPrice(draftPrice ?? p.item.price) }
                    })
                    .tint(P.accent)
                    .accessibilityIdentifier("sales-item-price")
                    ProfitBand(lo: lo, hi: hi, cost: p.unitCost, price: price)
                    Text(costLine.tidyText).textStyle(.caption, tint: P.inkFaint, numeric: true)
                }
                if typing {
                    TypedPriceField(price: price, range: lo...hi, cur: cur, unit: p.item.isService ? "per service" : "each",
                                    hint: { (v: Double) -> String? in
                        let lp = ItemModels.liveProfit(price: v, cost: p.unitCost)
                        return lp.outcome == .breakEven ? "At this price you break even on each one." : "At this price: \(lp.word) \(itemAmount(lp.amount, cur)) on each one."
                    }, onSet: { (v: Double) in draftPrice = v; commitPrice(v) })
                }
                quickPrices(p, cur, lo: lo, hi: hi)
            }
            listToggle(co, p.item)
        }
    }

    /// Text actions under the slider: price at cost, at fair value, or type an exact price.
    private func quickPrices(_ p: ItemPageData, _ cur: Currency, lo: Double, hi: Double) -> some View {
        let cost: Double = p.unitCost
        let fair: Double = p.fairValue
        return WrapRow {
            if !typing {
                Button("Type a price") { Haptics.tap(); Motion.animate(Motion.quickAnimation) { typing = true } }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("item-type-price")
            }
            if fair >= lo && fair <= hi {
                Button("Fair value \(itemAmount(fair, cur))") { Haptics.tap(); commitPrice(fair) }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
            }
            if cost >= lo && cost <= hi {
                Button("At cost \(itemAmount(cost, cur))") { Haptics.tap(); commitPrice(cost) }
                    .buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.inkSoft))
            }
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
            let title: String = chosen == 0 ? "End promotion" : (live > 0 ? "Change promotion" : "Start \(chosen)% off for \(weeks.weeksText)")
            PageGroup(title: "Promotion", trailing: {
                if live > 0 {
                    Text("\(live)% off \u{00B7} \(it.discountWeeksLeft.weeksText) left").textStyle(.caption, tint: P.gain)
                }
            }) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SegmentedPill(items: [0] + options, title: { (pc: Int) -> String in pc == 0 ? "None" : "\(pc)%" }, selection: pick)
                    if chosen > 0 {
                        Stepper(value: $weeks, in: 1...26) {
                            Text("For \(weeks.weeksText)").textStyle(.body, tint: P.ink)
                        }
                        .frame(minHeight: 44)
                    }
                    if changed && !(chosen == 0 && live == 0) {
                        Button(title) { Haptics.tap(); commitDiscount(Double(chosen)) }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                            .accessibilityIdentifier("item-promotion-go")
                    }
                }
                .padding(.top, Theme.Space.xs)
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

    // MARK: What the price does

    private func demandBlock(_ p: ItemPageData, _ f: ItemForecast, _ cur: Currency) -> some View {
        let profit: String = (f.profitChange >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(f.profitChange))
        let chance: String = String(format: "%.0f%%", p.saleProbability * 100)
        return PageGroup("At this price, a week") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                FigureRow(items: [
                    KeyFigures.Item(label: "Revenue", value: cur.tidyShort(f.revenue)),
                    KeyFigures.Item(label: "Profit change", value: profit, tint: f.profitChange >= 0 ? P.gain : P.loss),
                    KeyFigures.Item(label: "Demand", value: String(format: "%+.0f%%", f.demandChange * 100), tint: f.demandChange >= 0 ? P.gain : P.loss, sub: "vs market price"),
                ], combineCells: true)
                Text("\(chance) of interested buyers buy \u{00B7} fair value \(itemAmount(p.fairValue, cur))").textStyle(.caption, tint: P.inkFaint, numeric: true)
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: Supply

    @ViewBuilder private func supplyBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            // The current supplier shows as the "In use" row below when it is one of the offers; otherwise here.
            let listed: Bool = p.offers.prefix(4).contains { $0.vendorID == r.supplierID }
            let facts: [String] = supplyFacts(r)
            PageGroup(title: "Supply", trailing: {
                if !facts.isEmpty { Text(facts.joined(separator: " \u{00B7} ")).textStyle(.caption, tint: P.inkFaint).lineLimit(1).minimumScaleFactor(0.8) }
            }) {
                if !listed {
                    if let s = p.supply {
                        SupplierRow(name: s.vendorName, detail: "You pay \(itemAmount(s.buyPrice, cur))" + (s.discount > 0 ? " \u{00B7} \(Int((s.discount * 100).rounded()))% off for the relationship" : ""),
                                    badge: s.relationshipWord, current: true)
                    } else {
                        LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.warn, title: "No supplier chosen", subtitle: "Pick one below")
                    }
                }
                ForEach(Array(p.offers.prefix(4).enumerated()), id: \.element.vendorID) { (n: Int, o: ItemModels.SupplyLine) in
                    let current: Bool = o.vendorID == r.supplierID
                    if n > 0 || !listed { RowRule() }
                    SupplierRow(name: o.vendorName, detail: "You pay \(itemAmount(o.buyPrice, cur))" + (o.leadDays > 0 ? " \u{00B7} \(o.leadDays) days" : ""),
                                badge: o.relationshipWord, current: current, action: current ? nil : { choose(o.vendorID, o.vendorName) })
                }
            }
        }
    }

    private func supplyFacts(_ r: ItemModels.Record) -> [String] {
        var facts: [String] = []
        if r.leadDays > 0 { facts.append("\(r.leadDays) days lead time") }
        if r.model.holdsStock { facts.append("\(r.stock) in stock" + (r.onOrder > 0 ? ", \(r.onOrder) on order" : "")) }
        if r.capacity > 0 { facts.append(String(format: "makes %.0f a week", r.capacity)) }
        return facts
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
            PageGroup("Plans and promises") {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if reserved > 0 { Text("\(reserved) reserved for customers.").textStyle(.body, tint: P.ink) }
                    ForEach(Array(plans.enumerated()), id: \.offset) { pair in
                        Text(pair.element.text).textStyle(.body, tint: P.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Theme.Space.xs)
            }
        }
    }

    // MARK: History

    /// Profit so far as a figure with the weekly profit as a sparkline; the week-by-week rows open under it.
    @ViewBuilder private func historyBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        let all: [ItemModels.Week] = p.record?.history ?? []
        let weeksList: [ItemModels.Week] = Array(all.suffix(8).reversed())
        if !weeksList.isEmpty {
            let total: Double = all.reduce(0) { (a: Double, w: ItemModels.Week) -> Double in a + w.profit }
            PageGroup(title: "So far", trailing: {
                Button {
                    Haptics.choose()
                    Motion.animate(Motion.quickAnimation) { showWeeks.toggle() }
                } label: {
                    Text(showWeeks ? "Hide weeks" : "Week by week").textStyle(.caption, tint: P.accent).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("item-history-weeks")
            }) {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    Figure(label: "", value: (total >= 0 ? "profit " : "loss ") + usedCarMoney(total, cur), note: "over \(all.count.weeksText)", tint: total >= 0 ? P.gain : P.loss)
                    Spacer(minLength: 0)
                    Sparkline(values: all.suffix(16).map { $0.profit }, tint: total >= 0 ? P.gain : P.loss, filled: false).frame(width: 110, height: 36)
                }
                if showWeeks {
                    VStack(spacing: 0) {
                        ForEach(Array(weeksList.enumerated()), id: \.offset) { pair in
                            FlatRow(label: "Week \(pair.element.week)", value: String(format: "%.0f sold", pair.element.units),
                                    sub: (pair.element.profit >= 0 ? "profit " : "loss ") + itemAmount(pair.element.profit, cur), tint: nil, rule: pair.offset > 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Details

    @ViewBuilder private func detailsBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            PageGroup("Details") {
                FlatRow(label: "Kind", value: r.model.label, rule: false)
                FlatRow(label: "Cost basis", value: itemAmount(r.cost, cur), sub: r.prep > 0 ? "plus \(itemAmount(r.prep, cur)) preparation" : "")
            }
        }
    }

    // MARK: How it is sold

    @ViewBuilder private func soldBlock(_ e: GameEngine, _ co: Company) -> some View {
        let trade: Trade? = e.tradeInfo(companyID: co.id)
        let hasKnobs: Bool = !(trade?.knobs.isEmpty ?? true)
        let hasWays: Bool = e.waysToSell(companyID: co.id).contains { $0.canSwitch }
        if hasKnobs || hasWays {
            PageGroup("How the company sells") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("For the whole company, not only this item.").textStyle(.caption, tint: P.inkFaint)
                    HowYouSellSheet(companyID: co.id, embedded: true)
                }
            }
        }
    }
}
