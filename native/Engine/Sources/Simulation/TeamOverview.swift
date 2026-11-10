import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public struct TeamOverview: Sendable {
    public struct CompanyLine: Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var managedBy: String
        public var managerTitle: String?
        public var delegated: Bool
        public var authority: Int
        public var staff: Int
        public var monthlyWages: Double
        public var chainID: Int?
        public var holdingID: Int?
        public var issues: Int
        public var chainName: String?
        public var holdingName: String?
        public var score: Int?
        public var managerQuality: Double?
        public var managerLeaving: Bool
        public var isHolding: Bool
    }

    public struct Vacancy: Identifiable, Sendable {
        public var id: String
        public var title: String
        public var scope: String
        public var place: String
        public var detail: String
        public var companyID: Int?
        public var chainID: Int?
        public var needed: Bool
        public var employer: String = ""
        public var post: String = ""
        public var key: String = ""
        public var hirerName: String? = nil
        public var hirerTitle: String? = nil
        public var hirerAuthority: Int = -1
    }

    public struct Member: Identifiable, Sendable {
        public var id: String
        public var name: String
        public var role: String
        public var scope: String
        public var employer: String
        public var monthlyWage: Double
        public var companyID: Int?
        public var chainID: Int?
        public var personID: Int? = nil
    }

    public struct GroupOffice: Sendable {
        public var established: Bool
        public var tierName: String?
        public var employer: String
    }

    public struct Issue: Identifiable, Sendable {
        public enum Kind: String, Sendable { case decision, payroll, cash, vacancy, managerLeaving, managerWeak, staffSick, staffLeaving, tired, chainVacancy }
        public var id: String
        public var kind: Kind
        public var companyID: Int?
        public var chainID: Int?
        public var messageID: Int?
        public var title: String
        public var detail: String
        public var severity: Int
        public var handledBy: String
        public var beyondAuthority: Bool = false
        public var needsOwner: Bool { handledBy == TeamOverview.you }
    }

    public static let you = "You"
    public static let escalations: Set<String> = ["prop", "org56", "cpx56"]

    public var companies: [CompanyLine]
    public var issues: [Issue]
    public var vacancies: [Vacancy] = []
    public var members: [Member] = []
    public var groupOffice = GroupOffice(established: false, tierName: nil, employer: "Your group office")
    public var scorecards: [Headquarters.Scorecard] = []
}

public extension GameEngine {
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

    static func authorityText(level: Int) -> String { (Budget(rawValue: min(2, max(0, level))) ?? .tight).text }

    func teamOverview() -> TeamOverview {
        let s = state
        var lines: [TeamOverview.CompanyLine] = []
        var issues: [TeamOverview.Issue] = []
        var vacancies: [TeamOverview.Vacancy] = []
        var cards: [Headquarters.Scorecard] = []
        var members: [TeamOverview.Member] = []
        let chains = s.rest["chains"]?.array ?? []

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

            if !co.value("pr29")["late"].isNull { add(.payroll, "Wages are late at \(co.name)", "Staff have not been paid in full. Unpaid wages lead to claims and fines.", 3, by: TeamOverview.you) }
            else if wages > 0 && co.cash < wages && co.status == .open { add(.cash, "\(co.name) has less cash than a month of wages", "Next payday may not be covered. Move money in or cut costs.", 2, by: TeamOverview.you) }

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

            let sick = co.staff.filter { ($0.sickUntilWeek ?? -1) >= s.week }.count
            let leaving = co.staff.filter { $0.noticeWeeks > 0 }.count
            let tired = co.staff.filter { $0.tiredness > 75 }.count
            let staffBoss = co.managerID.flatMap { s.people[$0]?.name } ?? TeamOverview.you
            let n = co.staff.count
            if sick > 0 { add(.staffSick, "\(sick) off sick at \(co.name)", "Capacity is down until they are back.", n > 0 && sick * 4 >= n ? 2 : 1, by: staffBoss) }
            if leaving > 0 { add(.staffLeaving, "\(leaving) working their notice at \(co.name)", "Replace them before they go.", 1, by: staffBoss) }
            if tired > 0 { add(.tired, "\(tired) worn out at \(co.name)", "Long hours raise mistakes and resignations.", 1, by: staffBoss) }

            for m in s.inbox where m.status == "open" && m.companyID == co.id {
                let escalated = TeamOverview.escalations.contains(m.actionID)
                var detail = m.from
                if escalated, let b = bosses.first(where: { $0.name == m.from }) {
                    detail = "\(m.from), \(GameEngine.bossTitle(b.kind, trade: trade).lowercased()), \(GameEngine.authorityText(level: b.level))"
                }
                mine.append(.init(id: "decision-\(m.id)", kind: .decision, companyID: co.id, chainID: chainID, messageID: m.id,
                                  title: m.title, detail: detail, severity: 3, handledBy: TeamOverview.you, beyondAuthority: escalated))
            }

            let card = co.managerID == nil ? nil : Headquarters.review(s, companyID: co.id)
            if let card { cards.append(card) }
            let chainName: String? = chainID.flatMap { cid in chains.first { $0["id"].int == cid } }.map { $0["name"].string.isEmpty ? "Your chain" : $0["name"].string }
            lines.append(.init(id: co.id, name: co.name, managedBy: runner, managerTitle: first.map { GameEngine.bossTitle($0.kind, trade: trade) },
                               delegated: delegated, authority: co.managerID == nil ? -1 : ManagerModel.budget(of: co).rawValue,
                               staff: co.staff.count, monthlyWages: wages, chainID: chainID, holdingID: co.holdingID == 0 ? nil : co.holdingID,
                               issues: mine.filter { $0.needsOwner }.count,
                               chainName: chainName, holdingName: co.holdingID == 0 ? nil : s.company(co.holdingID)?.name,
                               score: card?.score,
                               managerQuality: co.managerID == nil ? nil : trade.map { ManagerModel.quality(co, $0, people: s.people) },
                               managerLeaving: co.managerID != nil && !co.value("mgrNotice").isNull,
                               isHolding: co.type == "hold"))
            issues += mine

            if co.type != "hold" && co.status == .open && trade?.family != "club" {
                let title = trade.map { ManagerModel.title($0) } ?? "Manager"
                if co.managerID == nil && !ownerWorksThere && !co.staff.isEmpty {
                    var v = TeamOverview.Vacancy(id: "mgr-\(co.id)", title: title, scope: "store", place: co.name,
                                                 detail: bosses.isEmpty ? "No one runs it day to day." : "\(runner) oversees it from above, with no one on site.",
                                                 companyID: co.id, chainID: chainID, needed: bosses.isEmpty, employer: co.name)
                    v.post = "mgr"
                    if let a = HierarchyHiring.appointer(s, post: .storeManager(companyID: co.id), data: data) { v.hirerName = a.name; v.hirerTitle = a.title; v.hirerAuthority = a.level }
                    vacancies.append(v)
                } else if co.managerID != nil && !co.value("mgrNotice").isNull {
                    var v = TeamOverview.Vacancy(id: "mgr-\(co.id)", title: title, scope: "store", place: co.name,
                                                 detail: "The manager is working their notice; a successor hired now can hand over.", companyID: co.id, chainID: chainID, needed: true, employer: co.name)
                    v.post = "mgr"
                    vacancies.append(v)
                }
            }
            for slot in ManagerModel.teamSlots(s, companyID: co.id, data: data) {
                let scope = slot.key == "reg" ? "region" : (slot.key == "ceo" && co.type == "hold") ? "group" : "company"
                if let pid = slot.personID, let p = s.people[pid] {
                    members.append(.init(id: "slot-\(co.id)-\(slot.id)", name: p.name, role: slot.title, scope: scope, employer: co.name,
                                         monthlyWage: slot.monthlyWage, companyID: co.id, chainID: chainID, personID: pid))
                } else {
                    var v = TeamOverview.Vacancy(id: "slot-\(co.id)-\(slot.id)", title: slot.title, scope: scope, place: co.name, detail: slot.detail,
                                                 companyID: co.id, chainID: chainID, needed: false, employer: co.name)
                    v.post = "team"; v.key = slot.key
                    vacancies.append(v)
                }
            }
        }

        let regs = ManagerModel.regionals(s)
        for ch in chains {
            let id = ch["id"].int
            let stores = s.companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == id }
            guard !stores.isEmpty else { continue }
            let name = ch["name"].string.isEmpty ? "Your chain" : ch["name"].string
            let hasChainManager = regs.contains { $0["scope"].string == "chain:\(id)" }
            let hasCEO = !ch["ceo56"].isNull && s.people[ch["ceo56"]["npc"].int] != nil
            let short = stores.count >= 5 && !hasChainManager && ch["ceo56"].isNull
            if short {
                issues.append(.init(id: "chainVacancy-\(id)", kind: .chainVacancy, companyID: stores.first?.id, chainID: id, messageID: nil,
                                    title: "\(name) has \(stores.count) stores and no chain manager", detail: "Every store reports straight to you.", severity: 1, handledBy: TeamOverview.you))
            }
            if hasCEO, let p = s.people[ch["ceo56"]["npc"].int] {
                members.append(.init(id: "cc\(id)", name: p.name, role: "Chain CEO", scope: "chain", employer: name, monthlyWage: ch["ceo56"]["wage"].double,
                                     companyID: stores.first?.id, chainID: id, personID: p.id))
            }
            for r in regs where r["scope"].string == "chain:\(id)" || r["scope"].string.hasPrefix("chain:\(id):") {
                guard let p = s.people[r["npc"].int] else { continue }
                let isRegion = r["scope"].string.split(separator: ":").count >= 3
                members.append(.init(id: "rm\(r["id"].int)", name: p.name, role: isRegion ? "Regional manager" : "Chain manager", scope: isRegion ? "region" : "chain",
                                     employer: name, monthlyWage: r["wage"].double, companyID: stores.first?.id, chainID: id, personID: p.id))
            }
            if !hasChainManager && stores.count >= 2 {
                var v = TeamOverview.Vacancy(id: "chainmgr-\(id)", title: "Chain manager", scope: "chain", place: name,
                                             detail: "Oversees the \(stores.count) stores so the store managers do not all report to you.",
                                             companyID: stores.first?.id, chainID: id, needed: short, employer: name)
                v.post = "chainmgr"
                if let a = HierarchyHiring.appointer(s, post: .chainManager(chainID: id), data: data) { v.hirerName = a.name; v.hirerTitle = a.title; v.hirerAuthority = a.level }
                vacancies.append(v)
            }
            if !hasCEO && stores.count >= 5 {
                var v = TeamOverview.Vacancy(id: "ceo56-\(id)", title: "Chain CEO", scope: "chain", place: name, detail: "Runs the whole chain above the chain and store managers.",
                                             companyID: stores.first?.id, chainID: id, needed: false, employer: name)
                v.post = "ceo56"
                vacancies.append(v)
            }
            let byCity = Dictionary(grouping: stores.filter { $0.status == .open }, by: { $0.cityID })
            for city in byCity.keys.sorted() where (byCity[city]?.count ?? 0) >= HierarchyHiring.regionalMinStores && !regs.contains(where: { $0["scope"].string == "chain:\(id):\(city)" }) {
                let place = ManagerModel.cityName(s, city, data)
                var v = TeamOverview.Vacancy(id: "region-\(id)-\(city)", title: "Regional manager", scope: "region", place: "\(name), \(place)",
                                             detail: "Runs the \(byCity[city]?.count ?? 0) stores in \(place) and hires their managers.", companyID: byCity[city]?.first?.id, chainID: id, needed: false, employer: name)
                v.post = "region"; v.key = city
                if let a = HierarchyHiring.appointer(s, post: .regional(chainID: id, cityID: city), data: data) { v.hirerName = a.name; v.hirerTitle = a.title; v.hirerAuthority = a.level }
                vacancies.append(v)
            }
        }

        let established = Headquarters.established(s)
        let groupEmployer = Headquarters.employerName(s, data)
        let md = s.rest["org56"]?["md"] ?? .null
        if !md.isNull, let p = s.people[md["npc"].int] {
            members.append(.init(id: "md", name: p.name, role: "Group managing director", scope: "group", employer: groupEmployer, monthlyWage: md["wage"].double, companyID: nil, chainID: nil, personID: p.id))
        } else if established && s.companies.filter({ $0.status.isLive }).count >= 2 {
            var v = TeamOverview.Vacancy(id: "md", title: "Group managing director", scope: "group", place: "Your group office",
                                         detail: "Runs the group under you; deals above the limit you set still come to you.", companyID: nil, chainID: nil, needed: false, employer: groupEmployer)
            v.post = "md"
            vacancies.append(v)
        }
        if let c = s.rest["group"]?["ceo"], !c.isNull, let p = s.people[c["npc"].int] {
            members.append(.init(id: "gceo", name: p.name, role: "Group CEO", scope: "group", employer: groupEmployer, monthlyWage: c["wage"].double, companyID: nil, chainID: nil, personID: p.id))
        }
        for r in regs where r["payCo"].isNull {
            guard let p = s.people[r["npc"].int] else { continue }
            members.append(.init(id: "rm\(r["id"].int)", name: p.name, role: "Regional manager", scope: "region", employer: groupEmployer, monthlyWage: r["wage"].double, companyID: nil, chainID: nil, personID: p.id))
        }
        if established {
            let roles = Headquarters.roles(data)
            for x in Headquarters.staff(s) where s.people[x["id"].int] != nil {
                members.append(.init(id: "hq-\(x["id"].int)", name: x["name"].string, role: roles.first { $0.id == x["role"].string }?.title ?? x["role"].string, scope: "group",
                                     employer: groupEmployer, monthlyWage: x["wage"].double, companyID: nil, chainID: nil, personID: x["id"].int))
            }
            for r in roles where Headquarters.room(s, role: r.id, data: data) == .ok {
                var v = TeamOverview.Vacancy(id: "hq-\(r.id)", title: r.title, scope: "group", place: "Your group office", detail: r.text, companyID: nil, chainID: nil, needed: false, employer: groupEmployer)
                v.post = "hq"; v.key = r.id
                vacancies.append(v)
            }
        }

        for m in s.inbox where m.status == "open" && (m.companyID == 0 || s.company(m.companyID) == nil) {
            issues.append(.init(id: "decision-\(m.id)", kind: .decision, companyID: nil, chainID: nil, messageID: m.id, title: m.title, detail: m.from, severity: 3,
                                handledBy: TeamOverview.you, beyondAuthority: TeamOverview.escalations.contains(m.actionID)))
        }

        issues.sort { ($0.needsOwner ? 1 : 0, $0.severity) > ($1.needsOwner ? 1 : 0, $1.severity) }
        let rankedVacancies = vacancies.enumerated().sorted { ($0.element.needed ? 0 : 1, $0.offset) < ($1.element.needed ? 0 : 1, $1.offset) }.map { $0.element }
        var out = TeamOverview(companies: lines, issues: issues, vacancies: rankedVacancies, scorecards: cards.sorted { ($0.score, $0.id) < ($1.score, $1.id) })
        out.members = members
        out.groupOffice = .init(established: established, tierName: established ? Headquarters.tier(s, data)?.name : nil, employer: groupEmployer)
        return out
    }

    struct ProfitBonusPreview: Equatable, Sendable {
        public var current: Double
        public var averageMonthlyProfit: Double
        public var monthlyCost: Double
        public var lastPaid: Double
    }

    func managerProfitBonusPreview(companyID: Int, share: Double) -> ProfitBonusPreview? {
        guard let co = state.company(companyID), co.managerID != nil else { return nil }
        let h = co.monthlyHistory.suffix(3)
        let avg = max(0, h.reduce(0) { $0 + $1.profit } / Double(max(1, h.count)))
        let factor = World(state: state, data: data).country(co).payrollFactor(monthlyWage: co.managerMonthlyWage)
        let x = min(0.3, max(0, share))
        return ProfitBonusPreview(current: co.managerProfitBonus, averageMonthlyProfit: avg, monthlyCost: avg * x * factor, lastPaid: co.num("mgrBonusLast"))
    }

    struct ManagerDuty: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var managerText: String
        public var ownerText: String
        public var manager: Bool
    }

    func managerDuties(companyID: Int) -> [ManagerDuty] {
        guard let co = state.company(companyID), co.managerID != nil else { return [] }
        return [ManagerDuty(id: "prem", title: "Asking for more space",
                            managerText: "When space is what limits sales, the manager asks to take about 25% more (or the boss above them decides).",
                            ownerText: "The manager never raises the premises; you watch for space yourself.",
                            manager: ManagerModel.dutyKept(co, "prem"))]
    }
}
