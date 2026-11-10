import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class RealRivalsTests: XCTestCase {
    private func game() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(6 * 7) { e.nextDay() }
        return (e, id)
    }

    private func cityName(_ co: Company, _ data: GameData) -> String {
        data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? ""
    }

    func testPlayerCompaniesInTheTradeAndCityComeFirstAndComputerRivalsStayOut() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let co = s.company(id)!, bd = data.catalog[co.type]!
            let k = Rivals.key(co), city = cityName(co, data)
            s.rest["mk"]![k]["n"] = 4
            s.rest["mk"]![k]["riv"] = .array([])
            RealRivals.set(&s, [RealCompany(name: "Brooks Cafe", owner: "Daniel Brooks", trade: bd.name, city: city, countryCode: co.countryCode, size: 1.2),
                                RealCompany(name: "Elsewhere Cafe", owner: "Sam Other", trade: bd.name, city: "Nowhere", countryCode: co.countryCode),
                                RealCompany(name: "Brooks Dental", owner: "Daniel Brooks", trade: "Dental clinic", city: city, countryCode: co.countryCode)])
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            let rs = Rivals.rivals(s, key: k)
            XCTAssertEqual(rs.map { $0.name }, ["Brooks Cafe"], "only the player's company, no computer filler")
            XCTAssertEqual(rs.first?.owner, "Daniel Brooks")
            XCTAssertEqual(rs.first?.size ?? 0, 1.2, accuracy: 1e-9)
            RivalGroups.assign(&s, key: k, type: co.type, countryCode: co.countryCode, data: data)
            XCTAssertNil(Rivals.rivals(s, key: k).first?.groupID, "a player's company never belongs to a computer group")
        }
    }

    func testEmptyWorldGetsComputerRivalsWithFullNamesAndNoMark() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let co = s.company(id)!, bd = data.catalog[co.type]!
            let k = Rivals.key(co)
            s.rest["mk"]![k]["n"] = 3
            s.rest["mk"]![k]["riv"] = .array([])
            RealRivals.set(&s, [RealCompany(name: "Elsewhere Cafe", owner: "Sam Other", trade: bd.name, city: "Nowhere", countryCode: co.countryCode)])
            Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
            let rs = Rivals.rivals(s, key: k)
            XCTAssertEqual(rs.count, 3)
            for r in rs {
                XCTAssertTrue(r.owner.contains(" "), "first and last name: \(r.owner)")
                XCTAssertFalse(r.name.lowercased().contains("simulat") || r.name.lowercased().contains("computer"))
                XCTAssertFalse(r.owner.lowercased().contains("simulat") || r.owner.lowercased().contains("computer"))
            }
        }
    }

    func testTheSameInputGivesTheSameRivals() throws {
        func names() throws -> [String] {
            var (e, id) = try game()
            var out: [String] = []
            e.update { s, data, _ in
                let co = s.company(id)!, bd = data.catalog[co.type]!
                let k = Rivals.key(co)
                s.rest["mk"]![k]["n"] = 4
                s.rest["mk"]![k]["riv"] = .array([])
                RealRivals.set(&s, [RealCompany(name: "A Cafe", owner: "A One", trade: bd.name, city: cityName(co, data), countryCode: co.countryCode),
                                    RealCompany(name: "B Cafe", owner: "B Two", trade: bd.name, city: cityName(co, data), countryCode: co.countryCode)])
                Rivals.ensure(&s, key: k, trade: bd, countryCode: co.countryCode, data: data)
                out = Rivals.rivals(s, key: k).map { $0.name + "|" + $0.strategy + "|\($0.priceFactor)" }
            }
            return out
        }
        let a = try names(), b = try names()
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a, b)
    }

    func testPlayerCompaniesAreRowsOnTheLeaderboard() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let co = s.company(id)!, bd = data.catalog[co.type]!
            RealRivals.set(&s, [RealCompany(name: "Hoffmann Cafe", owner: "Lea Hoffmann", trade: bd.name, city: "Nowhere", countryCode: co.countryCode, size: 1.3)])
            let board = CompanyRanking.board(s, data: data, scope: .world, metric: .revenue)
            let rows = board.entries.filter { $0.name == "Hoffmann Cafe" }
            XCTAssertEqual(rows.count, 1)
            XCTAssertFalse(rows.first?.isYou ?? true)
            XCTAssertGreaterThan(rows.first?.revenue ?? 0, 0)
        }
    }

    func testRepliesComeAfterAHumanDelayInsideWakingHours() {
        let sent = Date(timeIntervalSince1970: 1_800_000_000)
        for n in 1...40 {
            let id = String(format: "p%02d", n)
            for cc in ["NO", "UK", "US", "JP"] {
                let p = PlayerRhythm.profile(id: id)
                let at = PlayerRhythm.replyTime(id: id, countryCode: cc, sentAt: sent)
                XCTAssertGreaterThanOrEqual(at.timeIntervalSince(sent), Double(p.minDelay), "never at once: \(id)")
                let local = Int(at.timeIntervalSince1970) + PlayerRhythm.utcOffset(cc) * 3600
                let hour = (local % 86400) / 3600
                XCTAssertTrue(hour >= p.startHour && hour < p.endHour, "\(id) \(cc) answers at \(hour):xx")
                XCTAssertEqual(at, PlayerRhythm.replyTime(id: id, countryCode: cc, sentAt: sent), "deterministic")
            }
        }
    }

    func testPlayersDoNotAllKeepTheSameHoursOrPace() {
        let kinds = Set((1...40).map { (n: Int) -> String in
            let p = PlayerRhythm.profile(id: String(format: "p%02d", n))
            return "\(p.startHour)-\(p.endHour)-\(p.minDelay)"
        })
        XCTAssertGreaterThan(kinds.count, 4)
    }
}
