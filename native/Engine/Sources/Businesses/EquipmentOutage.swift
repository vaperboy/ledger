import Foundation
import GameCore

/// What a machine in repair takes away this week. One broken machine never stops the whole business: it cuts only the share of
/// the work that depends on it, and the rest keeps selling.
///
/// Rule, per machine that is required, sets capacity or goes with a person:
///  * out of service = the units short of what the business needs because of repairs, weighted by the days in repair, as a share of
///    what it needs (1 of 2 needed units down all week = 0.5; the only unit down for 3 days = 3/7);
///  * the share that depends on it: the products linked to it in the recipes (a café's display fridge: the cakes and lunch plates,
///    about a third of its customers); without a link, the work a person cannot do without their tool or vehicle; a machine that sets
///    capacity or a vehicle 100%; card terminals and furniture 30%; any other required machine 40%;
///  * lost = out of service x dependent share, at most `maxLoss` for any one machine. Machines down together combine (1 - a)(1 - b):
///    more is lost, never everything.
/// The kept share scales both the week's capacity and its customers, so the lost share of sales is lost even with room to spare.
/// A required machine never bought, premises, staff, licences and closures are not handled here: they still stop trading.
public enum EquipmentOutage {
    /// The most one machine in repair can take away.
    public static let maxLoss = 0.6
    static let kindShare: [String: Double] = ["pos": 0.3, "furn": 0.3]
    public static let otherRequiredShare = 0.4

    public struct Machine: Equatable, Sendable {
        public var id: String
        public var name: String
        /// Share of what it is needed for that is out of service this week (0 to 1).
        public var out: Double
        /// Share of the business's customers lost to it.
        public var lost: Double
        /// What customers miss while it is in repair, from the product links ("chilled items").
        public var offSale: String?
        public var unitsDown: Int
        public var units: Int
    }

    public struct Result: Equatable, Sendable {
        public var machines: [Machine] = []
        /// Share of customers that can still be served.
        public var kept: Double { machines.reduce(1) { $0 * (1 - $1.lost) } }
        public var lost: Double { 1 - kept }
        /// The machine that costs the most.
        public var worst: Machine? { machines.max { $0.lost < $1.lost } }

        /// "Display fridge in repair: chilled items off sale, about 33% fewer customers served."
        public var note: String? {
            guard lost >= 0.005 else { return nil }
            let what = machines.filter { $0.lost > 0 }.sorted { $0.lost > $1.lost }.map { m -> String in
                let all = m.units <= 1 || m.unitsDown >= m.units
                var t = all ? "\(m.name) in repair" : "\(m.name): \(m.unitsDown) of \(m.units) in repair"
                if let off = m.offSale { t += all ? ": \(off) off sale" : ": fewer \(off)" }
                return t
            }
            let pct = Int(saturating: jsRound(lost * 100))
            return what.joined(separator: "; ") + (pct >= 1 ? ", about \(pct)% fewer customers served." : ", a few customers fewer served.")
        }
    }

    /// How many units count for capacity: those working, plus those in repair beyond what the business needs (the outage is counted here instead).
    static func unitsCounted(installed: Double, available: Double, need: Double) -> Double { min(installed, max(available, need)) }

    /// Units the business needs of this machine at its size (personal equipment: per person).
    static func need(_ co: Company, _ bd: Trade, _ e: EquipmentSpec, _ w: World) -> Double {
        if PersonalEquipment.rule(bd, e, tables: w.catalog.tables) != nil { return PersonalEquipment.needed(co, bd, e, tables: w.catalog.tables) }
        return max(1, jsRound(e.standardCount * co.size))
    }

    /// The share of the business that depends on this machine, before the out-of-service share.
    static func dependentShare(_ bd: Trade, _ e: EquipmentSpec, _ w: World) -> (share: Double, off: String?) {
        if let link = FoodRecipes.dependentShare(trade: bd.id, equipmentID: e.id) { return (link.share, link.off) }
        if let rl = PersonalEquipment.rule(bd, e, tables: w.catalog.tables) { return (1 - rl.workWithout, nil) }
        let k = EquipmentMarket.kind(e, tradeID: bd.id, tables: w.catalog.tables)
        if let s = kindShare[k] { return (s, nil) }
        if e.vehicleModels != nil || e.limitsCapacity { return (1, nil) }
        return (otherRequiredShare, nil)
    }

    static func unitsDown(_ co: Company, _ e: EquipmentSpec) -> Int {
        if e.vehicleModels != nil { return co.value("veh").array.filter { $0["eq"].string == e.id && $0["down"].double > 0 }.count }
        return co.value("units")[e.id].array.filter { $0["down"].double > 0 }.count
    }

    public static func compute(_ co: Company, _ bd: Trade, _ w: World) -> Result {
        var r = Result()
        let tables = w.catalog.tables
        for e in bd.equipment where e.isRequired || e.limitsCapacity || PersonalEquipment.rule(bd, e, tables: tables) != nil {
            let installed = CapacityModel.equipmentCount(co, e)
            guard installed >= 0.01 else { continue }
            let available = CapacityModel.equipmentAvailable(co, e)
            guard available < installed - 1e-9 else { continue }
            let n = need(co, bd, e, w)
            guard n > 0 else { continue }
            let out = max(0, min(n, installed) - min(n, available)) / n
            guard out > 1e-9 else { continue }
            let dep = dependentShare(bd, e, w)
            let lost = min(maxLoss, out * dep.share)
            guard lost > 0 else { continue }
            r.machines.append(Machine(id: e.id, name: e.name, out: out, lost: lost, offSale: dep.off, unitsDown: unitsDown(co, e), units: Int(saturating: jsRound(installed))))
        }
        return r
    }
}
