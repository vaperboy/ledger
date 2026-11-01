import Foundation
import GameCore
import Finance

/// Monthly results of a company: this month so far and the last twelve months, each with income, expenses and the cost lines.
/// Original: `V.month30`, `monthOf` (features/screens/tidier_screens_and_monthly_bills.js).
public enum MonthView {
    public static let costNames: [String: String] = ["cogs": "Materials and goods", "wages": "Wages and payroll", "rent": "Rent and power", "mkt": "Marketing", "ins": "Insurance",
        "acc": "Accounting and payroll service", "dep": "Depreciation", "int": "Loan interest", "oth": "Leasing and other costs", "fine": "Fines", "loss": "Refunds and losses", "tax": "Company tax"]

    public struct Month: Equatable, Sendable {
        public var monthIndex: Int
        public var income: Double
        public var expenses: Double
        public var costs: [(name: String, amount: Double)]
        public var profit: Double { income - expenses }
        public static func == (a: Month, b: Month) -> Bool { a.monthIndex == b.monthIndex && a.income == b.income && a.expenses == b.expenses }
    }
    public struct Summary { public var thisMonth: Month; public var lastMonth: Double?; public var thisYear: Double; public var months: [Month] }

    static func lines(_ b: [String: Double]) -> [(name: String, amount: Double)] {
        costNames.keys.sorted().compactMap { k in (b[k] ?? 0) != 0 ? (costNames[k]!, b[k]!) : nil }
    }

    public static func summary(_ s: GameState, companyID: Int) -> Summary? {
        guard let co = s.company(companyID) else { return nil }
        let bm = co.books.month
        let now = Month(monthIndex: GameCalendar.monthIndex(week: s.week), income: bm["rev"] ?? 0, expenses: Books.expenses(bm), costs: lines(bm))
        let hist = Array(co.monthlyHistory.suffix(12).reversed())
        let months = hist.map { h -> Month in
            let bk = h.value("bk").object.mapValues { $0.double }
            return Month(monthIndex: h.monthIndex, income: h.revenue, expenses: h.revenue - h.profit, costs: lines(bk))
        }
        let year = GameCalendar.monthIndex(week: s.week) / 12
        let ytd = hist.filter { $0.monthIndex / 12 == year }.reduce(0) { $0 + $1.profit } + now.profit
        return Summary(thisMonth: now, lastMonth: hist.first?.profit, thisYear: ytd, months: months)
    }
}
