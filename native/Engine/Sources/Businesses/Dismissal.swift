import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Letting someone go: the ONE place that decides what a dismissal costs and books it (roadmap A1, A2).
///
/// - `quote` works out notice (pay in lieu, with the employer charge at this wage), severance and the termination fund fine from the labour law of
///   the company's country (`LabourRules.termination`), the reason, the tenure, the age and the wage. It is the figure every preview shows.
/// - `dismiss` (staff) and `dismissManager` decide the reason, roll an unfair-dismissal claim where one is possible, remove the person and call `book`.
/// - `book` is the only code that posts the Notice / Severance / Termination fund fine payments.
/// Callers (staff profile, layoffs, roster let-go, proposals, manager, board, team slots, resignations) pass a reason and delegate; none of them
/// computes or posts these payments itself.
public enum Dismissal {
    public typealias Reason = LabourRules.TerminationReason

    /// What a dismissal costs now, kept as three separate payments. `total` is what leaves the company's cash.
    public struct Quote: Equatable, Sendable {
        public var reason: Reason
        public var notice: Double
        public var severance: Double
        public var fine: Double
        /// Whether, without a documented reason, this person could claim unfair dismissal (not in probation, not at will).
        public var canClaimUnfairDismissal: Bool
        public var total: Double { notice + severance + fine }
    }

    /// What `dismiss` did: the quote it booked, and any unfair-dismissal settlement on top.
    public struct Outcome: Equatable, Sendable {
        public var quote: Quote
        public var claimedUnfairDismissal: Bool
        public var compensation: Double
        public var paid: Double { quote.total }
    }

    /// Payment labels. Manager and staff keep their own wording; one engine function posts them all.
    public struct Labels: Sendable {
        public var notice: String, severance: String, fine: String
        public static let staff = Labels(notice: "Notice pay", severance: "Severance", fine: "Termination fund fine")
        public static let manager = Labels(notice: "Manager notice pay", severance: "Manager severance", fine: "Termination fund fine")
        /// A team post or executive let go for a month of pay.
        public static func post(_ title: String) -> Labels { Labels(notice: "Notice pay", severance: "Severance: \(title)", fine: "Termination fund fine") }
    }

    public enum Payer: Sendable { case company(Int), player }

    // MARK: Decide

    /// The reason the player's own dismissal of this person is judged under: two warnings (or theft) on file make it for cause, otherwise it is unjustified.
    public static func reasonForDismissing(_ m: StaffMember) -> Reason { StaffProfile.isDocumented(m) ? .forCause : .unjustified }

    /// The quote for a wage, tenure and reason in this company's country. The single arithmetic behind every dismissal figure.
    public static func quote(_ world: World, _ co: Company, monthlyWage: Double, tenureWeeks: Double, reason: Reason, onNotice: Bool = false,
                             age: Double? = nil, massLayoff: Bool = false) -> Quote {
        let p = world.terminationPayments(co, monthlyWage: monthlyWage, tenureWeeks: tenureWeeks, onNotice: onNotice, reason: reason, age: age, massLayoff: massLayoff)
        return Quote(reason: reason, notice: p.notice, severance: p.severance, fine: p.fine, canClaimUnfairDismissal: world.labour(co).canClaimUnfairDismissal(tenureWeeks: tenureWeeks))
    }

    /// The quote for letting this member of staff go now. `reason` nil: judged by their warnings (`reasonForDismissing`).
    public static func quote(_ s: GameState, companyID: Int, staffID: Int, reason: Reason? = nil, noticeServed: Bool = false, data: GameData) -> Quote? {
        guard let co = s.company(companyID), let m = co.staff.first(where: { $0.id == staffID }) else { return nil }
        let world = World(state: s, data: data), why = reason ?? reasonForDismissing(m), onNotice = noticeServed || m.noticeWeeks > 0
        var q = quote(world, co, monthlyWage: m.monthlyWage, tenureWeeks: Double(s.week - m.hiredWeek), reason: why, onNotice: onNotice, age: s.people[staffID].map { Double($0.age) })
        // Extra notice agreed in a contract talk (ContractTalk, key "nx") is owed on top, in the cases where the country's law owes notice at all.
        let extra = Double(m.int("nx"))
        if extra > 0, !onNotice, world.labour(co).noticeReasons.contains(why.rawValue) {
            q.notice += m.monthlyWage * 12 / 52 * extra * world.country(co).payrollFactor(monthlyWage: m.monthlyWage)
        }
        return q
    }

    /// The summed quote for several people under one reason (the layoff card).
    public static func quote(_ s: GameState, companyID: Int, staffIDs: [Int], reason: Reason, data: GameData) -> Double {
        staffIDs.reduce(0) { $0 + (quote(s, companyID: companyID, staffID: $1, reason: reason, data: data)?.total ?? 0) }
    }

    // MARK: Staff

    /// Let a member of staff go and pay for it. `reason` nil: judged by their warnings, and without a documented reason a person who may claim
    /// (`canClaimUnfairDismissal`) sometimes does, which costs a settlement of two to four months' pay. `noticeServed`: they have already worked
    /// their notice (a resignation), so nothing is owed. Returns nil when the person is not on the payroll.
    @discardableResult
    public static func dismiss(_ s: inout GameState, companyID: Int, staffID: Int, reason: Reason? = nil, noticeServed: Bool = false, data: GameData) -> Outcome? {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        let m = s.companies[ci].staff[k]
        let why = reason ?? reasonForDismissing(m)
        guard let q = quote(s, companyID: companyID, staffID: staffID, reason: why, noticeServed: noticeServed, data: data) else { return nil }
        // The claim is rolled before the person goes, as it always was.
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

    // MARK: A fixed term running out

    /// The job ends on the date of a fixed term. What is owed is the country's data for the reason `expiry` (nothing where it lists none); notice is not
    /// paid again when the owner already said in time that the term would end (`noticeGiven`). Returns nil when the person is not on the payroll.
    @discardableResult
    public static func expire(_ s: inout GameState, companyID: Int, staffID: Int, noticeGiven: Bool, data: GameData) -> Quote? {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        let m = s.companies[ci].staff[k]
        var q = quote(World(state: s, data: data), s.companies[ci], monthlyWage: m.monthlyWage, tenureWeeks: Double(s.week - m.hiredWeek), reason: .expiry,
                      age: s.people[staffID].map { Double($0.age) })
        if noticeGiven { q.notice = 0 }
        s.companies[ci].staff.remove(at: k)
        if var p = s.people[staffID] { p.employerID = 0; s.people[staffID] = p }
        book(&s, payer: .company(companyID), notice: q.notice, severance: q.severance, fine: q.fine)
        return q
    }

    // MARK: Manager

    /// Dismiss (or, once the notice is worked, release) the company's manager: the same quote and booking as staff, under the manager's labels;
    /// then the owner runs the company again.
    @discardableResult
    public static func dismissManager(_ s: inout GameState, companyID: Int, reason: Reason = .redundancy, noticeServed: Bool = false, data: GameData) -> Quote? {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID else { return nil }
        let hired = s.companies[ci].value("mgrW0").isNull ? Double(s.week - 52) : s.companies[ci].num("mgrW0")
        let q = quote(World(state: s, data: data), s.companies[ci], monthlyWage: s.companies[ci].managerMonthlyWage, tenureWeeks: Double(s.week) - hired, reason: reason,
                      onNotice: noticeServed, age: s.people[mid].map { Double($0.age) })
        if var n = s.people[mid] { n.employerID = 0; s.people[mid] = n }
        book(&s, payer: .company(companyID), notice: q.notice, severance: q.severance, fine: q.fine, labels: .manager)
        ManagerModel.stepDown(&s, ci)
        return q
    }

    // MARK: Booking

    /// A month of pay with the employer's charge, the flat terms of an assistant, a team post or an executive (not the statutory quote).
    public static func monthOfPay(wage: Double, employerSocial: Double) -> Double { wage * (1 + employerSocial) }

    /// THE booking of a dismissal: notice (or pay in lieu), severance and the termination fine as separate payments, each only when owed.
    /// The company pays (category wages, so they stay apart from routine payroll); a player-level post is paid from the player's own account.
    public static func book(_ s: inout GameState, payer: Payer, notice: Double = 0, severance: Double = 0, fine: Double = 0, labels: Labels = .staff) {
        for (amount, label) in [(notice, labels.notice), (severance, labels.severance), (fine, labels.fine)] where amount > 0 {
            switch payer {
            case .company(let id): Payments.companyPays(&s, companyID: id, amount: amount, category: "wages", label: label)
            case .player: Payments.playerPays(&s, amount, label: label)
            }
        }
    }
}
