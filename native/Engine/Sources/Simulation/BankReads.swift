import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments

public enum BankAccountID: Hashable, Sendable, Identifiable {
    case personal, investments, company(Int)
    public var id: String {
        switch self { case .personal: return "personal"; case .investments: return "investments"; case .company(let n): return "company\(n)" }
    }
    public var companyID: Int? { if case .company(let n) = self { return n }; return nil }
}

public struct BankAccountRow: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case personal, investments, company }
    public var id: BankAccountID
    public var kind: Kind
    public var name: String
    public var detail: String
    public var companyID: Int?
    public var balance: Double
    public var loanCount: Int
    public var hasAlert: Bool
    public var alertNote: String?
}

public struct BankAccounts: Equatable, Sendable {
    public var rows: [BankAccountRow]
    public var total: Double
    public var dueWithin30Days: Double
    public var isCovered: Bool
    public var alertCount: Int
}

public struct BankLoan: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var kind: String
    public var balance: Double
    public var originalAmount: Double
    public var monthlyPayment: Double
    public var yearlyRate: Double
    public var monthsLeft: Int?
    public var isGuaranteed: Bool
}

public struct BankTransaction: Identifiable, Equatable, Sendable {
    public var id: String
    public var week: Int
    public var day: Int?
    public var dateText: String
    public var amount: Double
    public var label: String
    public var category: String
}

public struct BankStatementEntry: Identifiable, Equatable, Sendable {
    public var id: String { kind.rawValue }
    public var kind: ReportKind
    public var count: Int
    public var latestReportID: Int?
    public var latestTitle: String?
}

public struct BankStatement: Equatable, Sendable {
    public var kind: ReportKind
    public var reportID: Int
    public var title: String
    public var range: String
    public var opening: Double
    public var closing: Double
    public var lines: [BankTransaction]
    public var moneyIn: Double
    public var moneyOut: Double
}

public struct BankAccountDetail: Equatable, Sendable {
    public var id: BankAccountID
    public var name: String
    public var detail: String
    public var balance: Double
    public var available: Double
    public var overdraftLimit: Double
    public var overdraftUsed: Double
    public var overdraftRate: Double?
    public var monthChange: Double?
    public var alert: PayrollAlert?
    public var upcoming: [Obligation]
    public var recent: [BankTransaction]
    public var deposits: [DepositInfo]
    public var loans: [BankLoan]
    public var statements: [BankStatementEntry]
}

public extension GameEngine {

    func bankAccounts() -> BankAccounts {
        let s = state
        let alerts = Dictionary(payrollAlerts().map { ($0.companyID, $0) }, uniquingKeysWith: { (a, _) in a })
        var rows: [BankAccountRow] = []
        rows.append(BankAccountRow(id: .personal, kind: .personal, name: "Your account", detail: "", companyID: nil, balance: s.cash,
                                   loanCount: loans(for: .personal).count, hasAlert: false, alertNote: nil))
        rows.append(BankAccountRow(id: .investments, kind: .investments, name: "Investments", detail: "Shares · crypto · funds", companyID: nil,
                                   balance: investmentsValue, loanCount: 0, hasAlert: false, alertNote: nil))
        for co in s.liveCompanies {
            let a = alerts[co.id]
            rows.append(BankAccountRow(id: .company(co.id), kind: .company, name: co.name, detail: "\(tradeName(co)) · \(cityName(co))", companyID: co.id, balance: co.cash,
                                       loanCount: loans(for: .company(co.id)).count, hasAlert: a != nil, alertNote: a.map { alertNote($0, co) }))
        }
        let fo = financeOverview()
        return BankAccounts(rows: rows, total: rows.reduce(0) { $0 + $1.balance }, dueWithin30Days: fo.dueWithin30Days, isCovered: fo.shortfall == 0,
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
            return BankAccountDetail(id: id, name: "Your account", detail: s.player.name, balance: s.cash, available: max(0, s.cash + s.overdraftLimit),
                                     overdraftLimit: s.overdraftLimit, overdraftUsed: max(0, -s.cash),
                                     overdraftRate: Banking.overdraftRate(state: s, country: home, home: home, personal: true), monthChange: month, alert: nil,
                                     upcoming: upcoming, recent: bankTransactions(id, limit: 10),
                                     deposits: deposits, loans: loans(for: id), statements: statementEntries())
        case .investments:
            return BankAccountDetail(id: id, name: "Investments", detail: "Shares · crypto · funds", balance: investmentsValue, available: investmentsValue,
                                     overdraftLimit: 0, overdraftUsed: 0, overdraftRate: nil, monthChange: nil, alert: nil, upcoming: [],
                                     recent: bankTransactions(id, limit: 10), deposits: [], loans: [], statements: [])
        case .company(let cid):
            guard let co = s.company(cid), co.status.isLive else { return nil }
            let room = context.overdraftRoom(co, s)
            let thisMonth = GameCalendar.monthIndex(week: s.week)
            let before = co.monthlyHistory.last.flatMap { $0.monthIndex < thisMonth ? $0.cash : nil }
            return BankAccountDetail(id: id, name: co.name, detail: "Company account · \(tradeName(co)) · \(cityName(co))", balance: co.cash, available: max(0, co.cash + room),
                                     overdraftLimit: room, overdraftUsed: max(0, -co.cash),
                                     overdraftRate: Banking.overdraftRate(state: s, country: context.country(of: co, s), home: home),
                                     monthChange: before.map { co.cash - $0 }, alert: payrollAlerts().first { $0.companyID == cid },
                                     upcoming: financeOverview(companyID: cid).upcoming, recent: bankTransactions(id, limit: 10),
                                     deposits: [], loans: loans(for: id), statements: statementEntries())
        }
    }

    func bankTransactions(_ id: BankAccountID, limit: Int = 40) -> [BankTransaction] {
        switch id {
        case .personal:
            return state.statement.enumerated().prefix(limit).map { transaction($0.element, index: $0.offset) }
        case .investments:
            let prefixes = ["Bought ", "Sold ", "Dividend ", "Fixed deposit", "Deposit matured"]
            return state.statement.enumerated().filter { l in prefixes.contains { l.element.label.hasPrefix($0) } }.prefix(limit).map { transaction($0.element, index: $0.offset) }
        case .company(let cid):
            return companyMovements(companyID: cid).prefix(limit).map {
                BankTransaction(id: $0.id, week: $0.week, day: nil, dateText: GameCalendar.dateString(week: $0.week), amount: $0.amount, label: $0.label, category: $0.kind.rawValue)
            }
        }
    }

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

    private func loans(for id: BankAccountID) -> [BankLoan] {
        let owner = id.companyID ?? 0
        guard id == .personal || id.companyID != nil else { return [] }
        return state.loans.filter { $0.companyID == owner && $0.balance > 0 }.map { l in
            let p = loanPayoff(loanID: l.id)
            let inst = Banking.instalment(of: l, state: state, context: context)
            return BankLoan(id: l.id, name: l.name, kind: l.kind, balance: l.balance, originalAmount: l.originalAmount, monthlyPayment: l.kind == "start" ? l.monthlyPayment : inst.payment,
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
