import Foundation
import GameCore

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

public enum Ledger {
    public static let statementLimit = 600

    nonisolated(unsafe) package static var observer: ((CashHolder, Double) -> Void)?
    nonisolated(unsafe) package static var cause: String?

    package static func moveRaw(_ s: inout GameState, _ holder: CashHolder, _ amount: Double) {
        if let o = observer { o(holder, amount); cause = nil }
        switch holder {
        case .me: s.cash += amount; AccountingLedger.pending = nil
        case .company(let id):
            if let i = s.companyIndex(id) { AccountingLedger.record(&s, companyIndex: i, amount: amount); s.cash += amount }
        }
        s.cashFlow[holder.flowKey, default: 0] += amount
    }

    package static func move(_ s: inout GameState, _ holder: CashHolder, _ amount: Double, why: String? = nil, companyID: Int = 0) {
        moveRaw(&s, holder, amount)
        guard holder == .me, amount != 0 else { return }
        ReportCounters.recordPersonal(&s, label: why, amount: amount)
        if s.transient.stagedPlayerLines != nil {
            s.transient.stagedPlayerLines?.append(StatementLine(week: s.week, day: s.day, amount: amount, label: why ?? "Other", companyID: companyID, balanceAfter: 0))
        } else {
            addStatementLine(&s, amount: amount, label: why ?? "Other", companyID: companyID)
        }
    }

    package static func addStatementLine(_ s: inout GameState, amount: Double, label: String, companyID: Int) {
        let line = StatementLine(week: s.week, day: s.day, amount: jsRound(amount), label: label, companyID: companyID, balanceAfter: jsRound(s.cash))
        s.statement.insert(line, at: 0)
        if s.statement.count > statementLimit { s.statement.removeLast(s.statement.count - statementLimit) }
    }

    package static func set(_ s: inout GameState, to value: Double) {
        let d = value - s.cash
        s.cash = value
        s.cashFlow["me", default: 0] += d
    }

    public static func gaps(_ s: GameState) -> [(holder: String, difference: Double)] {
        var out: [(String, Double)] = []
        for id in (s.rest["pend"]?["co"].array ?? []).map({ $0[0].int }).sorted() {
            let left = HeldMoney.remaining(s, companyID: id)
            let live = s.company(id)?.status.isLive ?? false
            if !live && abs(left) > 1 { out.append(("held week money of \(s.company(id)?.name ?? "company \(id)")", left)) }
        }
        let gap = s.cash - s.openingCash - s.cashFlow.values.reduce(0, +)
        if abs(gap) > 1 { out.append(("me", gap)) }
        return out
    }
}
