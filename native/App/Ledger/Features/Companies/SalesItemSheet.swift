import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The price popup of one item: a price slider (30% to 300% of the market price, the engine's range) with live numbers from `itemForecast`,
/// a discount, the group listing and "How it is sold" (the company's choices, shared with `HowYouSellSheet`).
struct SalesItemSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    /// The price being dragged; nil = the item's own price.
    @State private var draftPrice: Double?
    @State private var weeks = 4

    /// Trades whose items can be offered to the owner's other companies (mirrors the engine's `OwnListings.kindsBySeller`).
    private static let listingTrades: Set<String> = ["webdev", "gamestudio", "startup", "mktg", "furniture", "factory", "hardware", "electrician", "plumber", "handy"]

    var body: some View {
        let title: String = store.engine?.salesItems(companyID: companyID).first(where: { (i: SalesItem) -> Bool in i.id == itemID })?.name ?? "Item"
        return PeopleSheet(title: title) { inner }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var inner: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let it = e.salesItems(companyID: companyID).first(where: { (i: SalesItem) -> Bool in i.id == itemID }) {
            let cur: Currency = e.currency(for: co)
            let price: Double = draftPrice ?? it.price
            let f: ItemForecast = e.itemForecast(companyID: companyID, itemID: itemID, price: price, discountPercent: it.discountPercent)
            priceSection(it, cur, price)
            numbers(f, cur)
            discountSection(co, it)
            listSection(co, it)
            soldSection(e, co)
        } else {
            Text("This item no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
        }
    }

    // MARK: Price

    /// The full price as the slider has it, to the cent: no snapping.
    private func exact(_ v: Double, _ cur: Currency) -> String {
        cur.country.currencySymbol + String(format: "%.2f", v / cur.rate)
    }

    private func priceSection(_ it: SalesItem, _ cur: Currency, _ price: Double) -> some View {
        let lo: Double = it.marketPrice * SalesItems.ratioRange.lowerBound
        let hi: Double = it.marketPrice * SalesItems.ratioRange.upperBound
        let amount = Binding<Double>(get: { min(max(price, lo), hi) }, set: { (v: Double) in draftPrice = v })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("PRICE").capsLabel()
                Spacer()
                Text(exact(price, cur)).font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.gold)
            }
            if hi > lo {
                Slider(value: amount, in: lo...hi, onEditingChanged: { (editing: Bool) in
                    if !editing { commitPrice(draftPrice ?? it.price) }
                })
                .tint(Theme.gold)
                .accessibilityIdentifier("sales-item-price")
            }
            Text("Market price \(exact(it.marketPrice, cur)). You can go from 30% to 300% of it.").font(.caption).foregroundStyle(Theme.ivoryMuted)
        }
    }

    private func commitPrice(_ price: Double) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemPrice(companyID: id, itemID: item, price: price) }
        draftPrice = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
    }

    // MARK: Live numbers

    private func numbers(_ f: ItemForecast, _ cur: Currency) -> some View {
        let profit: String = (f.profitChange >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(f.profitChange)) + " a week"
        let demand: String = String(format: "%+.0f%%", f.demandChange * 100)
        return Card(padding: 12) {
            VStack(spacing: 6) {
                stat("Units a week", String(format: "%.0f", f.units), Theme.ivory)
                stat("Revenue", cur.tidyShort(f.revenue) + " a week", Theme.ivory)
                stat("Profit change", profit, f.profitChange >= 0 ? Theme.gain : Theme.loss)
                stat("Demand change", demand, f.demandChange >= 0 ? Theme.gain : Theme.loss)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }

    // MARK: Discount

    @ViewBuilder private func discountSection(_ co: Company, _ it: SalesItem) -> some View {
        let options: [Int] = PriceMoves.discountOptions(co.type)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("DISCOUNT").capsLabel()
            if options.isEmpty {
                Text("This trade does not discount.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach([0] + options, id: \.self) { (p: Int) in chip(p, it) }
                }
                Stepper("For \(weeks.weeksText)", value: $weeks, in: 1...26).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                    .onChange(of: weeks) { _, _ in if it.discountPercent > 0 { commitDiscount(it.discountPercent) } }
                if it.discountPercent > 0 {
                    Text("\(Int(it.discountPercent))% off, \(it.discountWeeksLeft.weeksText) left.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                }
            }
        }
    }

    private func chip(_ p: Int, _ it: SalesItem) -> some View {
        let on: Bool = Int(it.discountPercent) == p
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return Button { Haptics.choose(); commitDiscount(Double(p)) } label: {
            Text(p == 0 ? "None" : "\(p)%").font(.system(size: 14, weight: .medium)).foregroundStyle(on ? Theme.gold : Theme.ivory)
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

    // MARK: List for my other companies

    @ViewBuilder private func listSection(_ co: Company, _ it: SalesItem) -> some View {
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

    // MARK: How it is sold

    @ViewBuilder private func soldSection(_ e: GameEngine, _ co: Company) -> some View {
        let trade: Trade? = e.tradeInfo(companyID: co.id)
        let hasKnobs: Bool = !(trade?.knobs.isEmpty ?? true)
        let hasWays: Bool = e.waysToSell(companyID: co.id).contains { $0.canSwitch }
        if hasKnobs || hasWays {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("HOW IT IS SOLD").capsLabel()
                Text("These choices apply to the whole company, not only this item.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                HowYouSellSheet(companyID: co.id, embedded: true)
            }
        }
    }
}
