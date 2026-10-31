import Foundation
import GameCore

/// Weekly, monthly and yearly reports. Native addition (the original game only had a one-screen week report).
///
/// A report is a frozen record of one period, written when the period closes and kept in the save (`rest["reports"]`).
/// Everything in it is a difference between two snapshots of the real books (`Company.books.total`, the cash ledger, net worth),
/// so the figures can be checked against the books: the weekly reports of a company add up to its books since the start.
///
/// All amounts are in the game's accounting unit (the home currency); the app converts for display, as everywhere else.

public enum ReportKind: String, Codable, CaseIterable, Sendable {
    case week, month, year

    /// Key inside `rest["reports"]`.
    var storeKey: String { switch self { case .week: return "w"; case .month: return "m"; case .year: return "y" } }
    /// How many reports of this kind a save keeps.
    public var keep: Int { switch self { case .week: return 26; case .month: return 36; case .year: return 10 } }
    public var noun: String { rawValue }
    public var title: String { switch self { case .week: return "Week"; case .month: return "Month"; case .year: return "Year" } }
}

/// What came in and went out of the books in a period: the profit and loss lines.
public struct ReportPnL: Codable, Equatable, Sendable {
    public var revenue = 0.0
    public var costOfSales = 0.0
    public var wages = 0.0
    public var rent = 0.0
    public var marketing = 0.0
    public var insurance = 0.0
    /// Running costs, fees and accounting (`oth` and `acc` in the books).
    public var other = 0.0
    public var depreciation = 0.0
    public var interest = 0.0
    public var fines = 0.0
    /// Refunds and losses (`loss` in the books).
    public var losses = 0.0
    /// Corporate tax charged for the period (accrued; what was paid in cash is in the group's `taxPaid`).
    public var tax = 0.0

    public init() {}

    /// From the change of a company's `books.total` over the period.
    public init(booksDelta d: [String: Double]) {
        revenue = d["rev"] ?? 0; costOfSales = d["cogs"] ?? 0; wages = d["wages"] ?? 0; rent = d["rent"] ?? 0
        marketing = d["mkt"] ?? 0; insurance = d["ins"] ?? 0; other = (d["oth"] ?? 0) + (d["acc"] ?? 0)
        depreciation = d["dep"] ?? 0; interest = d["int"] ?? 0; fines = d["fine"] ?? 0; losses = d["loss"] ?? 0; tax = d["tax"] ?? 0
    }

    public var costs: Double { costOfSales + wages + rent + marketing + insurance + other + depreciation + interest + fines + losses }
    public var profitBeforeTax: Double { revenue - costs }
    public var netProfit: Double { profitBeforeTax - tax }
    public var isEmpty: Bool { revenue == 0 && costs == 0 && tax == 0 }

    public static func + (a: ReportPnL, b: ReportPnL) -> ReportPnL {
        var r = ReportPnL()
        r.revenue = a.revenue + b.revenue; r.costOfSales = a.costOfSales + b.costOfSales; r.wages = a.wages + b.wages
        r.rent = a.rent + b.rent; r.marketing = a.marketing + b.marketing; r.insurance = a.insurance + b.insurance
        r.other = a.other + b.other; r.depreciation = a.depreciation + b.depreciation; r.interest = a.interest + b.interest
        r.fines = a.fines + b.fines; r.losses = a.losses + b.losses; r.tax = a.tax + b.tax
        return r
    }

    public struct Line: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var amount: Double
    }

    /// The cost lines in the order a statement shows them.
    public var costLines: [Line] {
        [Line(id: "cogs", label: "Cost of sales", amount: costOfSales), Line(id: "wages", label: "Wages", amount: wages),
         Line(id: "rent", label: "Rent and premises", amount: rent), Line(id: "mkt", label: "Marketing", amount: marketing),
         Line(id: "ins", label: "Insurance", amount: insurance), Line(id: "oth", label: "Running costs and fees", amount: other),
         Line(id: "dep", label: "Depreciation", amount: depreciation), Line(id: "int", label: "Interest", amount: interest),
         Line(id: "fine", label: "Fines", amount: fines), Line(id: "loss", label: "Refunds and losses", amount: losses)]
    }
}

/// How big the change is against another period, as an amount and a share. `share` is nil when the earlier figure was too small to compare.
public enum ReportMath {
    public static func share(_ now: Double, _ before: Double) -> Double? {
        guard before.isFinite, now.isFinite, abs(before) >= 1 else { return nil }
        return (now - before) / abs(before)
    }
}

/// A thing that happened, in a line.
public struct ReportEvent: Codable, Equatable, Sendable {
    public var text: String
    /// "good", "bad" or "n".
    public var tone: String
    public var companyID: Int
    public var week: Int
    public init(text: String, tone: String, companyID: Int, week: Int) { self.text = text; self.tone = tone; self.companyID = companyID; self.week = week }
}

/// What the player is worth, in the parts the Home screen shows.
public struct ReportNetWorth: Codable, Equatable, Sendable {
    /// Current account and savings.
    public var cash = 0.0
    /// Shares, crypto, funds and deposits.
    public var investments = 0.0
    /// The player's share of companies.
    public var companies = 0.0
    public var luxury = 0.0
    /// Private loans and tax assessed but not paid (a positive number; it reduces the total).
    public var debt = 0.0
    public var total = 0.0
    public init() {}
    public static func - (a: ReportNetWorth, b: ReportNetWorth) -> ReportNetWorth {
        var r = ReportNetWorth()
        r.cash = a.cash - b.cash; r.investments = a.investments - b.investments; r.companies = a.companies - b.companies
        r.luxury = a.luxury - b.luxury; r.debt = a.debt - b.debt; r.total = a.total - b.total
        return r
    }
}

/// One company in one period.
public struct ReportCompany: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var tradeID: String
    /// "setup", "open", "closed", "sold" or "bust" at the end of the period.
    public var status: String
    public var pnl = ReportPnL()
    public var cashStart = 0.0
    public var cashEnd = 0.0
    /// Money the owner put in, and money taken out (dividends and drawings).
    public var ownerIn = 0.0
    public var ownerOut = 0.0
    /// Principal borrowed and repaid on the company's loans.
    public var loansTaken = 0.0
    public var loansRepaid = 0.0
    /// Customers served (units sold) and the average share of capacity used, over the weeks it traded.
    public var customers = 0.0
    public var capacityUse: Double? = nil
    public var tradingWeeks = 0
    public var reputationStart = 0.0
    public var reputationEnd = 0.0
    public var qualityStart = 0.0
    public var qualityEnd = 0.0
    public var hired = 0
    public var left = 0
    public var staffEnd = 0
    /// The player's share of the company's value.
    public var valueStart = 0.0
    public var valueEnd = 0.0
    public var events: [ReportEvent] = []

    public var cashChange: Double { cashEnd - cashStart }
    /// What is left of the cash change after the owner's money and loans: trading, tax, equipment and everything else.
    public var operatingAndOther: Double { cashChange - ownerIn + ownerOut - loansTaken + loansRepaid }
    public var reputationChange: Double { reputationEnd - reputationStart }
    public var valueChange: Double { valueEnd - valueStart }
    public var margin: Double? { pnl.revenue > 0 ? pnl.netProfit / pnl.revenue : nil }
}

/// A named amount.
public struct ReportFlow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var amount: Double
}

/// The whole group (all companies and the player's own money) in one period.
public struct ReportGroup: Codable, Equatable, Sendable {
    public var pnl = ReportPnL()
    /// The player's current account and savings, and cash in all companies.
    public var accountStart = 0.0
    public var accountEnd = 0.0
    public var savingsStart = 0.0
    public var savingsEnd = 0.0
    public var companyCashStart = 0.0
    public var companyCashEnd = 0.0
    /// Movements on the player's current account, by kind, plus what is left unexplained (`other`). They add up to the account's change.
    public var accountFlows: [ReportFlow] = []
    /// Owner money moved between the player and companies (inside the group), and loan principal.
    public var ownerIn = 0.0
    public var ownerOut = 0.0
    public var loansTaken = 0.0
    public var loansRepaid = 0.0
    /// Cash taxes of the period (corporate, VAT, personal) from the game's tax statistics; dividends received; personal tax paid.
    public var taxPaid = 0.0
    public var dividendsReceived = 0.0
    public var personalTax = 0.0
    public var ownerPay = 0.0
    public var interestPaid = 0.0
    public var wagesPaid = 0.0
    public var customers = 0.0
    public var capacityUse: Double? = nil
    public var reputationStart = 0.0
    public var reputationEnd = 0.0
    public var hired = 0
    public var left = 0
    public var decisionsAnswered = 0
    public var breakdowns = 0
    public var fineCount = 0
    public var complaints = 0
    public var events: [ReportEvent] = []

    public var cashStart: Double { accountStart + companyCashStart }
    public var cashEnd: Double { accountEnd + companyCashEnd }
}

/// The figures of the period before, to compare with.
public struct ReportPrevious: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var pnl = ReportPnL()
    public var netWorthChange = 0.0
    public var customers = 0.0
    public var cashEnd = 0.0
    /// Each company's profit and loss in that period.
    public var companies: [ReportCompanyPnL] = []
}

public struct ReportCompanyPnL: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var pnl = ReportPnL()
    public init(id: Int, pnl: ReportPnL) { self.id = id; self.pnl = pnl }
}

public struct PeriodReport: Codable, Equatable, Sendable, Identifiable {
    public static let formatVersion = 1
    public var v = PeriodReport.formatVersion
    public var kind: ReportKind
    /// The game week the period ended in; unique within a kind.
    public var id: Int
    /// First and last game week of the period (the week counter, 0 = first week).
    public var firstWeek: Int
    public var lastWeek: Int
    /// "Week 12", "Oct 2026", "2026".
    public var title: String
    /// "5 Oct 2026 – 11 Oct 2026".
    public var range: String
    /// The report starts later than a full period (a save from before reports, or a game set up half way).
    public var partial = false
    public var group = ReportGroup()
    public var companies: [ReportCompany] = []
    public var netWorthStart = ReportNetWorth()
    public var netWorthEnd = ReportNetWorth()
    public var previous: ReportPrevious? = nil
    public var bestCompanyID: Int? = nil
    public var worstCompanyID: Int? = nil
    /// Company ids, best net profit first.
    public var ranking: [Int] = []
    /// Three to five sentences, written from the numbers above.
    public var summary: [String] = []
    /// Set on a report cut down to one company (`filtered(to:)`): the company's name. Never stored.
    public var scopeName: String? = nil

    public var netWorthChange: Double { netWorthEnd.total - netWorthStart.total }
    public var netWorthShare: Double? { ReportMath.share(netWorthEnd.total, netWorthStart.total) }
    public func company(_ id: Int) -> ReportCompany? { companies.first { $0.id == id } }
    public var best: ReportCompany? { bestCompanyID.flatMap { company($0) } }
    public var worst: ReportCompany? { worstCompanyID.flatMap { company($0) } }
    /// Anything worth showing: a company traded or paid costs.
    public var hasActivity: Bool { !group.pnl.isEmpty || !companies.isEmpty }

    /// A report limited to one company, for the company's own Finances screen. Group figures are that company's.
    public func filtered(to companyID: Int) -> PeriodReport? {
        guard let c = company(companyID) else { return nil }
        var r = self
        r.scopeName = c.name
        r.companies = [c]
        var g = ReportGroup()
        g.pnl = c.pnl
        g.companyCashStart = c.cashStart; g.companyCashEnd = c.cashEnd
        g.ownerIn = c.ownerIn; g.ownerOut = c.ownerOut; g.loansTaken = c.loansTaken; g.loansRepaid = c.loansRepaid
        g.customers = c.customers; g.capacityUse = c.capacityUse
        g.reputationStart = c.reputationStart; g.reputationEnd = c.reputationEnd
        g.hired = c.hired; g.left = c.left
        g.events = c.events
        g.breakdowns = Reports.count(c.events, ["broke down", "breakdown"])
        g.complaints = Reports.count(c.events, ["complaint"])
        g.fineCount = Reports.count(c.events, [" fine"])
        r.group = g
        var nwS = ReportNetWorth(), nwE = ReportNetWorth()
        nwS.companies = c.valueStart; nwS.total = c.valueStart; nwE.companies = c.valueEnd; nwE.total = c.valueEnd
        r.netWorthStart = nwS; r.netWorthEnd = nwE
        if var p = previous {
            p.pnl = p.companies.first { $0.id == companyID }?.pnl ?? ReportPnL()
            p.companies = p.companies.filter { $0.id == companyID }
            r.previous = p
        }
        r.bestCompanyID = nil; r.worstCompanyID = nil; r.ranking = [companyID]
        return r
    }
}
