import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// One time-bound piece of project work with its milestones, for the Projects tab: a job in hand, an event booking, a tender to bid on or
/// awaiting a decision, or a real-estate development. Read-only: every figure comes from the records the project engine already keeps
/// (`fm.jobs`, `fm.proj`, the tenders); nothing here is a rule and nothing is invented. Where the engine keeps no date (a job's finish,
/// the start of a development) the field is nil and the screen says so.
public struct ProjectTimeline: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case job, event, tender, bid, development }
    public enum StageState: String, Sendable { case done, current, upcoming }
    public struct Stage: Equatable, Sendable {
        public var name: String
        public var detail: String
        public var state: StageState
        /// The game week the stage starts or falls due, when the engine knows it.
        public var week: Int?
    }

    public var id: String
    public var companyID: Int
    public var companyName: String
    public var kind: Kind
    public var title: String
    /// Client, buyer or the development's size.
    public var subtitle: String
    /// When the work was taken on, if the engine records it.
    public var startWeek: Int?
    /// The next date that matters: event day, bid closing, decision, end of the current development stage.
    public var dueWeek: Int?
    public var stages: [Stage]
    public var progress: Double?
    /// What the client pays, the tender is worth, or the development is expected to sell for.
    public var value: Double
    /// Money spent on it so far where the engine tracks it (developments: land plus building; tenders: the cost of the bid); nil for jobs.
    public var costSoFar: Double?
    public var costBudget: Double?
    /// Money already received (jobs).
    public var receivedSoFar: Double?
    /// What is holding it up now, or nil.
    public var blocking: String?
    /// What it costs you if it runs late, in the engine's own terms.
    public var ifLate: String
    /// The money that the "if late" sentence is about (still to be paid, loan outstanding, tied up), in the company's currency.
    public var atStake: Double?
    public var atStakeLabel: String
    /// True when the engine records a delay on it.
    public var delayed: Bool
    /// Weeks past the planned finish of a job still open (0 when it is not late or the job has no recorded finish).
    public var overdueWeeks: Int = 0
}

public extension GameEngine {
    /// Every open project item across the live project companies. Order: by company, then the engine's own order.
    func projectTimelines() -> [ProjectTimeline] {
        var out: [ProjectTimeline] = []
        let now = state.week
        for co in state.companies where co.status.isLive {
            guard let board = projectBoard(companyID: co.id), let bd = data.catalog[co.type] else { continue }
            if board.isDeveloper {
                let wks = Int(bd.traits["wks"] ?? 70)
                let rawBy = Dictionary(uniqueKeysWithValues: ProjectDeveloper.projects(co).map { ($0.id, $0) })
                for p in board.developments { out.append(developmentTimeline(co, p, spent: rawBy[p.id]?.spent ?? 0, overrun: rawBy[p.id]?.overrun ?? 0, buildWeeks: wks, now: now)) }
                continue
            }
            let raw = co.value("fm")["jobs"].array.map { ProjectModel.Job(raw: $0.object) }
            let all = board.jobs + board.queuedJobs
            for row in all {
                guard let j = raw.first(where: { $0.id == row.id }) else { continue }
                out.append(jobTimeline(co, j, row, board: board, now: now))
            }
            for t in board.tenders where t.qualifies && t.myBid == nil {
                out.append(ProjectTimeline(
                    id: "t\(co.id)-\(t.id)", companyID: co.id, companyName: co.name, kind: .tender, title: t.title, subtitle: t.buyer,
                    startWeek: nil, dueWeek: now + t.weeksToBid,
                    stages: [
                        .init(name: "Bid", detail: t.weeksToBid == 0 ? "Closes this week" : "Open for \(t.weeksToBid) more \(t.weeksToBid == 1 ? "week" : "weeks")", state: .current, week: now + t.weeksToBid),
                        .init(name: "Decision", detail: "The buyer picks the best score on price and quality", state: .upcoming, week: t.awardWeek),
                        .init(name: "Work", detail: "A won tender joins your jobs", state: .upcoming, week: nil),
                    ],
                    progress: nil, value: t.worth, costSoFar: nil, costBudget: t.bidCost, receivedSoFar: nil,
                    blocking: nil,
                    ifLate: "After the closing date you can no longer bid. Writing a bid costs money even when you lose.",
                    atStake: t.bidCost, atStakeLabel: "Cost of a bid", delayed: false))
            }
            for t in board.myTenders where t.outcome == nil {
                out.append(ProjectTimeline(
                    id: "m\(co.id)-\(t.id)", companyID: co.id, companyName: co.name, kind: .bid, title: t.title, subtitle: t.buyer,
                    startWeek: nil, dueWeek: t.awardWeek,
                    stages: [
                        .init(name: "Bid sent", detail: t.myBid.map { String(format: "At %d%% of the list price", Int(($0 * 100).rounded())) } ?? "", state: .done, week: nil),
                        .init(name: "Decision", detail: "The buyer picks the best score on price and quality", state: .current, week: t.awardWeek),
                        .init(name: "Work", detail: "A won tender joins your jobs", state: .upcoming, week: nil),
                    ],
                    progress: nil, value: t.worth, costSoFar: t.bidCost, costBudget: t.bidCost, receivedSoFar: nil,
                    blocking: "Waiting for the buyer's decision.",
                    ifLate: "Nothing to do until the decision. You can withdraw the bid before then.",
                    atStake: nil, atStakeLabel: "", delayed: false))
            }
        }
        return out
    }

    private func jobTimeline(_ co: Company, _ j: ProjectModel.Job, _ row: ProjectBoard.JobRow, board: ProjectBoard, now: Int) -> ProjectTimeline {
        let started = j.hoursDone > 0
        let progress = row.progress
        let taken = ProjectTimeline.Stage(name: "Taken on", detail: j.client, state: .done, week: j.startWeek)
        var stages: [ProjectTimeline.Stage]
        let kind: ProjectTimeline.Kind = board.isEvent ? .event : .job
        let pct = { (v: Double) in Int((v * 100).rounded()) }
        if board.isEvent {
            let day = row.dueWeek
            stages = [
                .init(name: "Booked", detail: "30% paid at booking", state: .done, week: j.startWeek),
                .init(name: "Preparation", detail: "\(Int(j.hoursDone.rounded())) of \(Int(j.hours.rounded())) h done (\(pct(progress))%)", state: .current, week: nil),
                .init(name: "Event day", detail: "The event happens on its day, ready or not; the rest is invoiced after", state: .upcoming, week: day),
            ]
        } else if j.milestones == true || (j.milestones == nil && j.sizeClass == 2) {
            let half = progress >= 0.5
            stages = [
                taken,
                .init(name: "Start", detail: "30% paid when work begins", state: started ? .done : .current, week: nil),
                .init(name: "Halfway", detail: "Paid up to 70% at half the hours", state: half ? .done : (started ? .current : .upcoming), week: nil),
                .init(name: "Finished", detail: "The last 30% is paid on completion", state: .upcoming, week: nil),
            ]
        } else {
            stages = [
                taken,
                .init(name: "Work", detail: "\(Int(j.hoursDone.rounded())) of \(Int(j.hours.rounded())) h done (\(pct(progress))%)", state: started ? .current : .upcoming, week: nil),
                .init(name: "Finished", detail: "Paid in full on completion", state: .upcoming, week: nil),
            ]
        }
        var blocking: String?
        if j.delay > 0 { blocking = "Held up by an event. Work on it resumes when the delay clears." }
        else if !started {
            blocking = board.isEvent ? "Not started: preparation goes to the nearest date first."
                : String(format: "Waiting its turn: the team works the oldest jobs first and is booked about %.1f weeks ahead.", board.weeksBooked)
        }
        let late: String
        if board.isEvent {
            late = "Events happen on their day. If less than 90% is prepared the client notices, your reputation drops and they will not recommend you."
        } else {
            late = j.milestones == false || (j.milestones == nil && j.sizeClass != 2)
                ? "You are paid in full only when it is finished, so a late finish delays everything still to come."
                : "The last part is paid only when it is finished, so a late finish delays that cash."
        }
        // A job's planned finish is recorded when it is taken on; a job from an older save has none and shows none.
        let planned: Int? = (!board.isEvent && !j.value("due").isNull) ? j.dueWeek : nil
        if let planned, !board.isEvent, let last = stages.indices.last { stages[last].week = planned }
        return ProjectTimeline(id: "j\(co.id)-\(j.id)", companyID: co.id, companyName: co.name, kind: kind, title: row.title, subtitle: j.client,
                               startWeek: j.startWeek, dueWeek: board.isEvent ? row.dueWeek : planned, stages: stages, progress: progress, value: j.contractValue,
                               costSoFar: nil, costBudget: nil, receivedSoFar: j.paid, blocking: blocking, ifLate: late,
                               atStake: board.isEvent ? nil : max(0, j.contractValue - j.paid), atStakeLabel: "Still to be paid", delayed: j.delay > 0,
                               overdueWeeks: planned.map { max(0, now - $0) } ?? 0)
    }

    private func developmentTimeline(_ co: Company, _ p: ProjectBoard.DevelopmentRow, spent: Double, overrun: Double, buildWeeks: Int, now: Int) -> ProjectTimeline {
        let zoning = p.stage == "zoning", building = p.stage == "build"
        let zoningEnd = now + p.weeksLeft
        let readyWeek = zoning ? zoningEnd + buildWeeks : building ? now + p.weeksLeft : nil
        let stages: [ProjectTimeline.Stage] = [
            .init(name: "Land bought", detail: "Paid at the start", state: .done, week: nil),
            .init(name: "Zoning", detail: zoning ? "Decision in \(p.weeksLeft) \(p.weeksLeft == 1 ? "week" : "weeks"); objections can push it back" : "Approved", state: zoning ? .current : .done, week: zoning ? zoningEnd : nil),
            .init(name: "Building", detail: building ? "\(p.weeksLeft) \(p.weeksLeft == 1 ? "week" : "weeks") left" : zoning ? "About \(buildWeeks) weeks once approved" : "Complete", state: building ? .current : zoning ? .upcoming : .done, week: readyWeek),
            .init(name: "Selling", detail: "\(p.sold) of \(p.units) units sold", state: p.stage == "sell" ? .current : .upcoming, week: nil),
        ]
        var blocking: String?
        if zoning { blocking = "Waiting for the planning decision. It can be delayed by objections." }
        else if building && p.delayWeeks > 0 { blocking = "Building is held up: \(p.delayWeeks) \(p.delayWeeks == 1 ? "week" : "weeks") added." }
        else if p.stage == "sell" && p.sold < p.units {
            blocking = state.economy.housing < 0.85 ? "Waiting for buyers in a weak housing market." : "Waiting for buyers."
        }
        let late = p.loanBalance > 0
            ? "Delays cost interest on the construction loan ; it is repaid from 70% of sales, so later sales keep it open longer."
            : "Sales start later, and the money in land and building stays tied up until units sell."
        let progress: Double? = zoning ? nil : building ? max(0, min(1, 1 - Double(p.weeksLeft) / Double(max(1, buildWeeks)))) : Double(p.sold) / Double(max(1, p.units))
        return ProjectTimeline(id: "d\(co.id)-\(p.id)", companyID: co.id, companyName: co.name, kind: .development, title: p.name, subtitle: "\(p.units) units",
                               startWeek: nil, dueWeek: readyWeek, stages: stages, progress: progress, value: p.unitPrice * Double(p.units) * p.priceMultiplier,
                               costSoFar: p.land + spent,
                               costBudget: p.land + p.build + overrun, receivedSoFar: p.revenue > 0 ? p.revenue : nil, blocking: blocking, ifLate: late, atStake: p.loanBalance > 0 ? p.loanBalance : p.workInProgress, atStakeLabel: p.loanBalance > 0 ? "Construction loan outstanding" : "Tied up in land and building", delayed: p.delayWeeks > 0)
    }
}
