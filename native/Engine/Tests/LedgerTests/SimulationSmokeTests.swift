import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import Employees

/// End-to-end: a whole game, started natively, played for months. Nothing may break the books.
final class SimulationSmokeTests: XCTestCase {
    func newEngine(_ country: String = "UK", seed: Int = 4242) throws -> GameEngine {
        try GameEngine.newGame(countryCode: country, playerName: "Tester", seed: seed)
    }

    func startCompany(_ e: inout GameEngine, trade: String, form: LegalForm = .limited, fund: Double = 0) throws -> Int {
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            let r = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: form, data: data, context: ctx)
            if case .success(let i) = r { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: form, size: s.company(id)?.size ?? 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + fund)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0)
        return id
    }

    func testNewGameStartsCorrectly() throws {
        let e = try newEngine()
        XCTAssertEqual(e.state.week, 0)
        XCTAssertEqual(e.state.loans.count, 1)
        XCTAssertEqual(e.state.cash, e.state.loans[0].balance, accuracy: 1)
        // Net worth is cash minus the start-up loan: exactly zero, and explainable from its parts.
        let nw = e.netWorth
        XCTAssertEqual(nw.personal, nw.debt, accuracy: 1)
        XCTAssertEqual(nw.total, 0, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testACafeRunsForHalfAYearWithoutBreakingTheBooks() throws {
        var e = try newEngine()
        let id = try startCompany(&e, trade: "cafe")
        var opened = false
        for _ in 0..<(26 * 7) {
            e.nextDay()
            if e.state.company(id)?.status == .open { opened = true }
            XCTAssertFalse(e.state.cash.isNaN)
            if e.state.isGameOver { break }
        }
        XCTAssertTrue(opened, "the company should open once its paperwork is approved")
        let gaps = Ledger.gaps(e.state)
        XCTAssertTrue(gaps.isEmpty, "cash must equal what was booked: \(gaps)")
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(co.cash.isNaN)
        XCTAssertGreaterThan(co.monthlyHistory.count, 3)
        XCTAssertGreaterThan(co.monthlyHistory.map { $0.revenue }.reduce(0, +), 0)
        XCTAssertEqual(e.state.week, 26)
    }

    func testEveryNativeFamilyRunsWithoutErrors() throws {
        for trade in ["barber", "boutique", "webdev", "bakery", "taxi", "gym", "cleaning", "courier", "hotel", "hardware", "physio", "brewery", "restaurant", "grocery", "kiosk"] {
            var e = try newEngine("DE", seed: 99)
            let id = try startCompany(&e, trade: trade, form: .limited, fund: 3_000_000)
            for _ in 0..<(10 * 7) { e.nextDay() }
            let gaps = Ledger.gaps(e.state)
            XCTAssertTrue(gaps.isEmpty, "\(trade): ledger gaps \(gaps)")
            let co = try XCTUnwrap(e.state.company(id), trade)
            XCTAssertFalse(co.cash.isNaN, trade)
            XCTAssertTrue([.open, .setup, .closed, .bust].contains(co.status), trade)
        }
    }
}

extension SimulationSmokeTests {
    /// Not a pass/fail test: prints average results over several seeds so they can be compared with the original game
    /// (tools/ref/snippets/stats_run.js). The numbers feed docs/BALANCE_PARITY.md.
    func testPrintStatisticsForComparison() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        let seeds = (0..<12).map { 1000 + $0 * 37 }
        for trade in ["cafe", "barber", "gym", "restaurant", "courier", "boutique", "webdev", "bakery"] {
            var rev = 0.0, n = 0.0, cashEnd = 0.0, opened = 0, bust = 0
            for sd in seeds {
                var e = try newEngine("UK", seed: sd)
                let id = try startCompany(&e, trade: trade)
                for _ in 0..<(26 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
                let co = try XCTUnwrap(e.state.company(id))
                if co.status == .bust { bust += 1 }
                if co.openedWeek != nil { opened += 1 }
                for h in co.monthlyHistory.suffix(5) { rev += h.revenue; n += 1 }
                cashEnd += co.cash
            }
            print("STAT \(trade) revPerMonth=\(Int(rev / max(1, n))) cashEnd=\(Int(cashEnd / Double(seeds.count))) bust=\(bust) opened=\(opened) months=\(Int(n))")
        }
    }
}

extension SimulationSmokeTests {
    func testPrintDetail() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        for trade in ["restaurant", "courier", "barber", "cafe"] {
            for sd in [1000, 1037, 1074, 1111] {
                var e = try newEngine("UK", seed: sd)
                let id = try startCompany(&e, trade: trade)
                for _ in 0..<(26 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
                let co = try XCTUnwrap(e.state.company(id))
                let lw = co.value("lastW")
                print("DETAIL \(trade) D=\(Int(lw["D"].double)) cap=\(Int(lw["cap"].double)) units=\(Int(lw["units"].double)) rev=\(Int(lw["rev"].double)) staff=\(co.staff.map { $0.role }.joined(separator: ",")) aware=\(Int(co.awareness)) rep=\(Int(co.reputation)) q=\(Int(co.quality)) size=\(co.size) status=\(co.status.rawValue) veh=\(co.value("veh").array.count) eq=\(co.value("eq").object.keys.sorted().joined(separator: ","))")
            }
        }
    }
}

extension SimulationSmokeTests {
    func testDebugHiring() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var e = try newEngine("UK", seed: 1000)
        var id = 0
        var log: [String] = []
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 3_000_000)
            log = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        do {
            let co = e.state.company(id)!
            let m = co.staff[0]; let n = e.state.people[m.id]!
            let odds = StaffWeek.quitOdds(family: "venue", tradeID: "cafe", staff: m, person: n, payGap: 0, tenure: 1, week: 1, hasHRManager: false, hasTeamLead: false)
            print("DEBUG odds=\(odds) wage=\(m.monthlyWage) ask=\(n.askingMonthlyWage) pers=\(n.str("pers")) fit=\(StaffWeek.fit(staff: m, tradeID: "cafe")) tired=\(m.tiredness) happy=\(m.happyUntilWeek)")
        }
        print("DEBUG log=\(log) staff=\(e.state.company(id)!.staff.count) people=\(e.state.people.count) size=\(e.state.company(id)!.size)")
        for d in 0..<(26 * 7) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if d % 7 == 6 {
                let co = e.state.company(id)!
                print("DEBUG week \(d / 7) staff=\(co.staff.count) status=\(co.status.rawValue) cash=\(Int(co.cash)) aware=\(Int(co.awareness)) payGap=\(co.num("payGap")) notes=\((e.state.rest["rep"]?["ev"].array ?? []).map { $0["t"].string }.joined(separator: " | ").prefix(300))")
            }
        }
    }
}

extension SimulationSmokeTests {
    func testStaffRate() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var kept = 0, n = 0
        var causes: [String: Int] = [:]
        for sd in 1...30 {
            var e = try newEngine("UK", seed: sd * 13)
            let id = try startCompany(&e, trade: "cafe")
            var sawLeave = false
            for _ in 0..<(26 * 7) {
                e.nextDay()
                for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                for ev in (e.state.rest["rep"]?["ev"].array ?? []) {
                    let t = ev["t"].string
                    if t.contains("left") || t.contains("quit") || t.contains("notice") { causes[String(t.prefix(40)), default: 0] += 1; sawLeave = true }
                }
            }
            _ = sawLeave
            n += 1
            if !(e.state.company(id)?.staff.isEmpty ?? true) { kept += 1 }
        }
        print("STAFFRATE kept=\(kept) of \(n) causes=\(causes.sorted { $0.value > $1.value }.prefix(6))")
    }
}
