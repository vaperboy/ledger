import Foundation
import GameCore
import Countries
import Employees
import Finance

/// What each department head of the management team (`ManagerModel.teamRoles`) decides for the company, on top of their small standing bonus (`teamWeek`):
/// the sales director sets the ad budget, the marketing manager the item prices, the operations manager brings capacity and equipment proposals, the HR manager
/// keeps the hiring plan moving and holds the pay review, and the finance manager sweeps spare cash into the dearest loan and asks early when cash runs low.
/// These are the company's own finance and sales desks, not the fund manager of `FinanceManager`, who invests the owner's money. Heads act under the
/// manager's budget, and only while the company has a manager.
enum ManagerHeads {
    /// The person holding a head's post, nil when it is empty.
    static func head(_ s: GameState, _ co: Company, _ key: String) -> Person? { ManagerModel.person(s, ManagerModel.team(co)["heads"][key]) }

    /// Is the post filled? Read from the team's cached effect, so it is usable where only the company is at hand.
    static func has(_ co: Company, _ key: String) -> Bool { co.value("tm")[key].double > 0 }

    /// Who does a job that a head owns: the head when there is one, else the manager. `tag` is the byline added to the manager's report line.
    static func actor(_ s: GameState, _ co: Company, _ key: String, manager n: Person) -> (person: Person, tag: String) {
        guard let h = head(s, co, key) else { return (n, "") }
        let title = ManagerModel.teamRoles.first { $0.key == key }?.title.lowercased() ?? key
        return (h, " (\(ManagerModel.firstName(h.name)), the \(title))")
    }

    /// Who holds the monthly pay review, and how good they are at it: an HR manager reviews at least as well as their own skill allows.
    static func reviewer(_ s: GameState, _ co: Company, manager n: Person) -> Person { head(s, co, "hr") ?? n }
    static func reviewQuality(_ s: GameState, _ co: Company, manager q: Double) -> Double {
        guard let h = head(s, co, "hr") else { return q }
        return max(q, 0.35 + 0.55 * ManagerModel.skill01(h, "people"))
    }

    static func week(_ s: inout GameState, _ ci: Int, _ bd: Trade, manager n: Person, quality q: Double, utilisation util: Double, demand D: Double, capacity cap: Double, data: GameData) {
        guard s.companies[ci].status == .open else { return }
        if let h = head(s, s.companies[ci], "ops") { operations(&s, ci, bd, head: h, quality: q, utilisation: util, demand: D, capacity: cap, data: data) }
        if let h = head(s, s.companies[ci], "fin") { finance(&s, ci, head: h, quality: q, data: data) }
    }

    // MARK: Operations

    /// Customers are being turned away and a machine, a vehicle or the space is the limit: the operations manager brings the purchase to the owner
    /// (or buys it within the budget, as the manager would). People are the staffing plan's.
    static func operations(_ s: inout GameState, _ ci: Int, _ bd: Trade, head h: Person, quality q: Double, utilisation util: Double, demand D: Double, capacity cap: Double, data: GameData) {
        let co = s.companies[ci]
        guard s.week % 3 == 0, cap > 0, util > 0.9, D > cap * 1.12, co.value("flags")["mgrCool"].double <= 0,
              let p = ManagerModel.bottleneckProposal(s, co, bd, data: data) else { return }
        ManagerModel.propose(&s, ci, p, h, q, data: data)
    }

    // MARK: Finance

    /// Weeks of running costs kept in the account before spare cash goes to a loan.
    static let reserveWeeks = 12.0

    /// Ask the owner for money earlier than the manager would, and pay the dearest loan down with what the account can spare.
    static func finance(_ s: inout GameState, _ ci: Int, head h: Person, quality q: Double, data: GameData) {
        let co = s.companies[ci]
        let cur = World(state: s, data: data).currency(co)
        let week = ManagerModel.weekCost(s, co, data: data)
        if s.week % 3 == 0, co.cash < week * 4, co.cash < cur.scaledPrice(100000), co.value("flags")["mgrCool"].double <= 0 {
            ManagerModel.propose(&s, ci, ManagerModel.Proposal(kind: "cash"), h, q, data: data)
            return
        }
        guard s.week % 4 == 0, ManagerModel.budget(of: co).actsAlone else { return }
        let spare = co.cash - week * reserveWeeks
        let loans = s.loans.filter { $0.companyID == co.id && $0.bankCompanyID == 0 && $0.balance > 1 && s.week >= $0.graceUntilWeek }
        guard spare > 0, let loan = loans.max(by: { $0.margin < $1.margin }) else { return }
        let limit = ManagerModel.spendLimit(of: co, s, data: data) * ManagerVoice.budgetUse(h)
        let amount = jsRound(min(spare, limit, loan.balance))
        guard amount >= max(1, loan.monthlyPayment) else { return }
        let context = FinanceContext(countries: data.countries, trades: data.catalog)
        guard Banking.repay(loanID: loan.id, amount: amount, state: &s, context: context) else { return }
        ManagerVoice.record(&s, companyIndex: ci, "Paid \(cur.display(amount)) off the \(loan.name) loan from spare cash because it is the dearest money we have\(actor(s, s.companies[ci], "fin", manager: h).tag).")
    }
}
