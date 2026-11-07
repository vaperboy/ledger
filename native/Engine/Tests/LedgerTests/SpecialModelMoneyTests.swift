import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Audit part 3b: the special models' money. One seeded game per model, a year of play: the ledger has no gaps, the weekly reports add up to
/// the books of every company, and the holding earns no VAT on its own interest.
final class SpecialModelMoneyTests: XCTestCase {
    /// Play whole weeks, freezing the books at the end of the last day of the last week (just before it is reported).
    private func play(_ e: inout GameEngine, weeks: Int) -> [Int: [String: Double]] {
        var frozen: [Int: [String: Double]] = [:]
        for _ in 0..<weeks {
            while e.state.day != 6 && !e.state.isGameOver { e.nextDay(); answer(&e) }
            frozen = Dictionary(e.state.companies.map { ($0.id, $0.books.total) }, uniquingKeysWith: { a, _ in a })
            e.nextDay(); answer(&e)
            if e.state.isGameOver { break }
        }
        return frozen
    }
    private func answer(_ e: inout GameEngine) { for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }

    /// Gaps empty after a year; the last 26 weekly reports add up to the books of each company (all since the start of the game).
    private func check(_ e: inout GameEngine, _ name: String) throws {
        let frozen = play(&e, weeks: 26)
        let weeks = e.reports(.week)
        XCTAssertEqual(weeks.count, 26, name)
        var sum = ReportPnL()
        for w in weeks { sum = sum + w.group.pnl }
        var books = ReportPnL()
        for (_, b) in frozen { books = books + ReportPnL(booksDelta: b) }
        XCTAssertEqual(sum.revenue, books.revenue, accuracy: 0.5, "\(name) revenue")
        XCTAssertEqual(sum.costs, books.costs, accuracy: 0.5, "\(name) costs")
        XCTAssertEqual(sum.tax, books.tax, accuracy: 0.5, "\(name) tax")
        for (id, b) in frozen {
            let mine = weeks.compactMap { $0.company(id) }.reduce(ReportPnL()) { $0 + $1.pnl }
            XCTAssertEqual(mine.revenue, b["rev"] ?? 0, accuracy: 0.5, "\(name) company \(id) revenue")
            XCTAssertEqual(mine.profitBeforeTax, Books.profit(b), accuracy: 0.5, "\(name) company \(id) profit")
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(name) after 26 weeks: \(Ledger.gaps(e.state))")
        _ = play(&e, weeks: 26)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(name) after a year: \(Ledger.gaps(e.state))")
    }

    private func oneTrade(_ trade: String, country: String = "NO", extra: Double = 300_000_000, seed: Int = 5) throws {
        var e = try SpecialTradesTests.engine(country, seed: seed)
        let id = SpecialTradesTests.start(&e, trade, extra: extra)
        XCTAssertNotEqual(id, 0, trade)
        try check(&e, trade)
    }

    func testProjectContractorYear() throws { try oneTrade("construction", country: "UK") }
    func testProjectDeveloperYear() throws { try oneTrade("realdev", country: "UK", extra: 2_000_000_000) }
    func testRentalYear() throws { try oneTrade("resrent", country: "UK", extra: 500_000_000) }
    func testBankYear() throws { try oneTrade("bank", country: "UK", extra: 2_000_000_000) }
    func testInsuranceYear() throws { try oneTrade("insco", country: "UK", extra: 1_000_000_000) }
    func testFundYear() throws { try oneTrade("fund", country: "UK", extra: 1_000_000_000) }
    func testPowerYear() throws { try oneTrade("power", extra: 500_000_000) }
    func testSalmonYear() throws { try oneTrade("salmon", extra: 200_000_000) }

    func testFootballClubYear() throws {
        var e = try SpecialTradesTests.engine("NO", seed: 11)
        guard case .ok(let id) = e.foundClub(countryCode: "NO") else { return XCTFail("club not founded") }
        XCTAssertNotNil(e.state.company(id))
        try check(&e, "club")
    }

    func testHoldingYearAndNoVATOnItsOwnInterest() throws {
        var e = try SpecialTradesTests.engine("UK", seed: 9)
        let cafe = SpecialTradesTests.start(&e, "cafe")
        guard case .success(let hid) = e.createHolding(name: "Money Holding", companies: [cafe]) else { return XCTFail("holding") }
        e.update { s, _, _ in Payments.injectCash(&s, companyID: hid, amount: 50_000_000) }
        try check(&e, "holding")
        let h = try XCTUnwrap(e.state.company(hid))
        XCTAssertEqual(h.vatBalance, 0, accuracy: 0.01, "interest on a holding's cash is not a VATable sale")
        XCTAssertTrue(h.receivables.isEmpty, "interest is paid at once, not invoiced")
    }
}
