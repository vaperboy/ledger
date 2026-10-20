import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class ExecutivesBoardsTests: XCTestCase {
    func testActionsRunAndBooksBalance() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        var ids: [Int] = []
        for _ in 0..<2 {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 6_000_000) else { return XCTFail("start") }
            ids.append(id)
        }
        // academy
        let c = e.courses(companyID: ids[0])
        XCTAssertFalse(c.isEmpty)
        _ = e.sendOnCourse(companyID: ids[0], staffID: 0, courseID: c[0].id)
        // office, right hand, hiring
        XCTAssertEqual(e.rentOffice(tier: "small"), .ok)
        if let cands = e.searchOffice(role: "pa", mode: .agency), let n = cands.first {
            _ = e.hireOffice(role: "pa", personID: n.id, monthlyWage: n.askingMonthlyWage * 1.1)
        }
        // board and meetings
        let key = e.boardKey(companyID: ids[0])!
        _ = e.searchForSeat(key: key, role: "director")
        _ = e.holdBoardMeeting(key: key)
        _ = e.requestAnalystReport(companyID: nil)
        _ = e.callMeeting(companyID: nil, goal: "review", tone: "casual")
        _ = e.boardVote(kind: "sell", companyID: ids[0])
        _ = e.teamSlots(companyID: ids[0])
        _ = e.searchExecutive(.md)
        _ = e.decisionChain(companyID: ids[0])
        _ = e.setDividendPolicy(companyID: ids[0], policy: "mid")
        _ = e.runManagerScorecards()
        for _ in 0..<30 { e.nextDay(); _ = e.nextDay() }
        for _ in 0..<60 { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
