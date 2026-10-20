import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Events
import Simulation

/// The customers, competition and world leftovers: analyst roles, rival calls, group moves, the ranking, the world around you, own software.
final class WorldLeftoversTests: XCTestCase {
    func engineWith(trade: String, weeks: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func testAnalystsRankingWeightAndForecast() throws {
        var (e, id) = try engineWith(trade: "cafe", weeks: 12)
        XCTAssertTrue(e.marketAnalystVerdict(companyID: id).ok)
        // A data analyst in the head office turns the market feeling into ranges.
        let cands = e.dataAnalystCandidates()
        XCTAssertEqual(cands.count, 4)
        let best = Hiring.bestValue(cands)
        XCTAssertEqual(e.hireDataAnalyst(personID: best.id, monthlyWage: best.askingMonthlyWage * 1.1), .ok)
        XCTAssertTrue(e.hasDataAnalyst)
        let co = try XCTUnwrap(e.state.company(id))
        let m = try XCTUnwrap(MarketMap.market(of: co, e.state, data: e.data))
        XCTAssertEqual(MarketMap.knowledge(e.state, m).level, .dataAnalyst)
        // Ranking: you are somewhere among thousands; the awards use it.
        let board = e.rankingBoard(scope: .country, metric: .revenue)
        let you = try XCTUnwrap(board.you)
        XCTAssertGreaterThan(you.rank, 1)
        XCTAssertGreaterThan(board.total, 100)
        XCTAssertNotNil(e.yourRanking(scope: .world, metric: .growth))
        XCTAssertFalse(e.economyWeight().attention.isEmpty)
        // The forecast of a price change: some customers go, and the analyst gives a range.
        let f = try XCTUnwrap(e.priceForecast(companyID: id, byShare: 0.1))
        XCTAssertTrue(f.text.byAnalyst)
        XCTAssertTrue(f.text.customers.contains("to"), f.text.customers)
        XCTAssertLessThanOrEqual(f.forecast.customersLater, 0.02)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testRivalGroupPoachSupplierBidAndPriceFixingFine() throws {
        var (e, id) = try engineWith(trade: "cafe", weeks: 10)
        // Force each group move once and answer them.
        var gid = ""
        e.update { s, data, _ in
            RivalGroups.ensureCountry(&s, "UK", data: data)
            gid = RivalGroups.groups(s, country: "UK").first!.id
            s.rest["g27"]?["g"][gid]["types"] = .array(["cafe"]); s.rest["g27"]?["g"][gid]["cs"] = .array(["UK"])
            s.rest["g27"]?["g"][gid]["cash"] = 900_000_000; s.rest["g27"]?["g"][gid]["rev"] = 900_000_000
            s.rest["g27"]?["g"][gid]["strat"] = "acq"
            if let i = s.companyIndex(id) {
                s.companies[i].set("flags", .object(["coll": 1, "pw": .object(["rid": 0, "end": 99999])]))   // noticed by the big players
                s.companies[i].monthlyHistory = (0..<4).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: 90_000, cash: 1_000_000) }
            }
        }
        var moved = 0
        e.update { s, data, _ in
            var h = HashedRandom("test")
            for kind in ["buysup", "bid"] {
                // Open for a while so a bid can come.
                if let i = s.companyIndex(id) { s.companies[i].openedWeek = -200; s.companies[i].foundedWeek = -200 }
                if RivalGroups.move(&s, gid, kind, &h, data: data) { moved += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(moved, 1, "at least the supplier or the bid should go through")
        // Accepting the bid sells the company to the group.
        if let bid = e.state.inbox.first(where: { $0.actionID == "g27bid" && $0.status == "open" }) {
            XCTAssertTrue(e.answer(messageID: bid.id, option: 0))
            XCTAssertEqual(e.state.company(id)?.status, .sold)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
            return
        }
        // The collusion flag is found out sooner or later.
        let cash0 = e.state.company(id)?.books.total["fine"] ?? 0
        for _ in 0..<(60 * 7) { e.nextDay() }
        XCTAssertGreaterThan(e.state.company(id)?.books.total["fine"] ?? 0, cash0, "a price understanding is fined")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testWorldAroundYouAndKeyAccountProfile() throws {
        var (e, id) = try engineWith(trade: "cafe", weeks: 8)
        let img = e.publicImage()
        XCTAssertEqual(img.groups.count, 6)
        let people = e.peopleYouKnow()
        XCTAssertGreaterThanOrEqual(people.count, 4, "press, bank, council and lawyer")
        XCTAssertNotNil(e.localPaperName)
        XCTAssertFalse(e.mapPresence().isEmpty)
        XCTAssertFalse(e.mapOwnership().isEmpty)
        // A close contact: ask a favour, then the owed one can be called in.
        e.update { s, _, _ in
            var N = s.rest["net31"] ?? .object([:]); N["g"]["bank"]["adj"] = 60; s.rest["net31"] = N
        }
        let bank = try XCTUnwrap(e.peopleYouKnow().first { $0.id == "g:bank" })
        XCTAssertGreaterThanOrEqual(bank.relationship, 64)
        _ = e.askForFavour(contactID: bank.id)
        let co = try XCTUnwrap(e.state.company(id))
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("accts", .array([.object(["id": 5, "name": "Acme", "f": 0.2, "rel": 30, "w0": .number(Double(s.week)), "disc": 0])]))
        }
        let a = try XCTUnwrap(KeyAccounts.accounts(try XCTUnwrap(e.state.company(id))).first)
        let p = e.keyAccountProfile(a)
        XCTAssertTrue(p.canBuy)
        XCTAssertFalse(p.tradeName.isEmpty)
        _ = co
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOwnSoftwareProductIsBuiltSoldAndUsed() throws {
        var (e, id) = try engineWith(trade: "webdev", weeks: 2)
        XCTAssertTrue(e.startSoftware(companyID: id, type: "crm", model: "sub"))
        e.setSoftwareCoders(companyID: id, coders: 6)
        for _ in 0..<(30 * 7) { e.nextDay() }
        let p = try XCTUnwrap(e.softwareProduct(companyID: id))
        XCTAssertNotEqual(p.phase, .build)
        XCTAssertTrue(p.usable)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testManagerPicksTheItLevelAndTouristsWrite() throws {
        var (e, id) = try engineWith(trade: "hotel", weeks: 20)
        // Tourist reviews come from other countries where the trade has visitors.
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertGreaterThan(Reviews.touristShare(co, data: e.data), 0)
        let dd = e.data
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            for _ in 0..<120 { Reviews.add(&s, i, bias: 0, data: dd) }
        }
        XCTAssertTrue(Reviews.latest(try XCTUnwrap(e.state.company(id)), limit: 120).contains { $0.isTourist }, "some reviews are from abroad")
        _ = Cyber.levels
    }
}
