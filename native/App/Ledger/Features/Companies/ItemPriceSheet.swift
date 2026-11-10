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
    var onAdd: () -> Void
    var onChosen: (String) -> Void = { _ in }
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let noun: String = service ? "service" : "product"
        return PageGroup(service ? "Services" : "Products") {
            if items.isEmpty && company.status == .open && engine.needsFirstItemChoice(companyID: company.id) {
                FirstItemPicker(engine: engine, company: company, noun: noun, onAddOwn: onAdd, onChosen: onChosen)
            } else if items.isEmpty {
                EmptyState(glyph: service ? Glyph.opsWrench : Glyph.opsBox, title: "Nothing is on sale yet",
                           message: company.status == .open ? "Add what you sell." : "", centered: false)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, it: SalesItem) in
                    if i > 0 { RowRule(inset: 52) }
                    row(it, cur).coachAnchor(.firstItemRow, enabled: i == 0)
                }
            }
            if company.status == .open && !items.isEmpty {
                Hairline()
                Button { Haptics.tap(); onAdd() } label: {
                    HStack(spacing: Theme.Space.m) {
                        LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.medium, tint: P.accent).frame(width: 40)
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

struct ItemPriceSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var itemID: String
    var onClose: () -> Void
    @State private var draftPrice: Double?
    @State private var draftPercent: Int?
    @State private var weeks = 4

    private static let listingTrades: Set<String> = ["webdev", "gamestudio", "startup", "mktg", "furniture", "factory", "hardware", "electrician", "plumber", "handy"]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let base = e.itemPage(companyID: companyID, itemID: itemID) {
            content(e, co, base)
        } else {
            EmptyState(glyph: Glyph.opsBox, title: "This item no longer exists")
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ base: ItemPageData) -> some View {
        let cur: Currency = e.currency(for: co)
        let price: Double = draftPrice ?? base.item.price
        let pg: ItemPageData = draftPrice == nil ? base : (e.itemPage(companyID: companyID, itemID: itemID, price: price) ?? base)
        let f: ItemForecast = e.itemForecast(companyID: companyID, itemID: itemID, price: price, discountPercent: base.item.discountPercent)
        let setBy: String? = pg.item.priceSetter.isOwner ? nil : pg.item.priceSetter.label
        let move: Double = base.item.price > 0 ? price / base.item.price - 1 : 0
        let facts: [TradeFact] = TradeItemFactRows.rows(e, companyID: companyID, page: pg, price: price, cur: cur)
        return VStack(alignment: .leading, spacing: PopupSpace.block) {
            header(pg, cur, price)
            VStack(alignment: .leading, spacing: PopupSpace.row) {
                if let who = setBy {
                    Text("Set by \(who)").popupText(.caption)
                    PopupRow(label: "Market price", value: itemAmount(pg.item.marketPrice, cur))
                } else {
                    priceControls(e, co, pg, cur, price)
                }
                PopupRow(label: "Cost each", value: itemAmount(pg.unitCost, cur))
            }
            .coachAnchor(.itemPrice)
            preview(f, cur)
            if let line = hint(e, pg, f, move: move) { Text(line).popupText(.caption) }
            promotion(co, pg.item)
            listToggle(co, pg.item)
            if !facts.isEmpty { TradeItemFacts(rows: facts, plans: TradeItemFactRows.plans(pg)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(base.item.name.tidyText)
        .popupFooter { footer(owner: setBy == nil) }
    }

    private func header(_ p: ItemPageData, _ cur: Currency, _ price: Double) -> some View {
        let reading = itemProfitReading(p.live, cur)
        let margin: String = price > 0 ? String(format: "margin %.0f%%", (price - p.unitCost) / price * 100) : ""
        return HStack(alignment: .firstTextBaseline, spacing: PopupSpace.block) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(itemAmount(price, cur)).popupText(.figure)
                Text(p.item.isService ? "per service" : "each").popupText(.caption)
            }
            Spacer(minLength: PopupSpace.row)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(p.live.outcome == .breakEven ? reading.text : reading.text + " each").popupText(.rowValue).foregroundStyle(reading.tint)
                Text(margin).popupText(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func priceControls(_ e: GameEngine, _ co: Company, _ p: ItemPageData, _ cur: Currency, _ price: Double) -> some View {
        let range: ClosedRange<Double> = e.itemPriceRange(companyID: co.id)
        let lo: Double = p.item.marketPrice * range.lowerBound
        let hi: Double = p.item.marketPrice * range.upperBound
        let market: Double = p.item.marketPrice
        let amount = Binding<Double>(get: { min(max(price, lo), hi) }, set: { (v: Double) in draftPrice = v })
        let unit: String = p.item.isService ? "per service" : "each"
        if hi > lo {
            LedgerSlider(value: amount, in: lo...hi, onEditingChanged: { (editing: Bool) in
                if !editing { commitPrice(draftPrice ?? p.item.price) }
            })
            .tint(P.accent)
            .accessibilityIdentifier("sales-item-price")
            ProfitBand(lo: lo, hi: hi, cost: p.unitCost, price: price)
            HStack(alignment: .center, spacing: PopupSpace.row) {
                Text("Market price").popupText(.rowLabel)
                Text(itemAmount(market, cur)).popupText(.rowValue)
                Spacer(minLength: PopupSpace.row)
                if market >= lo && market <= hi {
                    Button("Use market price") { Haptics.tap(); commitPrice(market) }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                        .accessibilityIdentifier("item-use-market-price")
                }
            }
            TypedPriceField(price: price, range: lo...hi, cur: cur, unit: unit,
                            hint: { (v: Double) -> String? in
                let lp = ItemModels.liveProfit(price: v, cost: p.unitCost)
                return lp.outcome == .breakEven ? "Break-even on each one." : "At this price: \(lp.word) \(itemAmount(lp.amount, cur)) on each one."
            }, onSet: { (v: Double) in draftPrice = v; commitPrice(v) })
        } else {
            PopupRow(label: "Market price", value: itemAmount(market, cur))
        }
    }

    private func preview(_ f: ItemForecast, _ cur: Currency) -> some View {
        let profit: String = (f.profitChange >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(f.profitChange))
        return FigureRow(items: [
            KeyFigures.Item(label: "Demand", value: String(format: "%+.0f%%", f.demandChange * 100), tint: f.demandChange >= 0 ? P.gain : P.loss, sub: "vs market price"),
            KeyFigures.Item(label: "Sold a week", value: String(format: "about %.0f", f.units)),
            KeyFigures.Item(label: "Profit a week", value: profit, tint: f.profitChange >= 0 ? P.gain : P.loss, sub: "against now"),
        ], combineCells: true)
    }

    private func hint(_ e: GameEngine, _ p: ItemPageData, _ f: ItemForecast, move: Double) -> String? {
        guard abs(move) > 0.001, let pf = e.priceForecast(companyID: companyID, byShare: move * p.item.revenueWeight)?.forecast else { return nil }
        let later: Double = f.demandChange + (pf.customersLater - pf.customersAtFirst)
        var parts: [String] = [String(format: "Once customers are used to it: demand %+.0f%%", later * 100)]
        if let m = pf.marginAfter { parts.append(String(format: "margin %.0f%%", m * 100)) }
        if move < -0.08 { parts.append("rivals may match") }
        return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder private func footer(owner: Bool) -> some View {
        if owner && store.tutorialStep == .setPrice {
            Button("Keep this price") { Haptics.tap(); store.tutorialAdvance(from: .setPrice); onClose() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("item-keep-price")
            Button("Close") { Haptics.tap(); onClose() }
                .buttonStyle(QuietButtonStyle())
        } else {
            Button("Done") { Haptics.tap(); onClose() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("item-price-done")
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

    @ViewBuilder private func promotion(_ co: Company, _ it: SalesItem) -> some View {
        let options: [Int] = PriceMoves.discountOptions(co.type)
        if !options.isEmpty {
            let live: Int = Int(it.discountPercent)
            let chosen: Int = draftPercent ?? live
            let pick = Binding<Int>(get: { chosen }, set: { (v: Int) in Haptics.choose(); draftPercent = v })
            let changed: Bool = chosen != live || (chosen > 0 && weeks != it.discountWeeksLeft)
            let title: String = chosen == 0 ? "End promotion" : (live > 0 ? "Change promotion" : "Start \(chosen)% off for \(weeks.weeksText)")
            VStack(alignment: .leading, spacing: PopupSpace.row) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Promotion").popupText(.rowLabel)
                    Spacer(minLength: PopupSpace.row)
                    if live > 0 { Text("\(live)% off \u{00B7} \(it.discountWeeksLeft.weeksText) left").popupText(.effect) }
                }
                SegmentedPill(items: [0] + options, title: { (pc: Int) -> String in pc == 0 ? "None" : "\(pc)%" }, selection: pick)
                if chosen > 0 {
                    Stepper(value: $weeks, in: 1...26) { Text("For \(weeks.weeksText)").popupText(.body) }
                        .frame(minHeight: 44)
                }
                if changed && !(chosen == 0 && live == 0) {
                    Button(title) { Haptics.tap(); commitDiscount(Double(chosen)) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("item-promotion-go")
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
            HStack {
                Text("List for my other companies").popupText(.rowLabel)
                Spacer(minLength: PopupSpace.row)
                LedgerSwitch(isOn: on)
            }
            .frame(minHeight: 44)
        }
    }

    private func setListed(_ v: Bool) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemListedForGroup(companyID: id, itemID: item, listed: v) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else if r?.didChange == true { store.saved(v ? "listed for your companies" : "no longer listed") }
    }
}
