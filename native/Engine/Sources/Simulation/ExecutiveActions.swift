import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {

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
    @discardableResult
    mutating func setTeamBudget(companyID: Int, budget: Budget) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in ManagerModel.setTeamBudget(&s, companyID: companyID, budget: budget) }
    }
    func decisionChain(companyID: Int) -> [ManagerModel.Boss] { state.company(companyID).map { ManagerModel.decisionChain(state, $0, data: data) } ?? [] }

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
    @discardableResult
    mutating func setExecutiveBudget(_ level: ManagerModel.ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, budget: Budget) -> SettingResult {
        applySetting(probe: { s in .array([.object(s.rest), Chains.chain(s, id: chainID ?? -1) ?? .null]) }) { s, _, _ in
            ManagerModel.setExecutiveBudget(&s, level: level, chainID: chainID, regionalID: regionalID, budget: budget)
        }
    }
    @discardableResult
    mutating func setGroupLimit(_ amount: Double) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, _, _ in ManagerModel.setGroupLimit(&s, amount: amount) }
    }
    var regionalManagers: [JSONValue] { ManagerModel.regionals(state) }
    var groupManagingDirector: JSONValue { state.rest["org56"]?["md"] ?? .null }
    var groupOfficeEstablished: Bool { Headquarters.established(state) }
    var groupOfficeEmployer: String { Headquarters.employerName(state, data) }
    var groupOfficeMonthlyCost: Double { Headquarters.monthlyCost(state, data) }

    var boardKeys: [String] { ManagerModel.boardKeys(state) }
    func boardKey(companyID: Int) -> String? { state.company(companyID).map { ManagerModel.boardKey(state, $0) } }
    func boardName(key: String) -> String { ManagerModel.boardName(state, key: key) }
    func boardIsActive(key: String) -> Bool { ManagerModel.boardActive(state, key: key) }
    func boardSeats(key: String) -> [ManagerModel.Seat] { ManagerModel.seats(state, key: key) }
    func boardVoters(key: String) -> [ManagerModel.Voter] { ManagerModel.voters(state, key: key) }
    func boardMeetings(key: String) -> [ManagerModel.BoardMeeting] { ManagerModel.meetings(state, key: key) }
    func boardDecisionList() -> [ManagerModel.BoardDecision] { ManagerModel.boardDecisions(state, data: data) }
    func boardDecisionList(key: String) -> [ManagerModel.BoardDecision] { ManagerModel.boardDecisions(state, key: key, data: data) }
    @discardableResult
    mutating func decideBoardItem(id: String, approve: Bool) -> ManagerModel.BoardDecisionResult {
        guard let d = boardDecisionList().first(where: { $0.id == id }) else { return .gone }
        return decideBoardPoint(d, approve: approve, attended: false)
    }

    private mutating func decideBoardPoint(_ d: ManagerModel.BoardDecision, approve: Bool, attended: Bool) -> ManagerModel.BoardDecisionResult {
        if d.kind == "close" && approve {
            if !attended, let pct = ManagerModel.boardGate(state, kind: "close", companyID: d.companyID) {
                update { s, _, _ in ManagerModel.settleDecision(&s, d, approved: false) }
                return .voteFailed(pct)
            }
            let name = state.company(d.companyID)?.name ?? "The company"
            guard windUpCompany(companyID: d.companyID) else { return .refused("\(name) cannot be wound up now.") }
            update { s, _, _ in ManagerModel.settleDecision(&s, d, approved: true) }
            return .done("\(name) is wound up.")
        }
        var r = ManagerModel.BoardDecisionResult.gone
        update { s, dt, c in r = ManagerModel.decide(&s, d, approve: approve, attended: attended, data: dt, context: c) }
        return r
    }

    func boardMeetingAgenda(keys: [String]) -> [ManagerModel.BoardDecision] { ManagerModel.meetingAgenda(state, keys: keys, data: data) }
    func boardMeetingGuests(_ points: [ManagerModel.BoardDecision]) -> [ManagerModel.Attendee] { ManagerModel.meetingGuests(state, points) }
    mutating func beginBoardMeeting(keys: [String]) { update { s, _, _ in for k in keys { ManagerModel.countMeeting(&s, key: k) } } }

    mutating func voteOnBoardPoint(key: String, id: String, yes: Bool) -> ManagerModel.MeetingRuling? {
        guard let d = ManagerModel.meetingDecisions(state, key: key, data: data).first(where: { $0.id == id }) else { return nil }
        let ballot = ManagerModel.ballot(state, key: key, d, youYes: yes)
        let v = ballot.verdict
        let subject = ManagerModel.meetingSubject(d, state)
        func ruling(_ kind: ManagerModel.MeetingRuling.Kind, _ detail: String = "", line: String? = nil) -> ManagerModel.MeetingRuling {
            ManagerModel.MeetingRuling(id: id, kind: kind, line: line ?? ManagerModel.rulingLine(subject: subject, ballot: ballot, kind: kind, detail: detail),
                                       yesPercent: v.yesPercent, noPercent: v.noPercent, attendees: ballot.attendees)
        }
        if v.blockedByAbsent { return ruling(.blocked, v.blockers.map { $0.name }.joined(separator: ", ")) }
        if !ballot.passes {
            update { s, _, _ in ManagerModel.settleDecision(&s, d, approved: false) }
            return ruling(.votedDown)
        }
        switch decideBoardPoint(d, approve: true, attended: true) {
        case .done: return ruling(.carried, ManagerModel.meetingDone(d.kind))
        case .refused(let why): return ruling(.refused, why)
        case .voteFailed(let pct):
            return ruling(.votedDown, line: "\(subject) rejected by the directors: \(pct)% for.")
        case .declined, .gone: return nil
        }
    }

    func boardOpenDecisions(key: String) -> Int { ManagerModel.openDecisionCount(state, key: key, data: data) }
    var boardDecisionsWaiting: Int { boardKeys.reduce(0) { $0 + boardOpenDecisions(key: $1) } }
    func boardFollowUps(key: String) -> [ManagerModel.FollowUp] { ManagerModel.followUps(state, key: key) }
    @discardableResult
    mutating func completeBoardFollowUp(key: String, id: Int) -> Bool { var ok = false; update { s, _, _ in ok = ManagerModel.completeFollowUp(&s, key: key, id: id) }; return ok }
    @discardableResult
    mutating func pickEmergency(key: String, meetingID: Int, option: Int) -> String? { var r: String?; update { s, d, _ in r = ManagerModel.pickEmergency(&s, key: key, meetingID: meetingID, option: option, data: d) }; return r }
    func boardVote(kind: String, companyID: Int, amount: Double = 0) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: kind, companyID: companyID, amount: amount) }
    mutating func recordPushedThrough(companyID: Int) { update { s, _, _ in ManagerModel.recordPushedThrough(&s, companyID: companyID) } }

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
    @discardableResult
    mutating func fireOffice(personID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Headquarters.fire(&s, personID: personID) }; return ok }
    @discardableResult
    mutating func setPerformanceAnalystAuto(_ on: Bool) { update { s, _, _ in Headquarters.setPerformanceAuto(&s, on) } }
    func managerScorecard(companyID: Int) -> Headquarters.Scorecard? { Headquarters.review(state, companyID: companyID) }
    @discardableResult
    mutating func runManagerScorecards() -> [Headquarters.Scorecard] { var r: [Headquarters.Scorecard] = []; update { s, d, _ in r = Headquarters.managerScorecards(&s, data: d) }; return r }
    @discardableResult
    mutating func requestAnalystReport(companyID: Int?) -> [ManagerModel.AnalystLine]? { var r: [ManagerModel.AnalystLine]?; update { s, d, _ in r = ManagerModel.analystReport(&s, companyID: companyID, data: d) }; return r }

    @discardableResult
    mutating func meetForProposals(companyID: Int) -> Int? { var r: Int?; update { s, d, _ in r = ManagerModel.meetForProposals(&s, companyID: companyID, data: d) }; return r }
    var managersDueMeeting: [Company] { ManagerModel.managersDueMeeting(state) }
    func weeksSinceMeeting(companyID: Int) -> Int { state.company(companyID).map { ManagerModel.weeksSinceMeeting($0, week: state.week) } ?? 0 }
    mutating func setManagerDuty(companyID: Int, duty: String, manager: Bool) { update { s, _, _ in ManagerModel.setManagerDuty(&s, companyID: companyID, duty: duty, manager: manager) } }
    func personReport(companyID: Int, personID: Int) -> ManagerModel.PersonReport? { ManagerModel.personReport(state, companyID: companyID, personID: personID, data: data) }


    func courses(companyID: Int) -> [Academy.Course] { state.company(companyID).map { Academy.courses(forTrade: $0.type) } ?? [] }
    func courseCost(_ c: Academy.Course, companyID: Int) -> Double { state.company(companyID).map { Academy.cost(c, company: $0, data: data, state: state) } ?? 0 }
    mutating func sendOnCourse(companyID: Int, staffID: Int, courseID: String) -> Academy.Outcome {
        var r = Academy.Outcome.unavailable; update { s, d, _ in r = Academy.send(&s, companyID: companyID, staffID: staffID, course: courseID, data: d) }; return r
    }

}
