import XCTest
@testable import Events
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Startups, funding, private equity, listing, the big meeting and the owners of a company run, and the books still balance.
final class VenturesTests: XCTestCase {
    func engine() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 91)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(8 * 7) { e.nextDay() }
        return (e, id)
    }

    func testStartupsFundingPrivateEquityAndShares() throws {
        var (e, id) = try engine()
        guard case .ok(let sid) = e.foundStartup(name: "Testly", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 1) else { return XCTFail("founding") }
        XCTAssertEqual(e.foundedStartups.count, 1)
        _ = e.pitchStartupRound(startupID: sid)
        e.changeBuilders(startupID: sid, by: 1)
        _ = e.putMoneyIntoStartup(startupID: sid, amount: 100_000)
        e.update { s, d, _ in _ = Startups.pitches(&s, data: d) }
        let pitches = e.startupPitchesOnOffer
        XCTAssertEqual(pitches.count, 3)
        XCTAssertEqual(e.investInStartup(pitchID: pitches[0].id, amount: pitches[0].raise), .ok)
        let offers = e.privateEquityOffers()
        XCTAssertEqual(offers.count, 4)
        XCTAssertEqual(e.commitToFund(offerID: offers[2].id, amount: offers[2].minimum), .ok)
        if case .offers = e.pitchToInvestors(companyID: id, amount: 500_000) { XCTAssertTrue(e.acceptFundingOffer(companyID: id, index: 0)) }
        _ = e.sellPrivateShares(companyID: id, percent: 10, mode: "secondary")
        XCTAssertTrue(e.listSharesForSale(companyID: id, percent: 10, broker: true))
        e.setDividendPolicy(companyID: id, policy: "low")
        for _ in 0..<(60 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        _ = e.shutDownStartup(startupID: sid)   // nil when it already failed or exited
        XCTAssertFalse(e.foundedStartups[0].live)
        XCTAssertNotNil(Trophies.entries(e.state).first { $0.id == "su1" }?.reachedWeek)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
