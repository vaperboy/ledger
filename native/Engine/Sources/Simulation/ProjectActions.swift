import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// What the player sees and can do in a project company: the order book, tenders, developments.
public struct ProjectBoard: Equatable {
    public struct JobRow: Identifiable, Equatable {
        public var id: Int
        public var title: String
        public var client: String
        public var sizeClass: Int
        public var value: Double
        public var paid: Double
        public var hoursDone: Double
        public var hours: Double
        public var quotedHours: Double
        public var progress: Double
        public var held: Bool
        public var isPublic: Bool
        /// Estimated margin on this job: what the client pays less materials and subcontractors (labour is in the wages).
        public var margin: Double
        /// Event agency: the day of the event (week and day offset), otherwise nil.
        public var dueWeek: Int?
        public var started: Bool
    }
    public struct TenderRow: Identifiable, Equatable {
        public var id: Int
        public var title: String
        public var buyer: String
        public var worth: Double
        public var bidCost: Double
        public var priceWeight: Double
        public var weeksToBid: Int
        public var awardWeek: Int
        public var requirement: String?
        public var qualifies: Bool
        public var myBid: Double?
        public var myBidHigherQuality: Bool
        public var outcome: String?
    }
    public struct DevelopmentRow: Identifiable, Equatable {
        public var id: Int
        public var name: String
        public var stage: String
        public var weeksLeft: Int
        public var units: Int
        public var sold: Int
        public var land: Double
        public var build: Double
        public var unitPrice: Double
        public var priceMultiplier: Double
        public var workInProgress: Double
        public var revenue: Double
        public var loanBalance: Double
        public var delayWeeks: Int
    }
    public struct FinishedRow: Identifiable, Equatable { public var id: Int; public var name: String; public var units: Int; public var revenue: Double; public var cost: Double }

    public var isDeveloper = false
    public var isEvent = false
    public var jobs: [JobRow] = []
    public var queuedJobs: [JobRow] = []
    public var tenders: [TenderRow] = []
    public var myTenders: [TenderRow] = []
    public var developments: [DevelopmentRow] = []
    public var finishedDevelopments: [FinishedRow] = []
    public var bookedHours = 0.0
    public var hoursPerWeek = 0.0
    public var weeksBooked = 0.0
    public var finishedCount = 0
    public var requestsTurnedAway = 0
    public var managerBids = true
    public var hasManager = false
    public var outstandingPayments = 0.0
    /// Last week's figures.
    public var lastWeekHoursWorked = 0.0
    public var lastWeekRequests = 0
    public var lastWeekTaken = 0
}

public extension GameEngine {
    enum DevelopmentStart: Equatable { case started, notEnoughCash, loanRefused, notAvailable }

    /// Buy land and start a development. `financed`: a construction loan for most of the cost. Original: `devsheet` / `FAM.dev.start`.
    @discardableResult
    mutating func startDevelopment(companyID: Int, size: Double, financed: Bool) -> DevelopmentStart {
        var out = DevelopmentStart.notAvailable
        update { s, data, ctx in
            guard let co = s.company(companyID), co.status == .open else { return }
            switch ProjectDeveloper.start(&s, companyID: companyID, size: size, financed: financed, data: data, context: ctx) {
            case .started: out = .started
            case .notEnoughCash: out = .notEnoughCash
            case .loanRefused: out = .loanRefused
            case .notADeveloper: out = .notAvailable
            }
        }
        return out
    }

    /// What a development of this size would cost, for the sheet that starts one.
    func developmentQuote(companyID: Int, size: Double, financed: Bool) -> ProjectDeveloper.Quote? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], ProjectModel.isDeveloper(bd) else { return nil }
        return ProjectDeveloper.quote(co, bd, size: size, financed: financed, world: World(state: state, data: data), homeCurrency: homeCurrency)
    }

    mutating func setDevelopmentPrice(companyID: Int, projectID: Int, multiplier: Double) {
        update { s, _, _ in ProjectDeveloper.setPriceMultiplier(&s, companyID: companyID, projectID: projectID, multiplier: multiplier) }
    }

    /// Send a bid for a tender: price as a share of the list price, and a quality commitment (costs a little more to deliver).
    @discardableResult
    mutating func bidOnTender(companyID: Int, tenderID: Int, priceFactor: Double, higherQuality: Bool) -> ProjectTenders.BidResult {
        var out = ProjectTenders.BidResult.closed
        update { s, data, _ in out = ProjectTenders.placeBid(&s, companyID: companyID, tenderID: tenderID, priceFactor: priceFactor, higherQuality: higherQuality, data: data) }
        return out
    }

    mutating func withdrawBid(companyID: Int, tenderID: Int) {
        update { s, _, _ in ProjectTenders.withdrawBid(&s, companyID: companyID, tenderID: tenderID) }
    }

    /// Should the manager bid for tenders at list price when there is room? Original: `tnd56auto`.
    mutating func setManagerBids(companyID: Int, on: Bool) {
        update { s, _, _ in ProjectTenders.setManagerBids(&s, companyID: companyID, on: on) }
    }

    /// Findings specific to project companies (nothing for other trades).
    func projectInsights(for co: Company) -> [Insight] {
        guard co.status == .open, let bd = data.catalog[co.type], bd.family == "project", let b = projectBoard(companyID: co.id) else { return [] }
        var out: [Insight] = []
        if b.isDeveloper {
            if b.developments.isEmpty {
                out.append(Insight(id: "devidle", symbol: "building.2", text: "No development is running. Buy land and start one under Projects; the first sales come about two years later, so keep cash for the wait.", tone: .neutral))
            }
            if let p = b.developments.first(where: { $0.stage == "zoning" && $0.delayWeeks > 0 }) {
                out.append(Insight(id: "devdelay", symbol: "clock", text: "\(p.name) is held up. Delays cost interest on the construction loan.", tone: .warn))
            }
            if state.economy.housing < 0.85 {
                out.append(Insight(id: "housing", symbol: "chart.line.downtrend.xyaxis", text: "The housing market is weak: units sell slowly and for less.", tone: .warn))
            }
            return out
        }
        if b.requestsTurnedAway > 0 {
            out.append(Insight(id: "turnedaway", symbol: "tray.full", text: "Work was turned away in the last weeks: the firm is booked \(Int(jsRound(b.weeksBooked))) weeks ahead. More people or equipment would add revenue.", tone: .warn))
        } else if b.weeksBooked < 0.3, b.hoursPerWeek > 0 {
            out.append(Insight(id: "emptybook", symbol: "calendar", text: "The order book is nearly empty. Marketing, a lower price or a tender can fill it.", tone: .neutral))
        }
        if let t = b.tenders.first(where: { $0.qualifies && $0.myBid == nil }) {
            out.append(Insight(id: "tender", symbol: "doc.text.magnifyingglass", text: "A tender is open: \(t.title) from \(t.buyer). \(t.weeksToBid) weeks left to bid.", tone: .neutral))
        }
        return out
    }

    /// The order book, tenders and developments of a project company; nil for other trades.
    func projectBoard(companyID: Int) -> ProjectBoard? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], bd.family == "project" else { return nil }
        var b = ProjectBoard()
        let fm = co.value("fm")
        b.hasManager = co.managerID != nil
        b.managerBids = ProjectTenders.managerBids(state, companyID: companyID)
        if ProjectModel.isDeveloper(bd) {
            b.isDeveloper = true
            b.developments = ProjectDeveloper.projects(co).map { p in
                ProjectBoard.DevelopmentRow(id: p.id, name: p.name, stage: p.stage, weeksLeft: p.weeksLeft, units: p.units, sold: p.sold, land: p.land, build: p.build,
                                            unitPrice: p.unitPrice, priceMultiplier: p.priceMultiplier, workInProgress: p.workInProgress, revenue: p.revenue,
                                            loanBalance: state.loans.first { $0.id == p.loanID }?.balance ?? 0, delayWeeks: p.delay)
            }
            b.finishedDevelopments = fm["finished"].array.enumerated().map {
                ProjectBoard.FinishedRow(id: $0.offset, name: $0.element["name"].string, units: $0.element["units"].int, revenue: $0.element["rev"].double, cost: $0.element["cost"].double)
            }
            b.finishedCount = fm["doneCount"].int
            return b
        }
        b.isEvent = ProjectModel.specs[bd.id]?.isEvent ?? false
        let all = fm["jobs"].array.map { ProjectModel.Job(raw: $0.object) }
        let rows = all.map { j -> ProjectBoard.JobRow in
            let title = j.what.isEmpty ? "Job for \(j.client)" : j.what.prefix(1).uppercased() + j.what.dropFirst()
            return ProjectBoard.JobRow(id: j.id, title: title, client: j.client, sizeClass: j.sizeClass, value: j.contractValue, paid: j.paid, hoursDone: j.hoursDone,
                                       hours: j.hours, quotedHours: j.quotedHours, progress: j.hours > 0 ? min(1, j.hoursDone / j.hours) : j.progress, held: j.delay > 0,
                                       isPublic: j.isPublic, margin: 1 - j.costShare, dueWeek: j.dueDay.map { $0 / 7 }, started: j.hoursDone > 0)
        }
        b.jobs = rows.filter { $0.started }
        b.queuedJobs = rows.filter { !$0.started }
        b.outstandingPayments = all.reduce(0) { $0 + $1.remainingPayment }
        b.bookedHours = all.reduce(0) { $0 + ($1.inHours ? $1.remainingHours : 0) }
        b.hoursPerWeek = fm["hw41"].double
        b.weeksBooked = b.hoursPerWeek > 0 ? b.bookedHours / b.hoursPerWeek : 0
        b.finishedCount = fm["done"].int
        let wk = fm["wk41"]
        b.lastWeekHoursWorked = wk["used"].double
        b.lastWeekRequests = wk["req"].int
        b.lastWeekTaken = wk["took"].int
        b.requestsTurnedAway = fm["lost41"].array.reduce(0) { $0 + $1.int }
        func row(_ t: ProjectTenders.Tender) -> ProjectBoard.TenderRow {
            let q = ProjectTenders.qualification(t, co, week: state.week)
            var req: [String] = []
            if t.minimumYears > 0 { req.append("a year in business") }
            if t.minimumRating > 0 { req.append(String(format: "%.1f stars", t.minimumRating)) }
            let mine = t.bid(of: companyID)
            return ProjectBoard.TenderRow(id: t.id, title: t.title, buyer: t.buyer, worth: t.worth, bidCost: t.bidCost, priceWeight: t.priceWeight,
                                          weeksToBid: max(0, t.closesWeek - state.week), awardWeek: t.awardWeek, requirement: req.isEmpty ? nil : req.joined(separator: " and "),
                                          qualifies: q.ok, myBid: mine?.priceFactor, myBidHigherQuality: mine?.higherQuality ?? false, outcome: t.outcome)
        }
        b.tenders = ProjectTenders.openTenders(state, for: co).map(row)
        b.myTenders = ProjectTenders.tenders(state, bidBy: co).map(row).filter { $0.outcome != nil || $0.weeksToBid >= 0 }
        return b
    }
}
