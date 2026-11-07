import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// Pins `Complaints.answer`, the one place a complaint is answered (the dead copy `Satisfaction.answerComplaint` is gone).
final class ComplaintAnswerTests: XCTestCase {
    private func run(_ answer: Satisfaction.Answer) throws -> (result: Bool?, again: Bool?, open: Int, gaps: Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else { throw XCTSkip("no cafe") }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("compl", .array([.object(["id": 5, "w": .number(Double(s.week)), "who": "A", "t": "Late.", "sev": 2, "st": "open"])]))
        }
        var r: Bool?; var r2: Bool?
        e.update { s, d, _ in
            r = Complaints.answer(&s, companyID: id, complaintID: 5, answer: answer, data: d)
            r2 = Complaints.answer(&s, companyID: id, complaintID: 5, answer: answer, data: d)
        }
        return (r, r2, e.openComplaints(companyID: id).count, Ledger.gaps(e.state).count)
    }

    func testRefundIsAlwaysSatisfiedAndBooksBalance() throws {
        let r = try run(.refund)
        XCTAssertEqual(r.result, true); XCTAssertNil(r.again); XCTAssertEqual(r.open, 0); XCTAssertEqual(r.gaps, 0)
    }
    func testIgnoreIsNeverSatisfied() throws {
        let r = try run(.ignore)
        XCTAssertEqual(r.result, false); XCTAssertNil(r.again); XCTAssertEqual(r.open, 0); XCTAssertEqual(r.gaps, 0)
    }
    func testSorryClosesTheComplaint() throws {
        let r = try run(.sorry)
        XCTAssertNotNil(r.result); XCTAssertNil(r.again); XCTAssertEqual(r.open, 0); XCTAssertEqual(r.gaps, 0)
    }
    func testUnknownComplaintIsNil() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        XCTAssertNil(e.answerComplaint(companyID: 999, complaintID: 1, answer: .refund))
    }
}
