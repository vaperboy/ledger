import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class LifeStoriesTests: XCTestCase {
    private func json(_ s: GameState) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(s)) }

    func testDefaultStoryIsTheStartUpLoanAndUnchanged() throws {
        let a = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        let b = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .loan)
        XCTAssertEqual(try json(a.state), try json(b.state))
        XCTAssertEqual(a.lifeStory, .loan)
        XCTAssertNil(a.state.rest["start"], "the default start writes nothing new, so older saves and goldens are unchanged")
        XCTAssertEqual(a.state.loans.count, 1)
        XCTAssertEqual(a.state.loans[0].kind, "start")
        XCTAssertEqual(a.state.cash, a.state.loans[0].balance)
        XCTAssertEqual(a.state.openingCash, a.state.cash)
        XCTAssertTrue(a.state.companies.isEmpty)
        XCTAssertTrue(Ledger.gaps(a.state).isEmpty)
    }

    func testHeirInSeveralCountries() throws {
        for cc in ["UK", "US", "NO", "MX", "PL"] {
            let e = try GameEngine.newGame(countryCode: cc, playerName: "T", seed: 3, story: .heir)
            XCTAssertEqual(e.lifeStory, .heir, cc)
            XCTAssertTrue(e.state.loans.isEmpty, "\(cc): no start-up loan record at all")
            XCTAssertEqual(e.state.companies.count, 1, cc)
            let co = try XCTUnwrap(e.state.companies.first)
            XCTAssertEqual(co.type, "cafe"); XCTAssertEqual(co.status, .open, cc)
            XCTAssertGreaterThanOrEqual(co.reputation, 60); XCTAssertGreaterThanOrEqual(co.awareness, 45); XCTAssertEqual(co.ownerHours, 25)
            XCTAssertGreaterThan(co.cash, 0, cc)
            let savings = e.homeCurrency.scaledPrice(50000)
            XCTAssertEqual(e.state.cash, savings, accuracy: 1, "\(cc): the owner keeps the savings only")
            XCTAssertEqual(e.state.credit, 62)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(cc) \(Ledger.gaps(e.state))")
            XCTAssertEqual(e.state.player.cityID, e.homeCountry.cities[0].id)
        }
    }

    func testHeirChoosesTheCafeCity() throws {
        let country = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3).homeCountry
        let other = try XCTUnwrap(country.cities.last)
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", cityID: other.id, seed: 3, story: .heir)
        XCTAssertEqual(e.state.companies[0].cityID, other.id)
        XCTAssertEqual(e.state.player.cityID, other.id)
    }

    func testPreviewComesFromTheEngine() throws {
        let loan = try XCTUnwrap(GameEngine.storyPreview(.loan, countryCode: "UK"))
        let ref = try GameEngine.newGame(countryCode: "UK", playerName: "x", seed: 1)
        XCTAssertEqual(loan.cash, ref.state.cash); XCTAssertEqual(loan.debt, ref.state.loans[0].balance)
        XCTAssertGreaterThan(loan.monthlyRepayment, 0); XCTAssertNil(loan.companyName)
        let heir = try XCTUnwrap(GameEngine.storyPreview(.heir, countryCode: "UK"))
        XCTAssertEqual(heir.debt, 0); XCTAssertNotNil(heir.companyName); XCTAssertGreaterThan(heir.companyValue, 0)
        XCTAssertLessThan(heir.cash, loan.cash)
    }

    func testSaveRoundTripAndPlayingOn() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 9, story: .heir)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(try json(back), try JSONDecoder().decode(JSONValue.self, from: data))
        XCTAssertEqual(back.rest["start"]?["story"].string, "heir")
        for _ in 0..<(7 * 6) { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertEqual(e.state.companies.first?.status, .open)
        XCTAssertEqual(e.lifeStory, .heir)
    }

    func testAffordabilityListBlocksNothing() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        let rows = e.tradeAffordability()
        XCTAssertEqual(rows.count, e.data.catalog.all.filter { !SpecialFamilies.isRetired($0) }.count, "every trade is listed except the retired ones")
        let funded = rows.filter { $0.isFunded }
        XCTAssertFalse(funded.isEmpty); XCTAssertLessThan(funded.count, rows.count)
        XCTAssertEqual(rows.prefix(funded.count).map { $0.tradeID }, funded.map { $0.tradeID })
        XCTAssertEqual(funded.compactMap { $0.cost }, funded.compactMap { $0.cost }.sorted())
        for r in funded { XCTAssertLessThanOrEqual(r.minimum ?? .infinity, Payments.liquid(e.state)); XCTAssertEqual(r.shortfall, 0) }
        let r = try XCTUnwrap(rows.first { !$0.isFunded && $0.blocked == nil })
        let t = try XCTUnwrap(e.data.catalog[r.tradeID])
        var probe = e.state; probe.cash += 1_000_000_000
        let city = e.homeCountry.cities[0]
        let est = try XCTUnwrap(CompanySetup.estimate(tradeID: t.id, cityID: city.id,
                                                      size: CompanySetup.recommendedSize(t, city: city), state: probe, data: e.data))
        XCTAssertEqual(r.cost, est.total)
        let least = est.documents + est.premisesLeast + est.property + est.wait + est.registration + est.shareCapital + est.abroad + est.requiredEquipmentUpfront + est.requiredVehicles
        XCTAssertEqual(least, est.minimumToOpen, accuracy: 0.01)
        XCTAssertEqual(r.shortfall, max(0, least - Payments.liquid(e.state)), accuracy: 0.01)
        var e2 = e
        let res = e2.startCompany(tradeID: r.tradeID, cityID: city.id)
        _ = res
    }

    func testEveryStoryStartsAndOpensTheFirstCompany() throws {
        for cc in ["NO", "UK", "US", "JP", "MX", "PL", "LT"] {
            for trade in ["cafe", "barber", "bakery"] {
                let e: GameEngine
                do {
                    e = try GameEngine.newGame(countryCode: cc, playerName: "T", seed: 7, story: .fresh, tradeID: trade, companyName: "Test Co")
                } catch {
                    XCTFail("\(cc) \(trade): could not start a fresh game: \(error)")
                    continue
                }
                let co = try XCTUnwrap(e.state.companies.first, "\(cc) \(trade)")
                XCTAssertEqual(e.state.companies.count, 1, "\(cc) \(trade)")
                XCTAssertEqual(co.status, .open, "\(cc) \(trade)")
                XCTAssertEqual(co.type, trade, "\(cc) \(trade)")
                XCTAssertEqual(co.cash, e.state.cash, accuracy: 0.01, "\(cc) \(trade): company cash mirrors the one account")
                XCTAssertGreaterThan(e.state.cash, 0, "\(cc) \(trade)")
            }
        }
    }

    func testEveryStoryStartsForSeveralCountries() throws {
        for cc in ["NO", "UK", "US", "JP", "MX", "PL", "LT"] {
            for story in LifeStory.allCases {
                let e: GameEngine
                do {
                    e = try GameEngine.newGame(countryCode: cc, playerName: "T", seed: 11, story: story, tradeID: story == .fresh ? "cafe" : nil, companyName: story == .fresh ? "Test Co" : nil)
                } catch {
                    XCTFail("\(cc) \(story): could not start a game: \(error)")
                    continue
                }
                XCTAssertEqual(e.lifeStory, story, "\(cc)")
                if story == .loan {
                    XCTAssertTrue(e.state.companies.isEmpty, "\(cc): the loan start has no company yet")
                    XCTAssertEqual(e.state.loans.count, 1, cc)
                } else {
                    XCTAssertEqual(e.state.companies.first?.status, .open, "\(cc) \(story): the first company is open")
                }
            }
        }
    }
}
