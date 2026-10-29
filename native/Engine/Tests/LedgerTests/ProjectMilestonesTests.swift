import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// The milestone read model of the Projects tab agrees with the project boards it is read from.
final class ProjectMilestonesTests: XCTestCase {
    func testNoProjectCompaniesGivesNothing() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        XCTAssertTrue(e.projectTimelines().isEmpty)
    }

    private func check(_ trade: String, years: Int) throws -> [ProjectTimeline] {
        let (_, e, id) = try ProjectTradeTests.play(trade, seed: 7, years: years)
        let board = try XCTUnwrap(e.projectBoard(companyID: id))
        let lines = e.projectTimelines().filter { $0.companyID == id }
        let jobs = lines.filter { $0.kind == .job || $0.kind == .event }
        let devs = lines.filter { $0.kind == .development }
        XCTAssertEqual(jobs.count, board.jobs.count + board.queuedJobs.count, trade)
        XCTAssertEqual(devs.count, board.developments.count, trade)
        XCTAssertEqual(lines.filter { $0.kind == .tender }.count, board.tenders.filter { $0.qualifies && $0.myBid == nil }.count, trade)
        for l in lines {
            XCTAssertFalse(l.stages.isEmpty, l.title)
            XCTAssertFalse(l.ifLate.isEmpty, l.title)
            XCTAssertLessThanOrEqual(l.stages.filter { $0.state == .current }.count, 1, l.title)
            // A stage after the current one is never marked done.
            if let c = l.stages.firstIndex(where: { $0.state == .current }) {
                XCTAssertTrue(l.stages[(c + 1)...].allSatisfy { $0.state == .upcoming }, l.title)
            }
            if let p = l.progress { XCTAssertTrue((0...1).contains(p), l.title) }
        }
        for j in jobs {
            let row = (board.jobs + board.queuedJobs).first { "j\(id)-\($0.id)" == j.id }
            XCTAssertEqual(j.value, row?.value)
            XCTAssertEqual(j.receivedSoFar, row?.paid)
            XCTAssertEqual(j.delayed, row?.held)
        }
        for d in devs {
            let row = try XCTUnwrap(board.developments.first { "d\(id)-\($0.id)" == d.id })
            XCTAssertEqual(d.delayed, row.delayWeeks > 0)
            XCTAssertEqual(d.stages.first { $0.name == "Selling" }?.detail, "\(row.sold) of \(row.units) units sold")
            XCTAssertGreaterThanOrEqual(d.costBudget ?? 0, row.land + row.build)
            XCTAssertGreaterThanOrEqual(d.costSoFar ?? -1, row.land)
            XCTAssertLessThanOrEqual(d.costSoFar ?? 0, (d.costBudget ?? 0) * 1.0001)
        }
        return lines
    }

    func testBuilderTimelinesMatchTheBoard() throws { _ = try check("construction", years: 1) }
    func testEventAgencyTimelinesMatchTheBoard() throws { _ = try check("event", years: 1) }
    func testDeveloperTimelinesMatchTheBoard() throws {
        let lines = try check("realdev", years: 2)
        XCTAssertTrue(lines.contains { $0.kind == .development }, "a developer with a manager should have a development under way")
    }
}
