import Foundation
import GameCore
import Countries
import Finance

/// The hired manager replacing people who leave (`ManagementPolicy.autoRehire` needs a manager; nobody else hires automatically, see `ManagerHiring`). Once a week, an open company
/// with fewer people than its standard team, and the cash to pay them, recruits one replacement through its network at the
/// going rate. One hire per company per week, so a business that loses several people takes weeks to recover, as in life.
/// Not part of the original game, where the player hired every replacement by hand.
public enum AutoStaff {
    public static func weekly(_ s: inout GameState, data: GameData) {
        let context = FinanceContext(countries: data.countries, trades: data.catalog)
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status == .open, Delegation.autoRehire(s, co) || (s.policy.autoRehire && HierarchyHiring.staffBoss(s, co, data: data) != nil), let bd = data.catalog[co.type], !bd.hasTrait("noStaff"), bd.family != "rent" else { continue }
            // Replaces people who left; a company with nobody yet is staffed by the player, never automatically (owner decision, 2 Nov).
            guard !co.staff.isEmpty else { continue }
            let weekly = context.weeklyCost(co, s)
            guard co.cash > weekly * 4 else { continue }
            for (idx, st) in CompanySetup.standardStaff(bd, size: co.size).enumerated() {
                var target = st.count
                if idx == 0 && bd.ownerFTE >= 1 && co.managerID == nil && co.ownerHours >= 20 { target = max(0, target - 1) }
                // the manager's one rule: a free place, an empty post, or a leaver and the demand (ManagerHiring)
                guard ManagerHiring.verdict(s, companyID: co.id, role: st.role, target: target, data: data).allowed else { continue }
                if let r = ManagerHiring.fill(&s, companyID: co.id, role: st.role, target: target, data: data) {
                    let roleName = data.catalog.tables.roles[st.role]?.name ?? st.role
                    let by = co.managerID == nil ? (HierarchyHiring.staffBoss(s, co, data: data).map { "\($0.name), the \($0.title.lowercased())" } ?? "the boss above") : "the manager"
                    s.note("\(co.name): \(r.person.name) hired as \(roleName.lowercased()) by \(by)\(ManagerHiring.earlyNote(r.verdict)).", tone: "n", companyID: co.id)
                }
                break
            }
        }
    }
}
