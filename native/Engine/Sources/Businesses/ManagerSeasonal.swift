import Foundation
import GameCore
import Countries
import Employees

extension ManagerModel {
    public struct SeasonalPlan: Equatable, Sendable {
        public var role: String
        public var months: [Int]
        public var count: Int
        public var monthlyCost: Double
    }

    static func monthFactor(_ co: Company, _ bd: Trade, month m: Int, data: GameData) -> Double {
        var f = 1.0
        if let t = data.catalog.tables.seasons[bd.seasonKey], t.count == 12 { f = t[m - 1] }
        if let pk = data.balance.salesWays[co.type]?.first(where: { $0.kind == "peak" }), pk.peakMonths.contains(m) { f *= 1 + (pk.options["b"] ?? 0.3) }
        return f
    }

    public static func seasonalBusyMonths(_ co: Company, data: GameData) -> [Int] {
        guard let bd = data.catalog[co.type] else { return [] }
        return (1...12).filter { monthFactor(co, bd, month: $0, data: data) >= 1.08 }
    }

    static func bottleneckRole(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> String? {
        guard let bot = CapacityModel.compute(co, bd, World(state: s, data: data)).bottleneck, bot.kind == .staff else { return nil }
        let key = bot.key.split(separator: ":").last.map(String.init) ?? ""
        return data.catalog.tables.roles[key] != nil ? key : nil
    }

    static func seasonalRole(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> String? {
        if let key = bottleneckRole(s, co, bd, data: data) { return key }
        guard let first = CompanySetup.standardStaff(bd, size: co.size).first, data.catalog.tables.roles[first.role] != nil else { return nil }
        return first.role
    }

    public static func seasonalPlan(_ s: GameState, companyID: Int, capacity cap: Double, data: GameData) -> SeasonalPlan? {
        guard let co = s.company(companyID), co.status == .open, co.managerID != nil, cap > 0, let bd = data.catalog[co.type] else { return nil }
        let ms = seasonalBusyMonths(co, data: data)
        let now = StaffTalks.month1(s.week), ahead = StaffTalks.month1(s.week + 3)
        guard ms.contains(ahead), !ms.contains(now) else { return nil }
        if co.staff.contains(where: { $0.value("seas").array.contains { $0.int == ahead } }) { return nil }
        guard let role = seasonalRole(s, co, bd, data: data) else { return nil }
        let lift = monthFactor(co, bd, month: ahead, data: data) / max(0.2, monthFactor(co, bd, month: now, data: data)) - 1
        let permanent = co.staff.filter { $0.value("seas").isNull }.count
        let need = Int(saturating: jsRound(Double(permanent) * max(0, lift)))
        guard need >= 1 else { return nil }
        let n = min(4, need)
        return SeasonalPlan(role: role, months: ms, count: n, monthlyCost: marketWage(s, co, role: role, data: data) * 0.67 * Double(n))
    }

    @discardableResult
    public static func hireSeasonalCrew(_ s: inout GameState, companyID: Int, role: String, months: [Int], count: Int, hours: Double = 25, data: GameData) -> Int {
        guard let ci = s.companyIndex(companyID) else { return 0 }
        var got = 0
        for _ in 0..<max(1, count) {
            let co = s.companies[ci]
            let cands = Hiring.search(role: role, company: co, mode: .network, faces: false, state: &s, data: data)
            guard !cands.isEmpty else { break }
            if AutoHire.hireWorker(role: role, companyID: companyID, candidates: cands, terms: Hiring.Terms(hours: hours, seasonMonths: months), state: &s, data: data) != nil {
                got += 1
                StaffingPlan.payRecruiting(&s, companyID: companyID, role: role, months: StaffingPlan.seasonalFeeMonths, data: data)
            }
        }
        return got
    }
}
