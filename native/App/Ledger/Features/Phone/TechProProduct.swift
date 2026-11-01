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
    var onAdd: (StoreOrders.Line) -> Void

    private enum Mode: Hashable { case new, used, lease }
    @State private var mode: Mode = .new
    @State private var cls: Int? = nil
    @State private var selected: String? = nil
    @State private var quantity = 0
    @State private var finance = false
    @State private var pendingOwn: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let need = e.equipmentNeeds(companyID: companyID).first(where: { (n: EquipmentMarket.Need) -> Bool in n.equipmentID == equipmentID }) {
            content(e, co, need)
        } else {
            Text("Not sold here.").font(.system(size: 15)).foregroundStyle(P.inkSoft).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need) -> some View {
        let cur: Currency = e.currency(for: co)
        let one: Bool = need.kind == "soft" || need.kind == "svc"
        let modes: [Mode] = [.new] + (need.canUsed ? [Mode.used] : []) + (need.canLease ? [Mode.lease] : [])
        let current: Mode = modes.contains(mode) ? mode : .new
        return ShopScroll {
            VStack(alignment: .leading, spacing: 16) {
                header(co, need, cur)
                if modes.count > 1 { modePicker(modes, current, one: one, subscription: need.subscription) }
                if need.kind == "soft" { ownSoftware(e, need, cur) }
                offers(e, co, need, current, cur, one: one)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 40)
        }
        .confirmAction($pendingOwn)
    }

    @ViewBuilder private func offers(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ current: Mode, _ cur: Currency, one: Bool) -> some View {
        if need.isVehicle {
            vehicles(e, co, need, current, cur)
        } else if current == .used {
            used(e, co, need, cur)
        } else if need.subscription && current == .new {
            plans(e, co, need, cur)
        } else {
            brands(e, co, need, current, cur, one: one)
        }
    }

    // MARK: Header

    private func header(_ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let have: Int = Int((need.have + need.leased).rounded())
        let sub: String = EquipmentMarket.kindName(need.kind) + " \u{00B7} lasts about \(Int(need.lifeYears)) years" + (need.warrantyYears > 0 ? " \u{00B7} warranty \(Int(need.warrantyYears)) yr new" : "")
        return VStack(alignment: .leading, spacing: 10) {
            Text(need.name).font(.system(size: 24, weight: .bold)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
            Text(sub).font(.system(size: 13)).foregroundStyle(P.inkFaint)
            Card(padding: 12) {
                HStack(spacing: 0) {
                    stat("You have", "\(have)")
                    stat("Needed", need.need > 0 ? "\(Int(need.need))" : "\u{2013}")
                    stat("Cash", store.short(co.cash, in: co))
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
        }
        .frame(maxWidth: .infinity)
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

    @ViewBuilder private func brands(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ mode: Mode, _ cur: Currency, one: Bool) -> some View {
        let all: [EquipmentMarket.Offer] = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID)
        let list: [EquipmentMarket.Offer] = all.filter { (o: EquipmentMarket.Offer) -> Bool in cls == nil || o.cls == cls }
        let lease: Bool = mode == .lease
        VStack(alignment: .leading, spacing: 10) {
            classChips
            ShopHeading(text: one ? "Suppliers" : "Brands", trailing: "\(list.count)")
            ForEach(list) { (o: EquipmentMarket.Offer) in
                let p: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: o.priceFactor)
                let perf: Int = Int(((o.performance - 1) * 100).rounded())
                let sub: String = "\(o.className) \u{00B7} \(o.seller) \u{00B7} \(stars(o.rating, o.reviews)) \u{00B7} output \(o.performance >= 1 ? "+" : "")\(perf)% \u{00B7} reliability \(reliabilityWord(o.reliability))"
                offerRow(o.name, sub, lease ? cur.tidyShort(EquipmentMarket.leaseMonthly(price: p)) + "/mo" : cur.tidyShort(p), String(o.index))
            }
        }
        if let sel = all.first(where: { (o: EquipmentMarket.Offer) -> Bool in String(o.index) == selected }) {
            brandAdd(e, need, sel, lease, cur, one: one)
        }
    }

    private var classChips: some View {
        HStack(spacing: 6) {
            ForEach([-1, 0, 1, 2], id: \.self) { (c: Int) in
                let on: Bool = (c < 0 && cls == nil) || cls == c
                ShopChip(title: c < 0 ? "All" : EquipmentMarket.classNames[c], selected: on) {
                    cls = c < 0 ? nil : c
                    selected = nil
                }
            }
        }
    }

    private func brandAdd(_ e: GameEngine, _ need: EquipmentMarket.Need, _ sel: EquipmentMarket.Offer, _ lease: Bool, _ cur: Currency, one: Bool) -> some View {
        let unit: Double = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: sel.priceFactor)
        let q: Int = one ? 1 : (quantity > 0 ? quantity : max(1, Int(need.need - need.have - need.leased)))
        let total: Double = unit * Double(q)
        let canFin: Bool = !lease && e.canFinance(companyID: companyID, equipmentID: equipmentID, total: total)
        let useFinance: Bool = finance && canFin
        let pay: EquipmentMarket.Payment = lease ? .lease : (useFinance ? .finance : .cash)
        let line = StoreOrders.Line(kind: .new, equipmentID: equipmentID, quantity: q, offerIndex: sel.index, payment: pay)
        let label: String = lease ? "Lease, 3 years, service included" : (useFinance ? "Down payment now, loan for the rest" : "Total")
        let value: String = lease ? cur.tidyShort(EquipmentMarket.leaseMonthly(price: total)) + "/mo" : (useFinance ? cur.tidyShort(total * 0.2) : cur.tidyShort(total))
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                if !one { stepper(q) }
                if canFin { payChoice() }
                ShopFact(label: label, value: value, strong: true)
                addButton(e, line, lease ? "Add lease to basket" : "Add to basket")
            }
        }
    }

    private func addButton(_ e: GameEngine, _ line: StoreOrders.Line, _ title: String) -> some View {
        let ok: Bool = e.storeQuote(companyID: companyID, lines: [line], delivery: .standard) != nil
        return VStack(alignment: .leading, spacing: 6) {
            Button(title) {
                Haptics.success()
                onAdd(line)
                selected = nil
                quantity = 0
            }
            .buttonStyle(ShopFilledButtonStyle())
            .disabled(!ok)
            .accessibilityIdentifier("tp-add")
            if !ok { Text("This is not on offer right now.").font(.system(size: 12.5)).foregroundStyle(P.caution) }
        }
    }

    private func payChoice() -> some View {
        HStack {
            Text("How to pay").font(.system(size: 14)).foregroundStyle(P.inkSoft)
            Spacer()
            SegmentedChoice(items: [false, true], title: { (f: Bool) -> String in f ? "Finance" : "Cash" }, selection: $finance)
                .frame(maxWidth: 190)
        }
    }

    private func stepper(_ q: Int) -> some View {
        HStack {
            Text("Quantity").font(.system(size: 14)).foregroundStyle(P.inkSoft)
            Spacer()
            HStack(spacing: 0) {
                Button { quantity = max(1, q - 1); Haptics.choose() } label: {
                    GlyphView(glyph: Glyph.minus, size: 14, weight: 2, tint: P.accent).frame(width: 42, height: 34)
                }
                .disabled(q <= 1)
                Text("\(q)").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink).frame(minWidth: 30)
                Button { quantity = min(50, q + 1); Haptics.choose() } label: {
                    GlyphView(glyph: Glyph.hire, size: 14, weight: 2, tint: P.accent).frame(width: 42, height: 34)
                }
                .disabled(q >= 50)
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        }
    }

    // MARK: Your own software

    /// A product one of your own companies builds that does this job: the buyer pays the producer its internal price (set where the product is managed).
    /// It is taken at once (no delivery): it is a licence inside the group.
    @ViewBuilder private func ownSoftware(_ e: GameEngine, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let list: [SoftwareProducts.Offer] = e.ownSoftwareOffers(buyerID: companyID, equipmentName: need.name)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ShopHeading(text: "From your own companies", trailing: "\(list.count)")
                ForEach(list) { (o: SoftwareProducts.Offer) in ownRow(e, o, cur) }
            }
        }
    }

    private func ownRow(_ e: GameEngine, _ o: SoftwareProducts.Offer, _ cur: Currency) -> some View {
        let producer: String = e.state.company(o.producerID)?.name ?? "your company"
        let price: String = o.cost == 0 ? "free" : cur.tidyShort(o.cost) + (o.monthly ? "/mo" : "")
        return Card(padding: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                    Text("Built by \(producer) \u{00B7} \(o.modelName.lowercased())" + (o.tested ? " \u{00B7} test version: less reliable" : ""))
                        .font(.system(size: 12.5)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(price).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
                Button("Use it") { confirmOwn(o, producer, cur) }.buttonStyle(QuietButtonStyle())
            }
        }
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

    @ViewBuilder private func plans(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let all: [EquipmentMarket.Offer] = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID).filter { (o: EquipmentMarket.Offer) -> Bool in o.cls == 1 }
        let users: Int = EquipmentMarket.users(co)
        VStack(alignment: .leading, spacing: 12) {
            Text("Sold only as a subscription. Pick a provider and a plan. Plans are priced by users: you have \(users).")
                .font(.system(size: 13.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            ForEach(all) { (o: EquipmentMarket.Offer) in providerCard(e, o, cur) }
        }
    }

    private func providerCard(_ e: GameEngine, _ o: EquipmentMarket.Offer, _ cur: Currency) -> some View {
        let list: [EquipmentMarket.Plan] = e.subscriptionPlans(companyID: companyID, equipmentID: equipmentID, offer: o)
        return Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(o.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(P.ink)
                    Spacer(minLength: 8)
                    Text(stars(o.rating, o.reviews)).font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
                }
                ForEach(list, id: \.index) { (p: EquipmentMarket.Plan) in planRow(e, o, p, cur) }
            }
        }
    }

    private func planRow(_ e: GameEngine, _ o: EquipmentMarket.Offer, _ p: EquipmentMarket.Plan, _ cur: Currency) -> some View {
        let line = StoreOrders.Line(kind: .plan, equipmentID: equipmentID, offerIndex: o.index, plan: p.index)
        let ok: Bool = e.storeQuote(companyID: companyID, lines: [line], delivery: .standard) != nil
        let users: String = p.maxUsers > 1_000_000 ? "any number of users" : "up to \(p.maxUsers) users"
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name + (p.recommended ? " \u{00B7} fits your team" : "")).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink)
                Text(users).font(.system(size: 12)).foregroundStyle(P.inkFaint)
            }
            Spacer(minLength: 8)
            Text(cur.tidyShort(p.monthlyFee) + "/mo").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
            Button("Add") {
                Haptics.success()
                onAdd(line)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!ok)
        }
    }

    // MARK: Used

    @ViewBuilder private func used(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let list: [EquipmentMarket.UsedOffer] = e.usedListings(companyID: companyID, equipmentID: equipmentID)
        VStack(alignment: .leading, spacing: 10) {
            Text("Second-hand, sold as seen: no warranty and no guarantees. The seller describes the wear. It is not always the whole truth.")
                .font(.system(size: 13.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            if list.isEmpty {
                Text("Nothing for sale this month. New listings appear next month.").font(.system(size: 14)).foregroundStyle(P.inkSoft)
            }
            ForEach(list) { (x: EquipmentMarket.UsedOffer) in
                offerRow("\(x.name) \u{00B7} \(x.year)", usedLine(x), cur.tidyShort(x.price), x.id)
            }
        }
        if let sel = list.first(where: { (x: EquipmentMarket.UsedOffer) -> Bool in x.id == selected }) {
            usedAdd(e, sel, cur)
        }
    }

    private func usedLine(_ x: EquipmentMarket.UsedOffer) -> String {
        var s: String = "\(x.seller) \u{00B7} \(x.age) \(x.age == 1 ? "year" : "years") old \u{00B7} \(EquipmentMarket.wearWord(x.visibleCondition)) \u{00B7} \u{201C}\(x.says)\u{201D}"
        if x.kilometres > 0 { s += " \u{00B7} \(x.kilometres / 1000) 000 km \u{00B7} breakdown risk, your guess: \(x.risk.lowercased()) \u{00B7} fuel and service: \(x.fuel.lowercased())" }
        if x.knownToLast { s += " \u{00B7} known to last" }
        return s + " \u{00B7} no warranty"
    }

    private func usedAdd(_ e: GameEngine, _ sel: EquipmentMarket.UsedOffer, _ cur: Currency) -> some View {
        let canFin: Bool = e.canFinance(companyID: companyID, equipmentID: equipmentID, total: sel.price)
        let useFinance: Bool = finance && canFin
        let line = StoreOrders.Line(kind: .used, equipmentID: equipmentID, payment: useFinance ? .finance : .cash, used: sel)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                if canFin { payChoice() }
                ShopFact(label: useFinance ? "Down payment now, loan for the rest" : "Total", value: cur.tidyShort(useFinance ? sel.price * 0.2 : sel.price), strong: true)
                addButton(e, line, "Add used item to basket")
            }
        }
    }

    // MARK: Vehicles

    @ViewBuilder private func vehicles(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ mode: Mode, _ cur: Currency) -> some View {
        if mode == .used {
            used(e, co, need, cur)
        } else {
            let list: [EquipmentMarket.VehicleOffer] = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID)
            let lease: Bool = mode == .lease
            VStack(alignment: .leading, spacing: 10) {
                ShopHeading(text: "Makes and models", trailing: "\(list.count)")
                ForEach(list) { (o: EquipmentMarket.VehicleOffer) in vehicleCard(e, o, lease, cur) }
            }
            if let sel = list.first(where: { (o: EquipmentMarket.VehicleOffer) -> Bool in o.id == selected }) {
                vehicleAdd(e, sel, lease, cur)
            }
        }
    }

    private func vehicleCard(_ e: GameEngine, _ o: EquipmentMarket.VehicleOffer, _ lease: Bool, _ cur: Currency) -> some View {
        let price: Double = e.vehiclePrice(modelID: o.modelID, factor: o.priceFactor)
        let on: Bool = selected == o.id
        let right: String = lease ? cur.tidyShort(EquipmentMarket.vehicleLeaseMonthly(price: price)) + "/mo" : cur.tidyShort(price)
        return Button {
            Haptics.choose()
            selected = on ? nil : o.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ShopPhoto(name: TechPhotos.vehicle(model: o.modelID), glyph: Glyph.vehicle, height: 130)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.name + ", new").font(.system(size: 15.5, weight: .semibold)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                        Text("\(o.modelName) \u{00B7} \(stars(o.rating, o.reviews)) \u{00B7} reliability \(reliabilityWord(o.reliability))")
                            .font(.system(size: 12.5)).foregroundStyle(P.inkFaint).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Text(right).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(P.ink)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? P.accent.opacity(0.08) : P.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? P.accent : P.line, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("tp-offer-\(o.id)")
    }

    private func vehicleAdd(_ e: GameEngine, _ sel: EquipmentMarket.VehicleOffer, _ lease: Bool, _ cur: Currency) -> some View {
        let price: Double = e.vehiclePrice(modelID: sel.modelID, factor: sel.priceFactor)
        let pay: EquipmentMarket.Payment = lease ? .lease : (finance ? .finance : .cash)
        let line = StoreOrders.Line(kind: .vehicle, equipmentID: equipmentID, vehicleOfferID: sel.id, payment: pay)
        let label: String = lease ? "Lease, 3 years" : (finance ? "Down payment now, loan for the rest" : "Total")
        let value: String = lease ? cur.tidyShort(EquipmentMarket.vehicleLeaseMonthly(price: price)) + "/mo" : cur.tidyShort(finance ? price * 0.2 : price)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                if !lease { payChoice() }
                ShopFact(label: label, value: value, strong: true)
                addButton(e, line, lease ? "Add lease to basket" : "Add to basket")
            }
        }
    }
}
