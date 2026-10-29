import XCTest
@testable import Events
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The strategic decisions, selling a company, trophies, awards and the rich list run, and the books still balance.
final class DecisionsTests: XCTestCase {
    func engineWithCompany(trade: String = "cafe", weeks: Int = 0) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 777)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func testEveryDecisionCanBeFiredAndAnsweredWithBalancedBooks() throws {
        let (base, id) = try engineWithCompany(weeks: 8)
        XCTAssertGreaterThan(StrategicDecisions.definitions.count, 60)
        var fired = 0
        for def in StrategicDecisions.definitions {
            for option in 0..<max(1, def.opts.count) {
                var e = base
                var asked: Message? = nil
                e.update { s, data, ctx in
                    guard let i = s.companyIndex(id) else { return }
                    if StrategicDecisions.fire(&s, def, companyIndex: i, data: data, context: ctx) { fired += 1 }
                    asked = s.inbox.first { $0.actionID == StrategicDecisions.action && $0.status == "open" }
                }
                if let m = asked { XCTAssertTrue(e.answer(messageID: m.id, option: option), def.id) }
                e.update { s, data, ctx in StrategicDecisions.weekly(&s, data: data, context: ctx) }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(def.id) option \(option): \(Ledger.gaps(e.state))")
            }
        }
        XCTAssertGreaterThan(fired, 40)
    }

    func testAnUnansweredDecisionTakesItsDefault() throws {
        var (e, id) = try engineWithCompany(weeks: 6)
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            _ = StrategicDecisions.fire(&s, StrategicDecisions.byID["s_burnout"]!, companyIndex: i, data: data, context: ctx)
        }
        XCTAssertEqual(e.openDecisions.filter { $0.actionID == StrategicDecisions.action }.count, 1)
        for _ in 0..<(5 * 7) { e.nextDay() }
        XCTAssertTrue(e.openDecisions.filter { $0.actionID == StrategicDecisions.action }.isEmpty)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSellingACompany() throws {
        var (e, id) = try engineWithCompany(weeks: 10)
        e.update { s, _, _ in XCTAssertTrue(CompanySale.startListing(&s, companyID: id, broker: true)) }
        var offer: CompanySale.Offer? = nil
        for _ in 0..<(40 * 7) where offer == nil {
            e.nextDay()
            offer = CompanySale.listing(e.state, companyID: id)?.offers.first
        }
        let o = try XCTUnwrap(offer, "a broker finds a buyer within 40 weeks")
        let cashBefore = e.state.cash
        e.update { s, data, ctx in XCTAssertNotNil(CompanySale.accept(&s, companyID: id, offerID: o.id, data: data, context: ctx)) }
        XCTAssertEqual(e.state.company(id)?.status, .sold)
        XCTAssertNotEqual(e.state.cash, cashBefore)
        XCTAssertNil(CompanySale.listing(e.state, companyID: id))
        XCTAssertEqual(e.state.stats.companiesSold, 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTrophiesAwardsAndTheRichList() throws {
        var (e, _) = try engineWithCompany(weeks: 70)
        let got = Trophies.entries(e.state).filter { $0.reachedWeek != nil }
        XCTAssertFalse(got.isEmpty, "some trophy (first customer, first employee ...) is reached in 70 weeks")
        XCTAssertGreaterThan(Trophies.entries(e.state).count, 50)
        e.update { s, data, ctx in
            let st = RichList.standing(s, data: data, context: ctx)
            XCTAssertEqual(st.top.count, 10)
            XCTAssertGreaterThan(st.top[0].wealth, st.top[9].wealth)
        }
        XCTAssertFalse(Awards.years(e.state).isEmpty, "the year end passed, so the awards were held")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
