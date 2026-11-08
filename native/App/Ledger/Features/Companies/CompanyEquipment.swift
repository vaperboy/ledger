import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// What the company owns and lacks, in one list: machines, what is missing, vehicles and software. A category shows only where the trade
/// has use for it (`equipmentRelevance`). Buying is in TechPro Store; this screen services, sells, returns and cancels.
struct CompanyEquipmentScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
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
            let rel = e.equipmentRelevance(companyID: companyID)
            let needs: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: companyID)
            let owned: [EquipmentMarket.Owned] = e.ownedEquipment(companyID: companyID)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    if !(rel.machines || rel.vehicles || rel.software) {
                        EmptyState(glyph: Glyph.settings, title: "No equipment in this business").frame(maxWidth: .infinity).padding(.top, Theme.Space.xxl)
                    } else {
                        header(rel, needs, owned)
                        if rel.machines { machinesSection(e, co, needs, owned) }
                        missingSection(e, co, rel, needs)
                        if rel.vehicles { vehiclesSection(e, co, owned) }
                        if rel.software { softwareSection(e, co, needs, owned) }
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .confirmAction($asking)
            .appScreen(title: "Equipment", subtitle: co.name, tab: .company)
        } else {
            EmptyState(glyph: Glyph.settings, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    // MARK: Categories

    private func isMachine(_ o: EquipmentMarket.Owned) -> Bool { o.kind != "veh" && o.kind != "soft" }

    /// Items the trade needs more of than the company has (a required one never bought, or too few for the team).
    private func shortNeeds(_ rel: (machines: Bool, vehicles: Bool, software: Bool), _ needs: [EquipmentMarket.Need]) -> [EquipmentMarket.Need] {
        needs.filter { (n: EquipmentMarket.Need) -> Bool in
            guard n.ofTrade, n.need > 0, n.have + n.leased < n.need else { return false }
            return n.isVehicle ? rel.vehicles : n.isSoftware ? rel.software : rel.machines
        }
    }

    private func isWorn(_ seen: Double, _ down: Int) -> Bool { down == 0 && seen < 0.48 }

    // MARK: Header

    private func header(_ rel: (machines: Bool, vehicles: Bool, software: Bool), _ needs: [EquipmentMarket.Need], _ owned: [EquipmentMarket.Owned]) -> some View {
        let machineCount: Int = owned.filter { isMachine($0) }.reduce(0) { $0 + Int($1.count) + Int($1.leasedCount) }
        let vehicleCount: Int = owned.filter { $0.kind == "veh" }.reduce(0) { $0 + $1.vehicles.count }
        let units: [(seen: Double, down: Int)] = owned.flatMap { (o: EquipmentMarket.Owned) -> [(seen: Double, down: Int)] in
            o.units.map { (seen: $0.seenCondition, down: $0.daysInRepair) } + o.vehicles.map { (seen: $0.seenCondition, down: $0.daysInRepair) }
        }
        let attention: Int = shortNeeds(rel, needs).count + units.filter { $0.down > 0 || isWorn($0.seen, $0.down) }.count + owned.filter { $0.outdated }.count
        var parts: [String] = []
        if rel.machines { parts.append(machineCount.countText("machine")) }
        if rel.vehicles { parts.append(vehicleCount.countText("vehicle")) }
        return HStack(alignment: .center, spacing: Theme.Space.s) {
            Text(parts.joined(separator: " \u{00B7} ")).textStyle(.headline, numeric: true)
            Spacer(minLength: Theme.Space.s)
            AcctPill(text: attention > 0 ? "\(attention) need attention" : "All in order", tone: attention > 0 ? .warn : .good)
        }
    }

    // MARK: Rows

    /// One row: name over a caption, a status pill, and the one action.
    private func itemRow<T: View>(_ title: String, _ subtitle: String, pill: String, tone: AcctPill.Tone, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                if !subtitle.isEmpty { Text(subtitle.tidyText).textStyle(.caption).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                AcctPill(text: pill, tone: tone)
                trailing()
            }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moreMenu<T: View>(@ViewBuilder _ items: () -> T) -> some View {
        Menu { items() } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(P.inkSoft).frame(width: 32, height: 28)
        }
    }

    private func wearTint(_ seen: Double) -> Color { seen >= 0.8 ? P.gain : seen >= 0.48 ? P.inkSoft : P.loss }

    /// What the machine does for the business, from the trade's own flags.
    private func enables(_ e: GameEngine, _ equipmentID: String) -> String {
        guard let s = e.tradeInfo(companyID: companyID)?.allEquipment.first(where: { $0.id == equipmentID }) else { return "" }
        var parts: [String] = []
        if s.isRequired { parts.append("Needed to trade") }
        if s.limitsCapacity { parts.append("Sets capacity") }
        if s.affectsQuality { parts.append("Lifts quality") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func priceText(_ x: EquipmentMarket.Need, _ cur: Currency) -> String {
        x.subscription ? "from " + cur.tidyShort(x.fromPrice / max(1, x.lifeYears) / 12) + "/mo" : "from " + cur.tidyShort(x.fromPrice)
    }

    // MARK: Machines

    private func machinesSection(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need], _ all: [EquipmentMarket.Owned]) -> some View {
        let list: [EquipmentMarket.Owned] = all.filter { isMachine($0) }
        let cur: Currency = e.currency(for: co)
        return PageGroup("Machines") {
            if list.isEmpty {
                Text("None owned").textStyle(.caption).padding(.vertical, Theme.Space.s)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { n, o in
                if n > 0 { RowRule(inset: 0) }
                machineBlock(e, o, cur)
            }
        }
    }

    private func machineBlock(_ e: GameEngine, _ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        let down: Int = o.units.filter { $0.daysInRepair > 0 }.count
        let worn: Int = o.units.filter { isWorn($0.seenCondition, $0.daysInRepair) }.count
        let pill: String = down > 0 ? "\(down) in repair" : worn > 0 ? "Worn" : o.outdated ? "Outdated" : "Working"
        let tone: AcctPill.Tone = down > 0 ? .bad : (worn > 0 || o.outdated) ? .warn : .good
        var sub: [String] = []
        let en: String = enables(e, o.equipmentID)
        if !en.isEmpty { sub.append(en) }
        if o.count + o.leasedCount > 1 { sub.append("\(Int(o.count + o.leasedCount)) units") }
        if o.leasedCount > 0 { sub.append("\(Int(o.leasedCount)) leased, " + cur.tidyShort(o.leaseMonthly) + "/mo") }
        if let s = o.subscription { sub.append(s + ", " + cur.tidyShort(o.subscriptionMonthly) + "/mo") }
        else if let l = o.licence { sub.append(l) }
        return VStack(alignment: .leading, spacing: 0) {
            itemRow(o.name, sub.joined(separator: " \u{00B7} "), pill: pill, tone: tone) {
                HStack(spacing: Theme.Space.xs) {
                    if o.subscription == nil && o.licence == nil && o.count > 0 {
                        Button("Service \(cur.tidyShort(o.serviceCost))") { service(o.equipmentID) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                    }
                    moreMenu {
                        if o.count > 1 { Button("Sell all") { ask(.all(equipmentID: o.equipmentID, name: o.name.lowercased())) } }
                        if o.leasedCount > 0 {
                            Button("End the lease") { ask(.endLease(equipmentID: o.equipmentID, name: o.name.lowercased(), units: Int(o.leasedCount), monthly: cur.tidyShort(o.leaseMonthly))) }
                        }
                        if o.subscription != nil { Button("Cancel plan") { ask(.cancelPlan(equipmentID: o.equipmentID, name: o.name.lowercased())) } }
                    }
                }
            }
            if o.units.count > 1 || o.units.contains(where: { $0.daysInRepair > 0 }) {
                ForEach(o.units) { u in
                    HStack(spacing: Theme.Space.s) {
                        Text(u.name + (u.year > 0 ? " \u{00B7} \(u.year)" : "")).textStyle(.caption).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text(u.daysInRepair > 0 ? "In repair \(u.daysInRepair) days" : u.wear).textStyle(.caption, tint: u.daysInRepair > 0 ? P.loss : wearTint(u.seenCondition))
                        Button("Sell") { ask(.unit(equipmentID: o.equipmentID, unitID: u.id, name: o.name.lowercased())) }
                            .buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.inkSoft))
                    }
                    .padding(.leading, Theme.Space.m).padding(.bottom, Theme.Space.xs)
                }
            } else if let u = o.units.first {
                HStack(spacing: Theme.Space.s) {
                    Text(u.wear).textStyle(.caption, tint: wearTint(u.seenCondition))
                    Spacer(minLength: Theme.Space.s)
                    Button("Sell") { ask(.unit(equipmentID: o.equipmentID, unitID: u.id, name: o.name.lowercased())) }
                        .buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.inkSoft))
                }
                .padding(.leading, Theme.Space.m).padding(.bottom, Theme.Space.xs)
            }
        }
    }

    private func service(_ equipmentID: String) {
        switch store.act({ $0.serviceEquipment(companyID: companyID, equipmentID: equipmentID) }) {
        case .ok?: store.show("Serviced.", tone: "good")
        default: store.show("Not enough cash.", tone: "warn")
        }
    }

    // MARK: Missing

    @ViewBuilder private func missingSection(_ e: GameEngine, _ co: Company, _ rel: (machines: Bool, vehicles: Bool, software: Bool), _ needs: [EquipmentMarket.Need]) -> some View {
        let list: [EquipmentMarket.Need] = shortNeeds(rel, needs)
        let cur: Currency = e.currency(for: co)
        if !list.isEmpty {
            PageGroup(title: "Missing but needed", trailing: { Text("Buy in TechPro").textStyle(.caption) }) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, x in
                    if n > 0 { RowRule(inset: 0) }
                    let have: Int = Int((x.have + x.leased).rounded())
                    let none: Bool = x.have + x.leased < 1
                    let en: String = enables(e, x.equipmentID)
                    itemRow(x.name, en.isEmpty ? EquipmentMarket.kindName(x.kind) : en,
                            pill: none ? (x.required ? "Blocks trading" : "Missing") : "\(have) of \(Int(x.need))", tone: none && x.required ? .bad : .warn) {
                        Text(priceText(x, cur)).textStyle(.caption, numeric: true)
                    }
                }
            }
        }
    }

    // MARK: Vehicles

    @ViewBuilder private func vehiclesSection(_ e: GameEngine, _ co: Company, _ all: [EquipmentMarket.Owned]) -> some View {
        let cur: Currency = e.currency(for: co)
        let own: [EquipmentMarket.Owned] = all.filter { $0.kind == "veh" && $0.equipmentID != CompanyCarPerk.equipmentID }
        let perk: EquipmentMarket.Owned? = all.first { $0.equipmentID == CompanyCarPerk.equipmentID }
        let garage: Int? = e.carRepairGarages(for: companyID).first
        PageGroup("Vehicles") {
            if own.isEmpty && perk == nil { Text("None owned").textStyle(.caption).padding(.vertical, Theme.Space.s) }
            ForEach(Array(own.flatMap { $0.vehicles }.enumerated()), id: \.element.id) { n, v in
                if n > 0 { RowRule(inset: 0) }
                vehicleRow(e, v, cur, garage)
            }
            if let perk {
                ForEach(Array(perk.vehicles.enumerated()), id: \.element.id) { n, v in
                    if n > 0 || !own.isEmpty { RowRule(inset: 0) }
                    itemRow(v.driver.isEmpty ? v.name : v.driver, v.name + " \u{00B7} fuel " + cur.tidyShort(v.fuelPerWeek) + "/wk",
                            pill: v.daysInRepair > 0 ? "In repair" : "Company car", tone: v.daysInRepair > 0 ? .bad : .neutral) {
                        Text(cur.tidyShort(v.monthlyLease) + "/mo").textStyle(.caption, numeric: true)
                    }
                }
            }
            runningCosts(e, cur)
        }
    }

    private func vehicleRow(_ e: GameEngine, _ v: EquipmentMarket.VehicleRow, _ cur: Currency, _ garage: Int?) -> some View {
        let broken: Bool = v.daysInRepair > 0
        let worn: Bool = v.seenCondition < 0.8 || broken
        var sub: [String] = []
        if !v.driver.isEmpty { sub.append(v.driver) }
        sub.append(v.mode == "fin" ? "Financed" : v.mode == "lease" ? "Leased " + cur.tidyShort(v.monthlyLease) + "/mo" : "Owned")
        sub.append("\(v.kilometres / 1000) 000 km")
        if v.fuelPerWeek > 0 { sub.append("fuel " + cur.tidyShort(v.fuelPerWeek) + "/wk") }
        let pill: String = broken ? "In repair \(v.daysInRepair) days" : v.wear
        let tone: AcctPill.Tone = broken ? .bad : v.seenCondition >= 0.8 ? .good : v.seenCondition >= 0.48 ? .neutral : .warn
        let sell: Pending = .vehicle(id: v.id, name: v.name)
        return itemRow(v.name, sub.joined(separator: " \u{00B7} "), pill: pill, tone: tone) {
            HStack(spacing: Theme.Space.xs) {
                if let gid = garage, worn {
                    Menu {
                        ForEach(CarRepairJobs.kinds) { (k: RepairKind) in
                            Button(k.name) { askGarage(e, gid, k, v.name, cur) }
                        }
                    } label: { Text("Repair").textStyle(.caption, tint: P.accent, weight: .semibold).frame(minHeight: 28) }
                    moreMenu { Button(v.mode == "lease" ? "Return" : "Sell") { ask(sell) } }
                } else {
                    Button(v.mode == "lease" ? "Return" : "Sell") { ask(sell) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
            }
        }
    }

    @ViewBuilder private func runningCosts(_ e: GameEngine, _ cur: Currency) -> some View {
        let run = e.fleetRunningCosts(companyID: companyID)
        if run.total > 0 {
            RowRule(inset: 0)
            LedgerRow(title: "Running costs", value: cur.tidyShort(run.total), valueNote: "a week", density: .compact)
        }
    }

    private func askGarage(_ e: GameEngine, _ garageID: Int, _ kind: RepairKind, _ vehicle: String, _ cur: Currency) {
        guard let q = e.carRepairQuote(garageID: garageID, kind: kind.id) else {
            store.show("The garage has no room for this job now.", tone: "warn"); return
        }
        let cid: Int = companyID
        let weeks: String = "\(q.weeks) " + (q.weeks == 1 ? "week" : "weeks")
        let msg: String = q.garageName + " charges " + cur.tidyShort(q.price) + " plus " + cur.tidyShort(q.vat) + " VAT for " + kind.name.lowercased() + ", back in about " + weeks + "."
        asking = PendingAction(title: "Repair " + vehicle + "?", message: msg, button: "Order", amount: q.total, currency: cur, tone: .info, icon: "wrench.and.screwdriver") {
            let r: RepairResult? = store.act { (g: inout GameEngine) -> RepairResult in g.orderCarRepair(garageID: garageID, dealerID: cid, kind: kind.id, ref: vehicle) }
            switch r {
            case .ordered(let o)?: store.show("Ordered for " + cur.tidyShort(o.price + o.vat) + ", back in \(o.weeks) " + (o.weeks == 1 ? "week" : "weeks") + ".", tone: "good")
            case .refused(let why)?: store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    // MARK: Software

    @ViewBuilder private func softwareSection(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need], _ all: [EquipmentMarket.Owned]) -> some View {
        let cur: Currency = e.currency(for: co)
        let list: [EquipmentMarket.Need] = needs.filter { (n: EquipmentMarket.Need) -> Bool in
            guard n.isSoftware, n.ofTrade || n.have + n.leased > 0 else { return false }
            return !(n.need > 0 && n.have + n.leased < n.need)
        }
        if !list.isEmpty {
            PageGroup(title: "Software", trailing: { Text("Priced by users: \(EquipmentMarket.users(co))").textStyle(.caption) }) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, x in
                    if n > 0 { RowRule(inset: 0) }
                    softwareRow(e, x, all.first { $0.equipmentID == x.equipmentID }, cur)
                }
            }
        }
    }

    private func softwareRow(_ e: GameEngine, _ x: EquipmentMarket.Need, _ o: EquipmentMarket.Owned?, _ cur: Currency) -> some View {
        let mode = e.softwareMode(companyID: companyID, equipmentID: x.equipmentID)
        let modeWord: String = mode == .subscription ? "Subscription" : mode == .once ? "One-time licence" : "Licence with yearly updates"
        let pill: String = o?.subscription != nil ? "Active" : o?.licence != nil ? (o?.outdated == true ? "Outdated" : "Current") : "Not owned"
        let tone: AcctPill.Tone = o?.outdated == true ? .warn : o != nil ? .good : .neutral
        return itemRow(x.name, modeWord, pill: pill, tone: tone) {
            if let o, o.subscription != nil {
                HStack(spacing: Theme.Space.xs) {
                    Text(cur.tidyShort(o.subscriptionMonthly) + "/mo").textStyle(.caption, numeric: true)
                    moreMenu { Button("Cancel plan") { ask(.cancelPlan(equipmentID: x.equipmentID, name: x.name.lowercased())) } }
                }
            } else if o == nil {
                Text(priceText(x, cur)).textStyle(.caption, numeric: true)
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
        asking = PendingAction(title: askTitle(p), message: askMessage(p), button: buttonTitle(p), destructive: false, tone: .danger, icon: "tag") { confirm(p) }
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
}
