import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum UsedCarPhotos {
    static func name(family: String, title: String) -> String {
        let direct: String = TechPhotos.vehicle(model: family)
        if !direct.isEmpty { return direct }
        let f: String = (family + " " + title).lowercased()
        func has(_ words: [String]) -> Bool { words.contains { (w: String) -> Bool in f.contains(w) } }
        if has(["pickup"]) { return "techpro-pickup" }
        if has(["van", "truck", "bus", "trailer", "tractor", "ambulance"]) { return "techpro-van" }
        if has(["lux", "premium", "limousine", "coupe", "sport"]) { return "techpro-premium" }
        return "techpro-car"
    }
}

struct UsedCarPhoto: View {
    var family: String
    var title: String
    var size: CGFloat = 42
    var square = false

    var body: some View {
        let name: String = UsedCarPhotos.name(family: family, title: title)
        return slot(name).frame(width: size, height: size).accessibilityHidden(true)
    }

    @ViewBuilder private func slot(_ name: String) -> some View {
        #if canImport(UIKit)
        if let ui = ArtAsset.uiImage(name) {
            if square {
                let box = RoundedRectangle(cornerRadius: max(6, size * 0.22), style: .continuous)
                Image(uiImage: ui).resizable().scaledToFill().frame(width: size, height: size).clipped().clipShape(box).overlay(box.strokeBorder(Theme.borderStrong, lineWidth: 1))
            } else {
                Image(uiImage: ui).resizable().scaledToFill().frame(width: size, height: size).clipped().clipShape(Circle()).overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
            }
        } else {
            IconCircle(glyph: Glyph.vehicle, size: size, tint: Theme.gold)
        }
        #else
        IconCircle(glyph: Glyph.vehicle, size: size, tint: Theme.gold)
        #endif
    }
}

func usedCarMoney(_ v: Double, _ cur: Currency) -> String {
    let a: Double = abs(v)
    return a / cur.rate >= 100 ? cur.tidyShort(a) : itemAmount(a, cur)
}

func usedCarProfitReading(_ q: UsedCarQuote, _ cur: Currency) -> (text: String, tint: Color) {
    if abs(q.profit) / cur.rate < 0.005 { return ("Break-even", Theme.ivoryMuted) }
    return (q.verdict + " " + usedCarMoney(q.profit, cur), q.isProfit ? Theme.gain : Theme.loss)
}

func usedCarStatusText(_ c: UsedCarStockItem) -> String {
    switch c.status {
    case "repair": return c.repairWeeksLeft > 0 ? "In repair, back in \(c.repairWeeksLeft) \(c.repairWeeksLeft == 1 ? "week" : "weeks")" : "In repair"
    case "quoted": return "Quoted"
    case "new": return "Just arrived"
    default: return "Ready"
    }
}

struct UsedCarRowView: View {
    var car: UsedCarStockItem
    var cur: Currency
    var quote: UsedCarQuote?

    var body: some View {
        let reading: (text: String, tint: Color) = readingText()
        let atGarage: Bool = car.status == "repair"
        return HStack(alignment: .center, spacing: 12) {
            UsedCarPhoto(family: car.family, title: car.title)
            VStack(alignment: .leading, spacing: 4) {
                Text(car.title).textStyle(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(usedCarStatusText(car)).textStyle(.caption).lineLimit(1)
                    if car.reserved { TeamBadge(text: "Reserved", tint: Theme.gold) }
                    if car.stuck { TeamBadge(text: "Stuck", tint: Theme.loss) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(cur.tidyShort(car.askingPrice)).textStyle(.headline, numeric: true)
                Text(reading.text).textStyle(.caption, tint: reading.tint, numeric: true)
            }
            GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .opacity(atGarage ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func readingText() -> (text: String, tint: Color) {
        guard let q = quote else { return ("", Theme.ivoryMuted) }
        if !q.repairsKnown { return ("Not inspected", Theme.ivoryFaint) }
        return usedCarProfitReading(q, cur)
    }
}

struct UsedCarPick: Identifiable, Hashable { var id: Int }

struct UsedCarYardSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var openCar: UsedCarPick?
    @State private var showHire = false

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let cars: [UsedCarStockItem] = engine.usedCarStock(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            carsGroup(cars, cur)
            lotBlock(cur)
            buyersBlock()
            repairBlock()
            salesBlock(cur)
        }
        .navigationDestination(item: $openCar) { (p: UsedCarPick) in UsedCarPageView(companyID: company.id, carID: p.id) }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: company.id, startRole: "buyer") }
    }

    private func carsGroup(_ cars: [UsedCarStockItem], _ cur: Currency) -> some View {
        let value: Double = cars.reduce(0) { (a: Double, c: UsedCarStockItem) -> Double in a + c.purchasePrice + c.repairs }
        let noun: String = cars.count == 1 ? "car" : "cars"
        let count: String = "\(cars.count) \(noun), \(cur.tidyShort(value)) in stock"
        return PageGroup(title: "Cars", trailing: {
            Text(count).textStyle(.caption, tint: Theme.inkFaint)
        }) {
            if cars.isEmpty {
                Text("The yard is empty: buy cars in Marketplace.")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(cars.enumerated()), id: \.element.id) { (n: Int, c: UsedCarStockItem) -> AnyView in
                AnyView(VStack(spacing: 0) {
                    if n > 0 { RowRule(inset: 54) }
                    carRow(c, cur)
                })
            }
        }
    }

    private func carRow(_ c: UsedCarStockItem, _ cur: Currency) -> some View {
        let q: UsedCarQuote? = engine.usedCarQuote(companyID: company.id, carID: c.id, price: c.askingPrice)
        let id: Int = c.id
        return Button { Haptics.tap(); openCar = UsedCarPick(id: id) } label: { UsedCarRowView(car: c, cur: cur, quote: q) }
            .buttonStyle(AcctPressStyle())
            .accessibilityIdentifier("dealer-car-\(id)")
    }

    private func lotBlock(_ cur: Currency) -> some View {
        let lot: UsedCarLot? = engine.usedCarLot(companyID: company.id)
        let spaces: Int = lot?.spaces ?? 0
        let used: Int = lot?.used ?? 0
        let free: Int = lot?.free ?? 0
        let full: Color? = free == 0 ? Theme.loss : nil
        let sub: String = spaces == 0 ? "No space for cars here" : (free == 0 ? "Full: sell one before buying" : "")
        return PageGroup("Lot") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Spaces used", value: "\(used) of \(spaces)", sub: sub, tint: full, rule: false)
                FlatRow(label: "Free spaces", value: "\(free)", tint: free == 0 ? Theme.loss : Theme.gain)
            }
        }
    }

    private func buyersBlock() -> some View {
        let recs: [UsedCarBuyerRecord] = engine.usedCarBuyers(companyID: company.id)
        return PageGroup("Buyers") {
            VStack(alignment: .leading, spacing: 0) {
                if recs.isEmpty {
                    Text("You buy by hand in Marketplace.")
                        .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
                }
                ForEach(Array(recs.enumerated()), id: \.offset) { (i: Int, r: UsedCarBuyerRecord) in
                    FlatRow(label: r.name + " (" + roleWord(r.role) + ")", value: Words.level(r.rating, scale: .quality), sub: track(r), rule: i > 0)
                }
                if company.status == .open {
                    Button("Hire a buyer") { Haptics.tap(); showHire = true }
                        .buttonStyle(TertiaryButtonStyle(size: .compact))
                }
            }
        }
    }

    private func roleWord(_ role: String) -> String {
        switch role {
        case "buyer": return "buyer"
        case "manager": return "manager"
        default: return "you"
        }
    }

    private func track(_ r: UsedCarBuyerRecord) -> String {
        if r.deals == 0 { return "No deals yet" }
        let pct: String = String(format: "%.1f", abs(r.averageDiscount * 100))
        let how: String = r.averageDiscount >= 0 ? "under" : "over"
        return "\(r.deals) \(r.deals == 1 ? "deal" : "deals"), \(pct) percent \(how) fair value on average"
    }

    private func repairBlock() -> some View {
        let on: Bool = engine.usedCarAutoRepair(companyID: company.id)
        let binding: Binding<Bool> = Binding<Bool>(get: { on }, set: { (v: Bool) in
            let r: SettingResult? = store.act { (e: inout GameEngine) -> SettingResult in e.setUsedCarAutoRepair(companyID: company.id, on: v) }
            store.settle(r, v ? "Repairs go to the garage at once." : "You decide car by car.")
        })
        return PageGroup("Repairs") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Send every repair to the garage at once", isOn: binding).tint(Theme.gold).textStyle(.headline)
                Text("Off: you decide car by car.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func salesBlock(_ cur: Currency) -> some View {
        let sold: [UsedCarSale] = Array(engine.usedCarSales(companyID: company.id).suffix(6).reversed())
        if !sold.isEmpty {
            PageGroup("Last sold") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sold.enumerated()), id: \.offset) { (i: Int, s: UsedCarSale) in
                        FlatRow(label: s.title, value: saleReading(s, cur).text, sub: saleNote(s), tint: saleReading(s, cur).tint, rule: i > 0)
                    }
                }
            }
        }
    }

    private func saleReading(_ s: UsedCarSale, _ cur: Currency) -> (text: String, tint: Color) {
        if abs(s.profit) / cur.rate < 0.005 { return ("Break-even", Theme.ivoryMuted) }
        let word: String = s.profit >= 0 ? "Profit " : "Loss "
        return (word + usedCarMoney(s.profit, cur), s.profit >= 0 ? Theme.gain : Theme.loss)
    }

    private func saleNote(_ s: UsedCarSale) -> String {
        switch s.forced {
        case "": return "Sold"
        case "wholesaler": return "Sold to a wholesaler"
        default: return "Forced sale"
        }
    }
}
