import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum EquipmentTarget: Identifiable, Hashable {
    case machine(equipmentID: String, unitID: Int)
    case vehicle(equipmentID: String, vehicleID: Int)
    case plan(equipmentID: String)

    var id: String {
        switch self {
        case .machine(let e, let u): return "m\(e)\(u)"
        case .vehicle(let e, let v): return "v\(e)\(v)"
        case .plan(let e): return "p\(e)"
        }
    }

    var equipmentID: String {
        switch self {
        case .machine(let e, _): return e
        case .vehicle(let e, _): return e
        case .plan(let e): return e
        }
    }
}

// The one place to see a piece of equipment and act on it: service, repair, replace, sell, cancel.
struct EquipmentDetailScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var target: EquipmentTarget

    @State private var pending: PendingAction? = nil

    private struct Line: Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    private struct Facts {
        var name: String
        var kind: String
        var glyph: String
        var value: Double
        var condition: Double?
        var wear: String
        var status: String
        var tone: AcctPill.Tone
        var lines: [Line]
        var inRepairDays: Int = 0
        var leased: Bool = false
        var canService: Bool = false
        var serviceCost: Double = 0
        var count: Int = 1
        var hasSubscription: Bool = false
        var hasLicence: Bool = false
        var outdated: Bool = false
        var leasedUnits: Int = 0
        var leaseMonthly: Double = 0
        var perk: Bool = false
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let f = facts(e, e.currency(for: co)) {
            content(e, co, f)
        } else {
            EmptyState(glyph: Glyph.settings, title: "This item is gone").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
                .onAppear { dismiss() }
        }
    }

    // MARK: facts

    private func usedFor(_ e: GameEngine) -> String {
        guard let s = e.tradeInfo(companyID: companyID)?.allEquipment.first(where: { $0.id == target.equipmentID }) else { return "" }
        var parts: [String] = []
        if s.isRequired { parts.append("Needed to trade") }
        if s.limitsCapacity { parts.append("Sets capacity") }
        if s.affectsQuality { parts.append("Lifts quality") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func facts(_ e: GameEngine, _ cur: Currency) -> Facts? {
        guard let o = e.ownedEquipment(companyID: companyID).first(where: { (x: EquipmentMarket.Owned) -> Bool in x.equipmentID == target.equipmentID }) else { return nil }
        let life: Double = e.equipmentNeeds(companyID: companyID).first(where: { (n: EquipmentMarket.Need) -> Bool in n.equipmentID == target.equipmentID })?.lifeYears ?? 0
        var lines: [Line] = []
        let use: String = usedFor(e)
        switch target {
        case .machine(_, let uid):
            guard let u = o.units.first(where: { (x: EquipmentMarket.UnitRow) -> Bool in x.id == uid }) else { return nil }
            if u.year > 0 { lines.append(Line(label: "Built", value: "\(u.year)")) }
            if life > 0 { lines.append(Line(label: "Expected life", value: "about \(Int(life.rounded())) years")) }
            lines.append(Line(label: "Wear", value: u.daysInRepair > 0 ? "In repair \(u.daysInRepair) days" : u.wear))
            lines.append(Line(label: "Running cost", value: "Upkeep follows your maintenance setting"))
            if o.serviceCost > 0 && o.subscription == nil && o.licence == nil { lines.append(Line(label: "Service", value: cur.tidyShort(o.serviceCost) + " each time")) }
            lines.append(Line(label: "Warranty", value: u.warranty))
            if u.boughtUsed { lines.append(Line(label: "Bought", value: "Used")) }
            if !use.isEmpty { lines.append(Line(label: "Used for", value: use)) }
            let down: Int = u.daysInRepair
            return Facts(name: u.name.isEmpty ? o.name : u.name, kind: o.kind, glyph: Glyph.settings, value: o.bookValue / max(1, o.count), condition: u.seenCondition, wear: u.wear,
                         status: down > 0 ? "In repair" : u.seenCondition < 0.48 ? "Worn" : "Working",
                         tone: down > 0 ? .bad : u.seenCondition < 0.48 ? .warn : .good, lines: lines, inRepairDays: down,
                         canService: o.subscription == nil && o.licence == nil && o.count > 0, serviceCost: o.serviceCost, count: Int(o.count))
        case .vehicle(_, let vid):
            guard let v = o.vehicles.first(where: { (x: EquipmentMarket.VehicleRow) -> Bool in x.id == vid }) else { return nil }
            let perk: Bool = o.equipmentID == CompanyCarPerk.equipmentID
            if !v.driver.isEmpty { lines.append(Line(label: "Driver", value: v.driver)) }
            if v.kilometres > 0 { lines.append(Line(label: "Distance", value: "\(v.kilometres.formatted()) km")) }
            if life > 0 { lines.append(Line(label: "Expected life", value: "about \(Int(life.rounded())) years")) }
            lines.append(Line(label: "Wear", value: v.daysInRepair > 0 ? "In repair \(v.daysInRepair) days" : v.wear))
            lines.append(Line(label: "Ownership", value: v.mode == "fin" ? "Financed" : v.mode == "lease" ? "Leased" : "Owned"))
            if v.mode == "lease" || perk { lines.append(Line(label: "Lease", value: cur.tidyShort(v.monthlyLease) + " a month")) }
            if v.fuelPerWeek > 0 { lines.append(Line(label: "Fuel", value: cur.tidyShort(v.fuelPerWeek) + " a week")) }
            lines.append(Line(label: "Warranty", value: v.warranty))
            if !use.isEmpty { lines.append(Line(label: "Used for", value: use)) }
            return Facts(name: v.name, kind: "veh", glyph: Glyph.vehicle, value: v.bookValue, condition: v.seenCondition, wear: v.wear,
                         status: v.daysInRepair > 0 ? "In repair" : v.seenCondition < 0.48 ? "Worn" : "Working",
                         tone: v.daysInRepair > 0 ? .bad : v.seenCondition < 0.48 ? .warn : .good, lines: lines, inRepairDays: v.daysInRepair,
                         leased: v.mode == "lease", perk: perk)
        case .plan:
            var status: String = "Leased"
            var tone: AcctPill.Tone = .neutral
            if let s = o.subscription {
                lines.append(Line(label: "Plan", value: s))
                lines.append(Line(label: "Running cost", value: cur.tidyShort(o.subscriptionMonthly) + " a month"))
                status = "Active"; tone = .good
            } else if let l = o.licence {
                lines.append(Line(label: "Licence", value: l))
                lines.append(Line(label: "Version", value: o.outdated ? "Outdated" : "Current"))
                status = o.outdated ? "Outdated" : "Current"; tone = o.outdated ? .warn : .good
            }
            if o.leasedCount > 0 {
                lines.append(Line(label: "On lease", value: "\(Int(o.leasedCount))"))
                lines.append(Line(label: "Lease cost", value: cur.tidyShort(o.leaseMonthly) + " a month"))
            }
            if life > 0 { lines.append(Line(label: "Expected life", value: "about \(Int(life.rounded())) years")) }
            if !use.isEmpty { lines.append(Line(label: "Used for", value: use)) }
            return Facts(name: o.name, kind: o.kind, glyph: o.kind == "soft" ? Glyph.software : Glyph.hardware, value: o.bookValue, condition: nil, wear: "", status: status, tone: tone,
                         lines: lines, hasSubscription: o.subscription != nil, hasLicence: o.licence != nil, outdated: o.outdated,
                         leasedUnits: Int(o.leasedCount), leaseMonthly: o.leaseMonthly)
        }
    }

    // MARK: layout

    private func toneColor(_ t: AcctPill.Tone) -> Color {
        switch t {
        case .good: return P.gain
        case .warn: return P.caution
        case .bad: return P.loss
        case .neutral: return P.inkFaint
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ f: Facts) -> some View {
        let cur: Currency = e.currency(for: co)
        let art: String = ArtAsset.cellFallback(target.equipmentID, group: f.kind == "soft" ? "software" : "equipment", seed: target.equipmentID + "|" + co.type)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ListingHero(height: 240, counter: "") {
                    ShopPhoto(name: ArtAsset.equipment(target.equipmentID), glyph: f.glyph, height: 240, cornerRadius: 0, item: art)
                } badge: {
                    ListingPill(text: f.status, dot: toneColor(f.tone))
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(f.name.tidyText).textStyle(.title).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(cur.tidyShort(f.value)).textStyle(.display, numeric: true)
                        Text("value now").textStyle(.caption)
                    }
                }
                if let c = f.condition {
                    ListingPanel {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            HStack {
                                Text("Wear").textStyle(.caption)
                                Spacer(minLength: Theme.Space.s)
                                Text(f.inRepairDays > 0 ? "In repair \(f.inRepairDays) days" : f.wear).textStyle(.body, tint: c >= 0.48 ? nil : P.loss, weight: .semibold)
                            }
                            EquipmentWearBar(condition: c, height: 8)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                PageGroup("Details") {
                    ForEach(Array(f.lines.enumerated()), id: \.element.id) { (n: Int, l: Line) in
                        FlatRow(label: l.label, value: l.value, rule: n > 0)
                    }
                }
                actions(e, co, f, cur)
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .confirmAction($pending)
        .appScreen(title: "Equipment", subtitle: co.name, tab: .company)
        .accessibilityIdentifier("equipment-detail")
    }

    // MARK: actions

    @ViewBuilder private func actions(_ e: GameEngine, _ co: Company, _ f: Facts, _ cur: Currency) -> some View {
        VStack(spacing: Theme.Space.s) {
            switch target {
            case .machine(let eq, let uid):
                if f.canService && f.inRepairDays == 0 {
                    Button("Service for \(cur.tidyShort(f.serviceCost))") { service(eq, f.serviceCost, cur) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("equipment-service")
                }
                replaceButton(eq, title: "Replace in TechPro")
                if f.inRepairDays == 0 { marketButton(e, f, problem: e.unitSaleProblem(companyID: companyID, equipmentID: eq, unitID: uid)) }
                Button("Sell now") { askSellUnit(eq, uid, f.name) }.buttonStyle(SecondaryButtonStyle(fullWidth: true)).accessibilityIdentifier("equipment-sell")
                if f.count > 1 {
                    Button("Sell all \(f.count)") { askSellAll(eq, f.name) }.buttonStyle(TertiaryButtonStyle(size: .regular, tint: P.inkSoft))
                }
            case .vehicle(let eq, let vid):
                if let gid = e.carRepairGarages(for: companyID).first, (f.condition ?? 1) < 0.8, f.inRepairDays == 0 {
                    Menu {
                        ForEach(CarRepairJobs.kinds) { (k: RepairKind) in Button(k.name) { askGarage(e, gid, k, f.name, cur) } }
                    } label: {
                        Text("Repair").textStyle(.body, tint: P.onAccent, weight: .semibold).frame(maxWidth: .infinity, minHeight: 48)
                            .background(Capsule().fill(P.accent))
                    }
                    .id(vid)
                }
                if !f.perk {
                    replaceButton(eq, title: "Replace in TechPro")
                    if f.inRepairDays == 0 && !f.leased { marketButton(e, f, problem: e.vehicleSaleProblem(companyID: companyID, vehicleID: vid)) }
                    Button(f.leased ? "Return" : "Sell now") { askSellVehicle(vid, f.name, leased: f.leased) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true)).accessibilityIdentifier("equipment-sell")
                }
            case .plan(let eq):
                if f.hasSubscription {
                    Button("Change plan in TechPro") { store.openTechPro(companyID: companyID, equipmentID: eq) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    Button("Cancel plan") { askCancelPlan(eq, f.name) }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                } else if f.hasLicence {
                    Button(f.outdated ? "Update in TechPro" : "Buy more in TechPro") { store.openTechPro(companyID: companyID, equipmentID: eq) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                } else {
                    replaceButton(eq, title: "Buy more in TechPro")
                }
                if f.leasedUnits > 0 {
                    Button("End the lease") { askEndLease(eq, f.name, units: f.leasedUnits, monthly: cur.tidyShort(f.leaseMonthly)) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }
        }
    }

    private func replaceButton(_ equipmentID: String, title: String) -> some View {
        Button(title) { store.openTechPro(companyID: companyID, equipmentID: equipmentID) }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("equipment-replace")
    }

    @ViewBuilder private func marketButton(_ e: GameEngine, _ f: Facts, problem: String?) -> some View {
        if problem == nil {
            Button("Sell on Marketplace") {
                pending = PendingAction(title: "Sell on Marketplace", message: "\(f.name) leaves the company at its worth and goes to your inventory, where you can list it, repair it first, or sell it through a dealership.",
                                        button: "List it", alwaysAsk: true, icon: "tag") { moveToInventory(f.name) }
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("equipment-to-marketplace")
        }
    }

    private func short(of cost: Double, _ cur: Currency) {
        let cash: Double = store.engine?.state.company(companyID)?.cash ?? 0
        let need: Double = max(0, cost - cash)
        pending = PendingAction(title: "Not enough cash", message: "The company needs about " + cur.tidyShort(need) + " more. Put money in or take a loan.", button: "Get a loan",
                                alwaysAsk: true, icon: "banknote") {
            store.openBank(.personal, tab: .loans, applyLoan: need > 0 ? (need / 100).rounded(.up) * 100 : nil)
        }
    }

    private func service(_ equipmentID: String, _ cost: Double, _ cur: Currency) {
        let cid: Int = companyID
        switch store.act({ $0.serviceEquipment(companyID: cid, equipmentID: equipmentID) }) {
        case .ok?: store.show("Serviced.", tone: "good")
        default: short(of: cost, cur)
        }
    }

    private func askSellUnit(_ eq: String, _ uid: Int, _ name: String) {
        let cid: Int = companyID
        pending = PendingAction(title: "Sell this \(name.lowercased())?", message: "Used equipment sells for well under what you paid, less if it looks worn.", button: "Sell", destructive: false, tone: .danger, icon: "tag") {
            let v: Double = store.act { $0.sellEquipmentUnit(companyID: cid, equipmentID: eq, unitID: uid) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Not sold.", tone: v > 0 ? "good" : "warn")
            dismiss()
        }
    }

    private func askSellAll(_ eq: String, _ name: String) {
        let cid: Int = companyID
        pending = PendingAction(title: "Sell all \(name.lowercased())?", message: "You get about 70% of book value. Capacity may collapse.", button: "Sell all", destructive: false, tone: .danger, icon: "tag") {
            let v: Double = store.act { $0.sellAllEquipment(companyID: cid, equipmentID: eq) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Nothing was sold.", tone: v > 0 ? "good" : "warn")
            dismiss()
        }
    }

    private func askSellVehicle(_ vid: Int, _ name: String, leased: Bool) {
        let cid: Int = companyID
        pending = PendingAction(title: leased ? "Return \(name)?" : "Sell \(name)?", message: "You get roughly 78% of its book value. A loan on it is settled; a lease just ends.",
                                button: leased ? "Return" : "Sell", destructive: false, tone: .danger, icon: "tag") {
            let v: Double = store.act { $0.sellVehicle(companyID: cid, vehicleID: vid) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Vehicle returned.", tone: "good")
            dismiss()
        }
    }

    private func askCancelPlan(_ eq: String, _ name: String) {
        let cid: Int = companyID
        pending = PendingAction(title: "Cancel \(name.lowercased())?", message: "It stops working right away.", button: "Cancel plan", destructive: false, tone: .danger, icon: "xmark.circle") {
            let gone: Bool = store.act { $0.cancelSubscription(companyID: cid, equipmentID: eq) } ?? false
            store.show(gone ? "Plan cancelled." : "The plan could not be cancelled.", tone: gone ? "n" : "warn")
            dismiss()
        }
    }

    private func askEndLease(_ eq: String, _ name: String, units: Int, monthly: String) {
        let cid: Int = companyID
        let msg: String = "The \(units) leased \(units == 1 ? "unit goes" : "units go") back at once and the capacity they gave is lost until you replace \(units == 1 ? "it" : "them"). The \(monthly) a month stops."
        pending = PendingAction(title: "End the lease of \(name.lowercased())?", message: msg, button: "End the lease", destructive: false, tone: .danger, icon: "tag") {
            if store.act({ $0.endEquipmentLease(companyID: cid, equipmentID: eq) }) == true { Haptics.warning(); store.show("Lease of \(name.lowercased()) ended.", tone: "n") }
            else { store.show("There is no lease of \(name.lowercased()) to end.", tone: "warn") }
            dismiss()
        }
    }

    private func askGarage(_ e: GameEngine, _ garageID: Int, _ kind: RepairKind, _ vehicle: String, _ cur: Currency) {
        guard let q = e.carRepairQuote(garageID: garageID, kind: kind.id) else {
            store.show("The garage has no room for this job now.", tone: "warn"); return
        }
        let cid: Int = companyID
        let weeks: String = "\(q.weeks) " + (q.weeks == 1 ? "week" : "weeks")
        let msg: String = q.garageName + " charges " + cur.tidyShort(q.price) + " plus " + cur.tidyShort(q.vat) + " VAT for " + kind.name.lowercased() + ", back in about " + weeks + "."
        pending = PendingAction(title: "Repair " + vehicle + "?", message: msg, button: "Order", amount: q.total, currency: cur, tone: .info, icon: "wrench.and.screwdriver") {
            let r: RepairResult? = store.act { (g: inout GameEngine) -> RepairResult in g.orderCarRepair(garageID: garageID, dealerID: cid, kind: kind.id, ref: vehicle) }
            switch r {
            case .ordered(let o)?: store.show("Ordered for " + cur.tidyShort(o.price + o.vat) + ", back in \(o.weeks) " + (o.weeks == 1 ? "week" : "weeks") + ".", tone: "good")
            case .refused(let why)?: store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    private func moveToInventory(_ name: String) {
        let t: EquipmentTarget = target
        let cid: Int = companyID
        let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in
            switch t {
            case .machine(let eq, let uid): return g.moveUnitToInventory(companyID: cid, equipmentID: eq, unitID: uid, name: name)
            case .vehicle(_, let vid): return g.moveVehicleToInventory(companyID: cid, vehicleID: vid)
            case .plan: return SettingResult.refused("This cannot be listed.")
            }
        }
        if let why = r?.reason {
            Haptics.warning(); store.show(why, tone: "warn")
        } else {
            Haptics.success()
            dismiss()
            store.openApp(.marketplace)
        }
    }
}
