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
            // The reference script (tools/ref/snippets/stats_run.js) asks for the estimate at size 1, whatever size the company has.
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: form, size: 1, state: s, data: data)
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
        let base = Int(ProcessInfo.processInfo.environment["LEDGER_SEED0"] ?? "1000")!, step = Int(ProcessInfo.processInfo.environment["LEDGER_STEP"] ?? "37")!
        let seeds = (0..<12).map { base + $0 * step }
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
        for trade in ["restaurant", "gym", "bakery", "cafe"] {
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

extension SimulationSmokeTests {
    /// Prints the books after 26 weeks, for comparison with tools/ref/snippets/books_cafe.js.
    func testPrintBooks() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        for trade in ["cafe", "gym", "restaurant"] {
            var e = try newEngine("UK", seed: 1000)
            let id = try startCompany(&e, trade: trade)
            let afterSetup = e.state.company(id)!.cash
            for _ in 0..<(26 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
            let co = e.state.company(id)!
            print("BOOKS \(trade) cashAfterSetup=\(Int(afterSetup)) cashEnd=\(Int(co.cash)) staff=\(co.staff.count) books=\(co.books.total.mapValues { Int($0) }.sorted { $0.key < $1.key })")
        }
    }
}

extension SimulationSmokeTests {
    func testPrintSetup() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        for trade in ["cafe", "gym"] {
            var e = try newEngine("UK", seed: 1000)
            var id = 0
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 50_000_000, why: "Test funds")
                if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
                let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: s.company(id)!.size, state: s, data: data)!
                print("SETUP \(trade) size=\(s.company(id)!.size) est=\(est)")
                Payments.injectCash(&s, companyID: id, amount: est.total * 1.6)
                let before = s.company(id)!.cash
                let log = CompanySetup.quickSetup(&s, companyID: id, data: data)
                let co = s.company(id)!
                print("SETUP \(trade) before=\(Int(before)) after=\(Int(co.cash)) log=\(log) eq=\(co.value("eq").object.mapValues { $0["n"].double * 0 + $0["cost"].double }.mapValues { Int($0) }) prem=\(co.value("prem")) inv=\(co.inventory)")
            }
        }
    }
}

extension SimulationSmokeTests {
    func testPrintAwareness() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var e = try newEngine("UK", seed: 1000)
        let id = try startCompany(&e, trade: "cafe")
        for d in 0..<(26 * 7) {
            e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if d % 7 == 6, (d / 7) % 5 == 0 || d / 7 == 25 {
                let co = e.state.company(id)!
                print("AWARE week=\(e.state.week) aware=\(String(format: "%.1f", co.awareness)) aw23=\(co.num("aw23")) rating=\(Pricing.rating(co)) rep=\(Int(co.reputation)) q=\(Int(co.quality)) opened=\(String(describing: co.openedWeek))")
            }
        }
    }
}

extension SimulationSmokeTests {
    /// Averages of demand, capacity, units, staff and mood over weeks 13-26, for tools/ref/snippets/stats_parts.js.
    func testPrintParts() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        let seeds = (0..<12).map { 1000 + $0 * 37 }
        for trade in ["cafe", "gym", "restaurant", "bakery"] {
            var acc: [String: Double] = [:]; var n = 0.0
            for sd in seeds {
                var e = try newEngine("UK", seed: sd)
                let id = try startCompany(&e, trade: trade)
                for d in 0..<(26 * 7) {
                    e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                    if d % 7 == 6, d / 7 >= 12 {
                        let co = e.state.company(id)!; let lw = co.value("lastW")
                        acc["D", default: 0] += lw["D"].double; acc["cap", default: 0] += lw["cap"].double; acc["units", default: 0] += lw["units"].double
                        acc["rev", default: 0] += lw["rev"].double; acc["staff", default: 0] += Double(co.staff.count); acc["rep", default: 0] += co.reputation
                        acc["q", default: 0] += co.quality; acc["aware", default: 0] += co.awareness; n += 1
                    }
                }
            }
            print("PARTS \(trade) " + acc.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.1f", $0.value / n))" }.joined(separator: " "))
        }
    }
}

extension SimulationSmokeTests {
    func testPrintGymStaff() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        for k in 0..<8 {
            var e = try newEngine("UK", seed: 1000 + k * 37)
            let id = try startCompany(&e, trade: "gym")
            var row = [e.state.company(id)!.staff.map { String($0.role.prefix(1)) }.joined()]
            for d in 0..<(26 * 7) {
                e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                if d % 7 == 6, [3, 12, 25].contains(d / 7) { row.append(e.state.company(id)!.staff.map { String($0.role.prefix(1)) }.joined()) }
            }
            print("GYMSTAFF " + row.joined(separator: " | "))
        }
    }
}

extension SimulationSmokeTests {
    func testPrintQuitProbe() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var n = 0.0, odds = 0.0, gap = 0.0, fit = 0.0, tired = 0.0
        var gapNew = 0.0, nNew = 0.0
        StaffRoutine.probe = { g, o, t, f, ten in n += 1; odds += o; gap += g; tired += t; fit += f; if ten < 6 { gapNew += g; nNew += 1 } }
        defer { StaffRoutine.probe = nil }
        for k in 0..<12 {
            var e = try newEngine("UK", seed: 1000 + k * 37)
            _ = try startCompany(&e, trade: "gym")
            for _ in 0..<(26 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        }
        print("QUITPROBE newhires n=\(nNew) gap=\(gapNew / max(1, nNew))")
        print("QUITPROBE n=\(n) odds=\(odds / n) gap=\(gap / n) fit=\(fit / n) tired=\(tired / n)")
    }
}

extension SimulationSmokeTests {
    func testPrintMessageTally() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var tally: [String: Int] = [:]
        for k in 0..<12 {
            var e = try newEngine("UK", seed: 1000 + k * 37)
            _ = try startCompany(&e, trade: "gym")
            var seen = Set<Int>()
            for _ in 0..<(26 * 7) {
                e.nextDay()
                for m in e.state.inbox where !seen.contains(m.id) {
                    seen.insert(m.id)
                    let key = m.title.replacingOccurrences(of: #"[A-Z][a-z]+ [A-Z][a-z]+"#, with: "NAME", options: .regularExpression)
                        .replacingOccurrences(of: #"[0-9][0-9 ,.]*"#, with: "N", options: .regularExpression)
                    tally[String(key.prefix(60)), default: 0] += 1
                }
                for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            }
        }
        for (k, v) in tally.sorted(by: { $0.value > $1.value }).prefix(24) { print("MSG \(v) \(k)") }
    }
}

extension SimulationSmokeTests {
    func testPrintDemandParts() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var acc: [String: Double] = [:]; var n = 0.0
        for k in 0..<12 {
            var e = try newEngine("UK", seed: 1000 + k * 37)
            let id = try startCompany(&e, trade: "gym")
            for _ in 0..<(26 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
            let co = e.state.company(id)!
            let w = World(state: e.state, data: e.data)
            let r = DemandModel.compute(co, e.data.catalog["gym"]!, w)
            for p in r.parts { acc[p.name, default: 0] += p.value }
            acc["D", default: 0] += r.customers; n += 1
        }
        print("GYMPARTS " + acc.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.3f", $0.value / n))" }.joined(separator: " "))
    }
}

extension SimulationSmokeTests {
    func testPrintAskRatio() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var e = try newEngine("UK", seed: 5)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "gym", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
        }
        for role in ["trainer", "recept"] {
            var ratios: [Double] = [], skills: [Double] = [], asks: [Double] = [], mkt = 0.0
            for _ in 0..<60 {
                let cs = e.searchWorkers(companyID: id, role: role, mode: .network)
                let co = e.state.company(id)!
                let w = World(state: e.state, data: e.data)
                let base = e.data.catalog.tables.roles[role]!.baseMonthlyWage
                mkt = Wages.market(baseMonthlyWage: base, country: w.country(co), city: w.city(co)!, economy: e.state.economy, week: e.state.week, rates: w.rates)
                for c in cs { ratios.append(c.askingMonthlyWage / (mkt * (0.7 + c.skill / 160))); skills.append(c.skill); asks.append(c.askingMonthlyWage) }
            }
            let n = Double(ratios.count)
            print("ASK \(role) n=\(Int(n)) ratio=\(ratios.reduce(0, +) / n) skill=\(skills.reduce(0, +) / n) ask=\(asks.reduce(0, +) / n) mkt=\(mkt)")
        }
    }
}

extension SimulationSmokeTests {
    func testPrintHireGap() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        var rows: [String] = []
        var sumGap = 0.0, n = 0.0
        for k in 0..<6 {
            var e = try newEngine("UK", seed: 1000 + k * 37)
            let id = try startCompany(&e, trade: "gym")
            let co = e.state.company(id)!
            let w = World(state: e.state, data: e.data)
            for m in co.staff {
                let p = e.state.people[m.id]!
                let base = e.data.catalog.tables.roles[m.role]!.baseMonthlyWage
                let mkt = Wages.market(baseMonthlyWage: base, country: w.country(co), city: w.city(co)!, economy: e.state.economy, week: e.state.week, rates: w.rates)
                let gap = (mkt * (0.7 + p.skill / 160) - m.monthlyWage) / mkt
                sumGap += gap; n += 1
                rows.append("role=\(m.role) wage=\(Int(m.monthlyWage)) ask=\(Int(p.askingMonthlyWage)) mkt=\(Int(mkt)) skill=\(Int(p.skill)) gap=\(String(format: "%.3f", gap)) pt=\(m.partTimeShare)")
            }
        }
        print("HIREGAP avg=\(sumGap / n) n=\(Int(n))\n" + rows.prefix(8).joined(separator: "\n"))
    }
}
