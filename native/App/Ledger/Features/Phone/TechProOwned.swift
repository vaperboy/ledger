import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// TechPro "My items": what a company owns (units, condition, warranty, software and plans, the fleet), in the store's own look. It replaces
/// the old Equipment screen in the Phone (owner decision, 2 Nov). Selling, servicing, cancelling a plan and ending a lease happen here.
struct TechProOwnedView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var onBuy: (String) -> Void

    @State private var pending: PendingAction?

    var body: some View {
        ShopScroll {
            VStack(alignment: .leading, spacing: 14) {
                if let e = store.engine, let co = e.state.company(companyID) {
                    content(e, co)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 40)
        }
        .confirmAction($pending)
        .accessibilityIdentifier("tp-owned")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let list: [EquipmentMarket.Owned] = e.ownedEquipment(companyID: companyID)
        let cur: Currency = e.currency(for: co)
        ShopHeading(text: "My items", trailing: list.isEmpty ? "" : "\(list.count)")
        if list.isEmpty {
            Text("Nothing bought yet. Browse the store and add items to your basket.").font(.system(size: 14)).foregroundStyle(P.inkSoft)
        }
        ForEach(list) { (o: EquipmentMarket.Owned) in itemCard(e, o, cur) }
        if let h = e.equipmentHealth(companyID: companyID) {
            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Condition").font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                    Text("Equipment health, as far as you can tell: \(Int((h * 100).rounded()))%").font(.system(size: 13)).foregroundStyle(P.inkSoft)
                    Text("Old equipment breaks more often. Under warranty the maker repairs it for free, but it is away for days.")
                        .font(.system(size: 12)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func itemCard(_ e: GameEngine, _ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(o.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                planLine(o, cur)
                ForEach(o.units) { (u: EquipmentMarket.UnitRow) in unitRow(o, u) }
                ForEach(o.vehicles) { (v: EquipmentMarket.VehicleRow) in vehicleRow(v, cur) }
                leaseLine(o, cur)
                actions(e, o, cur)
            }
        }
    }

    @ViewBuilder private func planLine(_ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        if let s = o.subscription {
            Text(s + " \u{00B7} " + cur.tidyShort(o.subscriptionMonthly) + "/mo").font(.system(size: 13)).foregroundStyle(P.inkSoft)
        } else if let l = o.licence {
            Text(l + (o.outdated ? " \u{00B7} outdated" : " \u{00B7} current")).font(.system(size: 13)).foregroundStyle(o.outdated ? P.caution : P.inkSoft)
        }
    }

    private func tint(_ c: Double) -> Color { c >= 0.8 ? P.gain : c >= 0.48 ? P.inkSoft : P.loss }

    private func unitRow(_ o: EquipmentMarket.Owned, _ u: EquipmentMarket.UnitRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(u.name + (u.year > 0 ? " \u{00B7} \(u.year)" : "")).font(.system(size: 13.5)).foregroundStyle(P.ink)
                Text((u.boughtUsed ? "Bought used \u{00B7} " : "") + u.warranty + (u.daysInRepair > 0 ? " \u{00B7} in repair \(u.daysInRepair) days" : ""))
                    .font(.system(size: 11.5)).foregroundStyle(u.daysInRepair > 0 ? P.loss : P.inkFaint)
            }
            Spacer(minLength: 8)
            Text(u.wear).font(.system(size: 12.5)).foregroundStyle(tint(u.seenCondition))
            Button("Sell") { sellUnit(o, u) }.font(.system(size: 13, weight: .semibold)).foregroundStyle(P.loss).buttonStyle(PressableStyle())
        }
    }

    private func vehicleRow(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(v.name).font(.system(size: 13.5)).foregroundStyle(P.ink)
                Text(vehicleLine(v, cur)).font(.system(size: 11.5)).foregroundStyle(v.daysInRepair > 0 ? P.loss : P.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(v.wear).font(.system(size: 12.5)).foregroundStyle(tint(v.seenCondition))
            Button(v.mode == "lease" ? "Return" : "Sell") { sellVehicle(v) }.font(.system(size: 13, weight: .semibold)).foregroundStyle(P.loss).buttonStyle(PressableStyle())
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
            HStack {
                Text("\(Int(o.leasedCount)) on lease \u{00B7} " + cur.tidyShort(o.leaseMonthly) + "/mo").font(.system(size: 13)).foregroundStyle(P.inkSoft)
                Spacer(minLength: 8)
                Button("End lease") { endLease(o, cur) }.font(.system(size: 13, weight: .semibold)).foregroundStyle(P.loss).buttonStyle(PressableStyle())
            }
        }
    }

    private func actions(_ e: GameEngine, _ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        HStack(spacing: 16) {
            Button(o.subscription != nil ? "Plans" : "Buy more") { onBuy(o.equipmentID) }.foregroundStyle(P.accent)
            if o.subscription != nil {
                Button("Cancel plan") { cancelPlan(o) }.foregroundStyle(P.loss)
            } else if o.licence == nil && o.count > 0 && o.kind != "veh" {
                Button("Service all \u{00B7} " + cur.tidyShort(o.serviceCost)) { service(o) }.foregroundStyle(P.inkSoft)
                Button("Sell all") { sellAll(o) }.foregroundStyle(P.loss)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13.5, weight: .semibold)).buttonStyle(PressableStyle())
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
