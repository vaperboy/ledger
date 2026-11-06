import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

private enum EquipmentTab: String, CaseIterable, Hashable, Identifiable {
    case needed = "Equipment", fleet = "Fleet", software = "Software"
    var id: String { rawValue }
}

/// What the company owns, item by item: what is needed, what is owned unit by unit, the fleet and the software. Buying is in TechPro Store
/// (Phone) and the choice of premises in AirStay. Original: `eqUI` and its tabs (features/company/realistic_buying.js).
struct CompanyEquipmentScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var tab: EquipmentTab?
    @State private var asking: PendingAction? = nil

    private enum Pending: Identifiable {
        case unit(equipmentID: String, unitID: Int, name: String)
        case all(equipmentID: String, name: String)
        case vehicle(id: Int, name: String)
        case cancelPlan(equipmentID: String, name: String)
        case endLease(equipmentID: String, name: String, units: Int, monthly: String)
        var id: String {
            switch self {
            case .unit(let e, let u, _): return "u\(e)\(u)"
            case .all(let e, _): return "a\(e)"
            case .vehicle(let v, _): return "v\(v)"
            case .cancelPlan(let e, _): return "c\(e)"
            case .endLease(let e, _, _, _): return "l\(e)"
            }
        }
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let needs = e.equipmentNeeds(companyID: companyID)
            let tabs: [EquipmentTab] = visibleTabs(e, needs)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Cash \(store.short(co.cash, in: co))" + (e.equipmentHealth(companyID: companyID).map { " \u{00B7} equipment \(Words.level($0 * 100, scale: .condition).lowercased())" } ?? "") + " \u{00B7} buy in TechPro Store")
                        .textStyle(.caption)
                    // With only the equipment part there is no index to choose from: its page shows here directly.
                    if tabs.count == 1 {
                        pageContent(.needed, e, co, needs)
                    } else {
                        equipmentTable(e, co, needs, tabs)
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .confirmAction(tabs.count == 1 ? $asking : .constant(nil))
            .appScreen(title: "Equipment", subtitle: co.name, tab: .company)
            .navigationDestination(item: $tab) { (t: EquipmentTab) in
                SettingsPage(title: t.rawValue, subtitle: co.name) { pageContent(t, e, co, needs) }
                    .confirmAction($asking)
            }
        } else {
            EmptyState(glyph: Glyph.settings, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    /// One row per part of the equipment; each opens its own page.
    private func equipmentTable(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need], _ tabs: [EquipmentTab]) -> some View {
        let missing: Int = needs.filter { !$0.isVehicle && !$0.isSoftware && $0.need > 0 && $0.have + $0.leased < $0.need }.count
        let ownedCount: Int = e.ownedEquipment(companyID: companyID).filter { $0.kind != "veh" }.count
        return SettingsTable(heading: "Equipment") {
            ForEach(tabs) { (t: EquipmentTab) in
                switch t {
                case .needed:
                    SettingsTableRow(title: t.rawValue, note: "What is needed, what you own, buy, sell, service",
                                     value: missing > 0 ? "\(missing) missing" : "\(ownedCount) owned", valueTint: missing > 0 ? Theme.caution : Theme.ivory) { tab = t }
                case .fleet:
                    SettingsTableRow(title: t.rawValue, note: "Vehicles, loans and leases", value: "\(needs.filter { $0.isVehicle }.count) kinds") { tab = t }
                case .software:
                    SettingsTableRow(title: t.rawValue, note: "Licences and subscriptions", value: "\(needs.filter { $0.isSoftware }.count) kinds") { tab = t }
                }
            }
        }
    }

    @ViewBuilder private func pageContent(_ t: EquipmentTab, _ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        switch t {
        case .needed:
            needed(e, co, needs)
            owned(e, co)
        case .fleet: fleet(e, co, needs)
        case .software: software(e, co, needs)
        }
    }

    private func visibleTabs(_ e: GameEngine, _ needs: [EquipmentMarket.Need]) -> [EquipmentTab] {
        let hasVehicles: Bool = needs.contains { $0.isVehicle }
        let hasSoftware: Bool = needs.contains { $0.isSoftware }
        return EquipmentTab.allCases.filter { (t: EquipmentTab) -> Bool in
            switch t {
            case .fleet: return hasVehicles
            case .software: return hasSoftware
            default: return true
            }
        }
    }

    // MARK: Confirmations

    private func askTitle(_ p: Pending) -> String {
        switch p {
        case .unit(_, _, let n): return "Sell this \(n)?"
        case .all(_, let n): return "Sell all \(n)?"
        case .vehicle(_, let n): return "Sell \(n)?"
        case .cancelPlan(_, let n): return "Cancel \(n)?"
        case .endLease(_, let n, _, _): return "End the lease of \(n)?"
        }
    }
    private func askMessage(_ p: Pending) -> String {
        switch p {
        case .unit: return "Used equipment sells for well under what you paid, less if it looks worn."
        case .all: return "You get about 70% of book value. Capacity may collapse."
        case .vehicle: return "You get roughly 78% of its book value. A loan on it is settled; a lease just ends."
        case .cancelPlan: return "It stops working right away."
        case .endLease(_, _, let units, let monthly): return "The \(units) leased \(units == 1 ? "unit goes" : "units go") back at once and the capacity they gave is lost until you replace \(units == 1 ? "it" : "them"). The \(monthly) a month stops."
        }
    }
    private func buttonTitle(_ p: Pending) -> String {
        if case .cancelPlan = p { return "Cancel plan" }
        if case .endLease = p { return "End the lease" }
        return "Sell"
    }
    /// Selling, cancelling and ending a lease cannot be taken back, so each one asks.
    private func ask(_ p: Pending) {
        asking = PendingAction(title: askTitle(p), message: askMessage(p), button: buttonTitle(p), destructive: true) { confirm(p) }
    }
    private func confirm(_ p: Pending) {
        switch p {
        case .unit(let eq, let u, _):
            let v = store.act { $0.sellEquipmentUnit(companyID: companyID, equipmentID: eq, unitID: u) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Not sold.", tone: v > 0 ? "good" : "warn")
        case .all(let eq, _):
            let v = store.act { $0.sellAllEquipment(companyID: companyID, equipmentID: eq) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Nothing was sold.", tone: v > 0 ? "good" : "warn")
        case .vehicle(let id, _):
            let v = store.act { $0.sellVehicle(companyID: companyID, vehicleID: id) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Vehicle returned.", tone: "good")
        case .cancelPlan(let eq, _):
            let gone = store.act { $0.cancelSubscription(companyID: companyID, equipmentID: eq) } ?? false
            store.show(gone ? "Plan cancelled." : "The plan could not be cancelled.", tone: gone ? "n" : "warn")
        case .endLease(let eq, let name, _, _):
            if store.act({ $0.endEquipmentLease(companyID: companyID, equipmentID: eq) }) == true { Haptics.warning(); store.show("Lease of \(name) ended.", tone: "n") }
            else { store.show("There is no lease of \(name) to end.", tone: "warn") }
        }
    }

    // MARK: Needed

    @ViewBuilder private func needed(_ e: GameEngine, _ co: Company, _ all: [EquipmentMarket.Need]) -> some View {
        let needs = all.filter { $0.ofTrade || $0.have + $0.leased > 0 }
        let cur = e.currency(for: co)
        let missing = needs.filter { $0.required && $0.have + $0.leased < 1 }
        let short = needs.filter { $0.need > 0 && $0.have + $0.leased < $0.need && !($0.required && $0.have + $0.leased < 1) }
        let upgrades = needs.filter { $0.need == 0 && $0.have + $0.leased == 0 && !$0.required }
        let inPlace = needs.filter { $0.have + $0.leased > 0 && $0.have + $0.leased >= $0.need }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !missing.isEmpty {
                NoteCard(text: (co.status == .setup ? "You cannot open without " : "Work stops without ") + (missing.count > 1 ? "these \(missing.count) items." : missing[0].name.lowercased() + "."), glyph: Glyph.warning, tint: Theme.caution)
                needRows("Missing", missing, cur)
            }
            if !short.isEmpty { needRows("Short for your team", short, cur) }
            if !upgrades.isEmpty { needRows("Upgrades", upgrades, cur) }
            if !inPlace.isEmpty { needRows("In place", inPlace, cur) }
        }
    }

    private func needRows(_ title: String, _ list: [EquipmentMarket.Need], _ cur: Currency) -> some View {
        CardSection(title) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, x in
                    Button { store.openTechPro(companyID: companyID, equipmentID: x.equipmentID) } label: {
                        VStack(spacing: 0) {
                            if n > 0 { CardLine() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                                    Text(needLine(x)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Text(x.have + x.leased > 0 && x.have + x.leased >= x.need ? "Owned" : x.subscription ? "from " + cur.tidyShort(x.fromPrice / max(1, x.lifeYears) / 12) + "/mo" : "from " + cur.tidyShort(x.fromPrice))
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(x.have + x.leased >= max(1, x.need) ? Theme.gain : Theme.ivoryMuted)
                                MoreChevron()
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }
                    }.buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func needLine(_ x: EquipmentMarket.Need) -> String {
        var parts = [EquipmentMarket.kindName(x.kind)]
        let have = Int((x.have + x.leased).rounded())
        if x.need > 0 { parts.insert("\(have) of \(Int(x.need))", at: 0) } else if have > 0 { parts.insert("\(have) owned", at: 0) }
        if x.required { parts.append("required") }
        return parts.joined(separator: " · ")
    }

    // MARK: Owned

    @ViewBuilder private func owned(_ e: GameEngine, _ co: Company) -> some View {
        let list = e.ownedEquipment(companyID: companyID).filter { $0.kind != "veh" }
        let cur = e.currency(for: co)
        if list.isEmpty {
            NoteCard(text: "Nothing bought yet. Start under Needed.")
        }
        ForEach(list) { o in
            CardSection(o.name) {
                VStack(alignment: .leading, spacing: 0) {
                    if let s = o.subscription {
                        FlatRow(label: s, value: cur.tidyShort(o.subscriptionMonthly) + "/mo", sub: "Subscription", rule: false)
                    } else if let l = o.licence {
                        FlatRow(label: l, value: o.outdated ? "Outdated" : "Current", sub: "", tint: o.outdated ? Theme.caution : Theme.ivory, rule: false)
                    }
                    ForEach(Array(o.units.enumerated()), id: \.element.id) { n, u in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.name + (u.year > 0 ? " · \(u.year)" : "")).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text((u.boughtUsed ? "Bought used · " : "") + u.warranty + (u.daysInRepair > 0 ? " · in repair \(u.daysInRepair) days" : ""))
                                    .font(.system(size: 11)).foregroundStyle(u.daysInRepair > 0 ? Theme.loss : Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(u.wear).font(.system(size: 12.5)).foregroundStyle(u.seenCondition >= 0.8 ? Theme.gain : u.seenCondition >= 0.48 ? Theme.ivoryMuted : Theme.loss)
                            Button("Sell") { ask(.unit(equipmentID: o.equipmentID, unitID: u.id, name: o.name.lowercased())) }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8).overlay(alignment: .top) { if n > 0 || o.subscription != nil || o.licence != nil { CardLine() } }
                    }
                    if o.leasedCount > 0 {
                        FlatRow(label: "\(Int(o.leasedCount)) on lease", value: cur.tidyShort(o.leaseMonthly) + "/mo", sub: "Service included", rule: !o.units.isEmpty)
                        Button("End the lease…") { ask(.endLease(equipmentID: o.equipmentID, name: o.name.lowercased(), units: Int(o.leasedCount), monthly: cur.tidyShort(o.leaseMonthly))) }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                    }
                    HStack(spacing: Theme.Space.m) {
                        Button { store.openTechPro(companyID: companyID, equipmentID: o.equipmentID) } label: { Text(o.subscription != nil ? "Plans" : "Buy more").font(.subheadline.weight(.medium)).foregroundStyle(Theme.gold) }.buttonStyle(PressableStyle())
                        if o.subscription != nil {
                            Button("Cancel plan") { ask(.cancelPlan(equipmentID: o.equipmentID, name: o.name.lowercased())) }.buttonStyle(PressableStyle()).font(.subheadline).foregroundStyle(Theme.loss)
                        } else if o.licence == nil {
                            if o.count > 0 {
                                Button("Service all · \(cur.tidyShort(o.serviceCost))") {
                                    switch store.act({ $0.serviceEquipment(companyID: companyID, equipmentID: o.equipmentID) }) {
                                    case .ok?: store.show("Serviced.", tone: "good")
                                    default: store.show("Not enough cash.", tone: "warn")
                                    }
                                }.buttonStyle(PressableStyle()).font(.subheadline).foregroundStyle(Theme.ivoryMuted)
                                Button("Sell all") { ask(.all(equipmentID: o.equipmentID, name: o.name.lowercased())) }.buttonStyle(PressableStyle()).font(.subheadline).foregroundStyle(Theme.loss)
                            }
                        }
                        Spacer()
                    }.padding(.top, 8)
                }
            }
        }
        if let h = e.equipmentHealth(companyID: companyID) {
            CardSection("Condition") {
                VStack(alignment: .leading, spacing: 4) {
                    Meter(label: "Equipment health, as far as you can tell", value: h * 100, scale: .condition)
                    Text("Old equipment breaks more often. Under warranty the maker repairs it for free, but it is away for days. Servicing costs little; replacing costs a lot.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    // MARK: Fleet

    @ViewBuilder private func fleet(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let cur = e.currency(for: co)
        let owned = e.ownedEquipment(companyID: companyID)
        ForEach(needs.filter { $0.isVehicle }) { n in
            let mine = owned.first { $0.equipmentID == n.equipmentID }?.vehicles ?? []
            CardSection(title: n.name, trailing: { Text(n.need > 0 ? "\(mine.count) of \(Int(n.need))" : "\(mine.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if mine.isEmpty { Text("No vehicles yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6) }
                    ForEach(Array(mine.enumerated()), id: \.element.id) { i, v in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(vehicleLine(v, cur))
                                    .font(.system(size: 11)).foregroundStyle(v.daysInRepair > 0 ? Theme.loss : Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(v.wear).font(.system(size: 12.5)).foregroundStyle(v.seenCondition >= 0.8 ? Theme.gain : v.seenCondition >= 0.48 ? Theme.ivoryMuted : Theme.loss)
                            Button(v.mode == "lease" ? "Return" : "Sell") { ask(.vehicle(id: v.id, name: v.name)) }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8).overlay(alignment: .top) { if i > 0 { CardLine() } }
                    }
                    Button { store.openTechPro(companyID: companyID, equipmentID: n.equipmentID) } label: { Text("Buy, buy used or lease").font(.subheadline.weight(.medium)).foregroundStyle(Theme.gold) }.buttonStyle(PressableStyle()).padding(.top, 8)
                }
            }
        }
        perkCars(owned, cur)
        garageRepair(e, owned, cur)
        runningCosts(e, cur)
        Text("Cash keeps you debt-free but drains the account. Finance builds ownership over four to five years. Leasing is a low monthly cost with service included, but you own nothing at the end.")
            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
    }

    /// A worn or broken vehicle can go to a garage of yours: the quote shows price, VAT and weeks before anything is paid.
    @ViewBuilder private func garageRepair(_ e: GameEngine, _ owned: [EquipmentMarket.Owned], _ cur: Currency) -> some View {
        let garages: [Int] = e.carRepairGarages(for: companyID)
        let worn: [EquipmentMarket.VehicleRow] = owned.flatMap { (o: EquipmentMarket.Owned) -> [EquipmentMarket.VehicleRow] in o.vehicles }
            .filter { (v: EquipmentMarket.VehicleRow) -> Bool in v.seenCondition < 0.8 || v.daysInRepair > 0 }
        if let gid = garages.first, !worn.isEmpty {
            CardSection("Repair at your garage") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(worn.enumerated()), id: \.element.id) { i, v in
                        HStack(alignment: .firstTextBaseline) {
                            Text(v.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Spacer(minLength: 8)
                            Menu {
                                ForEach(CarRepairJobs.kinds) { (k: RepairKind) in
                                    Button(k.name) { askGarage(e, gid, k, v.name, cur) }
                                }
                            } label: { Text("Repair").font(.subheadline.weight(.medium)).foregroundStyle(Theme.gold) }
                        }.padding(.vertical, 8).overlay(alignment: .top) { if i > 0 { CardLine() } }
                    }
                    Text((e.state.company(gid)?.name ?? "Your garage") + " does the job at its own price, with VAT.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
                }
            }
        }
    }

    private func askGarage(_ e: GameEngine, _ garageID: Int, _ kind: RepairKind, _ vehicle: String, _ cur: Currency) {
        guard let q = e.carRepairQuote(garageID: garageID, kind: kind.id) else {
            store.show("The garage has no room for this job now.", tone: "warn"); return
        }
        let cid: Int = companyID
        let weeks: String = "\(q.weeks) " + (q.weeks == 1 ? "week" : "weeks")
        let msg: String = q.garageName + " charges " + cur.tidyShort(q.price) + " plus " + cur.tidyShort(q.vat) + " VAT for " + kind.name.lowercased() + ", back in about " + weeks + "."
        asking = PendingAction(title: "Repair " + vehicle + "?", message: msg, button: "Order", amount: q.total, currency: cur) {
            let r: RepairResult? = store.act { (g: inout GameEngine) -> RepairResult in g.orderCarRepair(garageID: garageID, dealerID: cid, kind: kind.id, ref: vehicle) }
            switch r {
            case .ordered(let o)?: store.show("Ordered for " + cur.tidyShort(o.price + o.vat) + ", back in \(o.weeks) " + (o.weeks == 1 ? "week" : "weeks") + ".", tone: "good")
            case .refused(let why)?: store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    @ViewBuilder private func perkCars(_ owned: [EquipmentMarket.Owned], _ cur: Currency) -> some View {
        if let perk = owned.first(where: { $0.equipmentID == "perkcar" }) {
            CardSection(title: perk.name, trailing: { Text("\(perk.vehicles.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(perk.vehicles.enumerated()), id: \.element.id) { i, v in
                        FlatRow(label: v.driver, value: cur.tidyShort(v.monthlyLease) + "/mo", sub: v.name + " · fuel " + cur.tidyShort(v.fuelPerWeek) + "/wk", rule: i > 0)
                    }
                }
            }
        }
    }

    @ViewBuilder private func runningCosts(_ e: GameEngine, _ cur: Currency) -> some View {
        let run = e.fleetRunningCosts(companyID: companyID)
        if run.total > 0 {
            CardSection(title: "Running costs", trailing: { Text("\(cur.tidyShort(run.total)) a week").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if run.fuel > 0 { FlatRow(label: "Fuel", value: cur.tidyShort(run.fuel), sub: "At full use; taxis, couriers and hauliers carry fuel in their cost of sales", rule: false) }
                    if run.leases > 0 { FlatRow(label: "Leases", value: cur.tidyShort(run.leases), sub: "Service included", rule: run.fuel > 0) }
                    if run.charges.insurance > 0 { FlatRow(label: "Motor insurance", value: cur.tidyShort(run.charges.insurance), sub: "", rule: true) }
                    if run.charges.vehicleTax > 0 { FlatRow(label: "Vehicle tax", value: cur.tidyShort(run.charges.vehicleTax), sub: "", rule: true) }
                    if run.charges.benefitCharge > 0 { FlatRow(label: "Charges on company cars", value: cur.tidyShort(run.charges.benefitCharge), sub: "Employer's share on the taxable benefit", rule: true) }
                }
            }
        }
    }

    private func vehicleLine(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> String {
        var line = v.driver.isEmpty ? "" : "\(v.driver) · "
        line += modeWord(v, cur) + " · \(v.kilometres / 1000) 000 km"
        if v.fuelPerWeek > 0 { line += " · fuel \(cur.tidyShort(v.fuelPerWeek))/wk" }
        line += " · " + v.warranty
        if v.daysInRepair > 0 { line += " · in repair \(v.daysInRepair) days" }
        return line
    }

    private func modeWord(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> String {
        v.mode == "fin" ? "Financed" : v.mode == "lease" ? "Leased " + cur.tidyShort(v.monthlyLease) + "/mo" : "Owned"
    }

    // MARK: Software

    @ViewBuilder private func software(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let cur = e.currency(for: co)
        let owned = e.ownedEquipment(companyID: companyID)
        Text("Small programs are bought once. Bigger systems cost more up front plus yearly updates. Some are only sold as a subscription, priced by how many people use them. You have \(EquipmentMarket.users(co)) \(EquipmentMarket.users(co) == 1 ? "user" : "users").")
            .font(.caption).foregroundStyle(Theme.ivoryMuted)
        CardSection("Software") {
            VStack(spacing: 0) {
                ForEach(Array(needs.filter { $0.isSoftware }.enumerated()), id: \.element.id) { n, x in
                    let o = owned.first { $0.equipmentID == x.equipmentID }
                    let mode = e.softwareMode(companyID: companyID, equipmentID: x.equipmentID)
                    Button { store.openTechPro(companyID: companyID, equipmentID: x.equipmentID) } label: {
                        VStack(spacing: 0) {
                            if n > 0 { CardLine() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                                    Text((mode == .subscription ? "Subscription only" : mode == .once ? "One-time licence" : "Licence up front + yearly updates") + (x.required ? " · required" : ""))
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Text(o?.subscription != nil ? cur.tidyShort(o?.subscriptionMonthly ?? 0) + "/mo" : o?.licence != nil ? (o?.outdated == true ? "Outdated" : "Owned") : "from " + cur.tidyShort(mode == .subscription ? x.fromPrice / max(1, x.lifeYears) / 12 : x.fromPrice))
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(o != nil ? Theme.gain : Theme.ivoryMuted)
                                MoreChevron()
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }
                    }.buttonStyle(PressableStyle())
                }
            }
        }
    }
}
