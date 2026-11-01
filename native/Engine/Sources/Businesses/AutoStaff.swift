import Foundation
import GameCore
import Countries
import Finance

/// The owner's standing instruction to replace people who leave (`ManagementPolicy.autoRehire`). Once a week, an open company
/// with fewer people than its standard team, and the cash to pay them, recruits one replacement through its network at the
/// going rate. One hire per company per week, so a business that loses several people takes weeks to recover, as in life.
/// Not part of the original game, where the player hired every replacement by hand.
public enum AutoStaff {
    public static func weekly(_ s: inout GameState, data: GameData) {
        guard s.policy.autoRehire else { return }
        let context = FinanceContext(countries: data.countries, trades: data.catalog)
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status == .open, let bd = data.catalog[co.type], !bd.hasTrait("noStaff"), bd.family != "rent" else { continue }
            let weekly = context.weeklyCost(co, s)
            guard co.cash > weekly * 4 else { continue }
            for (idx, st) in CompanySetup.standardStaff(bd, size: co.size).enumerated() {
                var target = st.count
                if idx == 0 && bd.ownerFTE >= 1 && co.managerID == nil && co.ownerHours >= 20 { target = max(0, target - 1) }
                let have = co.staff.filter { $0.role == st.role && $0.noticeWeeks <= 0 }.count
                guard have < target else { continue }
                let cands = Hiring.search(role: st.role, company: s.companies[i], mode: .network, faces: false, state: &s, data: data)
                guard !cands.isEmpty else { break }
                // as cheaply as possible for the best talent: the company's manager (else the owner) weighs the candidates and bargains (AutoHire)
                if let pick = AutoHire.hireWorker(role: st.role, companyID: co.id, candidates: cands, state: &s, data: data) {
                    let roleName = data.catalog.tables.roles[st.role]?.name ?? st.role
                    s.note("\(co.name): \(pick.name) hired as \(roleName.lowercased()) to fill a gap in the team.", tone: "n", companyID: co.id)
                }
                break
            }
        }
    }
}
