import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A car as one card in the showroom list. Same layout as a person in the Team list (`PersonCard`): a round holder, the name, two badges,
/// a note line and the figure at the right with its caption.
struct CarStockCard: View {
    var row: CarDealerRow
    var currency: Currency

    private var statusText: String {
        switch row.status {
        case .inStock: return "In showroom"
        case .onOrder: return "On order"
        case .reserved: return "Reserved"
        }
    }

    private var note: String {
        switch row.status {
        case .inStock:
            let p = row.profit
            if abs(p) / currency.rate < 0.005 { return "Break-even at this price" }
            let word: String = p >= 0 ? "Profit " : "Loss "
            return word + usedCarMoney(p, currency) + " at this price, " + String(format: "%.1f", abs(row.profitPercent)) + " percent"
        case .onOrder: return "Arrives in \(row.weeks) \(row.weeks == 1 ? "week" : "weeks"). Cost \(currency.tidyShort(row.cost))."
        case .reserved: return "A customer is waiting for it. Arrives in \(row.weeks) \(row.weeks == 1 ? "week" : "weeks")."
        }
    }

    private var noteTint: Color {
        if row.status != .inStock { return Theme.ivoryFaint }
        return row.profit >= 0 ? Theme.gain : Theme.loss
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            UsedCarPhoto(family: row.body, title: row.title)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).textStyle(.headline).lineLimit(1)
                Text(statusText + " \u{00B7} " + (row.body.isEmpty ? "car" : row.body)).textStyle(.caption).lineLimit(1)
                Text(note.tidyText).textStyle(.caption, tint: noteTint)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(currency.tidyShort(row.askingPrice)).textStyle(.headline, numeric: true)
                Text(row.status == .inStock ? "asking" : "list price").textStyle(.caption, tint: Theme.inkFaint)
            }
            if row.status == .inStock { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .opacity(row.status == .inStock ? 1 : 0.6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// An id for the sheets: the sheet reads the car again from the engine, so it never holds a stale copy.
struct CarSheetID: Identifiable, Hashable { var id: Int }

/// The new-car dealership page section: the supplier (distributor or brand), the showroom and cars on order, and ordering.
struct CarDealerSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var carSheet: CarSheetID?
    @State private var ordering = false
    @State private var brandScreen = false

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let rows: [CarDealerRow] = engine.carDealerRows(companyID: company.id)
        let sp = engine.carDealerSpaces(companyID: company.id)
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            PageGroup(title: "Showroom and orders", trailing: {
                Text("\(sp.used) of \(sp.total) spaces").textStyle(.caption, tint: Theme.inkFaint)
            }) {
                if rows.isEmpty {
                    Text("The showroom is empty. Cars only arrive when you order them from your supplier.")
                        .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.s)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, r: CarDealerRow) in
                        if n > 0 { RowRule(inset: 54) }
                        if r.status == .inStock {
                            Button { Haptics.tap(); carSheet = CarSheetID(id: r.id) } label: { CarStockCard(row: r, currency: cur) }
                                .buttonStyle(AcctPressStyle())
                                .accessibilityIdentifier("dealer-car-\(r.id)")
                        } else {
                            CarStockCard(row: r, currency: cur)
                        }
                    }
                }
                Button { Haptics.tap(); ordering = true } label: { Text("Order cars") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .padding(.top, Theme.Space.m)
                    .accessibilityIdentifier("dealer-order-cars")
            }
            supplierBlock(cur)
        }
        .centerSheet(item: $carSheet, title: "Car", category: .compact, tone: .info) { (c: CarSheetID) in CarPriceSheet(companyID: company.id, carID: c.id).environmentObject(store) }
        .centerSheet(isPresented: $ordering, title: "Order cars", category: .medium, tone: .info) { CarOrderSheet(companyID: company.id).environmentObject(store) }
        .centerSheet(isPresented: $brandScreen, title: "Brand contract", size: .tall, category: .detail, tone: .investment) { CarBrandScreen(companyID: company.id).environmentObject(store) }
    }

    /// Who supplies the cars, the margin on each, who orders; the row opens the brand contracts.
    private func supplierBlock(_ cur: Currency) -> some View {
        let con = engine.carBrandContract(companyID: company.id)
        let buyer = engine.carDealerHasBuyer(companyID: company.id)
        let margin: String = Currency.percent(con?.margin ?? CarBrands.distributorMargin, decimals: 1)
        return PageGroup("Supplier") {
            LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: Theme.inkSoft, title: engine.carDealerSupplier(companyID: company.id),
                      subtitle: con == nil ? "Distributor: any brand, but it keeps most of the margin" : "Brand contract: the margin is in every invoice price",
                      value: margin, valueNote: "dealer margin", identifier: "dealer-brand") { brandScreen = true }
            RowRule()
            LedgerRow(leading: .glyph(Glyph.person), leadingTint: buyer ? Theme.inkSoft : Theme.warn, title: buyer ? "A buyer or manager orders" : "You order by hand",
                      subtitle: buyer ? "Orders when the showroom runs thin" : "Hire a buyer, or a manager, to keep the showroom stocked")
        }
    }
}

/// One car: its cost, the list price and the price slider with what the sale would earn or lose right now.
struct CarPriceSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var carID: Int
    @State private var price = 0.0
    @State private var loaded = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let car = e.carDealerRows(companyID: companyID).first(where: { $0.id == carID && $0.status == .inStock }) {
            content(e.currency(for: co), car)
        } else {
            Text("This car has been sold.").popupText(.body)
        }
    }

    @ViewBuilder private func content(_ cur: Currency, _ car: CarDealerRow) -> some View {
        let profit: Double = price - car.cost
        let pct: Double = car.cost > 0 ? profit / car.cost * 100 : 0
        VStack(alignment: .leading, spacing: 16) {
            Text(car.title).popupText(.figure)
            PageGroup("Cost") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "You paid the supplier", value: cur.tidyShort(car.cost), rule: false)
                    FlatRow(label: "List price", value: cur.tidyShort(car.listPrice))
                    FlatRow(label: "In the showroom", value: "\(car.weeks) \(car.weeks == 1 ? "week" : "weeks")", sub: car.weeks > 13 ? "Old stock loses value every week." : "")
                }
            }
            PageGroup("Asking price") {
                VStack(alignment: .leading, spacing: 8) {
                    LedgerSlider(value: $price, in: (car.cost * 0.8)...(car.listPrice * 1.15), step: max(1, (car.listPrice / 400).rounded()),
                                 valueText: cur.tidyShort(price)) { editing in if !editing { commit() } }
                    TypedPriceField(price: price, range: (car.cost * 0.8)...(car.listPrice * 1.15), cur: cur, unit: "per car",
                                    hint: { (v: Double) -> String? in
                        let d: Double = v - car.cost
                        return (d >= 0 ? "Profit if it sells at this price: " : "Loss if it sells at this price: ") + usedCarMoney(d, cur)
                    }, onSet: { (v: Double) in price = v; commit() })
                    FlatRow(label: profit >= 0 ? "Profit if it sells" : "Loss if it sells", value: usedCarMoney(profit, cur) + "  (" + String(format: "%.1f", abs(pct)) + " percent)",
                            sub: profit >= 0 ? "Dearer cars sell more slowly." : "Below what the car cost you. Cheaper cars sell sooner.",
                            tint: profit >= 0 ? Theme.gain : Theme.loss, rule: false)
                }
            }
        }
        .onAppear { if !loaded { price = car.askingPrice; loaded = true } }
    }

    private func commit() {
        _ = store.act { $0.carDealerSetPrice(companyID: companyID, carID: carID, price: price) }
    }
}

/// Order cars from the current supplier: the distributor's whole range, or only the contract brand's.
struct CarOrderSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            list(e, e.currency(for: co))
        }
    }

    private func list(_ e: GameEngine, _ cur: Currency) -> some View {
        let offers: [CarDealerOffer] = e.carDealerOffers(companyID: companyID)
        let free = e.carDealerSpaces(companyID: companyID)
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(e.carDealerSupplier(companyID: companyID)). Paid on delivery. \(max(0, free.total - free.used)) free spaces.")
                .popupText(.subtitle)
            ForEach(offers) { (o: CarDealerOffer) in
                Button { order(o) } label: { offerCard(o, cur) }.buttonStyle(PressableStyle())
            }
        }
    }

    private func offerCard(_ o: CarDealerOffer, _ cur: Currency) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconCircle(glyph: Glyph.group, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(o.brandName + " " + o.modelName).popupText(.rowValue).lineLimit(1)
                HStack(spacing: 5) {
                    TeamBadge(text: o.body, tint: Theme.gold)
                    TeamBadge(text: o.fuel)
                }
                Text("List \(cur.tidyShort(o.listPrice)). Arrives in about \(o.leadWeeks) weeks.").popupText(.caption)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(cur.tidyShort(o.cost)).popupText(.rowValue)
                Text("you pay").popupText(.caption)
            }
        }
        .padding(.horizontal, PopupSpace.block + 2).padding(.vertical, PopupSpace.block)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.cardDeep))
        .contentShape(Rectangle())
    }

    private func order(_ o: CarDealerOffer) {
        let r = store.act { $0.carDealerOrder(companyID: companyID, brandID: o.brandID, modelID: o.modelID) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else { Haptics.success(); store.show("\(o.brandName) \(o.modelName) ordered.", tone: "good") }
    }
}
