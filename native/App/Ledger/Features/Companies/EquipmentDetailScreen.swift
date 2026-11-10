import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum EquipmentTarget: Identifiable, Equatable {
    case machine(equipmentID: String, unitID: Int)
    case vehicle(equipmentID: String, vehicleID: Int)

    var id: String {
        switch self {
        case .machine(let e, let u): return "m\(e)\(u)"
        case .vehicle(let e, let v): return "v\(e)\(v)"
        }
    }

    var equipmentID: String {
        switch self {
        case .machine(let e, _): return e
        case .vehicle(let e, _): return e
        }
    }
}

struct EquipmentDetailScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var target: EquipmentTarget
    var usedFor: String
    var garageID: Int?
    var onClose: () -> Void
    var onService: (String) -> Void
    var onRepair: (Int, RepairKind, String) -> Void
    var onSell: (EquipmentTarget, String) -> Void

    @State private var pending: PendingAction? = nil

    private struct Facts {
        var name: String
        var value: Double
        var condition: Double
        var wear: String
        var age: String
        var distance: String
        var inRepairDays: Int
        var leased: Bool
        var serviceCost: Double
        var canService: Bool
    }

    private func facts(_ e: GameEngine) -> Facts? {
        guard let o = e.ownedEquipment(companyID: companyID).first(where: { (x: EquipmentMarket.Owned) -> Bool in x.equipmentID == target.equipmentID }) else { return nil }
        switch target {
        case .machine(_, let uid):
            guard let u = o.units.first(where: { (x: EquipmentMarket.UnitRow) -> Bool in x.id == uid }) else { return nil }
            let year: Int = u.year
            return Facts(name: u.name.isEmpty ? o.name : u.name, value: o.bookValue / max(1, o.count), condition: u.seenCondition, wear: u.wear,
                         age: year > 0 ? "Built \(year)" : "", distance: "", inRepairDays: u.daysInRepair, leased: false, serviceCost: o.serviceCost,
                         canService: o.subscription == nil && o.licence == nil && o.count > 0)
        case .vehicle(_, let vid):
            guard let v = o.vehicles.first(where: { (x: EquipmentMarket.VehicleRow) -> Bool in x.id == vid }) else { return nil }
            return Facts(name: v.name, value: v.bookValue, condition: v.seenCondition, wear: v.wear, age: "", distance: v.kilometres > 0 ? "\(v.kilometres.formatted()) km" : "",
                         inRepairDays: v.daysInRepair, leased: v.mode == "lease", serviceCost: 0, canService: false)
        }
    }

    var body: some View {
        if let e = store.engine, let f = facts(e) {
            let cur: Currency = e.state.company(companyID).map { (c: Company) -> Currency in e.currency(for: c) } ?? e.homeCurrency
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Button { Haptics.tap(); onClose() } label: {
                    Label("Equipment", systemImage: "chevron.left").textStyle(.body, tint: P.accent, weight: .semibold).frame(minHeight: 44)
                }
                .accessibilityIdentifier("equipment-detail-back")
                SlotImage(asset: ArtAsset.equipment(target.equipmentID), glyph: Glyph.settings, size: 280)
                    .frame(maxWidth: .infinity, minHeight: 280)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(cur.tidyShort(f.value)).textStyle(.display)
                    Text(f.name.tidyText).textStyle(.title).fixedSize(horizontal: false, vertical: true)
                }
                conditionBar(f)
                PageGroup("Details") {
                    FlatRow(label: "Condition", value: f.inRepairDays > 0 ? "In repair \(f.inRepairDays) days" : f.wear)
                    if !f.age.isEmpty { FlatRow(label: "Age", value: f.age) }
                    if !f.distance.isEmpty { FlatRow(label: "Distance", value: f.distance) }
                    FlatRow(label: "Worth", value: cur.tidyShort(f.value), rule: !usedFor.isEmpty)
                    if !usedFor.isEmpty { FlatRow(label: "Used for", value: usedFor, rule: false) }
                }
                actions(e, f, cur)
            }
            .confirmAction($pending)
            .accessibilityIdentifier("equipment-detail")
        } else {
            EmptyState(glyph: Glyph.settings, title: "This item is gone").frame(maxWidth: .infinity).padding(.top, Theme.Space.xxl).onAppear { onClose() }
        }
    }

    private func conditionBar(_ f: Facts) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(P.hairline)
                Capsule().fill(f.condition >= 0.8 ? P.gain : f.condition >= 0.48 ? P.inkSoft : P.loss)
                    .frame(width: max(8, g.size.width * CGFloat(min(1, max(0, f.condition)))))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Condition \(f.wear)")
    }

    @ViewBuilder private func actions(_ e: GameEngine, _ f: Facts, _ cur: Currency) -> some View {
        VStack(spacing: Theme.Space.s) {
            if f.canService && f.inRepairDays == 0 {
                Button("Service for \(cur.tidyShort(f.serviceCost))") { onService(target.equipmentID) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
            if case .vehicle(_, let vid) = target, let gid = garageID, f.condition < 0.8, f.inRepairDays == 0 {
                Menu {
                    ForEach(CarRepairJobs.kinds) { (k: RepairKind) in Button(k.name) { onRepair(gid, k, f.name) } }
                } label: { Text("Repair").textStyle(.body, tint: P.accent, weight: .semibold).frame(maxWidth: .infinity, minHeight: 44) }
                    .id(vid)
            }
            if f.inRepairDays == 0 && !f.leased { marketButton(e, f) }
            Button(f.leased ? "Return" : "Sell now") { onSell(target, f.name) }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            Text("To replace it, sell this one and buy a new one in TechPro.").textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func marketButton(_ e: GameEngine, _ f: Facts) -> some View {
        let problem: String? = {
            switch target {
            case .machine(let eq, let uid): return e.unitSaleProblem(companyID: companyID, equipmentID: eq, unitID: uid)
            case .vehicle(_, let vid): return e.vehicleSaleProblem(companyID: companyID, vehicleID: vid)
            }
        }()
        if problem == nil {
            Button("Sell on Marketplace") {
                pending = PendingAction(title: "Sell on Marketplace", message: "\(f.name) leaves the company at its worth and goes to your inventory, where you can list it, repair it first, or sell it through a dealership.",
                                        button: "Move to inventory") { moveToInventory(f.name) }
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("equipment-to-marketplace")
        }
    }

    private func moveToInventory(_ name: String) {
        let t: EquipmentTarget = target
        let cid: Int = companyID
        let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in
            switch t {
            case .machine(let eq, let uid): return g.moveUnitToInventory(companyID: cid, equipmentID: eq, unitID: uid, name: name)
            case .vehicle(_, let vid): return g.moveVehicleToInventory(companyID: cid, vehicleID: vid)
            }
        }
        if let why = r?.reason { Haptics.warning(); store.show(why, tone: "warn") } else { Haptics.success(); store.show("In your inventory. Open Marketplace to list it.", tone: "good"); onClose() }
    }
}
