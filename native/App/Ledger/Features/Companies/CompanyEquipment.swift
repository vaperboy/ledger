import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

// Every piece of equipment as one slim row; a tap opens its single detail screen.
struct CompanyEquipmentScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    @State private var detail: EquipmentTarget? = nil

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
                        missingSection(e, co, rel, needs)
                        if rel.machines { machinesSection(e, co, owned) }
                        if rel.vehicles { vehiclesSection(e, co, owned) }
                        if rel.software { softwareSection(e, co, needs, owned) }
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .navigationDestination(item: $detail) { (t: EquipmentTarget) in
                EquipmentDetailScreen(companyID: companyID, target: t).environment(\.outsidePalette, P)
            }
            .appScreen(title: "Equipment", subtitle: co.name, tab: .company)
        } else {
            EmptyState(glyph: Glyph.settings, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func isMachine(_ o: EquipmentMarket.Owned) -> Bool { o.kind != "veh" && o.kind != "soft" }

    private func shortNeeds(_ rel: (machines: Bool, vehicles: Bool, software: Bool), _ needs: [EquipmentMarket.Need]) -> [EquipmentMarket.Need] {
        needs.filter { (n: EquipmentMarket.Need) -> Bool in
            guard n.ofTrade, n.need > 0, n.have + n.leased < n.need else { return false }
            return n.isVehicle ? rel.vehicles : n.isSoftware ? rel.software : rel.machines
        }
    }

    private func isWorn(_ seen: Double, _ down: Int) -> Bool { down == 0 && seen < 0.48 }

    private func wordFor(_ seen: Double, down: Int) -> (text: String, tone: AcctPill.Tone) {
        if down > 0 { return (text: "In repair", tone: .bad) }
        if seen < 0.48 { return (text: "Worn", tone: .warn) }
        return (text: "Working", tone: .good)
    }

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

    private func priceText(_ x: EquipmentMarket.Need, _ cur: Currency) -> String {
        x.subscription ? "from " + cur.tidyShort(x.fromPrice / max(1, x.lifeYears) / 12) + "/mo" : "from " + cur.tidyShort(x.fromPrice)
    }

    private func glyph(for kind: String) -> String {
        kind == "veh" ? Glyph.vehicle : kind == "soft" ? Glyph.software : Glyph.settings
    }

    // MARK: missing

    // Each missing item opens the shop on that exact item.
    @ViewBuilder private func missingSection(_ e: GameEngine, _ co: Company, _ rel: (machines: Bool, vehicles: Bool, software: Bool), _ needs: [EquipmentMarket.Need]) -> some View {
        let list: [EquipmentMarket.Need] = shortNeeds(rel, needs)
        let cur: Currency = e.currency(for: co)
        if !list.isEmpty {
            PageGroup(title: "Missing but needed", trailing: { Text("Opens TechPro").textStyle(.caption) }) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, x: EquipmentMarket.Need) in
                    let none: Bool = x.have + x.leased < 1
                    if n > 0 { RowRule(inset: 0) }
                    EquipmentListRow(equipmentID: x.equipmentID, name: x.name, detail: priceText(x, cur), condition: nil,
                                     status: none ? (x.required ? "Blocks trading" : "Missing") : "\(Int((x.have + x.leased).rounded())) of \(Int(x.need))",
                                     tone: none && x.required ? .bad : .warn, glyph: glyph(for: x.kind), identifier: "equipment-missing-\(x.equipmentID)") {
                        store.openTechPro(companyID: companyID, equipmentID: x.equipmentID)
                    }
                }
            }
        }
    }

    // MARK: machines

    private func planRow(_ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        var sub: String = ""
        var status: String = "Leased"
        var tone: AcctPill.Tone = .neutral
        if o.subscription != nil {
            sub = cur.tidyShort(o.subscriptionMonthly) + " a month"
            status = "Active"; tone = .good
        } else if o.licence != nil {
            status = o.outdated ? "Outdated" : "Current"; tone = o.outdated ? .warn : .good
        } else if o.leasedCount > 0 {
            sub = "\(Int(o.leasedCount)) on lease, " + cur.tidyShort(o.leaseMonthly) + " a month"
        }
        return EquipmentListRow(equipmentID: o.equipmentID, name: o.name, detail: sub, condition: nil, status: status, tone: tone, glyph: glyph(for: o.kind),
                                identifier: "equipment-plan-\(o.equipmentID)") {
            detail = .plan(equipmentID: o.equipmentID)
        }
    }

    @ViewBuilder private func machinesSection(_ e: GameEngine, _ co: Company, _ all: [EquipmentMarket.Owned]) -> some View {
        let list: [EquipmentMarket.Owned] = all.filter { isMachine($0) }
        let cur: Currency = e.currency(for: co)
        PageGroup("Machines") {
            if list.isEmpty {
                Text("None owned").textStyle(.caption).padding(.vertical, Theme.Space.s)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, o: EquipmentMarket.Owned) in
                if n > 0 { RowRule(inset: 0) }
                machineBlock(o, cur)
            }
        }
    }

    private func unitName(_ o: EquipmentMarket.Owned, _ u: EquipmentMarket.UnitRow, _ index: Int) -> String {
        if !u.name.isEmpty && u.name != o.name { return u.name }
        return o.units.count > 1 ? "\(o.name) \(index + 1)" : o.name
    }

    private func machineBlock(_ o: EquipmentMarket.Owned, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(o.units.enumerated()), id: \.element.id) { (n: Int, u: EquipmentMarket.UnitRow) in
                let w = wordFor(u.seenCondition, down: u.daysInRepair)
                if n > 0 { RowRule(inset: 0) }
                EquipmentListRow(equipmentID: o.equipmentID, name: unitName(o, u, n), detail: u.year > 0 ? "Built \(u.year)" : "", condition: u.seenCondition,
                                 status: w.text, tone: w.tone, identifier: "equipment-unit-\(o.equipmentID)-\(u.id)") {
                    detail = .machine(equipmentID: o.equipmentID, unitID: u.id)
                }
            }
            if o.subscription != nil || o.licence != nil || o.leasedCount > 0 {
                if !o.units.isEmpty { RowRule(inset: 0) }
                planRow(o, cur)
            }
        }
    }

    // MARK: vehicles

    @ViewBuilder private func vehiclesSection(_ e: GameEngine, _ co: Company, _ all: [EquipmentMarket.Owned]) -> some View {
        let cur: Currency = e.currency(for: co)
        let own: [EquipmentMarket.Owned] = all.filter { $0.kind == "veh" && $0.equipmentID != CompanyCarPerk.equipmentID }
        let perk: EquipmentMarket.Owned? = all.first { $0.equipmentID == CompanyCarPerk.equipmentID }
        let rows: [(eq: String, row: EquipmentMarket.VehicleRow)] = own.flatMap { (o: EquipmentMarket.Owned) -> [(eq: String, row: EquipmentMarket.VehicleRow)] in
            o.vehicles.map { (v: EquipmentMarket.VehicleRow) -> (eq: String, row: EquipmentMarket.VehicleRow) in (eq: o.equipmentID, row: v) }
        } + (perk?.vehicles ?? []).map { (v: EquipmentMarket.VehicleRow) -> (eq: String, row: EquipmentMarket.VehicleRow) in (eq: CompanyCarPerk.equipmentID, row: v) }
        PageGroup("Vehicles") {
            if rows.isEmpty { Text("None owned").textStyle(.caption).padding(.vertical, Theme.Space.s) }
            ForEach(Array(rows.enumerated()), id: \.element.row.id) { (n: Int, pair: (eq: String, row: EquipmentMarket.VehicleRow)) in
                if n > 0 { RowRule(inset: 0) }
                vehicleRow(pair.row, equipmentID: pair.eq, cur)
            }
            runningCosts(e, cur)
        }
    }

    private func vehicleRow(_ v: EquipmentMarket.VehicleRow, equipmentID: String, _ cur: Currency) -> some View {
        let w = wordFor(v.seenCondition, down: v.daysInRepair)
        var sub: [String] = []
        if !v.driver.isEmpty { sub.append(v.driver) }
        sub.append(v.mode == "fin" ? "Financed" : v.mode == "lease" ? "Leased" : "Owned")
        if v.kilometres > 0 { sub.append("\(v.kilometres / 1000) 000 km") }
        let name: String = equipmentID == CompanyCarPerk.equipmentID && !v.driver.isEmpty ? v.driver : v.name
        return EquipmentListRow(equipmentID: equipmentID, name: name, detail: sub.joined(separator: " \u{00B7} "), condition: v.seenCondition, status: w.text, tone: w.tone,
                                glyph: Glyph.vehicle, identifier: "equipment-vehicle-\(v.id)") {
            detail = .vehicle(equipmentID: equipmentID, vehicleID: v.id)
        }
    }

    @ViewBuilder private func runningCosts(_ e: GameEngine, _ cur: Currency) -> some View {
        let run = e.fleetRunningCosts(companyID: companyID)
        if run.total > 0 {
            RowRule(inset: 0)
            LedgerRow(title: "Running costs", value: cur.tidyShort(run.total), valueNote: "a week", density: .compact)
        }
    }

    // MARK: software

    @ViewBuilder private func softwareSection(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need], _ all: [EquipmentMarket.Owned]) -> some View {
        let cur: Currency = e.currency(for: co)
        let list: [EquipmentMarket.Need] = needs.filter { (n: EquipmentMarket.Need) -> Bool in
            guard n.isSoftware, n.ofTrade || n.have + n.leased > 0 else { return false }
            return !(n.need > 0 && n.have + n.leased < n.need)
        }
        if !list.isEmpty {
            PageGroup(title: "Software", trailing: { Text("Priced by users: \(EquipmentMarket.users(co))").textStyle(.caption) }) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, x: EquipmentMarket.Need) in
                    if n > 0 { RowRule(inset: 0) }
                    softwareRow(x, all.first { $0.equipmentID == x.equipmentID }, cur)
                }
            }
        }
    }

    @ViewBuilder private func softwareRow(_ x: EquipmentMarket.Need, _ o: EquipmentMarket.Owned?, _ cur: Currency) -> some View {
        if let o {
            planRow(o, cur)
        } else {
            EquipmentListRow(equipmentID: x.equipmentID, name: x.name, detail: priceText(x, cur), condition: nil, status: "Not owned", tone: .neutral, glyph: Glyph.software,
                             identifier: "equipment-software-\(x.equipmentID)") {
                store.openTechPro(companyID: companyID, equipmentID: x.equipmentID)
            }
        }
    }
}
