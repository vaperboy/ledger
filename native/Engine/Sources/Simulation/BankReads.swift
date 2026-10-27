import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

// The Bank app's read model (new look, Oct 2026): pick an account, then manage it. Only reshapes what the engine already keeps:
// `financeOverview` (what is coming), `companyMovements` and the player's statement (what went through), `Banking` (rates), the loans in the
// state, `reports` (statements) and `payrollAlerts`. Nothing here changes the game. Loans are never an account of their own: a loan belongs
// to the account it was taken for (the player's, or a company's) and is listed inside that account.

/// Which account: the player's own, the investments, or a company's.
public enum BankAccountID: Hashable, Sendable, Identifiable {
    case personal, investments, company(Int)
    public var id: String {
        switch self { case .personal: return "personal"; case .investments: return "investments"; case .company(let n): return "company\(n)" }
    }
    public var companyID: Int? { if case .company(let n) = self { return n }; return nil }
}

/// One row of the "pick an account" screen.
public struct BankAccountRow: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case personal, investments, company }
    public var id: BankAccountID
    public var kind: Kind
    public var name: String
    /// Companies: the trade and the city ("Café · London"); empty for the other accounts.
    public var detail: String
    public var companyID: Int?
    /// The balance of the account (the current account; for investments the value of what is held).
    public var balance: Double
    /// Personal account: the savings balance and the rate it pays (nil for the others).
    public var savings: Double?
    public var savingsRate: Double?
    public var loanCount: Int
    /// A payroll waits on the owner at this account (the red bubble). `alertNote` says which.
    public var hasAlert: Bool
    public var alertNote: String?
}

/// The "pick an account" screen.
public struct BankAccounts: Equatable, Sendable {
    public var rows: [BankAccountRow]
    /// Every balance added up (current accounts, savings, investments, company accounts).
    public var total: Double
    /// What falls due in the next 30 days across everything, and whether the cash on hand covers it.
    public var dueWithin30Days: Double
    public var isCovered: Bool
    /// Accounts with an alert: the number on the Bank app's icon.
    public var alertCount: Int
}

public struct BankLoan: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    /// "start", "biz", "cons", "mort" or "lomb".
    public var kind: String
    public var balance: Double
    public var originalAmount: Double
    public var monthlyPayment: Double
    public var yearlyRate: Double
    /// Instalments left at today's payment (nil when the payment does not cover the interest).
    public var monthsLeft: Int?
    public var isGuaranteed: Bool
}

public struct BankTransaction: Identifiable, Equatable, Sendable {
    public var id: String
    public var week: Int
    /// The day of the week, when the account keeps it (the player's own statement does; a company's movements are kept by week).
    public var day: Int?
    public var dateText: String
    public var amount: Double
    public var label: String
    /// payroll, bills, tax, owner or other.
    public var category: String
}

/// A statement the account can show: the newest report of that length, and how many are kept.
public struct BankStatementEntry: Identifiable, Equatable, Sendable {
    public var id: String { kind.rawValue }
    public var kind: ReportKind
    public var count: Int
    public var latestReportID: Int?
    public var latestTitle: String?
}

/// One statement of one account: the period, the balance at each end and what went through in between.
public struct BankStatement: Equatable, Sendable {
    public var kind: ReportKind
    public var reportID: Int
    public var title: String
    public var range: String
    public var opening: Double
    public var closing: Double
    /// Movements the account still keeps for the period, newest first (a company keeps its latest 40, the player 600).
    public var lines: [BankTransaction]
    public var moneyIn: Double
    public var moneyOut: Double
}

/// "Manage one account".
public struct BankAccountDetail: Equatable, Sendable {
    public var id: BankAccountID
    public var name: String
    public var detail: String
    public var balance: Double
    /// What can be spent now: the balance plus the room left on the overdraft (never below 0).
    public var available: Double
    public var overdraftLimit: Double
    public var overdraftUsed: Double
    /// Yearly interest charged on an overdrawn account (nil for the investments).
    public var overdraftRate: Double?
    /// How much the account moved so far this month (nil when the books cannot say yet).
    public var monthChange: Double?
    public var alert: PayrollAlert?
    /// What is coming: payroll, rent and supplier bills, tax, loan instalments, soonest first.
    public var upcoming: [Obligation]
    public var recent: [BankTransaction]
    /// Personal account only: the savings account and the fixed deposits.
    public var savings: Double?
    public var savingsRate: Double?
    public var deposits: [DepositInfo]
    /// The loans taken for this account (none for the investments).
    public var loans: [BankLoan]
    public var statements: [BankStatementEntry]
}

public extension GameEngine {
    // MARK: Accounts

    func bankAccounts() -> BankAccounts {
        let s = state
        let alerts = Dictionary(uniqueKeysWithValues: payrollAlerts().map { ($0.companyID, $0) })
        var rows: [BankAccountRow] = []
        rows.append(BankAccountRow(id: .personal, kind: .personal, name: "Personal account", detail: "", companyID: nil, balance: s.cash, savings: s.savings,
                                   savingsRate: PersonalFinance.savingsRate(s), loanCount: loans(for: .personal).count, hasAlert: false, alertNote: nil))
        rows.append(BankAccountRow(id: .investments, kind: .investments, name: "Investments", detail: "Shares · crypto · funds", companyID: nil,
                                   balance: investmentsValue, savings: nil, savingsRate: nil, loanCount: 0, hasAlert: false, alertNote: nil))
        for co in s.liveCompanies {
            let a = alerts[co.id]
            rows.append(BankAccountRow(id: .company(co.id), kind: .company, name: co.name, detail: "\(tradeName(co)) · \(cityName(co))", companyID: co.id, balance: co.cash,
                                       savings: nil, savingsRate: nil, loanCount: loans(for: .company(co.id)).count, hasAlert: a != nil, alertNote: a.map { alertNote($0, co) }))
        }
        let fo = financeOverview()
        return BankAccounts(rows: rows, total: rows.reduce(0) { $0 + $1.balance + ($1.savings ?? 0) }, dueWithin30Days: fo.dueWithin30Days, isCovered: fo.shortfall == 0,
                            alertCount: rows.filter(\.hasAlert).count)
    }

    func bankAccount(_ id: BankAccountID) -> BankAccountDetail? {
        let s = state
        let home = context.homeCountry(s)
        switch id {
        case .personal:
            let upcoming = financeOverview().upcoming.filter { $0.companyID == 0 }
            let thisMonth = GameCalendar.monthIndex(week: s.week)
            let month = s.statement.filter { GameCalendar.monthIndex(week: $0.week) == thisMonth }.reduce(0) { $0 + $1.amount }
            return BankAccountDetail(id: id, name: "Personal account", detail: s.player.name, balance: s.cash, available: max(0, s.cash + s.overdraftLimit),
                                     overdraftLimit: s.overdraftLimit, overdraftUsed: max(0, -s.cash),
                                     overdraftRate: Banking.overdraftRate(state: s, country: home, home: home, personal: true), monthChange: month, alert: nil,
                                     upcoming: upcoming, recent: bankTransactions(id, limit: 10), savings: s.savings, savingsRate: PersonalFinance.savingsRate(s),
                                     deposits: deposits, loans: loans(for: id), statements: statementEntries())
        case .investments:
            return BankAccountDetail(id: id, name: "Investments", detail: "Shares · crypto · funds", balance: investmentsValue, available: investmentsValue,
                                     overdraftLimit: 0, overdraftUsed: 0, overdraftRate: nil, monthChange: nil, alert: nil, upcoming: [],
                                     recent: bankTransactions(id, limit: 10), savings: nil, savingsRate: nil, deposits: [], loans: [], statements: [])
        case .company(let cid):
            guard let co = s.company(cid), co.status.isLive else { return nil }
            let room = context.overdraftRoom(co, s)
            let thisMonth = GameCalendar.monthIndex(week: s.week)
            let before = co.monthlyHistory.last.flatMap { $0.monthIndex < thisMonth ? $0.cash : nil }
            return BankAccountDetail(id: id, name: co.name, detail: "Company account · \(tradeName(co)) · \(cityName(co))", balance: co.cash, available: max(0, co.cash + room),
                                     overdraftLimit: room, overdraftUsed: max(0, -co.cash),
                                     overdraftRate: Banking.overdraftRate(state: s, country: context.country(of: co, s), home: home),
                                     monthChange: before.map { co.cash - $0 }, alert: payrollAlerts().first { $0.companyID == cid },
                                     upcoming: financeOverview(companyID: cid).upcoming, recent: bankTransactions(id, limit: 10), savings: nil, savingsRate: nil,
                                     deposits: [], loans: loans(for: id), statements: statementEntries())
        }
    }

    // MARK: Transactions and statements

    /// What went through the account, newest first.
    func bankTransactions(_ id: BankAccountID, limit: Int = 40) -> [BankTransaction] {
        switch id {
        case .personal:
            return state.statement.enumerated().prefix(limit).map { transaction($0.element, index: $0.offset) }
        case .investments:
            let prefixes = ["Bought ", "Sold ", "Dividend ", "Fixed deposit", "Deposit matured", "To savings", "From savings"]
            return state.statement.enumerated().filter { l in prefixes.contains { l.element.label.hasPrefix($0) } }.prefix(limit).map { transaction($0.element, index: $0.offset) }
        case .company(let cid):
            return companyMovements(companyID: cid).prefix(limit).map {
                BankTransaction(id: $0.id, week: $0.week, day: nil, dateText: GameCalendar.dateString(week: $0.week), amount: $0.amount, label: $0.label, category: $0.kind.rawValue)
            }
        }
    }

    /// One statement of the account: the newest of that length, or the one with `reportID`. Nil when none has closed yet.
    func bankStatement(_ id: BankAccountID, kind: ReportKind, reportID: Int? = nil) -> BankStatement? {
        guard id != .investments else { return nil }
        let all = reports(kind)
        guard let r = reportID.map({ rid in all.first { $0.id == rid } }) ?? all.last else { return nil }
        let opening: Double, closing: Double
        var lines: [BankTransaction]
        switch id {
        case .company(let cid):
            guard let c = r.company(cid) else { return nil }
            opening = c.cashStart; closing = c.cashEnd
            lines = companyMovements(companyID: cid, weeks: r.firstWeek...r.lastWeek).map {
                BankTransaction(id: $0.id, week: $0.week, day: nil, dateText: GameCalendar.dateString(week: $0.week), amount: $0.amount, label: $0.label, category: $0.kind.rawValue)
            }
        default:
            opening = r.group.accountStart; closing = r.group.accountEnd
            lines = state.statement.enumerated().filter { (r.firstWeek...r.lastWeek).contains($0.element.week) }.map { transaction($0.element, index: $0.offset) }
        }
        return BankStatement(kind: kind, reportID: r.id, title: r.title, range: r.range, opening: opening, closing: closing, lines: lines,
                             moneyIn: lines.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }, moneyOut: -lines.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount })
    }

    // MARK: Pieces

    private func statementEntries() -> [BankStatementEntry] {
        ReportKind.allCases.map { k in
            let r = reports(k)
            return BankStatementEntry(kind: k, count: r.count, latestReportID: r.last?.id, latestTitle: r.last?.title)
        }
    }

    private func transaction(_ l: StatementLine, index: Int) -> BankTransaction {
        BankTransaction(id: "me-\(index)", week: l.week, day: l.day, dateText: GameCalendar.dateString(week: l.week, dayOffset: l.day), amount: l.amount, label: l.label,
                        category: Self.movementKind(l.label).rawValue)
    }

    /// The loans taken for an account: the player's own on the personal account, a company's on its account.
    private func loans(for id: BankAccountID) -> [BankLoan] {
        let owner = id.companyID ?? 0
        guard id == .personal || id.companyID != nil else { return [] }
        return state.loans.filter { $0.companyID == owner && $0.balance > 0 }.map { l in
            let p = loanPayoff(loanID: l.id)
            return BankLoan(id: l.id, name: l.name, kind: l.kind, balance: l.balance, originalAmount: l.originalAmount, monthlyPayment: l.monthlyPayment,
                            yearlyRate: p?.yearlyRate ?? Banking.rate(of: l, state: state), monthsLeft: p?.monthsLeft, isGuaranteed: l.isGuaranteed)
        }
    }

    private var investmentsValue: Double {
        [Brokerage.Kind.stock, .crypto, .fund].reduce(0) { sum, k in sum + quotes(k).reduce(0) { $0 + $1.value } }
    }

    private func alertNote(_ a: PayrollAlert, _ co: Company) -> String {
        a.isLate ? "Payroll \(currency(for: co).short(a.amount)) is late: \(a.reason)"
                 : "Payroll \(currency(for: co).short(a.amount)) on \(a.dateText) needs you. No manager or accountant approves it."
    }
}
