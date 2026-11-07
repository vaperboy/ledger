import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Which picture a vehicle gets: the vehicle photos in the asset catalogue (`AppPhotos`), by the model of vehicle. Models without a photo
/// (buses, ships, aircraft) show the vehicle icon.
enum TechPhotos {
    static func vehicle(model: String) -> String {
        switch model {
        case "van_s", "van_l", "ev_van", "van_box", "taxi_xl", "minibus", "foodtruck": return "techpro-van"
        case "pickup": return "techpro-pickup"
        case "car_s", "car_ev", "taxi_ev", "taxi_cmf": return "techpro-car"
        case "car_lux", "taxi_prm": return "techpro-premium"
        default: return ""
        }
    }
}

/// One item of the TechPro Store: its brands and classes, used listings, lease, subscription plans and your own companies' software. This is the
/// old equipment shop, rebuilt for the store: choosing an offer adds a line to the basket (`StoreOrders.Line`); paying and delivery happen at checkout.
struct TechProProduct: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var equipmentID: String
    var offerKey: String
    var onBack: () -> Void = {}
    var onAdd: (StoreOrders.Line) -> Void

    private enum Mode: Hashable { case new, used, lease }
    @State private var mode: Mode = .new
    @State private var selected: String? = nil
    @State private var quantity = 0
    @State private var finance = false
    @State private var pendingOwn: PendingAction?
    @State private var ownQty = 1

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let need = e.equipmentNeeds(companyID: companyID).first(where: { (n: EquipmentMarket.Need) -> Bool in n.equipmentID == equipmentID }) {
            content(e, co, need)
        } else {
            ShopEmptyNote(text: "This product is not sold to this company.", buttonTitle: "Back to the suppliers", action: onBack)
                .padding(Theme.Space.page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need) -> some View {
        let cur: Currency = e.currency(for: co)
        let one: Bool = need.kind == "soft" || need.kind == "svc"
        let own: Bool = offerKey == "u" || offerKey == "own" || offerKey == "co"
        let modes: [Mode] = [.new] + (need.canLease && !own ? [Mode.lease] : [])
        let current: Mode = modes.contains(mode) ? mode : .new
        return ShopPage {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hero(e, need)
                header(co, need, cur, title: title(e, need))
            }
            if modes.count > 1 { modePicker(modes, current, one: one, subscription: need.subscription) }
            options(e, co, need, current, cur, one: one)
        }
        .confirmAction($pendingOwn)
    }

    /// The supplier this page is about: "n<index>" a brand or provider, "v<id>" a make and model, "u" the used listings, "own" your own companies.
    private var offerRest: String { String(offerKey.dropFirst()) }

    private func title(_ e: GameEngine, _ need: EquipmentMarket.Need) -> String {
        if offerKey == "u" { return "Used " + need.name }
        if offerKey == "own" { return "From your own companies" }
        if offerKey == "co" { return "Your companies" }
        if offerKey.hasPrefix("v"), let o = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.VehicleOffer) -> Bool in x.id == offerRest }) { return o.name }
        if offerKey.hasPrefix("n"), let o = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.Offer) -> Bool in String(x.index) == offerRest }) { return o.name }
        return need.name
    }

    private func hero(_ e: GameEngine, _ need: EquipmentMarket.Need) -> some View {
        var photo: String = ""
        let group: String = need.kind == "soft" ? "software" : "equipment"
        var item: String = ArtLibrary.itemKey(group: group, familyKey: equipmentID, seed: equipmentID) ?? ""
        if offerKey.hasPrefix("v"), let o = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.VehicleOffer) -> Bool in x.id == offerRest }) {
            photo = TechPhotos.vehicle(model: o.modelID)
            item = ArtLibrary.itemKey(group: "vehicle", familyKey: o.modelID, seed: equipmentID + "#" + String(o.index)) ?? ""
        } else if offerKey.hasPrefix("n"), let n = Int(offerRest) {
            item = ArtLibrary.itemKey(group: group, familyKey: equipmentID, seed: equipmentID + "#" + String(n)) ?? ""
        }
        return ShopPhoto(name: photo, glyph: need.isVehicle ? Glyph.vehicle : TechCategory.of(need).glyph, height: 170, item: item)
    }

    @ViewBuilder private func options(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ current: Mode, _ cur: Currency, one: Bool) -> some View {
        if offerKey == "u" {
            used(e, co, need, cur)
        } else if offerKey == "own" {
            ownSoftware(e, need, cur)
        } else if offerKey == "co" {
            companyListings(e, cur)
        } else if offerKey.hasPrefix("v") {
            vehicleOption(e, need, current, cur)
        } else if let o = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.Offer) -> Bool in String(x.index) == offerRest }) {
            brandOption(e, co, need, o, current, cur, one: one)
        } else {
            ShopEmptyNote(text: "This supplier has nothing on offer right now.", buttonTitle: "Back to the suppliers", action: onBack)
        }
    }

    @ViewBuilder private func brandOption(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ o: EquipmentMarket.Offer, _ mode: Mode, _ cur: Currency, one: Bool) -> some View {
        if need.subscription && mode == .new {
            ShopSection(note: "Sold only as a subscription. Plans are priced by users: you have \(EquipmentMarket.users(co)).") {
                providerCard(e, o, cur)
            }
        } else {
            let p: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: o.priceFactor, vendorID: o.vendorID)
            let sale: StoreDeals.Deal = e.equipmentDeal(equipmentID: equipmentID, vendorID: o.vendorID)
            let perf: Int = Int(((o.performance - 1) * 100).rounded())
            let base: [(label: String, value: String)] = [
                (label: "Seller", value: o.seller), (label: "Class", value: o.className), (label: "Rating", value: stars(o.rating, o.reviews)),
                (label: "Output", value: (o.performance >= 1 ? "+" : "") + "\(perf)%"), (label: "Reliability", value: reliabilityWord(o.reliability))
            ]
            let facts: [(label: String, value: String)] = base + (sale.isOn ? [(label: sale.label, value: "-\(sale.percentOff)%")] : [])
            ShopSection(title: "About this offer") {
                ShopFacts(facts: facts, total: (label: "Price each", value: cur.tidyShort(p)), tints: sale.isOn ? [facts.count - 1: P.loss] : [:])
            }
            brandAdd(e, need, o, mode == .lease, cur, one: one)
        }
    }

    @ViewBuilder private func vehicleOption(_ e: GameEngine, _ need: EquipmentMarket.Need, _ mode: Mode, _ cur: Currency) -> some View {
        if let o = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.VehicleOffer) -> Bool in x.id == offerRest }) {
            let price: Double = e.vehiclePrice(modelID: o.modelID, factor: o.priceFactor)
            let sale: StoreDeals.Deal = e.vehicleDeal(modelID: o.modelID, factor: o.priceFactor)
            let base: [(label: String, value: String)] = [
                (label: "Model", value: o.modelName), (label: "Rating", value: stars(o.rating, o.reviews)), (label: "Reliability", value: reliabilityWord(o.reliability))
            ]
            let facts: [(label: String, value: String)] = base + (sale.isOn ? [(label: sale.label, value: "-\(sale.percentOff)%")] : [])
            ShopSection(title: "About this offer") {
                ShopFacts(facts: facts, total: (label: "Price new", value: cur.tidyShort(price)), tints: sale.isOn ? [facts.count - 1: P.loss] : [:])
            }
            vehicleAdd(e, o, mode == .lease, cur)
        } else {
            ShopEmptyNote(text: "This model is not on offer right now.", buttonTitle: "Back to the suppliers", action: onBack)
        }
    }

    // MARK: Header

    private func header(_ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency, title: String) -> some View {
        let have: Int = Int((need.have + need.leased).rounded())
        let sub: String = EquipmentMarket.kindName(need.kind) + " \u{00B7} lasts about \(Int(need.lifeYears)) years" + (need.warrantyYears > 0 ? " \u{00B7} warranty \(Int(need.warrantyYears)) yr new" : "")
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ShopPageTitle(title: title, subtitle: sub)
                if need.dealPercent > 0 {
                    Text("\(need.dealLabel): up to \(need.dealPercent)% off, prices below already include it")
                        .textStyle(.caption, tint: P.loss, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                }
            }
            FigureRow(items: [
                KeyFigures.Item(label: "You have", value: "\(have)"),
                KeyFigures.Item(label: "Needed", value: need.need > 0 ? "\(Int(need.need))" : "\u{2013}"),
                KeyFigures.Item(label: "Cash", value: store.short(co.cash, in: co))
            ], columns: 3, combineCells: true)
        }
    }

    private func modeTitle(_ m: Mode, one: Bool, subscription: Bool) -> String {
        switch m {
        case .new: return one ? (subscription ? "Plans" : "Licences") : "New"
        case .used: return "Used"
        case .lease: return "Lease"
        }
    }

    private func modePicker(_ modes: [Mode], _ current: Mode, one: Bool, subscription: Bool) -> some View {
        SegmentedChoice(items: modes, title: { (m: Mode) -> String in modeTitle(m, one: one, subscription: subscription) },
                        selection: Binding<Mode>(get: { current }, set: { (m: Mode) in mode = m; selected = nil; finance = false }))
    }

    // MARK: Rows

    private func stars(_ r: Double, _ n: Int) -> String { String(format: "%.1f", r) + " \u{2605} (\(n))" }

    private func reliabilityWord(_ r: Double) -> String { r < 0.85 ? "excellent" : r < 1.05 ? "good" : r < 1.25 ? "fair" : "poor" }

    private func offerRow(_ title: String, _ sub: String, _ right: String, _ id: String) -> some View {
        ShopChoiceRow(title: title, subtitle: sub, trailing: right, selected: selected == id, identifier: "tp-offer-\(id)") {
            selected = selected == id ? nil : id
        }
    }

    // MARK: New equipment and licences, by brand

    private func brandAdd(_ e: GameEngine, _ need: EquipmentMarket.Need, _ sel: EquipmentMarket.Offer, _ lease: Bool, _ cur: Currency, one: Bool) -> some View {
        let unit: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: sel.priceFactor, vendorID: sel.vendorID)
        let q: Int = one ? 1 : (quantity > 0 ? quantity : max(1, Int(need.need - need.have - need.leased)))
        let total: Double = unit * Double(q)
        let canFin: Bool = !lease && e.canFinance(companyID: companyID, equipmentID: equipmentID, total: total)
        let useFinance: Bool = finance && canFin
        let pay: EquipmentMarket.Payment = lease ? .lease : (useFinance ? .finance : .cash)
        let line = StoreOrders.Line(kind: .new, equipmentID: equipmentID, quantity: q, offerIndex: sel.index, payment: pay)
        let label: String = lease ? "Lease, 3 years, service included" : (useFinance ? "Down payment now, loan for the rest" : "Total")
        let value: String = lease ? cur.tidyShort(EquipmentMarket.leaseMonthly(price: total)) + "/mo" : (useFinance ? cur.tidyShort(total * 0.2) : cur.tidyShort(total))
        return ShopSection(title: lease ? "Lease it" : "Buy it") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if !one { ShopQuantity(value: q, range: 1...50) { (v: Int) in quantity = v } }
                if canFin { payChoice() }
                ShopFact(label: label, value: value, strong: true)
                addButton(e, line, lease ? "Add lease to basket" : "Add to basket")
            }
        }
    }

    private func addButton(_ e: GameEngine, _ line: StoreOrders.Line, _ title: String) -> some View {
        let ok: Bool = e.storeQuote(companyID: companyID, lines: [line], delivery: .standard) != nil
        return PrimaryAction(title: title, blockedReason: ok ? nil : "This is not on offer right now.", identifier: "tp-add") {
            Haptics.success()
            onAdd(line)
            selected = nil
            quantity = 0
        }
    }

    private func payChoice() -> some View {
        HStack(spacing: Theme.Space.m) {
            Text("How to pay").textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            SegmentedChoice(items: [false, true], title: { (f: Bool) -> String in f ? "Finance" : "Cash" }, selection: $finance)
                .frame(maxWidth: 200)
        }
    }

    // MARK: Items your other companies sell

    @ViewBuilder private func companyListings(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [OwnListing] = e.ownCompanyListings(forBuyer: companyID).filter { (l: OwnListing) -> Bool in l.equipmentID == equipmentID }
        ShopSection(title: "Sold by your companies", trailing: "\(list.count)", note: "You pay the selling company; the profit is its, so it stays in your group.") {
            if list.isEmpty { ShopEmptyNote(text: "None of your companies offers this now.", buttonTitle: "Back to the suppliers", action: onBack) }
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, l: OwnListing) in
                if n > 0 { Hairline() }
                CompanyListingRow(listing: l, cur: cur, qty: ownQty) { confirmBuy(l, cur) }
            }
            if !list.isEmpty { ShopQuantity(value: ownQty, range: 1...99) { (v: Int) in ownQty = v } }
        }
    }

    private func confirmBuy(_ l: OwnListing, _ cur: Currency) {
        let buyer: Int = companyID
        let q: Int = ownQty
        let total: Double = l.price * Double(q)
        let message: String = "\(l.itemName) from \(l.sellerName), \(q) for \(cur.tidyDisplay(total)). The money and the profit go to \(l.sellerName)."
        pendingOwn = PendingAction(title: "Buy from \(l.sellerName)?", message: message, button: "Buy", amount: total, currency: cur) {
            let r = store.act { $0.buyFromOwnCompany(buyer: buyer, seller: l.sellerID, itemID: l.itemID, quantity: q) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show("Bought \(l.itemName) from \(l.sellerName).", tone: "good") }
        }
    }

    // MARK: Your own software

    /// A product one of your own companies builds that does this job: the buyer pays the producer its internal price (set where the product is managed).
    /// It is taken at once (no delivery): it is a licence inside the group.
    @ViewBuilder private func ownSoftware(_ e: GameEngine, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let list: [SoftwareProducts.Offer] = e.ownSoftwareOffers(buyerID: companyID, equipmentName: need.name)
        ShopSection(title: "From your own companies", trailing: "\(list.count)") {
            if list.isEmpty { ShopEmptyNote(text: "None of your companies builds this now.", buttonTitle: "Back to the suppliers", action: onBack) }
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, o: SoftwareProducts.Offer) in
                if n > 0 { Hairline() }
                ownRow(e, o, cur)
            }
        }
    }

    private func ownRow(_ e: GameEngine, _ o: SoftwareProducts.Offer, _ cur: Currency) -> some View {
        let producer: String = e.state.company(o.producerID)?.name ?? "your company"
        let price: String = o.cost == 0 ? "free" : cur.tidyShort(o.cost) + (o.monthly ? "/mo" : "")
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(o.name).textStyle(.headline)
                Text("Built by \(producer) \u{00B7} \(o.modelName.lowercased())" + (o.tested ? " \u{00B7} test version: less reliable" : ""))
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Text(price).textStyle(.headline, numeric: true)
            Button("Use it") { confirmOwn(o, producer, cur) }.buttonStyle(SecondaryButtonStyle(size: .compact))
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func confirmOwn(_ o: SoftwareProducts.Offer, _ producer: String, _ cur: Currency) {
        let id: Int = companyID
        let equip: String = equipmentID
        let price: String = o.cost == 0 ? "at no charge" : "for \(cur.tidyDisplay(o.cost))" + (o.monthly ? " a month" : " once")
        let message: String = "This company takes \(o.name) from \(producer) \(price); the money goes to \(producer). " + (o.tested ? "It is still a test version and may let you down. " : "") + "It replaces any other software of this kind here."
        pendingOwn = PendingAction(title: "Use \(o.name)?", message: message, button: "Use it", amount: o.cost, currency: cur) {
            switch store.act({ $0.useOwnSoftware(companyID: id, equipmentID: equip, producerID: o.producerID) }) {
            case .ok?:
                Haptics.success()
                store.show("Now using \(o.name) from \(producer).", tone: "good")
            case .notEnoughCash?:
                Haptics.warning()
                store.show("Not enough cash in the company.", tone: "warn")
            default:
                Haptics.warning()
                store.show("Not possible.", tone: "warn")
            }
        }
    }

    // MARK: Subscriptions

    private func providerCard(_ e: GameEngine, _ o: EquipmentMarket.Offer, _ cur: Currency) -> some View {
        let list: [EquipmentMarket.Plan] = e.subscriptionPlans(companyID: companyID, equipmentID: equipmentID, offer: o)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.name).textStyle(.headline)
                Spacer(minLength: Theme.Space.s)
                Text(stars(o.rating, o.reviews)).textStyle(.caption, tint: P.inkFaint)
            }
            ForEach(list, id: \.index) { (p: EquipmentMarket.Plan) in
                Hairline()
                planRow(e, o, p, cur)
            }
        }
    }

    private func planRow(_ e: GameEngine, _ o: EquipmentMarket.Offer, _ p: EquipmentMarket.Plan, _ cur: Currency) -> some View {
        let line = StoreOrders.Line(kind: .plan, equipmentID: equipmentID, offerIndex: o.index, plan: p.index)
        let ok: Bool = e.storeQuote(companyID: companyID, lines: [line], delivery: .standard) != nil
        let users: String = p.maxUsers > 1_000_000 ? "any number of users" : "up to \(p.maxUsers) users"
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(p.name + (p.recommended ? " \u{00B7} fits your team" : "")).textStyle(.headline)
                Text(ok ? users : users + " \u{00B7} not on offer now").textStyle(.caption)
            }
            Spacer(minLength: Theme.Space.s)
            Text(cur.tidyShort(p.monthlyFee) + "/mo").textStyle(.headline, numeric: true)
            Button("Add") {
                Haptics.success()
                onAdd(line)
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact))
            .disabled(!ok)
        }
    }

    // MARK: Used

    @ViewBuilder private func used(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        ShopNote(title: "Bought used", text: "Used items are in Marketplace: second-hand goods from private sellers, with a price you can talk down.",
                 actionTitle: "Open Marketplace", identifier: "tp-open-marketplace") {
            store.openApp(.marketplace)
        }
    }

    // MARK: Vehicles

    private func vehicleAdd(_ e: GameEngine, _ sel: EquipmentMarket.VehicleOffer, _ lease: Bool, _ cur: Currency) -> some View {
        let price: Double = e.vehiclePrice(modelID: sel.modelID, factor: sel.priceFactor)
        let pay: EquipmentMarket.Payment = lease ? .lease : (finance ? .finance : .cash)
        let line = StoreOrders.Line(kind: .vehicle, equipmentID: equipmentID, vehicleOfferID: sel.id, payment: pay)
        let label: String = lease ? "Lease, 3 years" : (finance ? "Down payment now, loan for the rest" : "Total")
        let value: String = lease ? cur.tidyShort(EquipmentMarket.vehicleLeaseMonthly(price: price)) + "/mo" : cur.tidyShort(finance ? price * 0.2 : price)
        return ShopSection(title: lease ? "Lease it" : "Buy it") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if !lease { payChoice() }
                ShopFact(label: label, value: value, strong: true)
                addButton(e, line, lease ? "Add lease to basket" : "Add to basket")
            }
        }
    }
}

/// One item a sister company sells to this one: the item, who sells it and the price a unit.
private struct CompanyListingRow: View {
    @Environment(\.outsidePalette) private var P
    var listing: OwnListing
    var cur: Currency
    var qty: Int
    var buy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(listing.itemName).textStyle(.headline)
                Text("Sold by \(listing.sellerName)").textStyle(.caption)
            }
            Spacer(minLength: Theme.Space.s)
            Text(cur.tidyShort(listing.price)).textStyle(.headline, numeric: true)
            Button("Buy") { buy() }.buttonStyle(SecondaryButtonStyle(size: .compact))
        }
        .padding(.vertical, Theme.Space.xs)
    }
}
