import Foundation
import GameCore
import Employees

/// How good the company's work is this week. Original: `qualityTarget` (engine/company/model.js).
/// Quality moves 18% of the way to this target each week; reputation then follows quality slowly.
public enum QualityModel {
    public static func target(_ co: Company, _ bd: Trade, utilisation util: Double, _ w: World, goods: (m: Double, q: Double)) -> Double {
        if let q = SpecialFamilies.qualityTarget(co, bd) { return q }
        let tables = w.catalog.tables
        var ss = 0.0, ns = 0.0
        for m in co.staff { ss += StaffModel.skill(m, person: w.state.people[m.id], salesRoles: tables.salesRoles); ns += 1 }
        let own = co.managerID != nil ? 0.0 : 1.0
        let sk = (ns != 0 || own != 0) ? (ss + co.ownerSkill * own * 1.2) / (ns + own * 1.2) : co.ownerSkill
        var tq = 0.0, hq = 0.0
        for e in bd.equipment where e.affectsQuality {
            tq += 1
            if CapacityModel.equipmentAvailable(co, e) > 0 { hq += CapacityModel.equipmentCondition(co, e) * 0.8 + 0.2 }
        }
        let eqQ = tq != 0 ? 16 * hq / tq : 8
        var q = 28 + 0.3 * sk + eqQ + Knobs.effect(co, bd, "q", w, sum: true)
        if co.managerID != nil { q += 9 * ManagerModel.quality(co, bd, people: w.state.people) }
        if co.ownerHours > 46 && co.managerID == nil { q -= (co.ownerHours - 46) * 0.7 }
        q -= max(0, util - 0.97) * 40
        q += [-3.0, 0, 2][min(2, max(0, co.maintenance))]
        q += goods.q
        return clamp(q, 5, 99)
    }
}
