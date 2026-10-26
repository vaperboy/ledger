import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// Who could run a company's payroll, with the monthly cost of each way.
public struct PayrollModeChoice: Equatable, Sendable, Identifiable {
    public var id: String { mode.rawValue }
    public var mode: Payday.Mode
    public var monthlyFee: Double
    public var isCurrent: Bool
    /// Why this way is not open to the company (nil if it is).
    public var unavailable: String?
}

/// The payroll picture of one company: who runs it, what is due, whether it waits for the owner.
public struct PayrollOverview: Equatable, Sendable {
    public var hasPayroll: Bool
    public var mode: Payday.Mode
    /// Finance companies, clubs, holdings and energy firms run their own payroll: no choice.
    public var modeIsFixed: Bool
    public var choices: [PayrollModeChoice]
    public var payslips: Int
    /// Wages owed now plus what builds up until the next pay day.
    public var estimate: Double
    public var nextPayDay: Int
    public var nextPayText: String
    /// Owner-run payroll that is waiting for the owner's approval for the coming pay day.
    public var needsApproval: Bool
    public var isApproved: Bool
    /// The owner's standing rule approves routine payroll the company can pay (Settings, "How much I decide").
    public var autoApproves: Bool
    public var isLate: Bool
    public var lateReason: String
    public var wagesOwed: Double
    public var companyCash: Double
}

public enum PayrollApprovalResult: Equatable, Sendable { case approved, alreadyApproved, notNeeded(String) }

public extension GameEngine {
    func payrollOverview(companyID: Int) -> PayrollOverview? {
        let s = state
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let t = Payday.dayNumber(week: s.week, day: s.day)
        let cfg = Payday.config(co, today: t)
        let mode = Payday.mode(of: co, trade: bd, config: cfg)
        let fixed = Payday.inHouseFamilies.contains(bd.family)
        let cur = context.currency(co.countryCode, s)
        let hq = s.hasHeadOffice("acc")
        let next = Payday.nextPay(co, config: cfg, today: t)
        let country = context.country(of: co, s)
        let est = (co.payables["wages"] ?? 0) + Payday.weeklyWageCost(co, employerFactor: country.employerCostFactor) * Double(max(0, (next - Payday.dayNumber(week: s.week, day: 0)) / 7))
        let choices = [Payday.Mode.manual, .accountant, .manager].map { m -> PayrollModeChoice in
            var why: String?
            if fixed { why = "This kind of company runs its own payroll." }
            else if m == .manager && co.managerID == nil { why = "Needs a manager first." }
            return PayrollModeChoice(mode: m, monthlyFee: Payday.fee(for: m, co: co, currency: cur, hasAccountingHQ: hq), isCurrent: m == mode, unavailable: why)
        }
        let key = Payday.monthNumber(next)
        let late = cfg.lateSince != nil
        let reason: String = {
            guard late else { return "" }
            switch cfg.lateWhy {
            case "notrun": return "The payroll was not approved in time."
            case "slip": return "The manager missed a step in the payroll software."
            default: return "The company's cash did not cover it."
            }
        }()
        return PayrollOverview(hasPayroll: Payday.hasPayroll(co), mode: mode, modeIsFixed: fixed, choices: choices, payslips: Payday.payslips(co), estimate: est,
                               nextPayDay: next, nextPayText: Payday.dateText(next),
                               needsApproval: mode == .manual && Payday.hasPayroll(co) && !late && cfg.paidMonth < key && cfg.approvedMonth != key,
                               isApproved: cfg.approvedMonth == key && cfg.paidMonth < key, autoApproves: s.policy.autoPayroll, isLate: late, lateReason: reason,
                               wagesOwed: co.payables["wages"] ?? 0, companyCash: co.cash)
    }

    /// The owner approves the coming pay day's payroll (what the Inbox "Approve payroll" message does, for one company).
    @discardableResult
    mutating func approvePayroll(companyID: Int) -> PayrollApprovalResult {
        guard let o = payrollOverview(companyID: companyID) else { return .notNeeded("This company no longer exists.") }
        if o.isApproved { return .alreadyApproved }
        if !o.hasPayroll { return .notNeeded("No one is on the payroll.") }
        if o.mode != .manual { return .notNeeded("Payroll is not run by you at this company.") }
        if o.isLate { return .notNeeded("Payroll is already late: run it now instead.") }
        if !o.needsApproval { return .notNeeded("This month's payroll is already paid.") }
        update { s, d, ctx in
            let key = Payday.monthNumber(o.nextPayDay)
            Payday.answer(&s, action: "pay29all", data: .object(["ids": .array([.number(Double(companyID))]), "mi": .number(Double(key))]), option: 0, companyID: companyID, data: d, context: ctx)
        }
        return .approved
    }

    /// Pay everyone now when payroll is late (what the Inbox "Run payroll now" message does). Returns what was paid and what is still short.
    @discardableResult
    mutating func runLatePayrollNow(companyID: Int) -> (paid: Double, short: Double)? {
        guard let o = payrollOverview(companyID: companyID), o.isLate else { return nil }
        var out: (paid: Double, short: Double)?
        update { s, d, ctx in
            guard let i = s.companyIndex(companyID) else { return }
            let r = Payday.runPayroll(&s, i, how: .manual, today: Payday.dayNumber(week: s.week, day: s.day), data: d, context: ctx)
            out = (r.paid, r.short)
        }
        return out
    }

    /// What moving a home-based company back home from its place would return, so the screen can say it before asking.
    /// `proceeds` is cash back (deposit, or the sale value less the mortgage); `shortfall` is what an owned place would still owe.
    func moveHomeQuote(companyID: Int) -> (isOwned: Bool, proceeds: Double, shortfall: Double)? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], PremisesExtras.isHomeTrade(bd) else { return nil }
        let prem = co.value("prem")
        guard prem["m2"].double > 0 else { return nil }
        if prem["owned"].bool {
            let debt = state.loans.first { $0.id == prem["loan"].int }?.balance ?? 0
            let value = prem["val"].double
            return (true, max(0, value - debt), max(0, debt - value))
        }
        return (false, prem["dep"].double, 0)
    }
}
