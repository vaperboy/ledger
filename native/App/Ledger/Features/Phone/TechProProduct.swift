import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

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

struct TechProProduct: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var equipmentID: String
    var offerKey: String
    var basketCount: Int = 0
    var onBack: () -> Void = {}
    var onAdd: (StoreOrders.Line) -> Void
    var onBasket: () -> Void = {}

    private enum Mode: Hashable { case new, used, lease }
    @State private var mode: Mode = .new
    @State private var quantity = 0
    @State private var finance = false
    @State private var pendingOwn: PendingAction?
    @State private var ownQty = 1

    private struct Purchase {
        var line: StoreOrders.Line
        var value: String
        var caption: String
        var title: String
        var ok: Bool
    }

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
        let buy: Purchase? = purchase(e, need, current, cur, one: one)
        return ShopPage {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hero(e, need)
                header(need, title: title(e, need))
            }
            if modes.count > 1 { modePicker(modes, current, one: one, subscription: need.subscription) }
            options(e, co, need, current, cur, one: one)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(buy) }
        .confirmAction($pendingOwn)
    }

    @ViewBuilder private func bottomBar(_ buy: Purchase?) -> some View {
        if buy != nil || basketCount > 0 {
            VStack(spacing: 0) {
                if basketCount > 0 {
                    HStack(spacing: Theme.Space.s) {
                        LedgerGlyph(glyph: Glyph.cart, size: Theme.Icon.small, tint: P.inkSoft)
                        Text(basketCount == 1 ? "1 item in your basket" : "\(basketCount) items in your basket").textStyle(.caption).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Button("View basket") { Haptics.tap(); onBasket() }
                            .buttonStyle(TertiaryButtonStyle(size: .compact))
                            .accessibilityIdentifier("tp-view-basket")
                    }
                    .padding(.horizontal, Theme.Space.page)
                    .frame(maxWidth: ShopMetrics.maxWidth).frame(maxWidth: .infinity)
                    .background(P.page)
                    .overlay(alignment: .top) { Hairline() }
                }
                if let buy {
                    ShopActionBar(left: { ShopPriceTag(value: buy.value, caption: buy.caption) }, action: {
                        PrimaryAction(title: buy.title, blockedReason: buy.ok ? nil : "Not on offer now.", identifier: "tp-add") {
                            Haptics.success()
                            onAdd(buy.line)
                            quantity = 0
                        }
                    })
                }
            }
        }
    }

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
        var photo: String = need.isVehicle ? "" : ArtAsset.equipment(equipmentID)
        let group: String = need.kind == "soft" ? "software" : "equipment"
        var item: String = ArtAsset.cellFallback(equipmentID, group: group, seed: equipmentID)
        if offerKey.hasPrefix("v"), let o = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.VehicleOffer) -> Bool in x.id == offerRest }) {
            photo = TechPhotos.vehicle(model: o.modelID)
            item = ArtLibrary.itemKey(group: "vehicle", familyKey: o.modelID, seed: equipmentID + "#" + String(o.index)) ?? ""
        } else if offerKey.hasPrefix("n"), let n = Int(offerRest) {
            item = ArtLibrary.itemKey(group: group, familyKey: equipmentID, seed: equipmentID + "#" + String(n)) ?? ""
        }
        return ShopPhoto(name: photo, glyph: need.isVehicle ? Glyph.vehicle : TechCategory.of(need).glyph, height: 220, item: item)
    }

    @ViewBuilder private func options(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ current: Mode, _ cur: Currency, one: Bool) -> some View {
        if offerKey == "u" {
            used()
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
            ShopSection(title: "Plans", note: "Priced by users: you have \(EquipmentMarket.users(co)).") {
                providerCard(e, o, cur)
            }
        } else {
            let p: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: o.priceFactor, vendorID: o.vendorID)
            let sale: StoreDeals.Deal = e.equipmentDeal(equipmentID: equipmentID, vendorID: o.vendorID)
            let perf: Int = Int(saturating: ((o.performance - 1) * 100).rounded())
            let base: [(label: String, value: String)] = [
                (label: "Price each", value: cur.tidyShort(p)),
                (label: "Seller", value: o.seller), (label: "Class", value: o.className), (label: "Rating", value: stars(o.rating, o.reviews)),
                (label: "Output", value: (o.performance >= 1 ? "+" : "") + "\(perf)%"), (label: "Reliability", value: reliabilityWord(o.reliability))
            ]
            let facts: [(label: String, value: String)] = base + (sale.isOn ? [(label: sale.label, value: "-\(sale.percentOff)%")] : [])
            buyControls(e, need, mode == .lease, one: one, total: p * Double(qty(need, one: one)))
            ShopSection(title: "About this offer") {
                ShopFacts(facts: facts, tints: sale.isOn ? [facts.count - 1: P.loss] : [:])
            }
        }
    }

    @ViewBuilder private func vehicleOption(_ e: GameEngine, _ need: EquipmentMarket.Need, _ mode: Mode, _ cur: Currency) -> some View {
        if let o = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.VehicleOffer) -> Bool in x.id == offerRest }) {
            let price: Double = e.vehiclePrice(modelID: o.modelID, factor: o.priceFactor)
            let sale: StoreDeals.Deal = e.vehicleDeal(modelID: o.modelID, factor: o.priceFactor)
            let base: [(label: String, value: String)] = [
                (label: "Price new", value: cur.tidyShort(price)),
                (label: "Model", value: o.modelName), (label: "Rating", value: stars(o.rating, o.reviews)), (label: "Reliability", value: reliabilityWord(o.reliability))
            ]
            let facts: [(label: String, value: String)] = base + (sale.isOn ? [(label: sale.label, value: "-\(sale.percentOff)%")] : [])
            if mode != .lease { payChoice() }
            ShopSection(title: "About this offer") {
                ShopFacts(facts: facts, tints: sale.isOn ? [facts.count - 1: P.loss] : [:])
            }
        } else {
            ShopEmptyNote(text: "This model is not on offer right now.", buttonTitle: "Back to the suppliers", action: onBack)
        }
    }

    private func header(_ need: EquipmentMarket.Need, title: String) -> some View {
        let have: Int = Int(saturating: (need.have + need.leased).rounded())
        let sub: String = EquipmentMarket.kindName(need.kind) + " \u{00B7} lasts about \(Int(need.lifeYears)) years" + (need.warrantyYears > 0 ? " \u{00B7} \(Int(need.warrantyYears)) yr warranty" : "")
        let owned: String = need.need > 0 ? "You have \(have) of \(Int(need.need)) needed" : (have > 0 ? "You have \(have)" : "You have none yet")
        let short: Bool = need.need > 0 && Double(have) < need.need
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ShopPageTitle(title: title, subtitle: sub)
            Text(owned).textStyle(.body, tint: short ? P.caution : P.inkSoft, weight: .medium)
            if need.dealPercent > 0 {
                Text("\(need.dealLabel): up to \(need.dealPercent)% off, already in the prices")
                    .textStyle(.caption, tint: P.loss, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modeTitle(_ m: Mode, one: Bool, subscription: Bool) -> String {
        switch m {
        case .new: return one ? (subscription ? "Plans" : "Licences") : "Buy"
        case .used: return "Used"
        case .lease: return "Lease"
        }
    }

    private func modePicker(_ modes: [Mode], _ current: Mode, one: Bool, subscription: Bool) -> some View {
        SegmentedChoice(items: modes, title: { (m: Mode) -> String in modeTitle(m, one: one, subscription: subscription) },
                        selection: Binding<Mode>(get: { current }, set: { (m: Mode) in mode = m; finance = false }))
    }

    private func stars(_ r: Double, _ n: Int) -> String { String(format: "%.1f", r) + " \u{2605} (\(n))" }

    private func reliabilityWord(_ r: Double) -> String { r < 0.85 ? "excellent" : r < 1.05 ? "good" : r < 1.25 ? "fair" : "poor" }

    private func qty(_ need: EquipmentMarket.Need, one: Bool) -> Int {
        one ? 1 : (quantity > 0 ? quantity : max(1, Int(need.need - need.have - need.leased)))
    }

    @ViewBuilder private func buyControls(_ e: GameEngine, _ need: EquipmentMarket.Need, _ lease: Bool, one: Bool, total: Double) -> some View {
        let canFin: Bool = !lease && e.canFinance(companyID: companyID, equipmentID: equipmentID, total: total)
        if !one || canFin {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if !one { ShopQuantity(value: qty(need, one: one), range: 1...50) { (v: Int) in quantity = v } }
                if canFin { payChoice() }
            }
        }
    }

    private func purchase(_ e: GameEngine, _ need: EquipmentMarket.Need, _ mode: Mode, _ cur: Currency, one: Bool) -> Purchase? {
        let lease: Bool = mode == .lease
        if offerKey.hasPrefix("v") {
            guard let o = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.VehicleOffer) -> Bool in x.id == offerRest }) else { return nil }
            let price: Double = e.vehiclePrice(modelID: o.modelID, factor: o.priceFactor)
            let pay: EquipmentMarket.Payment = lease ? .lease : (finance ? .finance : .cash)
            let line = StoreOrders.Line(kind: .vehicle, equipmentID: equipmentID, vehicleOfferID: o.id, payment: pay)
            let value: String = lease ? cur.tidyShort(EquipmentMarket.vehicleLeaseMonthly(price: price)) + "/mo" : cur.tidyShort(finance ? price * 0.2 : price)
            let caption: String = lease ? "lease, 3 years" : (finance ? "down now, loan for the rest" : "total")
            return Purchase(line: line, value: value, caption: caption, title: lease ? "Add lease" : "Add to basket", ok: quoteOK(e, line))
        }
        guard offerKey.hasPrefix("n"), !(need.subscription && mode == .new),
              let o = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID).first(where: { (x: EquipmentMarket.Offer) -> Bool in String(x.index) == offerRest }) else { return nil }
        let unit: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: o.priceFactor, vendorID: o.vendorID)
        let q: Int = qty(need, one: one)
        let total: Double = unit * Double(q)
        let canFin: Bool = !lease && e.canFinance(companyID: companyID, equipmentID: equipmentID, total: total)
        let useFinance: Bool = finance && canFin
        let pay: EquipmentMarket.Payment = lease ? .lease : (useFinance ? .finance : .cash)
        let line = StoreOrders.Line(kind: .new, equipmentID: equipmentID, quantity: q, offerIndex: o.index, payment: pay)
        let value: String = lease ? cur.tidyShort(EquipmentMarket.leaseMonthly(price: total)) + "/mo" : (useFinance ? cur.tidyShort(total * 0.2) : cur.tidyShort(total))
        let caption: String = lease ? "lease, 3 years, service included" : (useFinance ? "down now, loan for the rest" : (q == 1 ? "total" : "total for \(q)"))
        return Purchase(line: line, value: value, caption: caption, title: lease ? "Add lease" : "Add to basket", ok: quoteOK(e, line))
    }

    private func quoteOK(_ e: GameEngine, _ line: StoreOrders.Line) -> Bool {
        e.storeQuote(companyID: companyID, lines: [line], delivery: .standard) != nil
    }

    private func payChoice() -> some View {
        HStack(spacing: Theme.Space.m) {
            Text("How to pay").textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            SegmentedChoice(items: [false, true], title: { (f: Bool) -> String in f ? "Finance" : "Cash" }, selection: $finance)
                .frame(maxWidth: 200)
        }
    }

    @ViewBuilder private func companyListings(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [OwnListing] = e.ownCompanyListings(forBuyer: companyID).filter { (l: OwnListing) -> Bool in l.equipmentID == equipmentID }
        ShopSection(title: "Sold by your companies", trailing: "\(list.count)", note: "You pay the selling company; the profit stays in your group.") {
            if list.isEmpty { ShopEmptyNote(text: "None of your companies offers this now.", buttonTitle: "Back to the suppliers", action: onBack) }
            if !list.isEmpty { ShopQuantity(value: ownQty, range: 1...99) { (v: Int) in ownQty = v } }
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, l: OwnListing) in
                if n > 0 { Hairline() }
                CompanyListingRow(listing: l, cur: cur, qty: ownQty) { confirmBuy(l, cur) }
            }
        }
    }

    private func confirmBuy(_ l: OwnListing, _ cur: Currency) {
        let buyer: Int = companyID
        let q: Int = ownQty
        let total: Double = l.price * Double(q)
        let message: String = "\(l.itemName) from \(l.sellerName), \(q) for \(cur.tidyDisplay(total)). The money and the profit go to \(l.sellerName)."
        pendingOwn = PendingAction(title: "Buy from \(l.sellerName)?", message: message, button: "Buy", amount: total, currency: cur, tone: .info, icon: "cart") {
            let r = store.act { $0.buyFromOwnCompany(buyer: buyer, seller: l.sellerID, itemID: l.itemID, quantity: q) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show("Bought \(l.itemName) from \(l.sellerName).", tone: "good") }
        }
    }

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
                Text(price).textStyle(.headline, numeric: true)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Use it") { confirmOwn(o, producer, cur) }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }
        .padding(.vertical, Theme.Space.s)
    }

    private func confirmOwn(_ o: SoftwareProducts.Offer, _ producer: String, _ cur: Currency) {
        let id: Int = companyID
        let equip: String = equipmentID
        let price: String = o.cost == 0 ? "at no charge" : "for \(cur.tidyDisplay(o.cost))" + (o.monthly ? " a month" : " once")
        let message: String = "This company takes \(o.name) from \(producer) \(price); the money goes to \(producer). " + (o.tested ? "It is still a test version and may let you down. " : "") + "It replaces any other software of this kind here."
        pendingOwn = PendingAction(title: "Use \(o.name)?", message: message, button: "Use it", amount: o.cost, currency: cur, tone: .info, icon: "app.badge.checkmark") {
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

    private func providerCard(_ e: GameEngine, _ o: EquipmentMarket.Offer, _ cur: Currency) -> some View {
        let list: [EquipmentMarket.Plan] = e.subscriptionPlans(companyID: companyID, equipmentID: equipmentID, offer: o)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.index) { (n: Int, p: EquipmentMarket.Plan) in
                if n > 0 { Hairline() }
                planRow(e, o, p, cur)
            }
        }
    }

    private func planRow(_ e: GameEngine, _ o: EquipmentMarket.Offer, _ p: EquipmentMarket.Plan, _ cur: Currency) -> some View {
        let line = StoreOrders.Line(kind: .plan, equipmentID: equipmentID, offerIndex: o.index, plan: p.index)
        let ok: Bool = quoteOK(e, line)
        let users: String = p.maxUsers > 1_000_000 ? "Any number of users" : "Up to \(p.maxUsers) users"
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.s) {
                    Text(p.name).textStyle(.headline)
                    if p.recommended { Text("Fits your team").textStyle(.caption, tint: P.accent, weight: .semibold) }
                }
                Text(ok ? users : users + " \u{00B7} not on offer now").textStyle(.caption)
                Text(cur.tidyShort(p.monthlyFee) + "/mo").textStyle(.headline, numeric: true)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Add") {
                Haptics.success()
                onAdd(line)
            }
            .buttonStyle(p.recommended ? AnyButtonStyle(PrimaryButtonStyle(size: .compact)) : AnyButtonStyle(SecondaryButtonStyle(size: .compact)))
            .disabled(!ok)
            .accessibilityIdentifier(p.recommended ? "tp-add" : "tp-add-plan-\(p.index)")
        }
        .padding(.vertical, Theme.Space.m)
    }

    private func used() -> some View {
        ShopNote(title: "Bought used", text: "Used items are in Marketplace: second-hand goods from private sellers, with a price you can talk down.",
                 actionTitle: "Open Marketplace", identifier: "tp-open-marketplace") {
            store.openApp(.marketplace)
        }
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (ButtonStyleConfiguration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { (c: ButtonStyleConfiguration) -> AnyView in AnyView(s.makeBody(configuration: c)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

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
            Button("Buy") { buy() }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }
        .padding(.vertical, Theme.Space.xs)
    }
}
