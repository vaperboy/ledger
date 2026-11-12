import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
import Simulation

final class DataDecisionTests: XCTestCase {
    static let allowedKeys: Set<String> = ["cash", "loss", "fine", "rep", "aware", "q", "dem", "cap", "cogsUp", "quit", "raise", "stay", "bonus", "close",
                                           "fixeq", "brk", "collect", "loseR", "writeoff", "gamble", "tied", "later"]

    func engineWithCompany(trade: String = "cafe", seed: Int = 777, weeks: Int = 8) throws -> (GameEngine, Int) {
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
        return (e, id)
    }

    func branches(_ fx: JSONValue) -> [JSONValue] {
        var out = [fx]
        if !fx["gamble"].isNull { out += branches(fx["gamble"]["ok"]) + branches(fx["gamble"]["bad"]) }
        return out
    }

    func testTheLibraryCoversEveryStageOfTheGame() throws {
        let specs = DataDecisions.specs
        XCTAssertGreaterThanOrEqual(specs.count, 35)
        XCTAssertEqual(Set(specs.map { $0.id }).count, specs.count)
        XCTAssertGreaterThanOrEqual(specs.filter { $0.stages.contains("start") }.count, 8)
        XCTAssertGreaterThanOrEqual(specs.filter { $0.stages.contains("grow") }.count, 15)
        XCTAssertGreaterThanOrEqual(specs.filter { $0.stages.contains("est") }.count, 8)
        XCTAssertGreaterThanOrEqual(specs.filter { $0.isTrap }.count, 3)
        for id in ["d_firstorder", "d_festival_shift", "d_lease_expand", "d_rival_talks", "d_sponsor_team", "d_partner_exit", "d_lobby", "d_big_contract"] {
            XCTAssertNotNil(specs.first { $0.id == id }, id)
        }
        let mine = Set(specs.map { $0.id })
        XCTAssertEqual(StrategicDecisions.definitions.filter { mine.contains($0.id) }.count, specs.count, "every data decision is part of the library once")
        for spec in specs {
            XCTAssertFalse(spec.stages.isEmpty, spec.id)
            if spec.minNetWorth > 0 { XCTAssertFalse(spec.stages.contains("start"), "\(spec.id): big-company decisions do not reach new firms") }
            if spec.minWeeklyRevenue >= 5000 { XCTAssertFalse(spec.stages.contains("start"), spec.id) }
        }
    }

    func testEveryChoiceIsBoundedAndHonest() throws {
        let base: [String: Double] = ["wk": 1000, "pay": 500, "eqv": 20000, "k": 1, "staff": 5, "yr": 52000]
        for spec in DataDecisions.specs {
            XCTAssertTrue((2...3).contains(spec.choices.count), "\(spec.id): two or three options")
            XCTAssertTrue(spec.choices.indices.contains(spec.defaultChoice), spec.id)
            XCTAssertFalse(spec.title.isEmpty, spec.id)
            XCTAssertFalse(spec.body.isEmpty, spec.id)
            var vars = base
            for v in spec.variables { vars[v.name] = Formula(v.expression).evaluate(vars) }
            for (n, c) in spec.choices.enumerated() {
                XCTAssertFalse(c.label.isEmpty, spec.id)
                XCTAssertFalse(c.detail.isEmpty, "\(spec.id) option \(n): no explanation")
                var cost = EventPack.outflow(c.effects, vars, worst: true)
                for later in c.effects["later"].array { cost += EventPack.outflow(later["fx"], vars, worst: true) }
                XCTAssertLessThanOrEqual(cost, 10_000, "\(spec.id) option \(n) costs more than ten weeks of sales")
                if n == spec.defaultChoice {
                    XCTAssertLessThanOrEqual(EventPack.outflow(c.effects, vars, worst: true), 600, "\(spec.id): the default must be cheap")
                    XCTAssertEqual(c.effects["close"].double, 0, spec.id)
                }
                for b in branches(c.effects) {
                    XCTAssertTrue(Set(b.object.keys).isSubset(of: Self.allowedKeys), "\(spec.id): unknown effect \(Set(b.object.keys).subtracting(Self.allowedKeys))")
                    let g = b["gamble"]
                    if !g.isNull { XCTAssertTrue(g["p"].double > 0.05 && g["p"].double < 0.95, "\(spec.id): odds") }
                }
                let sure = EventPack.amount(c.effects["cash"], vars)
                if sure > 0 { XCTAssertTrue(!c.effects["gamble"].isNull || !c.effects["later"].array.isEmpty, "\(spec.id) option \(n): money with no risk") }
            }
        }
    }

    func testEveryPromptShowsItsOddsAndCosts() throws {
        let (base, id) = try engineWithCompany()
        var prompts = 0
        for spec in DataDecisions.specs {
            var e = base
            var asked: Message? = nil
            e.update { s, data, ctx in
                guard let i = s.companyIndex(id) else { return }
                _ = StrategicDecisions.fire(&s, DataDecisions.definition(spec), companyIndex: i, data: data, context: ctx)
                asked = s.inbox.first { $0.actionID == StrategicDecisions.action && $0.status == "open" }
            }
            let m = try XCTUnwrap(asked, spec.id)
            prompts += 1
            XCTAssertFalse(m.title.isEmpty, spec.id)
            XCTAssertFalse(m.body.isEmpty, spec.id)
            XCTAssertFalse(m.title.contains("{") || m.body.contains("{"), "\(spec.id): unresolved token")
            XCTAssertEqual(m.options.count, spec.choices.count, spec.id)
            XCTAssertNotNil(m.expiresWeek, spec.id)
            for (n, c) in spec.choices.enumerated() {
                let text = m.options[n]["d"].string
                XCTAssertFalse(text.contains("{"), "\(spec.id) option \(n): unresolved token")
                if !c.effects["gamble"].isNull { XCTAssertTrue(text.contains("%"), "\(spec.id) option \(n): odds are not shown") }
                if c.effects["cash"].double != 0 || !c.effects["cash"]["expr"].isNull && c.effects["cash"]["expr"].string.hasPrefix("-") {
                    XCTAssertTrue(text.contains("Costs"), "\(spec.id) option \(n): cost is not shown")
                }
            }
            XCTAssertEqual(StrategicDecisions.defaultOption(of: m), spec.defaultChoice, spec.id)
        }
        XCTAssertEqual(prompts, DataDecisions.specs.count)
    }

    func testEveryOptionResolvesAndLaterOutcomesKeepTheBooksBalanced() throws {
        let (base, id) = try engineWithCompany()
        for spec in DataDecisions.specs {
            for option in 0..<spec.choices.count {
                var e = base
                var asked: Message? = nil
                e.update { s, data, ctx in
                    guard let i = s.companyIndex(id) else { return }
                    _ = StrategicDecisions.fire(&s, DataDecisions.definition(spec), companyIndex: i, data: data, context: ctx)
                    asked = s.inbox.first { $0.actionID == StrategicDecisions.action && $0.status == "open" }
                }
                let m = try XCTUnwrap(asked, spec.id)
                XCTAssertTrue(e.answer(messageID: m.id, option: option), "\(spec.id) option \(option)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(spec.id) option \(option): \(Ledger.gaps(e.state))")
                e.update { s, data, ctx in
                    s.week += 40
                    StrategicDecisions.weekly(&s, data: data, context: ctx)
                }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(spec.id) option \(option) later: \(Ledger.gaps(e.state))")
                XCTAssertTrue(e.state.company(id)?.status.isLive ?? false, spec.id)
            }
        }
    }

    func testAnUnansweredDecisionTakesItsDefaultAndNeverRuinsTheCompany() throws {
        for spec in DataDecisions.specs.prefix(12) {
            var (e, id) = try engineWithCompany(weeks: 6)
            e.update { s, data, ctx in
                guard let i = s.companyIndex(id) else { return }
                _ = StrategicDecisions.fire(&s, DataDecisions.definition(spec), companyIndex: i, data: data, context: ctx)
            }
            XCTAssertEqual(e.openDecisions.filter { $0.actionID == StrategicDecisions.action }.count, 1, spec.id)
            for _ in 0..<(8 * 7) { e.nextDay() }
            let done = e.state.inbox.first { $0.actionID == StrategicDecisions.action && $0.value("data")["id"].string == spec.id }
            XCTAssertEqual(done?.status, "done", spec.id)
            XCTAssertEqual(done?.value("pick").int, spec.defaultChoice, spec.id)
            XCTAssertTrue(e.state.company(id)?.status.isLive ?? false, spec.id)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, spec.id)
        }
    }

    func testBigCompanyDecisionsAreGatedBySizeAndStage() throws {
        let (base, id) = try engineWithCompany()
        var e = base
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("lastW", .object(["rev": .number(100), "units": .number(10)]))
            s.companies[i].monthlyHistory = []
            let co = s.companies[i]
            for id in ["d_partner_exit", "d_big_contract", "d_pension", "d_brand_licence", "d_cost_consultant"] {
                let spec = DataDecisions.specs.first { $0.id == id }!
                XCTAssertFalse(DataDecisions.applies(spec, s, co, data), "\(id) must not reach a small company")
            }
        }
    }

    func testOnlyOneDecisionPerCompanyAtATimeAndAGapBetweenThem() throws {
        let (base, id) = try engineWithCompany(weeks: 10)
        var e = base
        e.update { s, data, ctx in
            guard let i = s.companyIndex(id) else { return }
            let first = DataDecisions.specs[0]
            XCTAssertTrue(StrategicDecisions.fire(&s, DataDecisions.definition(first), companyIndex: i, data: data, context: ctx))
            let strat = StrategicDecisions.definitions.filter { $0.cls == "strat" }
            XCTAssertFalse(StrategicDecisions.fireOne(&s, from: strat, companyIndex: i, data: data, context: ctx), "a decision is already waiting")
            XCTAssertTrue(StrategicDecisions.companyBusy(s, s.companies[i]))
            for k in s.inbox.indices where s.inbox[k].actionID == StrategicDecisions.action && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
            XCTAssertTrue(StrategicDecisions.companyBusy(s, s.companies[i]), "a few weeks must pass before the next one")
            s.week += DataDecisions.companyGapWeeks
            XCTAssertFalse(StrategicDecisions.companyBusy(s, s.companies[i]))
        }
    }

    func testDecisionsInALongGameAreSparseAndSpaced() throws {
        var (e, id) = try engineWithCompany(seed: 31, weeks: 3)
        for _ in 0..<4 {
            e.update { s, _, _ in _ = Payments.injectCash(&s, companyID: id, amount: 3_000_000) }
            for _ in 0..<(26 * 7) { e.nextDay() }
        }
        let followUps: Set<String> = ["g_location", "t_antitrust"]
        let asks = e.state.inbox.filter { $0.actionID == StrategicDecisions.action && $0.companyID == id && !followUps.contains($0.value("data")["id"].string) }.sorted { $0.week < $1.week }
        XCTAssertLessThanOrEqual(asks.count, 104 / DataDecisions.companyGapWeeks + 1)
        for (a, b) in zip(asks, asks.dropFirst()) { XCTAssertGreaterThanOrEqual(b.week - a.week, DataDecisions.companyGapWeeks, "\(a.title) / \(b.title)") }
        for m in asks where m.status == "open" { XCTAssertNotNil(m.expiresWeek) }
    }

    func testTheSameSeedGivesTheSameDecisions() throws {
        func run() throws -> [String] {
            var (e, id) = try engineWithCompany(seed: 515, weeks: 3)
            for _ in 0..<(60 * 7) { e.nextDay() }
            return e.state.inbox.filter { $0.actionID == StrategicDecisions.action && $0.companyID == id }.map { "\($0.week):\($0.title)" }
        }
        XCTAssertEqual(try run(), try run())
    }

    func testDelegatesTakeTheSafeDefault() throws {
        let (base, id) = try engineWithCompany()
        var e = base
        var asked: Message? = nil
        e.update { s, data, ctx in
            guard let i = s.companyIndex(id) else { return }
            let spec = DataDecisions.specs.first { $0.id == "d_seo_promise" }!
            _ = StrategicDecisions.fire(&s, DataDecisions.definition(spec), companyIndex: i, data: data, context: ctx)
            asked = s.inbox.first { $0.actionID == StrategicDecisions.action && $0.status == "open" }
        }
        let m = try XCTUnwrap(asked)
        XCTAssertEqual(StrategicDecisions.defaultOption(of: m), 2, "saying no to a doubtful pitch is the default")
    }
}
