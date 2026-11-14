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
        let sold: String = it.weeklyUnits >= 0.05 ? " \u{00B7} " + ItemPriceWords.units(it.weeklyUnits) + " a week" : ""
        let id: String = it.id
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: it.name, glyph: it.isService ? Glyph.opsWrench : Glyph.opsBox)),
                         title: it.name, subtitle: word + off + sold, value: itemAmount(it.price, cur),
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
    @State private var showMore = false
    @State private var overriding = false

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
        let setBy: String? = pg.item.priceSetter.isOwner || overriding ? nil : pg.item.priceSetter.label
        return VStack(alignment: .leading, spacing: PopupSpace.block) {
            VStack(alignment: .leading, spacing: PopupSpace.block) {
                if let who = setBy {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Set by \(who)").popupText(.caption)
                        Spacer(minLength: PopupSpace.row)
                        Button("Change") { Haptics.tap(); overriding = true }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                            .accessibilityIdentifier("item-price-take-back")
                    }
                    PopupRow(label: "Price", value: itemAmount(pg.item.price, cur))
                    PopupRow(label: "Market price", value: itemAmount(pg.item.marketPrice, cur))
                    PopupRow(label: "Cost each", value: itemAmount(pg.unitCost, cur))
                } else {
                    priceControls(e, co, pg, cur, price)
                    liveLine(f, pg, cur, price)
                    handBack(e)
                }
            }
            .coachAnchor(.itemPrice)
            moreSection(co, pg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(base.item.name.tidyText)
        .popupFooter { footer(owner: setBy == nil, current: base.item.price) }
    }

    /// The price figure with its steppers, the one bar and the three quick prices.
    @ViewBuilder private func priceControls(_ e: GameEngine, _ co: Company, _ p: ItemPageData, _ cur: Currency, _ price: Double) -> some View {
        let range: ClosedRange<Double> = e.itemPriceRange(companyID: co.id)
        let market: Double = p.item.marketPrice
        let lo: Double = market * range.lowerBound
        let hi: Double = market * range.upperBound
        let unit: String = p.item.isService ? "per service" : "each"
        if hi > lo {
            let shown: Double = min(max(price, lo), hi)
            PriceStepperField(price: shown, range: lo...hi, step: ItemPriceWords.step(market: market, cur: cur), cur: cur, unit: unit,
                              onSet: { (v: Double) in draftPrice = v; commitPrice(v) })
            PriceBar(lo: lo, hi: hi, cost: p.unitCost, market: market, price: shown,
                     onChange: { (v: Double) in draftPrice = min(max(v, lo), hi) },
                     onEnd: { commitPrice(roundedToCent(draftPrice ?? shown, cur, lo, hi)) })
            HStack {
                Text("Cost " + itemAmount(p.unitCost, cur)).popupText(.caption)
                Spacer(minLength: PopupSpace.row)
                Text("Market " + itemAmount(market, cur)).popupText(.caption)
            }
            HStack(spacing: PopupSpace.row) {
                quickButton("Cheap", target: market * 0.85, lo, hi, price, cur)
                quickButton("Market", target: market, lo, hi, price, cur)
                quickButton("Premium", target: market * 1.15, lo, hi, price, cur)
            }
        } else {
            PopupRow(label: "Market price", value: itemAmount(market, cur))
            PopupRow(label: "Cost each", value: itemAmount(p.unitCost, cur))
        }
    }

    /// After the owner took prices back, one tap lets the manager or advisor set them again.
    @ViewBuilder private func handBack(_ e: GameEngine) -> some View {
        if let helper = e.priceHelper(companyID: companyID), e.state.company(companyID).map(SalesItems.pricesTakenBack) == true {
            let who: String = helper == .advisor ? "your market advisor" : helper.label
            Button("Let \(who) set prices") {
                Haptics.tap()
                let id: Int = companyID
                let r = store.act { $0.handPricesBack(companyID: id) }
                if r?.didChange == true { overriding = false; store.saved("prices handed back") }
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
            .accessibilityIdentifier("item-price-hand-back")
        }
    }

    private func quickButton(_ title: String, target: Double, _ lo: Double, _ hi: Double, _ price: Double, _ cur: Currency) -> some View {
        let value: Double = roundedToCent(min(max(target, lo), hi), cur, lo, hi)
        let on: Bool = abs(value - price) < 0.005 * cur.rate
        return Button(title) { Haptics.tap(); draftPrice = value; commitPrice(value) }
            .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true, tint: on ? P.accent : nil))
            .accessibilityIdentifier("item-price-" + title.lowercased())
    }

    private func roundedToCent(_ v: Double, _ cur: Currency, _ lo: Double, _ hi: Double) -> Double {
        let cent: Double = 0.01 * cur.rate
        return min(max((v / cent).rounded() * cent, lo), hi)
    }

    /// What this price is expected to do in a week. Units and profit come from the same forecast.
    private func liveLine(_ f: ItemForecast, _ p: ItemPageData, _ cur: Currency, _ price: Double) -> some View {
        let weekly: Double = f.units * (price - p.unitCost)
        let word: String = weekly >= 0 ? "profit" : "loss"
        let sold: String = ItemPriceWords.units(f.units)
        return Text("\u{2248} \(sold) sold a week \u{00B7} \(word) \(cur.tidyShort(abs(weekly))) a week")
            .popupText(.rowValue).foregroundStyle(weekly >= 0 ? P.gain : P.loss)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("item-price-live")
    }

    /// Promotion and group listing, folded away until asked for.
    @ViewBuilder private func moreSection(_ co: Company, _ pg: ItemPageData) -> some View {
        if !PriceMoves.discountOptions(co.type).isEmpty || Self.listingTrades.contains(co.type) || pg.item.listedForGroup {
            Button { Haptics.tap(); Motion.animate(Motion.quickAnimation) { showMore.toggle() } } label: {
                HStack {
                    Text("More").popupText(.rowLabel)
                    Spacer(minLength: PopupSpace.row)
                    Image(systemName: showMore ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.inkFaint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("item-price-more")
            if showMore {
                VStack(alignment: .leading, spacing: PopupSpace.block) {
                    promotion(co, pg.item)
                    listToggle(co, pg.item)
                }
            }
        }
    }

    private func footer(owner: Bool, current: Double) -> some View {
        Button("Done") { Haptics.tap(); finish(owner: owner, current: current) }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .guideHint(owner && store.tutorialStep == .setPrice, key: "price.\(itemID)")
            .accessibilityIdentifier("item-price-done")
    }

    /// Done keeps the price on screen: a pending change is saved, and in the guide the shown price counts as the player's choice.
    private func finish(owner: Bool, current: Double) {
        if owner {
            if let d = draftPrice { commitPrice(d) } else if store.tutorialStep == .setPrice { commitPrice(current) }
        }
        onClose()
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
