import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum Dismissal {
    public typealias Reason = LabourRules.TerminationReason

    public struct Quote: Equatable, Sendable {
        public var reason: Reason
        public var notice: Double
        public var severance: Double
        public var fine: Double
        public var canClaimUnfairDismissal: Bool
        public var total: Double { notice + severance + fine }
    }

    public struct Outcome: Equatable, Sendable {
        public var quote: Quote
        public var claimedUnfairDismissal: Bool
        public var compensation: Double
        public var paid: Double { quote.total }
    }

    public struct Labels: Sendable {
        public var notice: String, severance: String, fine: String
        public static let staff = Labels(notice: "Notice pay", severance: "Severance", fine: "Termination fund fine")
        public static let manager = Labels(notice: "Manager notice pay", severance: "Manager severance", fine: "Termination fund fine")
        public static func post(_ title: String) -> Labels { Labels(notice: "Notice pay", severance: "Severance: \(title)", fine: "Termination fund fine") }
    }

    public enum Payer: Sendable { case company(Int), player }

    public static func reasonForDismissing(_ m: StaffMember) -> Reason { StaffProfile.isDocumented(m) ? .forCause : .unjustified }

    public static func quote(_ world: World, _ co: Company, monthlyWage: Double, tenureWeeks: Double, reason: Reason, onNotice: Bool = false,
                             massLayoff: Bool = false) -> Quote {
        let p = world.terminationPayments(co, monthlyWage: monthlyWage, tenureWeeks: tenureWeeks, onNotice: onNotice, reason: reason, massLayoff: massLayoff)
        return Quote(reason: reason, notice: p.notice, severance: p.severance, fine: p.fine, canClaimUnfairDismissal: world.labour(co).canClaimUnfairDismissal(tenureWeeks: tenureWeeks))
    }

    public static func quote(_ s: GameState, companyID: Int, staffID: Int, reason: Reason? = nil, noticeServed: Bool = false, data: GameData) -> Quote? {
        guard let co = s.company(companyID), let m = co.staff.first(where: { $0.id == staffID }) else { return nil }
        let world = World(state: s, data: data), why = reason ?? reasonForDismissing(m), onNotice = noticeServed || m.noticeWeeks > 0
        var q = quote(world, co, monthlyWage: m.monthlyWage, tenureWeeks: Double(s.week - m.hiredWeek), reason: why, onNotice: onNotice)
        let extra = Double(m.int("nx"))
        if extra > 0, !onNotice, world.labour(co).noticeReasons.contains(why.rawValue) {
            q.notice += m.monthlyWage * 12 / 52 * extra * (1 + world.country(co).employerOnCost(monthlyWage: m.monthlyWage))
        }
        return q
    }

    public static func quote(_ s: GameState, companyID: Int, staffIDs: [Int], reason: Reason, data: GameData) -> Double {
        staffIDs.reduce(0) { $0 + (quote(s, companyID: companyID, staffID: $1, reason: reason, data: data)?.total ?? 0) }
    }

    @discardableResult
    public static func dismiss(_ s: inout GameState, companyID: Int, staffID: Int, reason: Reason? = nil, noticeServed: Bool = false, data: GameData) -> Outcome? {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        let m = s.companies[ci].staff[k]
        let why = reason ?? reasonForDismissing(m)
        guard let q = quote(s, companyID: companyID, staffID: staffID, reason: why, noticeServed: noticeServed, data: data) else { return nil }
        let claims = why == .unjustified && q.canClaimUnfairDismissal && s.random.chance(!m.value("flag").isNull ? 0.35 : 0.55)
        let name = s.people[staffID]?.name ?? "A team member"
        s.companies[ci].staff.remove(at: k)
        if var p = s.people[staffID] { p.employerID = 0; s.people[staffID] = p }
        book(&s, payer: .company(companyID), notice: q.notice, severance: q.severance, fine: q.fine)
        var comp = 0.0
        if claims {
            let cur = World(state: s, data: data).currency(s.companies[ci])
            comp = cur.roundedStep(s.random.range(m.monthlyWage * 2, m.monthlyWage * 4), about: 100)
            Payments.companyPays(&s, companyID: companyID, amount: comp, category: "fine", label: "Unfair dismissal settlement")
            s.note("\(name) claimed unfair dismissal. \(s.companies[ci].name) paid \(cur.display(comp)) in compensation.", tone: "bad", companyID: companyID)
        }
        return Outcome(quote: q, claimedUnfairDismissal: claims, compensation: comp)
    }

    @discardableResult
    public static func expire(_ s: inout GameState, companyID: Int, staffID: Int, noticeGiven: Bool, data: GameData) -> Quote? {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        let m = s.companies[ci].staff[k]
        var q = quote(World(state: s, data: data), s.companies[ci], monthlyWage: m.monthlyWage, tenureWeeks: Double(s.week - m.hiredWeek), reason: .expiry)
        if noticeGiven { q.notice = 0 }
        s.companies[ci].staff.remove(at: k)
        if var p = s.people[staffID] { p.employerID = 0; s.people[staffID] = p }
        book(&s, payer: .company(companyID), notice: q.notice, severance: q.severance, fine: q.fine)
        return q
    }

    @discardableResult
    public static func dismissManager(_ s: inout GameState, companyID: Int, reason: Reason = .redundancy, noticeServed: Bool = false, data: GameData) -> Quote? {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID else { return nil }
        let hired = s.companies[ci].value("mgrW0").isNull ? Double(s.week - 52) : s.companies[ci].num("mgrW0")
        let q = quote(World(state: s, data: data), s.companies[ci], monthlyWage: s.companies[ci].managerMonthlyWage, tenureWeeks: Double(s.week) - hired, reason: reason,
                      onNotice: noticeServed)
        if var n = s.people[mid] { n.employerID = 0; s.people[mid] = n }
        book(&s, payer: .company(companyID), notice: q.notice, severance: q.severance, fine: q.fine, labels: .manager)
        ManagerModel.stepDown(&s, ci)
        GrowthPaths.installSuccessor(&s, companyID: companyID, data: data)
        if reason != .resignation { s.companies[ci].set("mgr12", s.companies[ci].managerID.map { .number(Double($0)) } ?? .null) }
        return q
    }

    public static func monthOfPay(wage: Double, employerSocial: Double) -> Double { wage * (1 + employerSocial) }

    public static func book(_ s: inout GameState, payer: Payer, notice: Double = 0, severance: Double = 0, fine: Double = 0, labels: Labels = .staff) {
        for (amount, label) in [(notice, labels.notice), (severance, labels.severance), (fine, labels.fine)] where amount > 0 {
            switch payer {
            case .company(let id): Payments.companyPays(&s, companyID: id, amount: amount, category: "wages", label: label)
            case .player: Payments.playerPays(&s, amount, label: label)
            }
        }
    }
}
