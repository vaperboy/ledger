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
    case .breakEven: return ("break-even", Theme.ivoryMuted)
    }
}

// MARK: List

/// One item as a bordered card, like a person in the Team list (`PersonCard`): thumbnail or glyph, name, status line, price with the live profit or loss, chevron.
struct ItemListRow: View {
    var name: String
    var status: String
    var statusTint: Color = Theme.ivoryMuted
    var price: String
    var reading: String
    var readingTint: Color
    var isService: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ThumbnailView(kind: .trade, key: name, size: 42, glyph: isService ? Glyph.opsWrench : Glyph.opsBox)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(status).font(.system(size: 12.5)).foregroundStyle(statusTint).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(price).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text(reading).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(readingTint)
            }
            GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The items of a company laid out like the staff list: caption "ITEMS" with a count and the weekly sales at the right, one card per item.
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
        return TeamGroup(title: "Items", trailing: {
            Text("\(items.count) \(items.count == 1 ? "item" : "items") \u{00B7} \(cur.tidyShort(total)) a week").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }) {
            if items.isEmpty { Text("Nothing is on sale yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
            ForEach(items) { (it: SalesItem) -> AnyView in AnyView(row(it, cur)) }
            if company.status == .open {
                TeamAction(title: "Add \(noun)") { onAdd() }.accessibilityIdentifier("sales-add-item")
            }
        }
    }

    private func row(_ it: SalesItem, _ cur: Currency) -> some View {
        let page: ItemPageData? = engine.itemPage(companyID: company.id, itemID: it.id)
        let reading: (text: String, tint: Color) = page.map { (p: ItemPageData) in itemProfitReading(p.live, cur) } ?? ("", Theme.ivoryMuted)
        let word: String = page?.statusWord ?? "On sale"
        let off: String = it.discountPercent > 0 ? " \u{00B7} \(Int(it.discountPercent))% off" : ""
        let id: String = it.id
        return Button { Haptics.tap(); onOpen(id) } label: {
            ItemListRow(name: it.name, status: word + off, price: itemAmount(it.price, cur), reading: reading.text, readingTint: reading.tint, isService: it.isService)
        }
        .buttonStyle(PressableStyle())
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
                Rectangle().fill(Theme.ivory).frame(width: 1.5).offset(x: max(0, x - 0.75))
                Circle().fill(price >= cost ? Theme.gain : Theme.loss).frame(width: 8, height: 8).offset(x: max(0, p - 4))
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: Page

/// One item as a scroll of blocks, like a staff member's page (`StaffProfileView`): Overview, Price, Sales and demand, Supply, Plans and promises,
/// History, Documents, Actions. A block with nothing to show is left out; an old titles-only item has no Supply, History or Documents.
struct ItemPageView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    @State private var draftPrice: Double?
    @State private var weeks = 4

    private static let listingTrades: Set<String> = ["webdev", "gamestudio", "startup", "mktg", "furniture", "factory", "hardware", "electrician", "plumber", "handy"]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let base = e.itemPage(companyID: companyID, itemID: itemID) {
            let cur: Currency = e.currency(for: co)
            let price: Double = draftPrice ?? base.item.price
            let pg: ItemPageData = draftPrice == nil ? base : (e.itemPage(companyID: companyID, itemID: itemID, price: price) ?? base)
            let f: ItemForecast = e.itemForecast(companyID: companyID, itemID: itemID, price: price, discountPercent: base.item.discountPercent)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    overview(pg, cur)
                    priceBlock(pg, co, cur, price)
                    demandBlock(pg, f, cur)
                    supplyBlock(pg, cur)
                    WaveItemBlocks(e: e, companyID: companyID, itemID: itemID, price: price, cur: cur)
                    plansBlock(pg)
                    historyBlock(pg, cur)
                    documentsBlock(pg, cur)
                    actionsBlock(pg, cur)
                    soldBlock(e, co)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: base.item.name, subtitle: base.modelLabel, tab: .company)
        } else {
            Text("This item no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    // MARK: Overview

    private func overview(_ p: ItemPageData, _ cur: Currency) -> some View {
        let reading = itemProfitReading(p.live, cur)
        var figures: [KeyFigures.Item] = [
            .init(label: "Cost", value: itemAmount(p.unitCost, cur), sub: p.record == nil ? "typical for the trade" : "a unit"),
            .init(label: "Price", value: itemAmount(p.item.price, cur), sub: p.item.discountPercent > 0 ? "\(Int(p.item.discountPercent))% off now" : "before discount"),
            .init(label: "Margin now", value: reading.text, tint: reading.tint),
        ]
        if let r = p.record, r.model.holdsStock {
            figures.append(.init(label: "In stock", value: "\(r.stock)", sub: r.onOrder > 0 ? "\(r.onOrder) on order" : ""))
        }
        figures.append(.init(label: "Sold a week", value: String(format: "%.0f", p.item.weeklyUnits)))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ThumbnailView(kind: .trade, key: p.item.name, size: 48, glyph: p.item.isService ? Glyph.opsWrench : Glyph.opsBox)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        TeamBadge(text: p.modelLabel, tint: Theme.gold)
                        TeamBadge(text: p.statusWord)
                    }
                }
                Spacer(minLength: 0)
            }
            Card(padding: 14, radius: Theme.Radius.hero) { KeyFigures(items: figures) }
        }
    }

    // MARK: Price

    private func priceBlock(_ p: ItemPageData, _ co: Company, _ cur: Currency, _ price: Double) -> some View {
        let lo: Double = p.item.marketPrice * SalesItems.ratioRange.lowerBound
        let hi: Double = p.item.marketPrice * SalesItems.ratioRange.upperBound
        let amount = Binding<Double>(get: { min(max(price, lo), hi) }, set: { (v: Double) in draftPrice = v })
        let reading = itemProfitReading(p.live, cur)
        let word: String = p.live.word
        return TeamGroup("Price") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(itemAmount(price, cur)).font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.gold)
                        Spacer()
                        Text(p.live.outcome == .breakEven ? word : word + " " + itemAmount(p.live.amount, cur))
                            .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(reading.tint)
                    }
                    if hi > lo {
                        LedgerSlider(value: amount, in: lo...hi, onEditingChanged: { (editing: Bool) in
                            if !editing { commitPrice(draftPrice ?? p.item.price) }
                        })
                        .tint(Theme.gold)
                        .accessibilityIdentifier("sales-item-price")
                        ProfitBand(lo: lo, hi: hi, cost: p.unitCost, price: price)
                    }
                    Text("Cost \(itemAmount(p.unitCost, cur)). Market price \(itemAmount(p.item.marketPrice, cur)). Red is a loss, green a profit; you can go from 30% to 300% of the market price.")
                        .font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    discountControls(co, p.item)
                    listToggle(co, p.item)
                }
            }
        }
    }

    private func commitPrice(_ price: Double) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemPrice(companyID: id, itemID: item, price: price) }
        draftPrice = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
    }

    @ViewBuilder private func discountControls(_ co: Company, _ it: SalesItem) -> some View {
        let options: [Int] = PriceMoves.discountOptions(co.type)
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("DISCOUNT").capsLabel()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach([0] + options, id: \.self) { (pc: Int) in chip(pc, it) }
                }
                Stepper("For \(weeks.weeksText)", value: $weeks, in: 1...26).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                    .onChange(of: weeks) { _, _ in if it.discountPercent > 0 { commitDiscount(it.discountPercent) } }
            }
        }
    }

    private func chip(_ pc: Int, _ it: SalesItem) -> some View {
        let on: Bool = Int(it.discountPercent) == pc
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return Button { Haptics.choose(); commitDiscount(Double(pc)) } label: {
            Text(pc == 0 ? "None" : "\(pc)%").font(.system(size: 14, weight: .medium)).foregroundStyle(on ? Theme.gold : Theme.ivory)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(shape.fill(on ? Theme.goldSelected : Theme.surface))
                .overlay(shape.strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func commitDiscount(_ percent: Double) {
        let id: Int = companyID
        let item: String = itemID
        let w: Int = weeks
        let r = store.act { $0.setItemDiscount(companyID: id, itemID: item, percent: percent, weeks: w) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
    }

    @ViewBuilder private func listToggle(_ co: Company, _ it: SalesItem) -> some View {
        if Self.listingTrades.contains(co.type) || it.listedForGroup {
            let on = Binding<Bool>(get: { it.listedForGroup }, set: { (v: Bool) in setListed(v) })
            VStack(alignment: .leading, spacing: 4) {
                Toggle("List for my other companies", isOn: on).tint(Theme.gold).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                Text("Your other companies in this country can buy it in TechPro. The profit stays with this company.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            }
        }
    }

    private func setListed(_ v: Bool) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemListedForGroup(companyID: id, itemID: item, listed: v) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
    }

    // MARK: Sales and demand

    private func demandBlock(_ p: ItemPageData, _ f: ItemForecast, _ cur: Currency) -> some View {
        let profit: String = (f.profitChange >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(f.profitChange)) + " a week"
        let chance: String = String(format: "%.0f%%", p.saleProbability * 100)
        return TeamGroup("Sales and demand") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Units a week", value: String(format: "%.0f", f.units), rule: false)
                    FlatRow(label: "Revenue", value: cur.tidyShort(f.revenue) + " a week")
                    FlatRow(label: "Profit change", value: profit, tint: f.profitChange >= 0 ? Theme.gain : Theme.loss)
                    FlatRow(label: "Demand against market price", value: String(format: "%+.0f%%", f.demandChange * 100), tint: f.demandChange >= 0 ? Theme.gain : Theme.loss)
                    FlatRow(label: "Chance an interested buyer buys this week", value: chance, sub: "Fair value \(itemAmount(p.fairValue, cur))")
                }
            }
        }
    }

    // MARK: Supply

    @ViewBuilder private func supplyBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            TeamGroup("Supply") {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        VStack(spacing: 0) {
                            if let s = p.supply {
                                FlatRow(label: "Comes from", value: s.vendorName, sub: s.relationshipWord, rule: false)
                                FlatRow(label: "You pay", value: itemAmount(s.buyPrice, cur), sub: s.discount > 0 ? "\(Int((s.discount * 100).rounded()))% off for the relationship" : "")
                            } else {
                                FlatRow(label: "Comes from", value: "No supplier chosen", rule: false)
                            }
                            if r.leadDays > 0 { FlatRow(label: "Lead time", value: "\(r.leadDays) days") }
                            if r.model.holdsStock {
                                FlatRow(label: "In stock", value: "\(r.stock)", sub: r.onOrder > 0 ? "\(r.onOrder) on order" : "")
                            }
                            if r.capacity > 0 { FlatRow(label: "Capacity", value: String(format: "%.0f a week", r.capacity)) }
                        }
                        if !p.offers.isEmpty {
                            WrapRow {
                                ForEach(p.offers.prefix(4), id: \.vendorID) { (o: ItemModels.SupplyLine) in
                                    TeamAction(title: o.vendorName, tint: o.vendorID == r.supplierID ? Theme.gain : Theme.gold) { choose(o.vendorID) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func choose(_ vendorID: String) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemSupplier(companyID: id, itemID: item, vendorID: vendorID) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
    }

    // MARK: Plans and promises

    @ViewBuilder private func plansBlock(_ p: ItemPageData) -> some View {
        let plans: [ItemModels.Plan] = p.record?.plans ?? []
        let reserved: Int = p.record?.reserved ?? 0
        if p.item.discountPercent > 0 || !plans.isEmpty || reserved > 0 {
            TeamGroup("Plans and promises") {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(alignment: .leading, spacing: 5) {
                        if p.item.discountPercent > 0 {
                            Text("\(Int(p.item.discountPercent))% off for \(p.item.discountWeeksLeft.weeksText) more.").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        }
                        if reserved > 0 { Text("\(reserved) reserved for customers.").font(.system(size: 13)).foregroundStyle(Theme.ivory) }
                        ForEach(Array(plans.enumerated()), id: \.offset) { pair in
                            Text(pair.element.text).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        }
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
            TeamGroup(title: "History", trailing: {
                Text("last \(weeksList.count) weeks").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }) {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(spacing: 0) {
                        ForEach(Array(weeksList.enumerated()), id: \.offset) { pair in
                            FlatRow(label: "Week \(pair.element.week)", value: String(format: "%.0f sold", pair.element.units),
                                    sub: (pair.element.profit >= 0 ? "profit " : "loss ") + itemAmount(pair.element.profit, cur), tint: nil, rule: pair.offset > 0)
                        }
                        FlatRow(label: "Profit or loss so far", value: (total >= 0 ? "profit " : "loss ") + itemAmount(total, cur), tint: total >= 0 ? Theme.gain : Theme.loss)
                    }
                }
            }
        }
    }

    // MARK: Documents

    @ViewBuilder private func documentsBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            TeamGroup("Documents") {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(spacing: 0) {
                        FlatRow(label: "Kind", value: r.model.label, rule: false)
                        FlatRow(label: "Cost basis", value: itemAmount(r.cost, cur), sub: r.prep > 0 ? "plus \(itemAmount(r.prep, cur)) preparation" : "")
                        if let s = p.supply { FlatRow(label: "Supplier terms", value: s.vendorName, sub: s.leadDays > 0 ? "delivers in \(s.leadDays) days" : "") }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func actionsBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        let cost: Double = p.unitCost
        let fair: Double = p.fairValue
        let lo: Double = p.item.marketPrice * SalesItems.ratioRange.lowerBound
        let hi: Double = p.item.marketPrice * SalesItems.ratioRange.upperBound
        return TeamGroup("What you can do") {
            Card(padding: 14, radius: Theme.Radius.row) {
                WrapRow {
                    if cost >= lo && cost <= hi { TeamAction(title: "Price at cost") { commitPrice(cost) } }
                    if fair >= lo && fair <= hi { TeamAction(title: "Price at fair value") { commitPrice(fair) } }
                    if p.item.discountPercent > 0 { TeamAction(title: "End discount", tint: Theme.loss) { commitDiscount(0) } }
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
            TeamGroup("How it is sold") {
                Text("These choices apply to the whole company, not only this item.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                HowYouSellSheet(companyID: co.id, embedded: true)
            }
        }
    }
}
