import Foundation
import GameCore
import Countries

public enum Payments {
    static let monthlyCategories: Set<String> = ["oth", "mkt", "ins", "acc", "rent"]

    @discardableResult
    public static func companyPays(_ s: inout GameState, companyID: Int, amount: Double, category: String?, label: String? = nil) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        var amt = amount
        if category == "fine" {
            if let q = s.companies[i].value("law")["q"].isNull ? nil : s.companies[i].value("law")["q"].double { amt *= 1.1 - 0.45 * q }
            if s.hasHeadOffice("law") { amt *= 0.85 }
            if s.companies[i].flag("brdLaw") { amt *= 0.9 }
            if amt > 0, s.rest["net31"]?["fineCut"].double ?? 0 != 0 { amt *= 0.5; s.rest["net31"]?["fineCut"] = 0 }
        }
        if category == "fine" || category == "acc", s.companies[i].value("tm")["fin"].double > 0 { amt *= 1 - 0.15 * s.companies[i].value("tm")["fin"].double }
        if s.transient.simulatingWeek && s.dayMode && label == nil, let cat = category, monthlyCategories.contains(cat), s.companies[i].status.isLive {
            let a = jsRound(amt)
            if a <= 0 { return true }
            s.companies[i].addPayable("other", a)
            var b = s.companies[i].books
            b.add(cat, a)
            s.companies[i].books = b
            var f30 = s.companies[i].value("f30")
            f30[cat] = .number(f30[cat].double + a)
            s.companies[i].set("f30", f30)
            return true
        }
        amt = jsRound(amt)
        if amt <= 0 { return true }
        if Ledger.observer != nil { Ledger.cause = "pays:\(category ?? "-"):\(label ?? "")" }
        AccountingLedger.note(category: category, label: label ?? defaultLabel(category, income: false))
        Ledger.moveRaw(&s, .company(companyID), -amt)
        if let cat = category {
            var b = s.companies[i].books
            b.add(cat, amt)
            s.companies[i].books = b
        }
        if let l = label { s.companies[i].addTransaction(week: s.week, amount: -amt, label: l) }
        return s.cash >= 0
    }

    static let categoryNames: [String: String] = ["rev": "Sales", "cogs": "Supplier purchases", "wages": "Payroll", "rent": "Rent", "mkt": "Marketing", "ins": "Insurance",
                                                   "oth": "Running costs", "int": "Interest", "fine": "Fines", "acc": "Accounting fees", "tax": "Tax", "loss": "Losses"]
    static func defaultLabel(_ category: String?, income: Bool) -> String { category.flatMap { categoryNames[$0] } ?? (income ? "Receipt" : "Payment") }

    public static func companyReceives(_ s: inout GameState, companyID: Int, amount: Double, category: String?, label: String?, bookInPnL: Bool = true) {
        guard let i = s.companyIndex(companyID) else { return }
        let amt = jsRound(amount)
        if Ledger.observer != nil { Ledger.cause = "gets:\(category ?? "-"):\(label ?? "")" }
        AccountingLedger.note(category: category, label: label ?? defaultLabel(category, income: true))
        Ledger.moveRaw(&s, .company(companyID), amt)
        if let cat = category, bookInPnL {
            var b = s.companies[i].books
            b.add(cat, amt)
            s.companies[i].books = b
        }
        if let l = label, bookInPnL { s.companies[i].addTransaction(week: s.week, amount: amt, label: l) }
    }

    public static func book(_ s: inout GameState, companyID: Int, category: String, amount: Double) {
        guard let i = s.companyIndex(companyID) else { return }
        var b = s.companies[i].books
        b.add(category, amount)
        s.companies[i].books = b
    }

    public static func ownerReceivesSale(_ s: inout GameState, from co: Company, amount: Double, gain: Double, label: String) {
        playerReceives(&s, amount, label: label, companyID: co.id)
        s.tax.gains += max(0, gain)
    }

    public static func playerPays(_ s: inout GameState, _ amount: Double, label: String, companyID: Int = 0) {
        Ledger.move(&s, .me, -jsRound(amount), why: label, companyID: companyID)
    }
    public static func playerReceives(_ s: inout GameState, _ amount: Double, label: String, companyID: Int = 0) {
        Ledger.move(&s, .me, jsRound(amount), why: label, companyID: companyID)
    }

    public static func liquid(_ s: GameState) -> Double { s.cash }

    public static func recordInvestment(_ s: inout GameState, companyID: Int, amount: Double) {
        guard let i = s.companyIndex(companyID) else { return }
        s.companies[i].ownerNetFlow += amount
        s.companies[i].injectedCapital += amount
    }

    public enum DividendResult: Equatable, Sendable { case ok, notEnoughCash }

    public static func payDividend(_ s: inout GameState, companyID: Int, amount: Double) -> DividendResult {
        guard let i = s.companyIndex(companyID) else { return .notEnoughCash }
        let co = s.companies[i]
        let outside = jsRound(amount * (1 - co.ownership / 100))
        if outside <= 0 { return .ok }
        if s.cash - outside < 0 { return .notEnoughCash }
        AccountingLedger.note(category: "owner", label: "Dividend to other shareholders")
        Ledger.moveRaw(&s, .company(companyID), -outside)
        s.companies[i].addTransaction(week: s.week, amount: -outside, label: "Dividend to other shareholders")
        return .ok
    }

    @discardableResult
    static func companyPaysLoanInstalment(_ s: inout GameState, companyID: Int, interest: Double, principal: Double, loanName: String, loanID: Int = 0, context: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        AccountingLedger.note(category: "loan", label: "Loan payment: \(loanName)", ref: loanID == 0 ? "" : "loan:\(loanID)")
        Ledger.moveRaw(&s, .company(companyID), -jsRound(interest + principal))
        var b = s.companies[i].books
        b.add("int", interest)
        s.companies[i].books = b
        s.companies[i].addTransaction(week: s.week, amount: -(interest + principal), label: "Loan payment: \(loanName)")
        return s.cash >= -s.overdraftLimit
    }

    @discardableResult
    static func playerPaysLoanInstalment(_ s: inout GameState, interest: Double, principal: Double, loanName: String) -> Bool {
        let total = interest + principal
        Ledger.move(&s, .me, -jsRound(total), why: "Loan payment: \(loanName)")
        s.stats.interestPaid += interest
        if s.cash < -s.overdraftLimit {
            s.credit = clamp(s.credit - 4, 0, 100)
            s.note("You could not cover a loan payment in full.", tone: "bad")
            return false
        }
        return true
    }
}
