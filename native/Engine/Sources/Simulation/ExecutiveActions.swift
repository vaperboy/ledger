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
    mutating func setTeamAuthority(companyID: Int, level: Int? = nil, buy: Double? = nil) { update { s, _, _ in ManagerModel.setTeamAuthority(&s, companyID: companyID, level: level, buy: buy) } }
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
    mutating func setExecutiveAuthority(_ level: ManagerModel.ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, authority: Int? = nil, buy: Double? = nil) {
        update { s, _, _ in ManagerModel.setExecutiveAuthority(&s, level: level, chainID: chainID, regionalID: regionalID, authority: authority, buy: buy) }
    }
    mutating func releaseGroupCEO() { update { s, _, _ in ManagerModel.releaseGroupCEO(&s) } }
    /// Deals above this amount always come to you.
    mutating func setGroupLimit(_ amount: Double) { update { s, _, _ in ManagerModel.setGroupLimit(&s, amount: amount) } }
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
    func boardCandidates(key: String) -> [Person] { ManagerModel.board(state, key: key)["cands"].array.compactMap { state.people[$0.int] } }
    var seatRoles: [ManagerModel.SeatRole] { ManagerModel.seatRoles }
    mutating func setBoardMode(key: String, regular: Bool? = nil, quarterly: Bool? = nil) { update { s, _, _ in ManagerModel.setBoardMode(&s, key: key, regular: regular, quarterly: quarterly) } }
    mutating func searchForSeat(key: String, role: String) -> [Person]? {
        var r: [Person]?; update { s, d, _ in r = ManagerModel.searchForSeat(&s, key: key, role: role, data: d) }; return r
    }
    mutating func fillSeat(key: String, personID: Int, monthlyFee: Double) -> ManagerModel.SeatResult {
        var r = ManagerModel.SeatResult.bad; update { s, _, _ in r = ManagerModel.fillSeat(&s, key: key, personID: personID, monthlyFee: monthlyFee) }; return r
    }
    mutating func removeFromBoard(key: String, personID: Int) { update { s, _, _ in ManagerModel.removeFromBoard(&s, key: key, personID: personID) } }
    @discardableResult
    mutating func holdBoardMeeting(key: String) -> Int? { var r: Int?; update { s, d, _ in r = ManagerModel.holdBoardMeeting(&s, key: key, data: d) }; return r }
    @discardableResult
    mutating func decideMeetingItem(key: String, meetingID: Int, item: Int, approve: Bool) -> ManagerModel.ItemResult {
        var r = ManagerModel.ItemResult.gone; update { s, d, _ in r = ManagerModel.decideMeetingItem(&s, key: key, meetingID: meetingID, item: item, approve: approve, data: d) }; return r
    }
    /// Answer an emergency meeting from its page; "hire" comes back when you now need to pick a manager.
    @discardableResult
    mutating func pickEmergency(key: String, meetingID: Int, option: Int) -> String? { var r: String?; update { s, d, _ in r = ManagerModel.pickEmergency(&s, key: key, meetingID: meetingID, option: option, data: d) }; return r }
    /// What the board and owners say to selling ("sell"), closing ("close") or a big loan ("loan").
    func boardVote(kind: String, companyID: Int, amount: Double = 0) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: kind, companyID: companyID, amount: amount) }
    mutating func recordPushedThrough(companyID: Int) { update { s, _, _ in ManagerModel.recordPushedThrough(&s, companyID: companyID) } }

    // MARK: Your right hand and the main office

    var rightHand: Headquarters.RightHand? { Headquarters.rightHand(state) }
    mutating func setRightHand(decidesForYou: Bool? = nil, briefing: String? = nil) { update { s, _, _ in Headquarters.setRightHand(&s, decidesForYou: decidesForYou, briefing: briefing) } }
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
    mutating func fireOffice(personID: Int) { update { s, _, _ in Headquarters.fire(&s, personID: personID) } }
    mutating func tickOfficePaperwork(personID: Int, item: String) { update { s, _, _ in Headquarters.tickPaperwork(&s, personID: personID, item: item) } }
    func officePaperwork(personID: Int) -> [(key: String, text: String, done: Bool)] { Headquarters.paperwork(state, personID: personID) }
    mutating func toggleOfficeAssignment(role: String, companyID: Int) { update { s, _, _ in Headquarters.toggleAssignment(&s, role: role, companyID: companyID) } }
    mutating func setReports(frequency: Int? = nil, detail: String? = nil, only: String? = nil) { update { s, _, _ in Headquarters.setReports(&s, frequency: frequency, detail: detail, only: only) } }
    mutating func setPerformanceAnalystAuto(_ on: Bool) { update { s, _, _ in Headquarters.setPerformanceAuto(&s, on) } }
    func managerScorecard(companyID: Int) -> Headquarters.Scorecard? { Headquarters.review(state, companyID: companyID) }
    @discardableResult
    mutating func runManagerScorecards() -> [Headquarters.Scorecard] { var r: [Headquarters.Scorecard] = []; update { s, d, _ in r = Headquarters.managerScorecards(&s, data: d) }; return r }
    @discardableResult
    mutating func requestAnalystReport(companyID: Int?) -> [ManagerModel.AnalystLine]? { var r: [ManagerModel.AnalystLine]?; update { s, d, _ in r = ManagerModel.analystReport(&s, companyID: companyID, data: d) }; return r }

    // MARK: Meetings with managers

    var meetingGoals: [(key: String, label: String)] { ManagerModel.meetingGoals }
    var meetingTones: [(key: String, label: String)] { ManagerModel.meetingTones }
    /// Meet one manager (companyID) or all managers (nil) about one thing in a tone. Original: `callMeeting`.
    mutating func callMeeting(companyID: Int?, goal: String, tone: String) -> ManagerModel.MeetingResult {
        var r = ManagerModel.MeetingResult.none; let m = marketing; update { s, d, _ in r = ManagerModel.callMeeting(&s, companyID: companyID, goal: goal, tone: tone, data: d, marketing: m) }; return r
    }
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
