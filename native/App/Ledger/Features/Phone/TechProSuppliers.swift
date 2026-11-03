import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The card every TechPro grid shares: a rounded picture panel with the glyph, a bold title, a red "from <price>" line with the discount share
/// and a small label (Upgrade, Buy, Owned, or a rating). The caller wraps it in a button.
struct TechTile: View {
    @Environment(\.outsidePalette) private var P
    var photo: String = ""
    var glyph: String
    var title: String
    var from: String
    var deal: Int
    var label: String
    var tint: Color
    /// A cell key of the items sheet (see ArtLibrary.itemKey); empty keeps the photo or glyph.
    var item: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShopPhoto(name: photo, glyph: glyph, height: 96, item: item)
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(P.ink).multilineTextAlignment(.leading).lineLimit(2)
            HStack(spacing: 6) {
                Text(from).font(.system(size: 13).monospacedDigit()).foregroundStyle(deal > 0 ? P.loss : P.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                if deal > 0 { Text("-\(deal)%").font(.system(size: 12, weight: .bold)).foregroundStyle(P.loss) }
            }
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// All suppliers of one product group, each as its own box: brands (or providers, makes and models), the used listings and your own companies'
/// software. Choosing a box opens that supplier's product page (`TechProProduct`) with the key the box carries.
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
        /// How many reviews the supplier has (0 when it has none).
        var reviews: Int = 0
        /// Breakdown tendency, lower is better; 99 when the supplier does not publish one.
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
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need) -> some View {
        let cur: Currency = e.currency(for: co)
        let rows: [Row] = sorted(rowsFor(e, need, cur))
        let cols: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return ShopScroll {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(need.name).font(.system(size: 24, weight: .bold)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                    Text(EquipmentMarket.kindName(need.kind) + " \u{00B7} choose a supplier").font(.system(size: 13)).foregroundStyle(P.inkFaint)
                }
                orderChips
                ShopHeading(text: "Suppliers", trailing: rows.count == 1 ? "1 supplier" : "\(rows.count) suppliers")
                if rows.isEmpty { ShopEmptyNote(text: "Nothing on offer right now. New offers appear as the weeks go by.", buttonTitle: "Back", action: onBack) }
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(rows) { (r: Row) in box(r) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-suppliers")
    }

    private var orderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Order.allCases, id: \.self) { (o: Order) in
                    ShopChip(title: o.rawValue, selected: order == o) { order = o }.accessibilityIdentifier("tp-supsort-\(o.rawValue)")
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func box(_ r: Row) -> some View {
        Button {
            Haptics.tap()
            onPick(r.key)
        } label: {
            TechTile(photo: r.photo, glyph: r.glyph, title: r.title, from: r.from, deal: r.deal, label: r.sub, tint: P.inkFaint, item: r.item)
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
            out.append(Row(key: "mk", title: "Used items are in Marketplace", photo: "", glyph: Glyph.marketplace, price: 0, from: "Second-hand, from private sellers", deal: 0,
                           sub: "Open Marketplace", rating: 0))
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
