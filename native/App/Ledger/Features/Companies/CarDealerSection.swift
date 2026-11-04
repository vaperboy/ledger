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
                Text(row.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                HStack(spacing: 5) {
                    TeamBadge(text: statusText, tint: row.status == .inStock ? Theme.gold : Theme.ivoryMuted)
                    TeamBadge(text: row.body.isEmpty ? "car" : row.body)
                }
                Text(note.tidyText).font(.system(size: 12)).foregroundStyle(noteTint)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(currency.tidyShort(row.askingPrice)).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text(row.status == .inStock ? "asking" : "list price").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }
            if row.status == .inStock { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 18) {
            supplierBlock(cur)
            TeamGroup(title: "Showroom and orders", trailing: {
                Text("\(sp.used) of \(sp.total) spaces").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                if rows.isEmpty {
                    Text("The showroom is empty. Cars only arrive when you order them from your supplier.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rows) { (r: CarDealerRow) in
                        if r.status == .inStock {
                            Button { Haptics.tap(); carSheet = CarSheetID(id: r.id) } label: { CarStockCard(row: r, currency: cur) }.buttonStyle(PressableStyle())
                        } else {
                            CarStockCard(row: r, currency: cur)
                        }
                    }
                }
                Button { Haptics.tap(); ordering = true } label: { Text("Order cars").frame(maxWidth: .infinity) }
                    .buttonStyle(GoldButtonStyle())
            }
        }
        .sheet(item: $carSheet) { (c: CarSheetID) in CarPriceSheet(companyID: company.id, carID: c.id).environmentObject(store).popupHost() }
        .sheet(isPresented: $ordering) { CarOrderSheet(companyID: company.id).environmentObject(store).popupHost() }
        .sheet(isPresented: $brandScreen) { CarBrandScreen(companyID: company.id).environmentObject(store).popupHost() }
    }

    private func supplierBlock(_ cur: Currency) -> some View {
        let con = engine.carBrandContract(companyID: company.id)
        let buyer = engine.carDealerHasBuyer(companyID: company.id)
        return MoreBlock("Supplier") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: con == nil ? "Distributor" : "Brand contract", value: engine.carDealerSupplier(companyID: company.id), rule: false)
                FlatRow(label: "Dealer margin", value: Currency.percent(con?.margin ?? CarBrands.distributorMargin, decimals: 1),
                        sub: con == nil ? "The distributor sells any brand but keeps most of the margin." : "Built into the invoice price of every car.")
                FlatRow(label: "Who orders", value: buyer ? "Buyer or manager" : "You, by hand",
                        sub: buyer ? "Orders when the showroom runs thin." : "Hire a buyer, or a manager, to keep the showroom stocked.")
                Button { Haptics.tap(); brandScreen = true } label: { Text(con == nil ? "Brand contracts" : "Your brand contract").frame(maxWidth: .infinity) }
                    .buttonStyle(GreyOutlineButtonStyle()).padding(.top, 10)
            }
        }
    }
}

/// One car: its cost, the list price and the price slider with what the sale would earn or lose right now.
struct CarPriceSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var carID: Int
    @State private var price = 0.0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID), let car = e.carDealerRows(companyID: companyID).first(where: { $0.id == carID && $0.status == .inStock }) {
                    content(e.currency(for: co), car)
                } else {
                    Text("This car has been sold.").foregroundStyle(Theme.ivoryMuted).padding(24)
                }
            }
            .ledgerBackground()
            .navigationTitle("Car").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private func content(_ cur: Currency, _ car: CarDealerRow) -> some View {
        let profit: Double = price - car.cost
        let pct: Double = car.cost > 0 ? profit / car.cost * 100 : 0
        VStack(alignment: .leading, spacing: 16) {
            Text(car.title).popupText(.figure)
            MoreBlock("Cost") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "You paid the supplier", value: cur.tidyShort(car.cost), rule: false)
                    FlatRow(label: "List price", value: cur.tidyShort(car.listPrice))
                    FlatRow(label: "In the showroom", value: "\(car.weeks) \(car.weeks == 1 ? "week" : "weeks")", sub: car.weeks > 13 ? "Old stock loses value every week." : "")
                }
            }
            MoreBlock("Asking price") {
                VStack(alignment: .leading, spacing: 8) {
                    LedgerSlider(value: $price, in: (car.cost * 0.8)...(car.listPrice * 1.15), step: max(1, (car.listPrice / 400).rounded()),
                                 valueText: cur.tidyShort(price)) { editing in if !editing { commit() } }
                    FlatRow(label: profit >= 0 ? "Profit if it sells" : "Loss if it sells", value: usedCarMoney(profit, cur) + "  (" + String(format: "%.1f", abs(pct)) + " percent)",
                            sub: profit >= 0 ? "Dearer cars sell more slowly." : "Below what the car cost you. Cheaper cars sell sooner.",
                            tint: profit >= 0 ? Theme.gain : Theme.loss, rule: false)
                }
            }
        }
        .padding(16)
        .onAppear { if !loaded { price = car.askingPrice; loaded = true } }
    }

    private func commit() {
        _ = store.act { $0.carDealerSetPrice(companyID: companyID, carID: carID, price: price) }
    }
}

/// Order cars from the current supplier: the distributor's whole range, or only the contract brand's.
struct CarOrderSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID) {
                    list(e, e.currency(for: co))
                }
            }
            .ledgerBackground()
            .navigationTitle("Order cars").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        }.padding(16)
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
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func order(_ o: CarDealerOffer) {
        let r = store.act { $0.carDealerOrder(companyID: companyID, brandID: o.brandID, modelID: o.modelID) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else { Haptics.success(); store.show("\(o.brandName) \(o.modelName) ordered.", tone: "good") }
    }
}
