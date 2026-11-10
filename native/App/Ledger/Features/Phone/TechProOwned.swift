import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct TechProOwnedView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var onBuy: (String) -> Void

    @State private var pending: PendingAction?

    var body: some View {
        ShopPage {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(e, co)
            }
        }
        .confirmAction($pending)
        .accessibilityIdentifier("tp-owned")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let list: [EquipmentMarket.Owned] = e.ownedEquipment(companyID: companyID)
        let cur: Currency = e.currency(for: co)
        hero(e, list)
        missingSection(e)
        if list.isEmpty {
            ShopEmptyNote(text: "Nothing bought yet. Browse the store and add items to your basket.", glyph: Glyph.cart)
        } else {
            ShopSection(title: "What you own", trailing: "\(list.count)") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, o: EquipmentMarket.Owned) in
                        if n > 0 { Hairline() }
                        itemBlock(e, o, cur)
                    }
                }
            }
        }
    }

    private func hero(_ e: GameEngine, _ list: [EquipmentMarket.Owned]) -> some View {
        let units: Int = list.reduce(0) { (s: Int, o: EquipmentMarket.Owned) -> Int in s + o.units.count + o.vehicles.count }
        let repairs: Int = list.reduce(0) { (s: Int, o: EquipmentMarket.Owned) -> Int in
            s + o.units.filter { (u: EquipmentMarket.UnitRow) -> Bool in u.daysInRepair > 0 }.count + o.vehicles.filter { (v: EquipmentMarket.VehicleRow) -> Bool in v.daysInRepair > 0 }.count
        }
        let h: Double? = e.equipmentHealth(companyID: companyID)
        let note: String = (units == 1 ? "1 unit" : "\(units) units") + (repairs > 0 ? " \u{00B7} \(repairs) in repair" : "") + " \u{00B7} old kit breaks more often"
        return ShopHero(label: "Condition", value: h.map { (x: Double) -> String in Words.level(x * 100, scale: .condition) } ?? "\u{2013}", note: note,
                        noteTint: repairs > 0 ? P.loss : nil, valueTint: h.map { (x: Double) -> Color in tint(x) == P.inkSoft ? P.ink : tint(x) })
    }

    @ViewBuilder private func missingSection(_ e: GameEngine) -> some View {
        let missing: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: companyID).filter { (n: EquipmentMarket.Need) -> Bool in n.need > 0 && n.have + n.leased < n.need }
        if !missing.isEmpty {
            ShopSection(title: "Still needed", trailing: "\(missing.count)") {
                VStack(spacing: 0) {
                    ForEach(Array(missing.enumerated()), id: \.element.id) { (i: Int, n: EquipmentMarket.Need) in
                        if i > 0 { Hairline() }
                        LedgerRow(leading: .glyph(TechCategory.of(n).glyph), leadingTint: n.required ? P.loss : P.caution, title: n.name,
                                  subtitle: "\(Int(saturating: (n.have + n.leased).rounded())) of \(Int(n.need))" + (n.required ? " \u{00B7} required to trade" : ""),
                                  value: "Shop", valueTint: P.accent) { onBuy(n.equipmentID) }
                    }
                }
            }
        }
    }

    private func itemBlock(_ e: GameEngine, _ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                itemThumb(o)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(o.name).textStyle(.headline).lineLimit(2)
                    if let u = single(o) {
                        Text(unitLine(u)).textStyle(.caption, tint: u.daysInRepair > 0 ? P.loss : P.inkSoft).lineLimit(2)
                    } else {
                        Text(summary(o, cur)).textStyle(.caption, tint: o.outdated ? P.caution : P.inkSoft).lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if let u = single(o) { Text(u.wear).textStyle(.caption, tint: tint(u.seenCondition), weight: .medium) }
                ShopMoreMenu(label: "Actions for \(o.name)") {
                    if let u = single(o) { Button("Sell", role: .destructive) { sellUnit(o, u) } }
                    itemActions(o, cur)
                }
            }
            if single(o) == nil {
                ForEach(Array(o.units.enumerated()), id: \.element.id) { (n: Int, u: EquipmentMarket.UnitRow) in unitRow(o, u, n + 1) }
            }
            ForEach(o.vehicles) { (v: EquipmentMarket.VehicleRow) in vehicleRow(v, cur) }
        }
        .padding(.vertical, Theme.Space.m)
    }

    private func summary(_ o: EquipmentMarket.Owned, _ cur: Currency) -> String {
        if let s = o.subscription { return s + " \u{00B7} " + cur.tidyShort(o.subscriptionMonthly) + "/mo" }
        if let l = o.licence { return l + (o.outdated ? " \u{00B7} outdated" : " \u{00B7} current") }
        var parts: [String] = []
        if o.count > 0 { parts.append("\(Int(o.count)) owned") }
        if o.leasedCount > 0 { parts.append("\(Int(o.leasedCount)) leased, " + cur.tidyShort(o.leaseMonthly) + "/mo") }
        return parts.isEmpty ? EquipmentMarket.kindName(o.kind) : parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder private func itemActions(_ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        Button(o.subscription != nil ? "Change plan" : "Buy more") { onBuy(o.equipmentID) }
        if o.subscription != nil {
            Button("Cancel plan", role: .destructive) { cancelPlan(o) }
        } else if o.licence == nil && o.count > 0 && o.kind != "veh" {
            Button("Service all, " + cur.tidyShort(o.serviceCost)) { service(o) }
            Button("Sell all", role: .destructive) { sellAll(o) }
        }
        if o.leasedCount > 0 {
            Button("End lease", role: .destructive) { endLease(o, cur) }
        }
    }

    private func itemThumb(_ o: EquipmentMarket.Owned) -> some View {
        let group: String = o.kind == "soft" ? "software" : "equipment"
        let key: String = ArtLibrary.itemKey(group: group, familyKey: o.equipmentID, seed: o.equipmentID) ?? ""
        return ShopThumb(glyph: o.kind == "veh" ? Glyph.vehicle : (o.kind == "soft" ? Glyph.software : Glyph.hardware), item: key)
    }

    private func single(_ o: EquipmentMarket.Owned) -> EquipmentMarket.UnitRow? {
        o.units.count == 1 && o.vehicles.isEmpty ? o.units.first : nil
    }

    private func unitLine(_ u: EquipmentMarket.UnitRow) -> String {
        (u.year > 0 ? "\(u.year) \u{00B7} " : "") + (u.boughtUsed ? "bought used \u{00B7} " : "") + u.warranty + (u.daysInRepair > 0 ? " \u{00B7} in repair \(u.daysInRepair) days" : "")
    }

    private func tint(_ c: Double) -> Color { c >= 0.8 ? P.gain : c >= 0.48 ? P.inkSoft : P.loss }

    private func unitRow(_ o: EquipmentMarket.Owned, _ u: EquipmentMarket.UnitRow, _ number: Int) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(u.name == o.name ? "Unit \(number)" : u.name).textStyle(.body)
                Text(unitLine(u)).textStyle(.caption, tint: u.daysInRepair > 0 ? P.loss : P.inkFaint)
            }
            Spacer(minLength: Theme.Space.s)
            Text(u.wear).textStyle(.caption, tint: tint(u.seenCondition), weight: .medium)
            ShopMoreMenu(label: "Actions for \(u.name)") {
                Button("Sell", role: .destructive) { sellUnit(o, u) }
            }
        }
        .padding(.leading, 60)
    }

    private func vehicleRow(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(v.name).textStyle(.body)
                Text(vehicleLine(v, cur)).textStyle(.caption, tint: v.daysInRepair > 0 ? P.loss : P.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Text(v.wear).textStyle(.caption, tint: tint(v.seenCondition), weight: .medium)
            ShopMoreMenu(label: "Actions for \(v.name)") {
                Button(v.mode == "lease" ? "Return" : "Sell", role: .destructive) { sellVehicle(v) }
            }
        }
        .padding(.leading, 60)
    }

    private func vehicleLine(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> String {
        var line: String = v.driver.isEmpty ? "" : v.driver + " \u{00B7} "
        let mode: String = v.mode == "fin" ? "Financed" : v.mode == "lease" ? "Leased " + cur.tidyShort(v.monthlyLease) + "/mo" : "Owned"
        line += mode + " \u{00B7} \(v.kilometres / 1000) 000 km"
        if v.fuelPerWeek > 0 { line += " \u{00B7} fuel " + cur.tidyShort(v.fuelPerWeek) + "/wk" }
        line += " \u{00B7} " + v.warranty
        if v.daysInRepair > 0 { line += " \u{00B7} in repair \(v.daysInRepair) days" }
        return line
    }

    private func ask(_ title: String, _ message: String, _ button: String, hold: Bool = false, icon: String = "tag", _ run: @escaping () -> Void) {
        pending = PendingAction(title: title, message: message, button: button, destructive: hold, tone: hold ? .danger : .warning, icon: icon, run: run)
    }

    private func result(_ v: Double, _ none: String) {
        store.show(v > 0 ? "Sold for \(store.short(v))." : none, tone: v > 0 ? "good" : "warn")
    }

    private func sellUnit(_ o: EquipmentMarket.Owned, _ u: EquipmentMarket.UnitRow) {
        ask("Sell this \(o.name.lowercased())?", "It is sold at its current second-hand value.", "Sell") {
            result(store.act { $0.sellEquipmentUnit(companyID: companyID, equipmentID: o.equipmentID, unitID: u.id) } ?? 0, "Not sold.")
        }
    }

    private func sellAll(_ o: EquipmentMarket.Owned) {
        ask("Sell all \(o.name.lowercased())?", "Every unit is sold at its current second-hand value.", "Sell all", hold: true) {
            result(store.act { $0.sellAllEquipment(companyID: companyID, equipmentID: o.equipmentID) } ?? 0, "Nothing was sold.")
        }
    }

    private func sellVehicle(_ v: EquipmentMarket.VehicleRow) {
        ask(v.mode == "lease" ? "Return \(v.name)?" : "Sell \(v.name)?", "This cannot be undone.", v.mode == "lease" ? "Return" : "Sell") {
            result(store.act { $0.sellVehicle(companyID: companyID, vehicleID: v.id) } ?? 0, "Vehicle returned.")
        }
    }

    private func cancelPlan(_ o: EquipmentMarket.Owned) {
        ask("Cancel the plan for \(o.name.lowercased())?", "The software stops when the plan ends.", "Cancel plan", icon: "xmark.circle") {
            let gone: Bool = store.act { $0.cancelSubscription(companyID: companyID, equipmentID: o.equipmentID) } ?? false
            store.show(gone ? "Plan cancelled." : "The plan could not be cancelled.", tone: gone ? "n" : "warn")
        }
    }

    private func endLease(_ o: EquipmentMarket.Owned, _ cur: Currency) {
        ask("End the lease of \(o.name.lowercased())?", "\(Int(o.leasedCount)) on lease at " + cur.tidyShort(o.leaseMonthly) + " a month go back.", "End lease") {
            let ended: Bool = store.act { $0.endEquipmentLease(companyID: companyID, equipmentID: o.equipmentID) } ?? false
            store.show(ended ? "Lease ended." : "There is no lease to end.", tone: ended ? "n" : "warn")
        }
    }

    private func service(_ o: EquipmentMarket.Owned) {
        switch store.act({ $0.serviceEquipment(companyID: companyID, equipmentID: o.equipmentID) }) {
        case .ok?: store.show("Serviced.", tone: "good")
        default: store.show("Not enough cash.", tone: "warn")
        }
    }
}
