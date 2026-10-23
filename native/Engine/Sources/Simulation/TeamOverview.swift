import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The Team tab's read model. Who runs each company day to day (the delegation chain of `ManagerModel.decisionChain`: store manager,
/// regional manager, chain manager, chain CEO or managing director, group managing director), and the problems that need the owner:
/// decisions waiting, wages at risk, companies nobody runs, managers who leave or fail, and staff trouble in the companies you run yourself.
/// Staff trouble inside a company a manager runs is listed as handled by that manager, not as yours.
public struct TeamOverview: Sendable {
    public struct CompanyLine: Identifiable, Sendable {
        public var id: Int
        public var name: String
        /// "You" or the name of the person who runs it day to day.
        public var managedBy: String
        public var managerTitle: String?
        public var delegated: Bool
        /// The store manager's authority (0 asks you, 1 within limits, 2 full control); -1 without a store manager.
        public var authority: Int
        public var staff: Int
        public var monthlyWages: Double
        public var chainID: Int?
        public var holdingID: Int?
        public var issues: Int
    }

    public struct Issue: Identifiable, Sendable {
        public enum Kind: String, Sendable { case decision, payroll, cash, vacancy, managerLeaving, managerWeak, staffSick, staffLeaving, paperwork, tired, chainVacancy }
        public var id: String
        public var kind: Kind
        public var companyID: Int?
        public var chainID: Int?
        public var messageID: Int?
        public var title: String
        public var detail: String
        /// 3 act now, 2 soon, 1 for information.
        public var severity: Int
        /// "You", or the name of the manager whose job it is.
        public var handledBy: String
        public var needsOwner: Bool { handledBy == TeamOverview.you }
    }

    public static let you = "You"
    public var companies: [CompanyLine]
    public var issues: [Issue]
}

public extension GameEngine {
    /// Title of a boss in the delegation chain.
    static func bossTitle(_ kind: String, trade: Trade?) -> String {
        switch kind {
        case "mgr": return trade.map { ManagerModel.title($0) } ?? "Manager"
        case "region": return "Regional manager"
        case "chainmgr": return "Chain manager"
        case "ceo56": return "Chain CEO"
        case "mdir": return "Managing director"
        default: return "Group managing director"
        }
    }

    func teamOverview() -> TeamOverview {
        let s = state
        var lines: [TeamOverview.CompanyLine] = []
        var issues: [TeamOverview.Issue] = []

        for co in s.companies where co.status.isLive {
            let trade = data.catalog[co.type]
            let bosses = ManagerModel.decisionChain(s, co, data: data)
            let first = bosses.first
            let runner = first?.name ?? TeamOverview.you
            let delegated = first != nil
            let wages = co.staff.reduce(0) { $0 + $1.monthlyWage } + (co.managerID != nil ? co.managerMonthlyWage : 0)
            let chainID = co.value("chain").isNull ? nil : co.value("chain").int
            var mine: [TeamOverview.Issue] = []
            func add(_ kind: TeamOverview.Issue.Kind, _ title: String, _ detail: String, _ sev: Int, by: String, msg: Int? = nil) {
                mine.append(.init(id: "\(kind.rawValue)-\(co.id)-\(msg ?? 0)", kind: kind, companyID: co.id, chainID: chainID, messageID: msg,
                                  title: title, detail: detail, severity: sev, handledBy: by))
            }

            // Wages and cash: always the owner's problem, whoever runs the company.
            if !co.value("pr29")["late"].isNull { add(.payroll, "Wages are late at \(co.name)", "Staff have not been paid in full. Unpaid wages lead to claims and fines.", 3, by: TeamOverview.you) }
            else if wages > 0 && co.cash < wages && co.status == .open { add(.cash, "\(co.name) has less cash than a month of wages", "Next payday may not be covered. Move money in or cut costs.", 2, by: TeamOverview.you) }

            // Who runs it.
            let ownerWorksThere = co.ownerHours > 0 && co.type != "hold"
            if co.managerID == nil && !ownerWorksThere && co.status == .open && !co.staff.isEmpty && co.type != "hold" {
                add(.vacancy, "No one runs \(co.name)", bosses.isEmpty ? "You do not work there and it has no manager." : "No store manager; \(runner) oversees it from above.", bosses.isEmpty ? 3 : 2, by: TeamOverview.you)
            }
            if co.managerID != nil {
                let above = bosses.dropFirst().first?.name ?? TeamOverview.you
                if !co.value("mgrNotice").isNull {
                    add(.managerLeaving, "The manager of \(co.name) is leaving", "Hire a successor before the notice ends so they can hand over.", 3, by: above)
                } else {
                    let started = co.value("mgrW0").isNull ? s.week : co.int("mgrW0")
                    if s.week - started >= 13, let tr = trade, ManagerModel.quality(co, tr, people: s.people) < 0.35 {
                        add(.managerWeak, "The manager of \(co.name) is struggling", "Results are weak after three months. Coach, replace or limit their authority.", 2, by: above)
                    }
                }
            }

            // Staff trouble: the runner's job when someone runs the company, yours when you run it yourself.
            let sick = co.staff.filter { ($0.sickUntilWeek ?? -1) >= s.week }.count
            let leaving = co.staff.filter { $0.noticeWeeks > 0 }.count
            let papers = co.staff.reduce(0) { $0 + StaffExtras.missing($1).count }
            let tired = co.staff.filter { $0.tiredness > 75 }.count
            let staffBoss = co.managerID.flatMap { s.people[$0]?.name } ?? TeamOverview.you
            let n = co.staff.count
            if sick > 0 { add(.staffSick, "\(sick) off sick at \(co.name)", "Capacity is down until they are back.", n > 0 && sick * 4 >= n ? 2 : 1, by: staffBoss) }
            if leaving > 0 { add(.staffLeaving, "\(leaving) working their notice at \(co.name)", "Replace them before they go.", 1, by: staffBoss) }
            if papers > 0 { add(.paperwork, "\(papers) paperwork item\(papers == 1 ? "" : "s") missing at \(co.name)", "An inspection can fine you.", 1, by: staffBoss) }
            if tired > 0 { add(.tired, "\(tired) worn out at \(co.name)", "Long hours raise mistakes and resignations.", 1, by: staffBoss) }

            // Decisions waiting on this company.
            for m in s.inbox where m.status == "open" && m.companyID == co.id {
                mine.append(.init(id: "decision-\(m.id)", kind: .decision, companyID: co.id, chainID: chainID, messageID: m.id,
                                  title: m.title, detail: m.from, severity: 3, handledBy: TeamOverview.you))
            }

            lines.append(.init(id: co.id, name: co.name, managedBy: runner, managerTitle: first.map { GameEngine.bossTitle($0.kind, trade: trade) },
                               delegated: delegated, authority: co.managerID == nil ? -1 : Int(co.value("auth")["lvl"].double),
                               staff: co.staff.count, monthlyWages: wages, chainID: chainID, holdingID: co.holdingID == 0 ? nil : co.holdingID,
                               issues: mine.filter { $0.needsOwner }.count))
            issues += mine
        }

        // A chain of five or more stores with no one above the store managers.
        let regs = ManagerModel.regionals(s)
        for ch in s.rest["chains"]?.array ?? [] {
            let id = ch["id"].int
            let stores = s.companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == id }
            let hasChief = regs.contains { $0["scope"].string == "chain:\(id)" } || !ch["ceo56"].isNull
            if stores.count >= 5 && !hasChief {
                let name = ch["name"].string.isEmpty ? "Your chain" : ch["name"].string
                issues.append(.init(id: "chainVacancy-\(id)", kind: .chainVacancy, companyID: stores.first?.id, chainID: id, messageID: nil,
                                    title: "\(name) has \(stores.count) stores and no chain manager", detail: "Every store reports straight to you.", severity: 1, handledBy: TeamOverview.you))
            }
        }

        // Decisions not tied to a company.
        for m in s.inbox where m.status == "open" && (m.companyID == 0 || s.company(m.companyID) == nil) {
            issues.append(.init(id: "decision-\(m.id)", kind: .decision, companyID: nil, chainID: nil, messageID: m.id, title: m.title, detail: m.from, severity: 3, handledBy: TeamOverview.you))
        }

        issues.sort { ($0.needsOwner ? 1 : 0, $0.severity) > ($1.needsOwner ? 1 : 0, $1.severity) }
        return TeamOverview(companies: lines, issues: issues)
    }
}
