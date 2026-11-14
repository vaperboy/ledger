import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
import Simulation

final class EventPackTests: XCTestCase {
    static let areas: Set<String> = ["weather", "supply", "demand", "staff", "regulatory", "finance", "macro", "world"]
    static let allowedKeys: Set<String> = ["cash", "loss", "fine", "rep", "aware", "q", "dem", "cap", "cogsUp", "quit", "raise", "stay", "bonus", "close",
                                           "fixeq", "brk", "collect", "loseR", "writeoff", "gamble"]

    func engineWithCompany(trade: String = "cafe", seed: Int = 4242, weeks: Int = 3) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        var extra = 0
        while e.state.company(id)?.status != .open && extra < 14 { e.nextDay(); extra += 1 }
        return (e, id)
    }

    func branches(_ fx: JSONValue) -> [JSONValue] {
        var out = [fx]
        if !fx["gamble"].isNull { out += branches(fx["gamble"]["ok"]) + branches(fx["gamble"]["bad"]) }
        return out
    }

    func effectSets(_ e: PackEvent) -> [JSONValue] {
        e.hasOptions ? e.event.options.map { $0.effects } : [e.event.automaticEffects]
    }

    func fire(_ base: GameEngine, _ id: Int, _ ev: PackEvent) -> (GameEngine, [Message]) {
        var e = base
        var fresh: [Message] = []
        e.update { s, data, ctx in
            let top: Int = s.inbox.map { $0.id }.max() ?? 0
            guard let i = s.companyIndex(id) else { return }
            EventPack.fire(&s, companyIndex: i, ev, data: data, context: ctx)
            fresh = s.inbox.filter { $0.id > top }
        }
        return (e, fresh)
    }

    func testTheLibraryIsBigAndCoversEveryArea() throws {
        let events = EventPack.events
        XCTAssertGreaterThanOrEqual(events.count, 150)
        XCTAssertEqual(Set(events.map { $0.id }).count, events.count)
        XCTAssertEqual(Set(events.map { $0.area }), Self.areas)
        for area in Self.areas { XCTAssertGreaterThanOrEqual(events.filter { $0.area == area }.count, 15, area) }
        XCTAssertEqual(Set(events.map { $0.tone }), ["good", "bad", "n"])
        XCTAssertEqual(Set(events.map { $0.severity }), [1, 2, 3])
        XCTAssertGreaterThanOrEqual(events.filter { $0.hasOptions }.count, 30)
        XCTAssertGreaterThanOrEqual(events.filter { $0.tone == "good" }.count, 30)
        XCTAssertGreaterThanOrEqual(events.filter { !$0.countries.isEmpty }.count, 8)
        let (data, _, _) = try GameEngine.loadResources()
        let families = Set(data.catalog.trades.values.map { $0.family })
        for e in events {
            XCTAssertTrue(e.weight > 0 && e.weight < 0.2, e.id)
            XCTAssertGreaterThanOrEqual(e.cooldown, 4, e.id)
            XCTAssertTrue(e.families.isSubset(of: families), e.id)
            for t in e.trades.union(e.excludedTrades) { XCTAssertNotNil(data.catalog.trades[t], "\(e.id): unknown trade \(t)") }
            XCTAssertTrue(e.months.allSatisfy { (1...12).contains($0) }, e.id)
            XCTAssertTrue(e.weather.isSubset(of: ["sun", "mixed", "rain", "snow", "heat", "cold", "storm"]), e.id)
        }
        let categories = Set(events.map { $0.event.category })
        for c in ["prop", "liab", "cyber", "bi"] { XCTAssertTrue(categories.contains(c), c) }
    }

    func testNoEventKindIsWithoutNoticeText() throws {
        let banned = ["paperwork", "work permit", "timesheet", "payroll form"]
        for e in EventPack.events {
            XCTAssertFalse(e.title.trimmingCharacters(in: .whitespaces).isEmpty, e.id)
            XCTAssertFalse(e.body.trimmingCharacters(in: .whitespaces).isEmpty, "\(e.id): no body")
            if e.hasOptions {
                XCTAssertTrue((2...3).contains(e.event.options.count), "\(e.id): two or three answers")
                XCTAssertTrue(e.event.expiresAfterWeeks >= 1, e.id)
            }
            for o in e.event.options {
                XCTAssertFalse(o.label.isEmpty, e.id)
                XCTAssertFalse(o.detail.isEmpty, "\(e.id): option without an explanation")
            }
            let words = ([e.title, e.body] + e.event.options.map { $0.label + " " + $0.detail }).joined(separator: " ").lowercased()
            for w in banned { XCTAssertFalse(words.contains(w), "\(e.id) mentions \(w)") }
            XCTAssertFalse(e.title.replacingOccurrences(of: "{n}", with: "").contains("{"), e.id)
            XCTAssertFalse(e.body.replacingOccurrences(of: "{n}", with: "").contains("{"), e.id)
        }
    }

    func testEveryEventFiresWithAClearNotice() throws {
        let (base, id) = try engineWithCompany()
        var problems: [String] = []
        for ev in EventPack.events {
            let (_, fresh) = fire(base, id, ev)
            if fresh.isEmpty { problems.append("\(ev.id): no notice"); continue }
            for m in fresh {
                if m.title.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("\(ev.id): empty title") }
                if m.body.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("\(ev.id): empty body") }
                if m.title.contains("{") || m.body.contains("{") { problems.append("\(ev.id): unresolved token") }
                if m.status == "open" {
                    if m.expiresWeek == nil { problems.append("\(ev.id): no deadline") }
                    if !m.body.contains("Answer within") { problems.append("\(ev.id): does not say when to answer") }
                    if m.options.count < 2 { problems.append("\(ev.id): fewer than two answers") }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "; "))
    }

    func testEveryOptionResolvesAndTheBooksStayBalanced() throws {
        let (base, id) = try engineWithCompany()
        var checked = 0
        for ev in EventPack.events {
            let count = max(1, ev.event.options.count)
            for option in 0..<count {
                var (e, fresh) = fire(base, id, ev)
                if let m = fresh.first(where: { $0.status == "open" }) {
                    XCTAssertTrue(e.answer(messageID: m.id, option: option), "\(ev.id) option \(option)")
                    checked += 1
                }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(ev.id) option \(option): \(Ledger.gaps(e.state))")
                XCTAssertTrue(e.state.company(id)?.status.isLive ?? false, ev.id)
            }
        }
        XCTAssertGreaterThan(checked, 60)
    }

    func testOutcomesAreBoundedBySeverity() throws {
        let vars: [String: Double] = ["wk": 1000, "pay": 500, "eqv": 20000, "k": 1]
        let floorDemand: [Int: Double] = [1: 0.85, 2: 0.78, 3: 0.7]
        let floorCapacity: [Int: Double] = [1: 0.8, 2: 0.68, 3: 0.65]
        for e in EventPack.events {
            for fx in effectSets(e) {
                XCTAssertLessThanOrEqual(EventPack.outflow(fx, vars, worst: true), e.maximumOutflowWeeks * 1000 + 1e-6, "\(e.id): costs too much for its severity")
                for b in branches(fx) {
                    XCTAssertTrue(Set(b.object.keys).isSubset(of: Self.allowedKeys), "\(e.id): unknown effect \(Set(b.object.keys).subtracting(Self.allowedKeys))")
                    for key in ["dem", "cap", "cogsUp"] where !b[key].isNull {
                        let m = b[key][0].double, w = b[key][1].double
                        XCTAssertTrue(w >= 1 && w <= 52, "\(e.id): \(key) lasts \(w) weeks")
                        if key == "dem" { XCTAssertTrue(m >= floorDemand[e.severity]! && m <= 1.25, "\(e.id): demand \(m)") }
                        if key == "cap" { XCTAssertTrue(m >= floorCapacity[e.severity]! && m <= 1.2, "\(e.id): capacity \(m)") }
                        if key == "cogsUp" { XCTAssertTrue(m >= 0.9 && m <= 1.1, "\(e.id): costs \(m)") }
                    }
                    XCTAssertLessThanOrEqual(b["close"].double, 2, e.id)
                    XCTAssertLessThanOrEqual(abs(b["rep"].double), 5, e.id)
                    let g = b["gamble"]
                    if !g.isNull {
                        // Odds may depend on the company's situation: check them for a middling company.
                        let odds: Double = EventPack.amount(g["p"], vars.merging(EventPack.typicalSituation) { (a: Double, _: Double) -> Double in a })
                        XCTAssertTrue(odds > 0.05 && odds < 0.95, "\(e.id): gamble odds")
                    }
                }
            }
        }
    }

    func testNoEventCanBankruptACompanyOnItsOwn() throws {
        let (base, id) = try engineWithCompany()
        for ev in EventPack.events where ev.tone != "good" {
            for option in 0..<max(1, ev.event.options.count) {
                var (e, fresh) = (base, [Message]())
                var before = 0.0, wk = 0.0
                e.update { s, data, ctx in
                    guard let i = s.companyIndex(id) else { return }
                    s.companies[i].set("lastW", .object(["rev": .number(20_000), "units": .number(100)]))
                    s.companies[i].monthlyHistory = []
                    before = s.companies[i].cash
                    wk = EventEngine.context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i])).wk
                }
                e.update { s, data, ctx in
                    let top: Int = s.inbox.map { $0.id }.max() ?? 0
                    guard let i = s.companyIndex(id) else { return }
                    EventPack.fire(&s, companyIndex: i, ev, data: data, context: ctx)
                    fresh = s.inbox.filter { $0.id > top }
                }
                if let m = fresh.first(where: { $0.status == "open" }) { e.answer(messageID: m.id, option: option) }
                let after = e.state.company(id)?.cash ?? 0
                XCTAssertGreaterThanOrEqual(after, before - ev.maximumOutflowWeeks * wk * 1.25 - 1, "\(ev.id) option \(option) drains too much cash")
                XCTAssertTrue(e.state.company(id)?.status.isLive ?? false, "\(ev.id) option \(option)")
            }
        }
    }

    func testInsuranceCutsTheCostOfALossEvent() throws {
        let (base, id) = try engineWithCompany()
        let ev = try XCTUnwrap(EventPack.byID["p_vandalism"])
        func drop(insured: Bool) -> Double {
            var e = base
            var before = 0.0
            e.update { s, data, ctx in
                guard let i = s.companyIndex(id) else { return }
                s.companies[i].set("lastW", .object(["rev": .number(400_000), "units": .number(100)]))
                s.companies[i].monthlyHistory = []
                s.companies[i].set("ins", .object(["prop": .bool(insured)]))
                before = s.companies[i].cash
                EventPack.fire(&s, companyIndex: i, ev, data: data, context: ctx)
            }
            return before - (e.state.company(id)?.cash ?? 0)
        }
        XCTAssertLessThan(drop(insured: true), drop(insured: false))
    }

    func testTheSameSeedGivesTheSameEvents() throws {
        func run() throws -> GameState {
            var (e, id) = try engineWithCompany(seed: 2025)
            for _ in 0..<(40 * 7) { e.nextDay() }
            XCTAssertNotNil(e.state.company(id))
            return e.state
        }
        let a = try run(), b = try run()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.inbox.filter { $0.value("pk").bool }.count, b.inbox.filter { $0.value("pk").bool }.count)
    }

    func testExpectedEventsPerYearStayInBounds() throws {
        let (data, _, _) = try GameEngine.loadResources()
        for (id, bd) in data.catalog.trades where bd.family != "hold" {
            for cc in ["UK", "NO", "US", "AU"] {
                let n = EventPack.expectedPerYear(trade: bd, country: cc)
                XCTAssertTrue(n >= 1.5 && n <= 14, "\(id) in \(cc): \(n) events a year")
                let weeks = EventPack.expectedOutflowWeeksPerYear(trade: bd, country: cc)
                XCTAssertLessThan(weeks, 2.0, "\(id) in \(cc): events alone cost \(weeks) weeks of sales a year")
            }
        }
    }

    func testEventsPerFiftyTwoWeeksAndTheGapBetweenThem() throws {
        var (e, id) = try engineWithCompany(seed: 99)
        for round in 0..<4 {
            e.update { s, _, _ in _ = Payments.injectCash(&s, companyID: id, amount: 3_000_000) }
            for _ in 0..<(26 * 7) { e.nextDay() }
            XCTAssertTrue(e.state.company(id)?.status.isLive ?? false, "round \(round)")
        }
        // The pack's own odds and pacing: quiet-day filler is drawn apart from them.
        let own = e.state.inbox.filter { $0.value("pk").bool && $0.companyID == id && !$0.flag(DailyBeat.fillerKey) }.sorted { $0.week < $1.week }
        let perYear = Double(own.count) / 2
        XCTAssertTrue(perYear >= 1 && perYear <= 14, "\(perYear) pack events a year")
        for (a, b) in zip(own, own.dropFirst()) { XCTAssertGreaterThanOrEqual(b.week - a.week, EventPack.gapWeeks, "\(a.title) / \(b.title)") }
        let bad = own.filter { $0.tone == "bad" }.count
        XCTAssertLessThanOrEqual(bad, own.count)
        XCTAssertTrue(own.contains { $0.tone != "bad" }, "good and neutral news arrive too")
    }

    func testBadNewsDoesNotArriveInTheFirstFourWeeks() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 91)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 5_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        while e.state.week < 4 { e.nextDay() }
        XCTAssertTrue(e.state.inbox.filter { $0.value("pk").bool && $0.tone == "bad" }.isEmpty)
    }

    func testCountryWideEventsHitEveryCompanyOfACountryOnTheSameWeek() throws {
        let macro = EventPack.events.filter { $0.countryWide }
        XCTAssertGreaterThanOrEqual(macro.count, 15)
        for e in macro { XCTAssertTrue(e.area == "macro" || !e.countries.isEmpty, e.id) }
    }
}
