import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// TechPro "My items": what a company owns (units, condition, warranty, software and plans, the fleet), in the store's own look.
/// Selling, servicing, cancelling a plan and ending a lease happen here.
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
        missingSection(e)
        ShopSection(title: "My items", trailing: list.isEmpty ? "" : "\(list.count)") {
            if list.isEmpty {
                ShopEmptyNote(text: "Nothing bought yet. Browse the store and add items to your basket.", glyph: Glyph.cart)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, o: EquipmentMarket.Owned) in
                if n > 0 { Hairline() }
                itemBlock(e, o, cur)
            }
        }
        if let h = e.equipmentHealth(companyID: companyID) {
            ShopNote(title: "Condition \u{00B7} \(Int((h * 100).rounded()))%",
                     text: "Equipment health, as far as you can tell. Old equipment breaks more often. Under warranty the maker repairs it for free, but it is away for days.")
        }
    }

    /// What the business still needs to run properly (the engine's own needs list): each row opens the item in the store.
    @ViewBuilder private func missingSection(_ e: GameEngine) -> some View {
        let missing: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: companyID).filter { (n: EquipmentMarket.Need) -> Bool in n.need > 0 && n.have + n.leased < n.need }
        if !missing.isEmpty {
            ShopSection(title: "Missing", trailing: "\(missing.count)") {
                VStack(spacing: 0) {
                    ForEach(Array(missing.enumerated()), id: \.element.id) { (i: Int, n: EquipmentMarket.Need) in
                        if i > 0 { Hairline() }
                        LedgerRow(title: n.name, subtitle: "\(Int((n.have + n.leased).rounded())) of \(Int(n.need))", value: "Shop", valueTint: P.accent,
                                  pill: n.required ? "Required" : nil, pillTone: .bad) { onBuy(n.equipmentID) }
                    }
                }
            }
        }
    }

    private func itemBlock(_ e: GameEngine, _ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                itemThumb(o)
                Text(o.name).textStyle(.headline)
                Spacer(minLength: 0)
            }
            planLine(o, cur)
            ForEach(o.units) { (u: EquipmentMarket.UnitRow) in unitRow(o, u) }
            ForEach(o.vehicles) { (v: EquipmentMarket.VehicleRow) in vehicleRow(v, cur) }
            leaseLine(o, cur)
            actions(e, o, cur)
        }
        .padding(.vertical, Theme.Space.s)
    }

    /// The item's picture from the items sheet; nothing is shown while the family has no art.
    @ViewBuilder private func itemThumb(_ o: EquipmentMarket.Owned) -> some View {
        #if canImport(UIKit)
        let group: String = o.kind == "soft" ? "software" : "equipment"
        let key: String = ArtLibrary.itemKey(group: group, familyKey: o.equipmentID, seed: o.equipmentID) ?? ""
        if let ui = ArtLibrary.image(.items, key) {
            Image(uiImage: ui).resizable().scaledToFill().frame(width: 48, height: 48).clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)).accessibilityHidden(true)
        }
        #endif
    }

    @ViewBuilder private func planLine(_ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        if let s = o.subscription {
            Text(s + " \u{00B7} " + cur.tidyShort(o.subscriptionMonthly) + "/mo").textStyle(.body, tint: P.inkSoft)
        } else if let l = o.licence {
            Text(l + (o.outdated ? " \u{00B7} outdated" : " \u{00B7} current")).textStyle(.body, tint: o.outdated ? P.caution : P.inkSoft)
        }
    }

    private func tint(_ c: Double) -> Color { c >= 0.8 ? P.gain : c >= 0.48 ? P.inkSoft : P.loss }

    /// A destructive word button (Sell, Return, End lease) at the full 44 pt target.
    private func dangerButton(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(title, action: run).buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.loss))
    }

    private func unitRow(_ o: EquipmentMarket.Owned, _ u: EquipmentMarket.UnitRow) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(u.name + (u.year > 0 ? " \u{00B7} \(u.year)" : "")).textStyle(.body)
                Text((u.boughtUsed ? "Bought used \u{00B7} " : "") + u.warranty + (u.daysInRepair > 0 ? " \u{00B7} in repair \(u.daysInRepair) days" : ""))
                    .textStyle(.caption, tint: u.daysInRepair > 0 ? P.loss : P.inkFaint)
            }
            Spacer(minLength: Theme.Space.s)
            Text(u.wear).textStyle(.caption, tint: tint(u.seenCondition))
            dangerButton("Sell") { sellUnit(o, u) }
        }
    }

    private func vehicleRow(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(v.name).textStyle(.body)
                Text(vehicleLine(v, cur)).textStyle(.caption, tint: v.daysInRepair > 0 ? P.loss : P.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Text(v.wear).textStyle(.caption, tint: tint(v.seenCondition))
            dangerButton(v.mode == "lease" ? "Return" : "Sell") { sellVehicle(v) }
        }
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

    @ViewBuilder private func leaseLine(_ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        if o.leasedCount > 0 {
            HStack(spacing: Theme.Space.s) {
                Text("\(Int(o.leasedCount)) on lease \u{00B7} " + cur.tidyShort(o.leaseMonthly) + "/mo").textStyle(.body, tint: P.inkSoft)
                Spacer(minLength: Theme.Space.s)
                dangerButton("End lease") { endLease(o, cur) }
            }
        }
    }

    private func actions(_ e: GameEngine, _ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        WrapRow(spacing: Theme.Space.s) {
            Button(o.subscription != nil ? "Plans" : "Buy more") { onBuy(o.equipmentID) }.buttonStyle(SecondaryButtonStyle(size: .compact))
            if o.subscription != nil {
                dangerButton("Cancel plan") { cancelPlan(o) }
            } else if o.licence == nil && o.count > 0 && o.kind != "veh" {
                Button("Service all \u{00B7} " + cur.tidyShort(o.serviceCost)) { service(o) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                dangerButton("Sell all") { sellAll(o) }
            }
        }
    }

    // MARK: Actions

    private func ask(_ title: String, _ message: String, _ button: String, _ run: @escaping () -> Void) {
        pending = PendingAction(title: title, message: message, button: button, destructive: true, run: run)
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
        ask("Sell all \(o.name.lowercased())?", "Every unit is sold at its current second-hand value.", "Sell all") {
            result(store.act { $0.sellAllEquipment(companyID: companyID, equipmentID: o.equipmentID) } ?? 0, "Nothing was sold.")
        }
    }

    private func sellVehicle(_ v: EquipmentMarket.VehicleRow) {
        ask(v.mode == "lease" ? "Return \(v.name)?" : "Sell \(v.name)?", "This cannot be undone.", v.mode == "lease" ? "Return" : "Sell") {
            result(store.act { $0.sellVehicle(companyID: companyID, vehicleID: v.id) } ?? 0, "Vehicle returned.")
        }
    }

    private func cancelPlan(_ o: EquipmentMarket.Owned) {
        ask("Cancel the plan for \(o.name.lowercased())?", "The software stops when the plan ends.", "Cancel plan") {
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
