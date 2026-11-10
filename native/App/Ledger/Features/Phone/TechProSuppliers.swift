import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct TechTile: View {
    @Environment(\.outsidePalette) private var P
    var photo: String = ""
    var glyph: String
    var title: String
    var from: String
    var deal: Int
    var label: String
    var tint: Color
    var item: String = ""

    var body: some View {
        ShopProductCard(photo: photo, glyph: glyph, item: item, title: title, price: from, priceTint: deal > 0 ? P.loss : P.inkSoft, deal: deal,
                        note: label, noteTint: tint)
    }
}

struct TechProSuppliers: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var equipmentID: String
    var onBack: () -> Void = {}
    var onPick: (String) -> Void

    private enum Order: String, CaseIterable, Hashable {
        case best = "Best rated", low = "Price: low to high", high = "Price: high to low", deal = "Biggest discount", popular = "Most reviewed", reliable = "Most reliable", az = "A to Z"
    }
    @State private var order: Order = .best

    private struct Row: Identifiable {
        var key: String
        var title: String
        var photo: String
        var glyph: String
        var price: Double
        var from: String
        var deal: Int
        var sub: String
        var rating: Double
        var reviews: Int = 0
        var breakdown: Double = 99
        var item: String = ""
        var id: String { key }
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let need = e.equipmentNeeds(companyID: companyID).first(where: { (n: EquipmentMarket.Need) -> Bool in n.equipmentID == equipmentID }) {
            content(e, co, need)
        } else {
            ShopEmptyNote(text: "This product is not sold to this company.", buttonTitle: "Back to the store", action: onBack)
                .padding(Theme.Space.page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need) -> some View {
        let cur: Currency = e.currency(for: co)
        let rows: [Row] = sorted(rowsFor(e, need, cur))
        let priced: [Double] = rows.filter { (r: Row) -> Bool in r.key != "mk" && r.price > 0 }.map { (r: Row) -> Double in r.price }
        let count: String = rows.count == 1 ? "1 supplier" : "\(rows.count) suppliers"
        let low: String = priced.min().map { (v: Double) -> String in " \u{00B7} from " + cur.tidyShort(v) + (need.subscription ? "/mo" : "") } ?? ""
        return ShopPage {
            ShopHero(label: EquipmentMarket.kindName(need.kind), value: need.name, note: count + low)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    ShopHeading(text: "Choose a supplier")
                    Spacer(minLength: Theme.Space.s)
                    sortMenu
                }
                if rows.isEmpty { ShopEmptyNote(text: "Nothing on offer right now. New offers appear as the weeks go by.", buttonTitle: "Back", action: onBack) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, r: Row) in
                    if n > 0 { Hairline().padding(.leading, 68) }
                    box(r)
                }
            }
        }
        .accessibilityIdentifier("tp-suppliers")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(Order.allCases, id: \.self) { (o: Order) in
                Button { Haptics.choose(); order = o } label: {
                    if o == order { Label(o.rawValue, systemImage: "checkmark") } else { Text(o.rawValue) }
                }
                .accessibilityIdentifier("tp-supsort-\(o.rawValue)")
            }
        } label: {
            ShopMenuLabel(text: order.rawValue)
        }
        .accessibilityLabel("Sort: \(order.rawValue)")
    }

    private func box(_ r: Row) -> some View {
        Button {
            Haptics.tap()
            onPick(r.key)
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                ShopThumb(photo: r.photo, glyph: r.glyph, item: r.item, size: 56)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(r.title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(r.sub.tidyText).textStyle(.caption).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    if r.key != "mk" { Text(r.from.tidyText).textStyle(.headline, tint: r.deal > 0 ? P.loss : nil, numeric: true).lineLimit(1).minimumScaleFactor(0.7) }
                    if r.deal > 0 { Text("-\(r.deal)%").textStyle(.caption, tint: P.loss, weight: .semibold) }
                }
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("tp-supplier-\(r.key)")
    }

    private func sorted(_ rows: [Row]) -> [Row] {
        rows.sorted { (a: Row, b: Row) -> Bool in
            switch order {
            case .best: return a.rating != b.rating ? a.rating > b.rating : a.title < b.title
            case .low: return a.price != b.price ? a.price < b.price : a.title < b.title
            case .high: return a.price != b.price ? a.price > b.price : a.title < b.title
            case .deal: return a.deal != b.deal ? a.deal > b.deal : a.title < b.title
            case .popular: return a.reviews != b.reviews ? a.reviews > b.reviews : a.title < b.title
            case .reliable: return a.breakdown != b.breakdown ? a.breakdown < b.breakdown : a.title < b.title
            case .az: return a.title < b.title
            }
        }
    }

    private func reliabilityWord(_ r: Double) -> String { r < 0.85 ? "excellent" : r < 1.05 ? "good" : r < 1.25 ? "fair" : "poor" }

    private func stars(_ r: Double, _ n: Int) -> String { String(format: "%.1f", r) + " \u{2605} (\(n))" }

    private func cell(_ need: EquipmentMarket.Need, _ seed: String) -> String {
        let group: String = need.kind == "soft" ? "software" : "equipment"
        return ArtLibrary.itemKey(group: group, familyKey: need.equipmentID, seed: seed) ?? ""
    }

    private func rowsFor(_ e: GameEngine, _ need: EquipmentMarket.Need, _ cur: Currency) -> [Row] {
        var out: [Row] = []
        let glyph: String = TechCategory.of(need).glyph
        if need.isVehicle {
            for o in e.vehicleOffers(companyID: companyID, equipmentID: equipmentID) {
                let p: Double = e.vehiclePrice(modelID: o.modelID, factor: o.priceFactor)
                let sale: StoreDeals.Deal = e.vehicleDeal(modelID: o.modelID, factor: o.priceFactor)
                out.append(Row(key: "v" + o.id, title: o.name, photo: TechPhotos.vehicle(model: o.modelID), glyph: Glyph.vehicle, price: p, from: "from " + cur.tidyShort(p),
                               deal: sale.isOn ? sale.percentOff : 0, sub: stars(o.rating, o.reviews) + " \u{00B7} reliability " + reliabilityWord(o.reliability), rating: o.rating, reviews: o.reviews, breakdown: o.reliability,
                               item: ArtLibrary.itemKey(group: "vehicle", familyKey: o.modelID, seed: equipmentID + "#" + String(o.index)) ?? ""))
            }
        } else if need.subscription {
            for o in e.equipmentOffers(companyID: companyID, equipmentID: equipmentID) where o.cls == 1 {
                let fees: [Double] = e.subscriptionPlans(companyID: companyID, equipmentID: equipmentID, offer: o).map { (p: EquipmentMarket.Plan) -> Double in p.monthlyFee }
                let low: Double = fees.min() ?? 0
                out.append(Row(key: "n\(o.index)", title: o.name, photo: "", glyph: glyph, price: low, from: "from " + cur.tidyShort(low) + "/mo", deal: 0,
                               sub: stars(o.rating, o.reviews), rating: o.rating, reviews: o.reviews, breakdown: o.reliability,
                               item: cell(need, equipmentID + "#" + String(o.index))))
            }
        } else {
            for o in e.equipmentOffers(companyID: companyID, equipmentID: equipmentID) {
                let p: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: o.priceFactor, vendorID: o.vendorID)
                let sale: StoreDeals.Deal = e.equipmentDeal(equipmentID: equipmentID, vendorID: o.vendorID)
                out.append(Row(key: "n\(o.index)", title: o.name, photo: "", glyph: glyph, price: p, from: "from " + cur.tidyShort(p), deal: sale.isOn ? sale.percentOff : 0,
                               sub: o.className + " \u{00B7} " + stars(o.rating, o.reviews), rating: o.rating, reviews: o.reviews, breakdown: o.reliability,
                               item: cell(need, equipmentID + "#" + String(o.index))))
            }
        }
        if need.canUsed {
            out.append(Row(key: "mk", title: "Buy it used on Marketplace", photo: "", glyph: Glyph.marketplace, price: 0, from: "", deal: 0,
                           sub: "Second-hand, from private sellers", rating: 0))
        }
        if need.kind == "soft" {
            let own: [SoftwareProducts.Offer] = e.ownSoftwareOffers(buyerID: companyID, equipmentName: need.name)
            if !own.isEmpty {
                let low: Double = own.map { (o: SoftwareProducts.Offer) -> Double in o.cost }.min() ?? 0
                out.append(Row(key: "own", title: "Your own companies", photo: "", glyph: glyph, price: low, from: low == 0 ? "free" : "from " + cur.tidyShort(low), deal: 0,
                               sub: own.count == 1 ? "1 product" : "\(own.count) products", rating: 5, item: cell(need, equipmentID)))
            }
        }
        let mine: [OwnListing] = e.ownCompanyListings(forBuyer: companyID).filter { (l: OwnListing) -> Bool in l.equipmentID == equipmentID }
        if !mine.isEmpty {
            let low: Double = mine.map { (l: OwnListing) -> Double in l.price }.min() ?? 0
            out.append(Row(key: "co", title: "Your companies", photo: "", glyph: glyph, price: low, from: "from " + cur.tidyShort(low), deal: 0,
                           sub: mine.count == 1 ? "1 item, profit stays in the group" : "\(mine.count) items, profit stays in the group", rating: 5, item: cell(need, equipmentID)))
        }
        return out
    }
}
