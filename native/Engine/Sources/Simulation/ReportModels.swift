import Foundation
import GameCore

public enum ReportKind: String, Codable, CaseIterable, Sendable {
    case week, month, year

    var storeKey: String { switch self { case .week: return "w"; case .month: return "m"; case .year: return "y" } }
    public var keep: Int { switch self { case .week: return 26; case .month: return 36; case .year: return 10 } }
    public var noun: String { rawValue }
    public var title: String { switch self { case .week: return "Week"; case .month: return "Month"; case .year: return "Year" } }
}

public struct ReportPnL: Codable, Equatable, Sendable {
    public var revenue = 0.0
    public var costOfSales = 0.0
    public var wages = 0.0
    public var rent = 0.0
    public var marketing = 0.0
    public var insurance = 0.0
    public var other = 0.0
    public var depreciation = 0.0
    public var interest = 0.0
    public var fines = 0.0
    public var losses = 0.0
    public var tax = 0.0

    public init() {}

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

    public var costLines: [Line] {
        [Line(id: "cogs", label: "Cost of sales", amount: costOfSales), Line(id: "wages", label: "Wages", amount: wages),
         Line(id: "rent", label: "Rent and premises", amount: rent), Line(id: "mkt", label: "Marketing", amount: marketing),
         Line(id: "ins", label: "Insurance", amount: insurance), Line(id: "oth", label: "Running costs and fees", amount: other),
         Line(id: "dep", label: "Depreciation", amount: depreciation), Line(id: "int", label: "Interest", amount: interest),
         Line(id: "fine", label: "Fines", amount: fines), Line(id: "loss", label: "Refunds and losses", amount: losses)]
    }
}

public enum ReportMath {
    public static func share(_ now: Double, _ before: Double) -> Double? {
        guard before.isFinite, now.isFinite, abs(before) >= 1 else { return nil }
        return (now - before) / abs(before)
    }
}

public struct ReportEvent: Codable, Equatable, Sendable {
    public var text: String
    public var tone: String
    public var companyID: Int
    public var week: Int
    public init(text: String, tone: String, companyID: Int, week: Int) { self.text = text; self.tone = tone; self.companyID = companyID; self.week = week }
}

public struct ReportNetWorth: Codable, Equatable, Sendable {
    public var cash = 0.0
    public var investments = 0.0
    public var companies = 0.0
    public var luxury = 0.0
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

public struct ReportCompany: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var tradeID: String
    public var status: String
    public var pnl = ReportPnL()
    public var loansTaken = 0.0
    public var loansRepaid = 0.0
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
    public var valueStart = 0.0
    public var valueEnd = 0.0
    public var events: [ReportEvent] = []

    public var reputationChange: Double { reputationEnd - reputationStart }
    public var valueChange: Double { valueEnd - valueStart }
    public var margin: Double? { pnl.revenue > 0 ? pnl.netProfit / pnl.revenue : nil }
}

public struct ReportFlow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var amount: Double
}

public struct ReportGroup: Codable, Equatable, Sendable {
    public var pnl = ReportPnL()
    public var accountStart = 0.0
    public var accountEnd = 0.0
    public var accountFlows: [ReportFlow] = []
    public var loansTaken = 0.0
    public var loansRepaid = 0.0
    public var taxPaid = 0.0
    public var dividendsReceived = 0.0
    public var personalTax = 0.0
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

    public var cashStart: Double { accountStart }
    public var cashEnd: Double { accountEnd }
}

public struct ReportPrevious: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var pnl = ReportPnL()
    public var netWorthChange = 0.0
    public var customers = 0.0
    public var cashEnd = 0.0
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
    public var id: Int
    public var firstWeek: Int
    public var lastWeek: Int
    public var title: String
    public var range: String
    public var partial = false
    public var group = ReportGroup()
    public var companies: [ReportCompany] = []
    public var netWorthStart = ReportNetWorth()
    public var netWorthEnd = ReportNetWorth()
    public var previous: ReportPrevious? = nil
    public var bestCompanyID: Int? = nil
    public var worstCompanyID: Int? = nil
    public var ranking: [Int] = []
    public var summary: [String] = []
    public var scopeName: String? = nil

    public var netWorthChange: Double { netWorthEnd.total - netWorthStart.total }
    public var netWorthShare: Double? { ReportMath.share(netWorthEnd.total, netWorthStart.total) }
    public func company(_ id: Int) -> ReportCompany? { companies.first { $0.id == id } }
    public var best: ReportCompany? { bestCompanyID.flatMap { company($0) } }
    public var worst: ReportCompany? { worstCompanyID.flatMap { company($0) } }
    public var hasActivity: Bool { !group.pnl.isEmpty || !companies.isEmpty }

    public func filtered(to companyID: Int) -> PeriodReport? {
        guard let c = company(companyID) else { return nil }
        var r = self
        r.scopeName = c.name
        r.companies = [c]
        var g = ReportGroup()
        g.pnl = c.pnl
        g.loansTaken = c.loansTaken; g.loansRepaid = c.loansRepaid
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
