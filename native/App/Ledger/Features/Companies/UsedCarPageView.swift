import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct UsedCarPageView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var carID: Int
    @State private var draft: Double?
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let car = e.usedCarStock(companyID: companyID).first(where: { (c: UsedCarStockItem) -> Bool in c.id == carID }) {
            let cur: Currency = e.currency(for: co)
            let price: Double = draft ?? car.askingPrice
            let quote: UsedCarQuote? = e.usedCarQuote(companyID: companyID, carID: carID, price: price)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(car)
                    figures(car, quote, cur)
                    priceBlock(car, quote, cur, price)
                    repairBlock(e, car, cur)
                    offerBlock(e, car, cur)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .confirmAction($pending)
            .appScreen(title: car.title, subtitle: usedCarStatusText(car), tab: .company)
        } else {
            Text("This car is no longer in your yard.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func header(_ car: UsedCarStockItem) -> some View {
        HStack(spacing: 12) {
            UsedCarPhoto(family: car.family, title: car.title, size: 64, square: true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    TeamBadge(text: usedCarStatusText(car), tint: Theme.gold)
                    if car.reserved { TeamBadge(text: "Reserved") }
                    if car.stuck { TeamBadge(text: "Stuck", tint: Theme.loss) }
                }
                Text("\(car.weeksInStock) \(car.weeksInStock == 1 ? "week" : "weeks") in the yard").textStyle(.caption)
            }
            Spacer(minLength: 0)
        }
    }

    private func figures(_ car: UsedCarStockItem, _ q: UsedCarQuote?, _ cur: Currency) -> some View {
        let known: Bool = q?.repairsKnown ?? car.inspected
        let repairs: String = !known ? "Not known" : (car.repairs <= 0 && car.repairQuote <= 0 ? "None" : usedCarMoney(max(car.repairs, car.repairQuote), cur))
        let repairSub: String = !known ? "not inspected" : (car.status == "repair" ? "ordered" : (car.status == "quoted" ? "quoted" : (car.repairs > 0 ? "paid" : "")))
        let ahead: String = q.map { (x: UsedCarQuote) -> String in "+ " + usedCarMoney(x.holdingAhead, cur) + " ahead" } ?? ""
        let items: [KeyFigures.Item] = [
            KeyFigures.Item(label: "Buy price", value: usedCarMoney(car.purchasePrice, cur)),
            KeyFigures.Item(label: "Repairs", value: repairs, sub: repairSub),
            KeyFigures.Item(label: "Holding", value: usedCarMoney(car.holdingSoFar, cur), sub: ahead),
            KeyFigures.Item(label: "Worth", value: usedCarMoney(car.fairValue, cur), sub: "fair value"),
            KeyFigures.Item(label: "Cost so far", value: usedCarMoney(car.costBasis, cur)),
            KeyFigures.Item(label: "Asking", value: usedCarMoney(car.askingPrice, cur)),
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) { FigureStrip(items: items) }
    }

    private func priceBlock(_ car: UsedCarStockItem, _ q: UsedCarQuote?, _ cur: Currency, _ price: Double) -> some View {
        let basis: Double = max(car.costBasis, 1)
        let fair: Double = max(car.fairValue, 1)
        let lo: Double = max(1, min(min(basis, fair) * 0.5, car.askingPrice * 0.9))
        let hi: Double = max(max(basis, fair) * 1.6, car.askingPrice * 1.1)
        let step: Double = max(1, (fair / 400).rounded())
        let binding: Binding<Double> = Binding<Double>(get: { draft ?? car.askingPrice }, set: { (v: Double) in draft = v })
        return PageGroup(title: "Asking price", trailing: {
            Text(cur.tidyShort(price)).textStyle(.caption, tint: Theme.inkFaint, numeric: true)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                LedgerSlider(value: binding, in: lo...hi, step: step, valueText: cur.tidyShort(price)) { (editing: Bool) in
                    if !editing { commit(price) }
                }
                TypedPriceField(price: price, range: lo...hi, cur: cur, unit: "per car", market: fair,
                                hint: { (v: Double) -> String? in
                    guard let q else { return nil }
                    let d: Double = q.profit + (v - price)
                    return (d >= 0 ? "Profit if it sells at this price: " : "Loss if it sells at this price: ") + usedCarMoney(d, cur)
                }, onSet: { (v: Double) in draft = v; commit(v) })
                if let q { liveRows(car, q, cur, price, lo, hi) }
            }
        }
    }

    @ViewBuilder private func liveRows(_ car: UsedCarStockItem, _ q: UsedCarQuote, _ cur: Currency, _ price: Double, _ lo: Double, _ hi: Double) -> some View {
        let reading: (text: String, tint: Color) = usedCarProfitReading(q, cur)
        ProfitBand(lo: lo, hi: hi, cost: price - q.profit, price: price)
        FlatRow(label: reading.text == "Break-even" ? "Break-even" : q.verdict, value: reading.text == "Break-even" ? "" : usedCarMoney(q.profit, cur),
                sub: "Price minus buy price, repairs and holding.", tint: reading.tint, rule: false)
        FlatRow(label: "Sells in a week", value: oddsText(q.weeklyOdds), sub: q.priceVsFair > 0 ? percentVsFair(q.priceVsFair) : "")
        FlatRow(label: "Expected wait", value: waitText(q.expectedWeeks))
        if !q.repairsKnown {
            Text("Repairs not known yet.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
        if car.stuck {
            Text("Stuck: losing value faster.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
        if car.reserved {
            Text("A customer reserved it at " + usedCarMoney(car.reservedPrice, cur) + ". It sells to them at that price when the repair is done.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func oddsText(_ o: Double) -> String {
        if o < 0.01 { return "under 1 percent" }
        return String(format: "%.0f percent", o * 100)
    }

    private func percentVsFair(_ r: Double) -> String {
        let d: Double = (r - 1) * 100
        if abs(d) < 0.5 { return "Priced at what it is worth" }
        return String(format: "%.0f percent ", abs(d)) + (d > 0 ? "above what it is worth" : "below what it is worth")
    }

    private func waitText(_ w: Double) -> String {
        if w > 52 { return "over a year" }
        if w < 1.5 { return "about a week" }
        return "about \(Int(saturating: w.rounded())) weeks"
    }

    private func commit(_ price: Double) {
        let r: SettingResult? = store.act { (e: inout GameEngine) -> SettingResult in e.setUsedCarPrice(companyID: companyID, carID: carID, price: price) }
        if let why = r?.reason { Haptics.warning(); store.show(why, tone: "warn") }
        draft = nil
    }

    @ViewBuilder private func repairBlock(_ e: GameEngine, _ car: UsedCarStockItem, _ cur: Currency) -> some View {
        if car.status == "quoted" {
            quotedBlock(e, car, cur)
        } else if car.status == "repair" {
            PageGroup("At the garage") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: car.repairSupplierName.isEmpty ? "Garage" : car.repairSupplierName, value: usedCarMoney(car.repairQuote, cur), sub: "Paid when it is done", rule: false)
                    FlatRow(label: "Back in", value: car.repairWeeksLeft <= 1 ? "this week or next" : "\(car.repairWeeksLeft) weeks",
                            sub: "It is greyed out on the list, but customers can still reserve it.")
                }
            }
        } else if car.status == "new" {
            PageGroup("Inspection") {
                Text("Inspected next week, with a repair quote.")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func quotedBlock(_ e: GameEngine, _ car: UsedCarStockItem, _ cur: Currency) -> some View {
        let offer: UsedCarRepairOffer? = e.usedCarRepairOffer(companyID: companyID, carID: carID)
        let price: Double = offer?.price ?? car.repairQuote
        let who: String = offer?.supplierName ?? "A garage"
        let weeks: Int = offer?.weeks ?? 1
        let own: String = (offer?.isOwn ?? false) ? "Your own company, at the group price." : "An independent garage at the market price."
        return PageGroup("Repair") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Repair quote", value: usedCarMoney(car.repairQuote, cur), sub: "What the faults cost at market price.", rule: false)
                FlatRow(label: who, value: usedCarMoney(price, cur), sub: own + " About \(weeks) \(weeks == 1 ? "week" : "weeks").")
                Button { Haptics.tap(); askRepair(who, price, weeks, cur) } label: { Text("Send to repair").frame(maxWidth: .infinity) }
                    .buttonStyle(GoldButtonStyle()).padding(.top, 10)
                Button { Haptics.tap(); askAsIs(car, cur) } label: { Text("Sell as it is").frame(maxWidth: .infinity) }
                    .buttonStyle(GreyOutlineButtonStyle()).padding(.top, 8)
            }
        }
    }

    private func askRepair(_ who: String, _ price: Double, _ weeks: Int, _ cur: Currency) {
        let id: Int = carID, cid: Int = companyID
        pending = PendingAction(title: "Send to repair?", message: who + " repairs it for " + usedCarMoney(price, cur) + " in about \(weeks) \(weeks == 1 ? "week" : "weeks"). It is greyed out meanwhile, but customers can reserve it.",
                                button: "Send", amount: price, currency: cur, tone: .info, icon: "wrench.and.screwdriver") {
            let r: SettingResult? = store.act { (e: inout GameEngine) -> SettingResult in e.sendUsedCarToRepair(companyID: cid, carID: id) }
            store.settle(r, "Sent to the garage.")
        }
    }

    private func askAsIs(_ car: UsedCarStockItem, _ cur: Currency) {
        let id: Int = carID, cid: Int = companyID
        pending = PendingAction(title: "Sell as it is?", message: "No repair is paid. Customers see the faults, so the car looks worth less and sells at a lower price.",
                                button: "Sell as it is", risk: "You cannot send it to repair afterwards.", tone: .info, icon: "tag") {
            let r: SettingResult? = store.act { (e: inout GameEngine) -> SettingResult in e.sellUsedCarAsIs(companyID: cid, carID: id) }
            store.settle(r, "It is for sale as it is.")
        }
    }

    @ViewBuilder private func offerBlock(_ e: GameEngine, _ car: UsedCarStockItem, _ cur: Currency) -> some View {
        if let m = wholesalerOffer(e) {
            let offer: Double = m.value("data")["price"].double
            let diff: Double = offer - car.costBasis
            let note: String = diff >= 0 ? usedCarMoney(diff, cur) + " over what it cost you" : usedCarMoney(diff, cur) + " under what it cost you"
            PageGroup("Wholesaler offer") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "A wholesaler offers", value: usedCarMoney(offer, cur), sub: note, tint: diff >= 0 ? Theme.gain : Theme.loss, rule: false)
                    Button { Haptics.tap(); accept(m) } label: { Text("Sell to the wholesaler").frame(maxWidth: .infinity) }
                        .buttonStyle(GoldButtonStyle()).padding(.top, 10)
                    Button { Haptics.tap(); store.answer(m, option: 1) } label: { Text("Keep the car").frame(maxWidth: .infinity) }
                        .buttonStyle(GreyOutlineButtonStyle()).padding(.top, 8)
                }
            }
        }
    }

    private func wholesalerOffer(_ e: GameEngine) -> Message? {
        e.state.inbox.first { (m: Message) -> Bool in
            m.status == "open" && m.actionID == UsedCarDealer.offerAction && m.companyID == companyID && m.value("data")["car"].int == carID
        }
    }

    private func accept(_ m: Message) {
        store.answer(m, option: 0)
        store.show("Sold to the wholesaler.", tone: "n")
    }
}
