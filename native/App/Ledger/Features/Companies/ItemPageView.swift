import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

func itemAmount(_ v: Double, _ cur: Currency) -> String {
    let sym: String = cur.country.currencySymbol
    let shown: String = String(format: "%.2f", abs(v) / cur.rate)
    if shown == "0.00" && v != 0 { return "<" + sym + "0.01" }
    return sym + shown
}

func itemProfitReading(_ lp: ItemModels.LiveProfit, _ cur: Currency) -> (text: String, tint: Color) {
    switch lp.outcome {
    case .profit: return ("profit " + itemAmount(lp.amount, cur), Theme.gain)
    case .loss: return ("loss " + itemAmount(lp.amount, cur), Theme.loss)
    case .breakEven: return ("break-even", Theme.inkSoft)
    }
}

struct ItemsList: View {
    var engine: GameEngine
    var company: Company
    var items: [SalesItem]
    var service: Bool
    var onOpen: (String) -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        return PageGroup(service ? "Services" : "Products") {
            if items.isEmpty {
                EmptyState(glyph: service ? Glyph.opsWrench : Glyph.opsBox, title: "Nothing is on sale yet",
                           message: company.status == .open ? "Add what you sell under Prices." : "", centered: false)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, it: SalesItem) in
                    if i > 0 { RowRule(inset: 52) }
                    row(it, cur)
                }
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

struct ItemPageView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    @State private var weeks = 4
    @State private var draftPercent: Int?
    @State private var showWeeks = false
    @Environment(\.outsidePalette) private var P

    private static let listingTrades: Set<String> = ["webdev", "gamestudio", "startup", "mktg", "furniture", "factory", "hardware", "electrician", "plumber", "handy"]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let base = e.itemPage(companyID: companyID, itemID: itemID) {
            let cur: Currency = e.currency(for: co)
            let price: Double = base.item.price
            let pg: ItemPageData = base
            let f: ItemForecast = e.itemForecast(companyID: companyID, itemID: itemID, price: price, discountPercent: base.item.discountPercent)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    priceLine(pg, cur, f)
                    demandBlock(pg, f, cur, move: 0)
                    promotionBlock(co, pg.item)
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

    private func priceLine(_ p: ItemPageData, _ cur: Currency, _ f: ItemForecast) -> some View {
        let reading = itemProfitReading(p.live, cur)
        let each: String = p.live.outcome == .breakEven ? "break-even on each" : reading.text + " each"
        let facts: String = String(format: "about %.0f sold a week", f.units) + "  \u{00B7}  market " + itemAmount(p.item.marketPrice, cur)
        return CompanyHero(label: "Price " + (p.item.isService ? "per service" : "each"), value: itemAmount(p.item.price, cur), change: each, changeTint: reading.tint, context: facts)
    }

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

    private func demandBlock(_ p: ItemPageData, _ f: ItemForecast, _ cur: Currency, move: Double) -> some View {
        let profit: String = (f.profitChange >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(f.profitChange))
        let chance: String = String(format: "%.0f%%", p.saleProbability * 100)
        return PageGroup("At this price, a week") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                FigureRow(items: [
                    KeyFigures.Item(label: "Revenue", value: cur.tidyShort(f.revenue)),
                    KeyFigures.Item(label: "Profit change", value: profit, tint: f.profitChange >= 0 ? P.gain : P.loss),
                    KeyFigures.Item(label: "Demand", value: String(format: "%+.0f%%", f.demandChange * 100), tint: f.demandChange >= 0 ? P.gain : P.loss, sub: "vs market price"),
                ], combineCells: true)
                marketMarker(f.marketPosition)
                Text(forecastLine(p, f, move: move)).textStyle(.caption, tint: P.inkFaint, numeric: true)
                Text("\(chance) of interested buyers buy \u{00B7} fair value \(itemAmount(p.fairValue, cur))").textStyle(.caption, tint: P.inkFaint, numeric: true)
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    private func marketMarker(_ position: Double) -> some View {
        let shown: Double = min(max(position, -0.3), 0.3)
        let word: String = abs(position) < 0.02 ? "At the market price" : String(format: "%.0f%% ", abs(position) * 100) + (position > 0 ? "above the market" : "below the market")
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            GeometryReader { (g: GeometryProxy) in
                ZStack(alignment: .leading) {
                    Capsule().fill(P.inkFaint.opacity(0.25)).frame(height: 4)
                    Circle().fill(position > 0.02 ? P.loss : position < -0.02 ? P.gain : P.accent).frame(width: 10, height: 10)
                        .offset(x: (shown + 0.3) / 0.6 * (g.size.width - 10))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 10)
            Text(word).textStyle(.caption, tint: P.inkSoft, numeric: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func forecastLine(_ p: ItemPageData, _ f: ItemForecast, move: Double) -> String {
        var parts: [String] = [String(format: "Demand %+.0f%% now", f.demandChange * 100)]
        if abs(move) > 0.001, let pf = store.engine?.priceForecast(companyID: companyID, byShare: move * p.item.revenueWeight)?.forecast {
            let later: Double = f.demandChange + (pf.customersLater - pf.customersAtFirst)
            parts.append(String(format: "%+.0f%% once customers are used to it", later * 100))
            if let m = pf.marginAfter { parts.append(String(format: "margin %.0f%%", m * 100)) }
        }
        if move < -0.08 { parts.append("rivals may match") }
        return parts.joined(separator: " \u{00B7} ")
    }

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

    @ViewBuilder private func detailsBlock(_ p: ItemPageData, _ cur: Currency) -> some View {
        if let r = p.record {
            PageGroup("Details") {
                FlatRow(label: "Kind", value: r.model.label, rule: false)
                FlatRow(label: "Cost basis", value: itemAmount(r.cost, cur), sub: r.prep > 0 ? "plus \(itemAmount(r.prep, cur)) preparation" : "")
            }
        }
    }

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
