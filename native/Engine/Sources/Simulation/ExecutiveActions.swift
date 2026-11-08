import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Boards, the management team, chain and group executives, the main office, meetings, the academy, owners and the big meeting, as player actions.
/// Models: `ManagerTeam`, `ManagerBoards`, `ManagerMeetings`, `ManagerPromotions`, `ManagerProposals`, `ChainHierarchy`, `Headquarters`, `Academy`.
public extension GameEngine {
    // MARK: Management team of a company (managing director, department heads, regional manager)

    func teamSlots(companyID: Int) -> [ManagerModel.TeamSlot] { ManagerModel.teamSlots(state, companyID: companyID, data: data) }
    mutating func searchTeam(companyID: Int, key: String) -> [Person]? {
        var r: [Person]?; update { s, d, _ in r = ManagerModel.searchTeam(&s, companyID: companyID, key: key, data: d) }; return r
    }
    mutating func hireTeam(companyID: Int, key: String, personID: Int, monthlyWage: Double) -> ManagerModel.OfferResult {
        var r = ManagerModel.OfferResult.refused; update { s, d, _ in r = ManagerModel.hireTeam(&s, companyID: companyID, key: key, personID: personID, monthlyWage: monthlyWage, data: d) }; return r
    }
    @discardableResult
    mutating func releaseTeam(companyID: Int, key: String, regionalID: Int? = nil) -> Bool {
        var r = false; update { s, d, _ in r = ManagerModel.releaseTeam(&s, companyID: companyID, key: key, regionalID: regionalID, data: d) }; return r
    }
    /// The budget of the company's managing director.
    @discardableResult
    mutating func setTeamBudget(companyID: Int, budget: Budget) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in ManagerModel.setTeamBudget(&s, companyID: companyID, budget: budget) }
    }
    /// The old authority setting: `level` 0, 1, 2 is the budget tight, normal, free; `buy` is ignored (the budget sets the limit).
    @discardableResult
    mutating func setTeamAuthority(companyID: Int, level: Int? = nil, buy: Double? = nil) -> SettingResult {
        guard let level else { return .unchanged }
        return setTeamBudget(companyID: companyID, budget: Budget(rawValue: min(2, max(0, level))) ?? .normal)
    }
    /// Who decides above the manager, lowest first.
    func decisionChain(companyID: Int) -> [ManagerModel.Boss] { state.company(companyID).map { ManagerModel.decisionChain(state, $0, data: data) } ?? [] }

    // MARK: Chain and group executives

    mutating func searchExecutive(_ level: ManagerModel.ExecLevel) -> [Person]? {
        var r: [Person]?; update { s, d, _ in r = ManagerModel.searchExecutive(&s, level: level, data: d) }; return r
    }
    mutating func hireExecutive(_ level: ManagerModel.ExecLevel, personID: Int, monthlyWage: Double, chainID: Int? = nil, city: String? = nil) -> ManagerModel.OfferResult {
        var r = ManagerModel.OfferResult.refused; update { s, d, _ in r = ManagerModel.hireExecutive(&s, level: level, personID: personID, monthlyWage: monthlyWage, chainID: chainID, city: city, data: d) }; return r
    }
    @discardableResult
    mutating func releaseExecutive(_ level: ManagerModel.ExecLevel, chainID: Int? = nil, regionalID: Int? = nil) -> Bool {
        var r = false; update { s, d, _ in r = ManagerModel.releaseExecutive(&s, level: level, chainID: chainID, regionalID: regionalID, data: d) }; return r
    }
    /// The budget of a chain or group executive.
    @discardableResult
    mutating func setExecutiveBudget(_ level: ManagerModel.ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, budget: Budget) -> SettingResult {
        applySetting(probe: { s in .array([.object(s.rest), Chains.chain(s, id: chainID ?? -1) ?? .null]) }) { s, _, _ in
            ManagerModel.setExecutiveBudget(&s, level: level, chainID: chainID, regionalID: regionalID, budget: budget)
        }
    }
    /// The old authority setting: `authority` 0, 1, 2 is the budget tight, normal, free; `buy` is ignored (the budget sets the limit).
    @discardableResult
    mutating func setExecutiveAuthority(_ level: ManagerModel.ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, authority: Int? = nil, buy: Double? = nil) -> SettingResult {
        guard let authority else { return .unchanged }
        return setExecutiveBudget(level, chainID: chainID, regionalID: regionalID, budget: Budget(rawValue: min(2, max(0, authority))) ?? .normal)
    }
    /// Deals above this amount always come to you.
    @discardableResult
    mutating func setGroupLimit(_ amount: Double) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, _, _ in ManagerModel.setGroupLimit(&s, amount: amount) }
    }
    var regionalManagers: [JSONValue] { ManagerModel.regionals(state) }
    var groupManagingDirector: JSONValue { state.rest["org56"]?["md"] ?? .null }
    /// The owner has set up a group office (`rentOffice`); group-level posts exist only from then on.
    var groupOfficeEstablished: Bool { Headquarters.established(state) }
    /// Who employs the group office's people: a holding with spare cash, else the office the owner set up.
    var groupOfficeEmployer: String { Headquarters.employerName(state, data) }
    /// What the group office costs a month now (0 before it is set up).
    var groupOfficeMonthlyCost: Double { Headquarters.monthlyCost(state, data) }

    // MARK: Boards

    var boardKeys: [String] { ManagerModel.boardKeys(state) }
    func boardKey(companyID: Int) -> String? { state.company(companyID).map { ManagerModel.boardKey(state, $0) } }
    func boardName(key: String) -> String { ManagerModel.boardName(state, key: key) }
    func boardIsActive(key: String) -> Bool { ManagerModel.boardActive(state, key: key) }
    func boardSeats(key: String) -> [ManagerModel.Seat] { ManagerModel.seats(state, key: key) }
    func boardVoters(key: String) -> [ManagerModel.Voter] { ManagerModel.voters(state, key: key) }
    func boardMeetings(key: String) -> [ManagerModel.BoardMeeting] { ManagerModel.meetings(state, key: key) }
    /// The one list of what the board puts to you: sell, close, dividend, replace the CEO, put in capital, open or close a location. Each item carries
    /// the recommendation of whoever knows the company; the ones they recommend come first.
    func boardDecisionList() -> [ManagerModel.BoardDecision] { ManagerModel.boardDecisions(state, data: data) }
    /// The decision list of one board.
    func boardDecisionList(key: String) -> [ManagerModel.BoardDecision] { ManagerModel.boardDecisions(state, key: key, data: data) }
    /// Approve (the shares vote, then it is carried out) or decline an item of the decision list by its `id`.
    @discardableResult
    mutating func decideBoardItem(id: String, approve: Bool) -> ManagerModel.BoardDecisionResult {
        guard let d = boardDecisionList().first(where: { $0.id == id }) else { return .gone }
        // Winding a company up is an engine action of its own; the board only puts it to the vote around it.
        if d.kind == "close" && approve {
            if let pct = ManagerModel.boardGate(state, kind: "close", companyID: d.companyID) {
                update { s, _, _ in ManagerModel.settleDecision(&s, d, approved: false) }
                return .voteFailed(pct)
            }
            let name = state.company(d.companyID)?.name ?? "The company"
            guard windUpCompany(companyID: d.companyID) else { return .refused("\(name) cannot be wound up now.") }
            update { s, _, _ in ManagerModel.settleDecision(&s, d, approved: true) }
            return .done("\(name) is wound up.")
        }
        var r = ManagerModel.BoardDecisionResult.gone
        update { s, dt, c in r = ManagerModel.decideBoardItem(&s, id: id, approve: approve, data: dt, context: c) }
        return r
    }
    /// Points waiting for you on one board (decision list plus unanswered emergencies); the number on the badges.
    func boardOpenDecisions(key: String) -> Int { ManagerModel.openDecisionCount(state, key: key, data: data) }
    /// Points waiting for you across every board.
    var boardDecisionsWaiting: Int { boardKeys.reduce(0) { $0 + boardOpenDecisions(key: $1) } }
    func boardFollowUps(key: String) -> [ManagerModel.FollowUp] { ManagerModel.followUps(state, key: key) }
    @discardableResult
    mutating func completeBoardFollowUp(key: String, id: Int) -> Bool { var ok = false; update { s, _, _ in ok = ManagerModel.completeFollowUp(&s, key: key, id: id) }; return ok }
    /// Answer an emergency meeting from its page; "hire" comes back when you now need to pick a manager.
    @discardableResult
    mutating func pickEmergency(key: String, meetingID: Int, option: Int) -> String? { var r: String?; update { s, d, _ in r = ManagerModel.pickEmergency(&s, key: key, meetingID: meetingID, option: option, data: d) }; return r }
    /// What the board and owners say to selling ("sell"), closing ("close") or a big loan ("loan").
    func boardVote(kind: String, companyID: Int, amount: Double = 0) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: kind, companyID: companyID, amount: amount) }
    mutating func recordPushedThrough(companyID: Int) { update { s, _, _ in ManagerModel.recordPushedThrough(&s, companyID: companyID) } }

    // MARK: Your right hand and the main office

    var rightHand: Headquarters.RightHand? { Headquarters.rightHand(state) }
    @discardableResult
    mutating func setRightHand(decidesForYou: Bool? = nil, briefing: String? = nil) -> SettingResult {
        applySetting(refuse: { Headquarters.rightHand($0) == nil ? "You have no right hand to set this for." : nil }, probe: { $0.rest["lh"] ?? .null }) { s, _, _ in Headquarters.setRightHand(&s, decidesForYou: decidesForYou, briefing: briefing) }
    }
    var officeTiers: [Headquarters.Tier] { Headquarters.tiers(data) }
    var officeTier: Headquarters.Tier? { Headquarters.tier(state, data) }
    var officeRoles: [Headquarters.Role] { Headquarters.roles(data) }
    var officeStaff: [JSONValue] { Headquarters.staff(state) }
    func officeRent(tier: Headquarters.Tier) -> Double { Headquarters.rent(state, tier: tier, cityID: state.rest["office"]?["city"].string ?? state.player.cityID, data: data) }
    func officeRoom(role: String) -> Headquarters.RoomResult { Headquarters.room(state, role: role, data: data) }
    func officeRoleResult(role: String) -> String { Headquarters.result(state, role: role, data: data) }
    var deskUse: Int { Headquarters.desksUsed(state) }
    var fame: Double { Headquarters.fame(state, data) }
    mutating func rentOffice(tier: String, cityID: String? = nil) -> Headquarters.RentResult {
        var r = Headquarters.RentResult.bad; update { s, d, _ in r = Headquarters.rentOffice(&s, tier: tier, cityID: cityID, data: d) }; return r
    }
    mutating func searchOffice(role: String, mode: Headquarters.SearchMode) -> [Person]? {
        var r: [Person]?; update { s, d, _ in r = Headquarters.search(&s, role: role, mode: mode, data: d) }; return r
    }
    mutating func hireOffice(role: String, personID: Int, monthlyWage: Double) -> Headquarters.HireResult {
        var r = Headquarters.HireResult.refuse; update { s, d, _ in r = Headquarters.hire(&s, role: role, personID: personID, monthlyWage: monthlyWage, data: d) }; return r
    }
    /// True when that person worked in the group office and has been let go.
    @discardableResult
    mutating func fireOffice(personID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Headquarters.fire(&s, personID: personID) }; return ok }
    @discardableResult
    mutating func tickOfficePaperwork(personID: Int, item: String) -> Bool { var ok = false; update { s, _, _ in ok = Headquarters.tickPaperwork(&s, personID: personID, item: item) }; return ok }
    func officePaperwork(personID: Int) -> [(key: String, text: String, done: Bool)] { Headquarters.paperwork(state, personID: personID) }
    mutating func setPerformanceAnalystAuto(_ on: Bool) { update { s, _, _ in Headquarters.setPerformanceAuto(&s, on) } }
    func managerScorecard(companyID: Int) -> Headquarters.Scorecard? { Headquarters.review(state, companyID: companyID) }
    @discardableResult
    mutating func runManagerScorecards() -> [Headquarters.Scorecard] { var r: [Headquarters.Scorecard] = []; update { s, d, _ in r = Headquarters.managerScorecards(&s, data: d) }; return r }
    @discardableResult
    mutating func requestAnalystReport(companyID: Int?) -> [ManagerModel.AnalystLine]? { var r: [ManagerModel.AnalystLine]?; update { s, d, _ in r = ManagerModel.analystReport(&s, companyID: companyID, data: d) }; return r }

    // MARK: Meetings with managers

    /// The manager brings proposals to the table as messages. Returns how many.
    @discardableResult
    mutating func meetForProposals(companyID: Int) -> Int? { var r: Int?; update { s, d, _ in r = ManagerModel.meetForProposals(&s, companyID: companyID, data: d) }; return r }
    var managersDueMeeting: [Company] { ManagerModel.managersDueMeeting(state) }
    func weeksSinceMeeting(companyID: Int) -> Int { state.company(companyID).map { ManagerModel.weeksSinceMeeting($0, week: state.week) } ?? 0 }
    mutating func setManagerDuty(companyID: Int, duty: String, manager: Bool) { update { s, _, _ in ManagerModel.setManagerDuty(&s, companyID: companyID, duty: duty, manager: manager) } }
    func personReport(companyID: Int, personID: Int) -> ManagerModel.PersonReport? { ManagerModel.personReport(state, companyID: companyID, personID: personID, data: data) }

    // MARK: Chains: money between stores, requests

    func groupLoanBalance(companyID: Int) -> Double { ManagerModel.groupLoanBalance(state, companyID: companyID) }
    /// Move money from a sister store as a group loan (what a boss does for a store that is short).
    @discardableResult
    mutating func lendFromSister(companyID: Int, amount: Double) -> Bool {
        var ok = false
        update { s, d, _ in if let co = s.company(companyID) { ok = ManagerModel.sisterCash(&s, to: co, need: amount, data: d) != nil } }
        return ok
    }

    // MARK: Academy

    func courses(companyID: Int) -> [Academy.Course] { state.company(companyID).map { Academy.courses(forTrade: $0.type) } ?? [] }
    func courseCost(_ c: Academy.Course, companyID: Int) -> Double { state.company(companyID).map { Academy.cost(c, company: $0, data: data, state: state) } ?? 0 }
    /// `staffID` 0 sends the owner.
    mutating func sendOnCourse(companyID: Int, staffID: Int, courseID: String) -> Academy.Outcome {
        var r = Academy.Outcome.unavailable; update { s, d, _ in r = Academy.send(&s, companyID: companyID, staffID: staffID, course: courseID, data: d) }; return r
    }

}
