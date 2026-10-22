import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Rivals with a strategy and a fortune: they fail, leave a gap, press on your demand, and nudge hiring and rate-sensitive trades.
final class RivalLifeTests: XCTestCase {
    private func game() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(3 * 7) { e.nextDay() }
        return (e, id)
    }

    func testNewRivalsGetAStrategyAndFortuneAndOldOnesGetDefaults() throws {
        var (e, id) = try game()
        e.update { s, _, _ in
            let co = s.company(id)!
            let rs = Rivals.rivals(s, for: co)
            XCTAssertFalse(rs.isEmpty)
            XCTAssertTrue(rs.allSatisfy { Rivals.strategies.contains($0.strategy) && $0.fortune > 0.5 })
            // an old record without the new fields still reads
            let old: JSONValue = .object(["id": 77, "name": "Old Co", "size": 1.0, "pm16": 1.0, "ig16": 1])
            XCTAssertTrue(Rivals.strategies.contains(Rivals.strategyOf(old)))
            XCTAssertEqual(Rivals.fortuneOf(old), 1)
            XCTAssertFalse(Rivals.traits(rs[0].strategy).strength.isEmpty)
            XCTAssertTrue(Ledger.gaps(s).isEmpty)
        }
    }

    func testStrongCheapRivalTakesCustomersAndAFailingOneReleasesThem() {
        func market(size: Double, price: Double, fort: Double) -> JSONValue {
            .object(["riv": .array([.object(["id": 1, "size": .number(size), "pm16": .number(price), "ig16": 1, "st": "cheap", "fort": .number(fort)])])])
        }
        let strong = Rivals.strengthFactor(market(size: 1.6, price: 0.85, fort: 1.5), week: 10)
        let average = Rivals.strengthFactor(market(size: 1.0, price: 1.0, fort: 1), week: 10)
        let failing = Rivals.strengthFactor(market(size: 1.0, price: 1.0, fort: -0.3), week: 10)
        XCTAssertLessThan(strong, average)
        XCTAssertGreaterThan(failing, average)
        XCTAssertEqual(average, 1, accuracy: 1e-9)
        XCTAssertTrue((0.88...1.1).contains(strong) && (0.88...1.1).contains(failing))
        XCTAssertEqual(Rivals.strengthFactor(.object([:]), week: 10), 1)
    }

    func testBrokeRivalExitsWithAMessageAndTheGapIsFilledOnlyAfterADelayByANewName() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let co = s.company(id)!, bd = data.catalog[co.type]!
            let k = Rivals.key(co)
            s.rest["mk"]![k]["n"] = 1
            s.rest["mk"]![k]["riv"] = .array([])
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            let first = Rivals.rivals(s, key: k)
            XCTAssertEqual(first.count, 1)
            let msgs = s.inbox.count
            Rivals.mutate(&s, key: k, id: first[0].id) { $0["fort"] = -1.4 }
            s.week = 52 * 3 + 1   // a new year
            Rivals.fortuneYear(&s, data: data)
            XCTAssertTrue(Rivals.rivals(s, key: k).isEmpty, "out of money, it closes")
            XCTAssertGreaterThan(s.inbox.count, msgs, "you are told")
            let m = s.rest["mk"]![k]
            XCTAssertTrue(Rivals.vacant(m, week: s.week))
            XCTAssertEqual(Rivals.strengthFactor(m, week: s.week), 1)
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            XCTAssertTrue(Rivals.rivals(s, key: k).isEmpty, "no instant replacement")
            s.week = Int(m["vac"].double) + 1
            let names = Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            XCTAssertEqual(names.count, 1)
            XCTAssertNotEqual(names.first, first[0].name)
            XCTAssertTrue(s.rest["mk"]![k]["vac"].isNull)
            XCTAssertTrue(Ledger.gaps(s).isEmpty)
        }
    }

    func testFortuneFollowsTheEconomyCycle() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let co = s.company(id)!
            let k = Rivals.key(co)
            func after(demand: Double) -> Double {
                var t = s
                t.economy.demand = demand
                t.week = 52 * 4 + 1
                let rid = Rivals.rivals(t, key: k)[0].id
                Rivals.mutate(&t, key: k, id: rid) { $0["fort"] = 1.0; $0["st"] = "cheap"; $0["g27"] = .null }
                Rivals.fortuneYear(&t, data: data)
                return Rivals.rivals(t, key: k).first { $0.id == rid }?.fortune ?? -9
            }
            XCTAssertGreaterThan(after(demand: 1.08), after(demand: 0.9))
        }
    }

    func testExpanderOpensInANearbyCityAndRaisesHiringCostThere() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let co = s.company(id)!
            let k = Rivals.key(co)
            guard let c = data.countries.city(co.cityID, preferring: co.countryCode) else { return XCTFail("no city") }
            let idx = c.country.cities.firstIndex { $0.id == co.cityID }!
            guard let other = c.country.cities.indices.first(where: { $0 != idx && abs($0 - idx) <= 3 }) else { return }
            let tk = co.type + "|" + c.country.cities[other].id
            s.rest["mk"]![tk] = s.rest["mk"]![k]
            let rid = Rivals.rivals(s, key: k)[0].id
            Rivals.mutate(&s, key: k, id: rid) { $0["st"] = "expander"; $0["fort"] = 2; $0["size"] = 1.3 }
            s.rest["mk"]![tk] = s.rest["mk"]![k]
            Rivals.mutate(&s, key: tk, id: rid) { $0["name"] = "Someone Else" }
            let before = Rivals.rivals(s, key: tk).count
            Rivals.expand(&s, key: k, id: rid, data: data)
            XCTAssertEqual(Rivals.rivals(s, key: tk).count, before + 1)
            XCTAssertTrue(Rivals.rivals(s, key: tk).contains { $0.name == Rivals.rivals(s, key: k)[0].name })
            XCTAssertTrue(Rivals.rivals(s, key: tk).map { $0.id }.count == Set(Rivals.rivals(s, key: tk).map { $0.id }).count)
            var other2 = co
            other2.cityID = c.country.cities[other].id
            XCTAssertEqual(Rivals.hiringPressure(s, other2), 1.05)
            XCTAssertEqual(Rivals.hiringPressure(s, co), 1)
        }
    }

    func testPolicyRateNudgesRateSensitiveTradesOnly() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let cafe = s.company(id)!
            var hi = s; hi.economy.policyRate = 0.10
            var lo = s; lo.economy.policyRate = 0.01
            let w1 = World(state: hi, data: data), w0 = World(state: lo, data: data)
            XCTAssertEqual(DemandModel.creditFactor(cafe, w1), 1)
            var car = cafe; car.type = "cardealer"
            XCTAssertLessThan(DemandModel.creditFactor(car, w1), 1)
            XCTAssertGreaterThan(DemandModel.creditFactor(car, w0), 1)
            XCTAssertTrue((0.96...1.03).contains(DemandModel.creditFactor(car, w1)))
        }
    }
}
