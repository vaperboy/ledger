import Foundation
import Countries

/// The plain-language summary of a report: three to five sentences, every number taken from the report itself.
/// Nothing is invented: if a comparison or a company is not in the numbers, the sentence is left out.
public enum ReportSummary {
    public static func sentences(_ r: PeriodReport, currency cur: Currency) -> [String] {
        func amount(_ v: Double) -> String { cur.short(abs(v)).replacingOccurrences(of: "\u{00A0}", with: " ") }
        func pct(_ x: Double) -> String { abs(x) < 0.1 ? String(format: "%.1f%%", abs(x) * 100) : "\(Int((abs(x) * 100).rounded()))%" }
        let noun = r.kind.noun
        let g = r.group
        let net = g.pnl.netProfit
        let prev = r.previous
        var out: [String] = []

        // 1. Profit, against the period before, with the company that moved it most
        if g.pnl.isEmpty {
            out.append("No company earned or spent anything this \(noun).")
        } else {
            var s: String
            if let p = prev, abs(p.pnl.netProfit) >= 1 {
                let before = p.pnl.netProfit
                if net >= 0 && before > 0 {
                    s = "Profit \(net >= before ? "rose" : "fell") \(pct((net - before) / before)) to \(amount(net))"
                } else if net >= 0 {
                    s = "Profit was \(amount(net)), against a loss of \(amount(before)) last \(noun)"
                } else if before < 0 {
                    s = "The group lost \(amount(net)), \(abs(net) < abs(before) ? "less" : "more") than the \(amount(before)) lost last \(noun)"
                } else {
                    s = "The group lost \(amount(net)), after a profit of \(amount(before)) last \(noun)"
                }
                if let rs = ReportMath.share(g.pnl.revenue, p.pnl.revenue) {
                    if abs(rs) < 0.01 { s += " on flat revenue" }
                    else { s += " on \(rs > 0 ? "higher" : "lower") revenue (\(rs > 0 ? "+" : "−")\(pct(rs)))" }
                }
                if let lead = leader(r, prev: p, direction: net - before) { s += ", mostly at \(lead)" }
            } else {
                s = net >= 0 ? "Profit was \(amount(net))" : "The group lost \(amount(net))"
                if g.pnl.revenue > 0 { s += " on revenue of \(amount(g.pnl.revenue))" }
            }
            out.append(s + ".")
        }

        // 2. What the costs took
        let rev = g.pnl.revenue
        let costs = g.pnl.costLines.filter { $0.amount > 0 }.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.id < $1.id }
        if rev > 0, let top = costs.first {
            var s = "\(top.label) took \(Int((top.amount / rev * 100).rounded()))% of revenue"
            if let p = prev, p.pnl.revenue > 0, let was = p.pnl.costLines.first(where: { $0.id == top.id }) {
                let before = was.amount / p.pnl.revenue, now = top.amount / rev
                if abs(now - before) >= 0.02 { s += " (\(Int((before * 100).rounded()))% last \(noun))" }
            }
            if costs.count > 1 { s += ", then \(costs[1].label.lowercased()) at \(Int((costs[1].amount / rev * 100).rounded()))%" }
            out.append(s + ".")
        } else if rev <= 0, g.pnl.costs > 0 {
            out.append("Costs were \(amount(g.pnl.costs)) with no revenue yet.")
        }

        // 3. Best and weakest company
        if let b = r.best, let w = r.worst, b.id != w.id {
            out.append("\(b.name) did best (\(signed(b.pnl.netProfit, amount))) and \(w.name) did worst (\(signed(w.pnl.netProfit, amount))).")
        }

        // 4. Net worth
        let change = r.netWorthChange
        if abs(change) < 1 {
            out.append("Your net worth stayed at \(amount(r.netWorthEnd.total)).")
        } else {
            var s = "Your net worth \(change > 0 ? "rose" : "fell") by \(amount(change))"
            if let share = r.netWorthShare, abs(share) >= 0.001 { s += " (\(share > 0 ? "+" : "−")\(pct(share)))" }
            s += " to \(r.netWorthEnd.total < 0 ? "−" : "")\(amount(r.netWorthEnd.total))"
            if let driver = driver(r) { s += ", mostly from \(driver)" }
            out.append(s + ".")
        }

        // 5. Year: tax and dividends. Otherwise cash and what happened.
        if r.kind == .year, g.taxPaid > 0 || g.dividendsReceived > 0 || g.personalTax > 0 {
            var parts: [String] = []
            if g.taxPaid > 0 { parts.append("paid \(amount(g.taxPaid)) in tax") }
            if g.dividendsReceived > 0 { parts.append("received \(amount(g.dividendsReceived)) in dividends") }
            if g.personalTax > 0 { parts.append("settled \(amount(g.personalTax)) of personal income tax") }
            out.append("Over the year you " + joined(parts) + ".")
        } else {
            let dc = g.cashEnd - g.cashStart
            var s = "Cash in your accounts and companies \(dc >= 0 ? "rose" : "fell") by \(amount(dc)) to \(g.cashEnd < 0 ? "−" : "")\(amount(g.cashEnd))"
            var bits: [String] = []
            if g.decisionsAnswered > 0 { bits.append("\(g.decisionsAnswered) decision\(g.decisionsAnswered == 1 ? "" : "s") answered") }
            if g.breakdowns > 0 { bits.append("\(g.breakdowns) breakdown\(g.breakdowns == 1 ? "" : "s")") }
            if g.complaints > 0 { bits.append("\(g.complaints) complaint\(g.complaints == 1 ? "" : "s")") }
            if g.fineCount > 0 { bits.append("\(g.fineCount) fine\(g.fineCount == 1 ? "" : "s")") }
            if !bits.isEmpty { s += "; " + joined(bits) }
            out.append(s + ".")
        }
        return Array(out.prefix(5))
    }

    private static func signed(_ v: Double, _ f: (Double) -> String) -> String { (v < 0 ? "−" : "+") + f(v) }

    private static func joined(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return parts[0] + " and " + parts[1]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    /// The company whose profit moved most in the direction the group moved, when it explains a good part of the change.
    private static func leader(_ r: PeriodReport, prev: ReportPrevious, direction: Double) -> String? {
        guard direction != 0 else { return nil }
        var best: (name: String, move: Double)?
        for c in r.companies {
            let before = prev.companies.first { $0.id == c.id }?.pnl.netProfit ?? 0
            let move = c.pnl.netProfit - before
            guard move * direction > 0 else { continue }
            if best == nil || abs(move) > abs(best!.move) { best = (c.name, move) }
        }
        guard let b = best, abs(b.move) >= abs(direction) * 0.4, r.companies.count > 1 else { return nil }
        return b.name
    }

    /// The part of net worth that changed most, as a phrase.
    private static func driver(_ r: PeriodReport) -> String? {
        let d = r.netWorthEnd - r.netWorthStart
        let parts: [(String, Double)] = [("cash and savings", d.cash), ("investments", d.investments), ("the value of your companies", d.companies),
                                         ("luxury items", d.luxury), ("debt", -d.debt)]
        guard let top = parts.max(by: { abs($0.1) < abs($1.1) }), abs(top.1) >= 1 else { return nil }
        if abs(top.1) < abs(d.total) * 0.3 { return nil }
        if top.0 == "debt" { return top.1 > 0 ? "lower debt" : "higher debt" }
        return top.0
    }
}
