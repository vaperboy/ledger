import Foundation
import GameCore

/// Who holds cash: the player's private account or one company.
public enum CashHolder: Equatable, Sendable {
    case me
    case company(Int)

    var flowKey: String {
        switch self {
        case .me: return "me"
        case .company(let id): return "co\(id)"
        }
    }
}

/// The one place where cash balances change. Original: `engine/money/ledger.js`.
///
/// Every movement of money goes through `move` (or `set`). Each holder keeps a running total of everything
/// booked (`cashFlow`), so a test can prove that cash always equals what was booked: nothing appears or
/// disappears. The player's private account also keeps a statement (newest first): no money moves without a line.
public enum Ledger {
    public static let statementLimit = 600

    /// Test hook: called for every balance change (used by the balance tests to tally cash by cause). Nil in the app.
    nonisolated(unsafe) public static var observer: ((CashHolder, Double) -> Void)?
    nonisolated(unsafe) public static var cause: String?

    /// The balance moves; no statement line (used by the weekly staging, which writes its own lines).
    public static func moveRaw(_ s: inout GameState, _ holder: CashHolder, _ amount: Double) {
        if let o = observer { o(holder, amount); cause = nil }
        switch holder {
        case .me: s.cash += amount
        case .company(let id):
            if let i = s.companyIndex(id) { s.companies[i].cash += amount }
        }
        s.cashFlow[holder.flowKey, default: 0] += amount
    }

    /// Move money. `why` is the line on the player's statement; `companyID` is the company it concerns.
    public static func move(_ s: inout GameState, _ holder: CashHolder, _ amount: Double, why: String? = nil, companyID: Int = 0) {
        moveRaw(&s, holder, amount)
        guard holder == .me, amount != 0 else { return }
        ReportCounters.recordPersonal(&s, label: why, amount: amount)
        // While a week is being worked out, the player's lines wait and later land whole on one day of the week.
        if s.transient.stagedPlayerLines != nil {
            s.transient.stagedPlayerLines?.append(StatementLine(week: s.week, day: s.day, amount: amount, label: why ?? "Other", companyID: companyID, balanceAfter: 0))
        } else {
            addStatementLine(&s, amount: amount, label: why ?? "Other", companyID: companyID)
        }
    }

    public static func addStatementLine(_ s: inout GameState, amount: Double, label: String, companyID: Int) {
        let line = StatementLine(week: s.week, day: s.day, amount: jsRound(amount), label: label, companyID: companyID, balanceAfter: jsRound(s.cash))
        s.statement.insert(line, at: 0)
        if s.statement.count > statementLimit { s.statement.removeLast(s.statement.count - statementLimit) }
    }

    /// Set a balance directly (used when a company is wound up). The difference is booked.
    public static func set(_ s: inout GameState, _ holder: CashHolder, to value: Double) {
        switch holder {
        case .me:
            let d = value - s.cash
            s.cash = value
            s.cashFlow["me", default: 0] += d
        case .company(let id):
            guard let i = s.companyIndex(id) else { return }
            let d = value - s.companies[i].cash
            s.companies[i].cash = value
            s.cashFlow[holder.flowKey, default: 0] += d
        }
    }

    /// Differences between cash and what was booked, per holder (empty = consistent). Original: `ledgerGaps`.
    /// Money still held back for a company that is sold or gone is a gap too: nobody can ever be paid it.
    public static func gaps(_ s: GameState) -> [(holder: String, difference: Double)] {
        var out: [(String, Double)] = []
        for id in (s.rest["pend"]?["co"].array ?? []).map({ $0[0].int }).sorted() {
            let left = HeldMoney.remaining(s, companyID: id)
            let live = s.company(id)?.status.isLive ?? false
            if !live && abs(left) > 1 { out.append(("held week money of \(s.company(id)?.name ?? "company \(id)")", left)) }
        }
        let me = s.cash - s.openingCash - (s.cashFlow["me"] ?? 0)
        if abs(me) > 1 { out.append(("me", me)) }
        for c in s.companies {
            let g = c.cash - (s.cashFlow["co\(c.id)"] ?? 0)
            if abs(g) > 1 { out.append((c.name, g)) }
        }
        return out
    }
}
