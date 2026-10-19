import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// How fast does each trade make its owner rich? Plays every supported trade for three years with the standard set-up and
/// prints return on the money put in. Run with LEDGER_BALANCE=1 (slow); the regular suite only checks the ceiling below.
final class BalanceProbeTests: XCTestCase {
    struct Outcome { var trade: String; var invested: Double; var profitY1: Double; var profitY3: Double; var value: Double; var cash: Double; var status: String; var staff: Int }

    static func play(trade: String, country: String = "UK", seed: Int, years: Int = 3, aggressive: Bool = false) throws -> Outcome? {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 200_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            invested = (est?.total ?? 1_000_000) * 1.3
            Payments.injectCash(&s, companyID: id, amount: invested)
            // An owner who does not work in the business: the standard team does everything (how an empire scales)
            if ProcessInfo.processInfo.environment["LEDGER_NOOWNER"] != nil { s.companies[s.companyIndex(id)!].ownerHours = 0 }
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        guard id != 0 else { return nil }
        // A sensible marketing plan: search ads and social ads at their second-lowest budget, website and SEO at the lowest
        if ProcessInfo.processInfo.environment["LEDGER_MKT"] != nil {
            for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
            }
        }
        if aggressive {
            for (k, ch) in e.marketing.channels.sorted(by: { $0.key < $1.key }) where ch.onlyInCountry == nil {
                _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions.last ?? 0)
            }
        }
        for _ in 0..<(years * 52 * 7) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            // Money the owner adds to keep a company alive counts as invested
            if let co = e.state.company(id), co.status.isLive, co.cash < -50_000 {
                let top = -co.cash + 100_000
                e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }
                invested += top
            }
        }
        guard let co = e.state.company(id) else { return nil }
        let h = co.monthlyHistory
        let y1 = h.prefix(12).reduce(0) { $0 + $1.profit }, y3 = h.suffix(12).reduce(0) { $0 + $1.profit }
        let v = Valuation.companyValue(co, state: e.state, trades: e.data.catalog)
        return Outcome(trade: trade, invested: invested, profitY1: y1, profitY3: y3, value: v, cash: co.cash, status: co.status.rawValue, staff: co.staff.count)
    }

    func testPrintWealthSpeedOfEveryTrade() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_BALANCE"] != nil else { return }
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        let trades = e.data.catalog.all.filter { CompanyWeek.isSupported($0) }.map { $0.id }.sorted()
        let only = ProcessInfo.processInfo.environment["LEDGER_TRADES"]?.split(separator: ",").map(String.init)
        let country = ProcessInfo.processInfo.environment["LEDGER_COUNTRY"] ?? "UK"
        let aggressive = ProcessInfo.processInfo.environment["LEDGER_AGGR"] != nil
        print("BAL trade | invested k | profit y1 k | profit y3 k | y3 ROI | value k | value/invested | status")
        for t in trades where only == nil || only!.contains(t) {
            var outs: [Outcome] = []
            for seed in [11, 12, 13] { if let o = try Self.play(trade: t, country: country, seed: seed, aggressive: aggressive) { outs.append(o) } }
            guard !outs.isEmpty else { continue }
            func avg(_ f: (Outcome) -> Double) -> Double { outs.map(f).reduce(0, +) / Double(outs.count) }
            let inv = avg { $0.invested }, y1 = avg { $0.profitY1 }, y3 = avg { $0.profitY3 }, v = avg { $0.value }
            print(String(format: "BAL %@ | %.0f | %.0f | %.0f | %.0f%% | %.0f | %.1fx | %@ | staff %.0f", t, inv / 1000, y1 / 1000, y3 / 1000, y3 / inv * 100, v / 1000, v / inv,
                         outs.map { $0.status }.joined(separator: ","), avg { Double($0.staff) }))
        }
    }
}

extension BalanceProbeTests {
    /// LEDGER_TRACE=<trade>: what holds a company back, week by week.
    func testPrintTrace() throws {
        guard let trade = ProcessInfo.processInfo.environment["LEDGER_TRACE"] else { return }
        var e = try GameEngine.newGame(countryCode: ProcessInfo.processInfo.environment["LEDGER_COUNTRY"] ?? "UK", playerName: "T", seed: 11)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 200_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3)
            if ProcessInfo.processInfo.environment["LEDGER_NOOWNER"] != nil { s.companies[s.companyIndex(id)!].ownerHours = 0 }
            print("TRACE setup log:", CompanySetup.quickSetup(&s, companyID: id, data: data))
        }
        if ProcessInfo.processInfo.environment["LEDGER_MKT"] != nil {
            for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
            }
        }
        for w in 0..<156 {
            if let co = e.state.company(id), co.status.isLive, co.cash < -50_000 { e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: -co.cash + 100_000) } }
            for _ in 0..<7 { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
            guard let co = e.state.company(id) else { break }
            if w < 6 || w % 8 == 0 {
                let lw = co.value("lastW")
                if let bd = e.data.catalog[co.type], w < 4 {
                    let r = CapacityModel.compute(co, bd, World(state: e.state, data: e.data))
                    print("TRACE   std=\(bd.standardStaff.map { "\($0.role)x\($0.count)" }) ownerFTE=\(bd.ownerFTE) cap=\(Int(r.capacity)) parts=\(r.parts.map { "\($0.key) have=\($0.have) cap=\(Int($0.capacity.isFinite ? $0.capacity : -1))" })")
                }
                let b = co.monthlyHistory.last
                print("TRACE month rev=\(Int((b?.revenue ?? 0)/1000))k profit=\(Int((b?.profit ?? 0)/1000))k wages/mo=\(Int(co.staff.reduce(0) { $0 + $1.monthlyWage }/1000))k")
                print("TRACE w\(w) \(co.status.rawValue) staff=\(co.staff.map { $0.role }) cash=\(Int(co.cash/1000))k rev=\(Int(co.lastWeekRevenue/1000))k units=\(Int(co.lastWeekUnits)) cap=\(Int(lw["cap"].double)) D=\(Int(lw["D"].double)) aw=\(Int(co.awareness)) rep=\(Int(co.reputation)) q=\(Int(co.quality)) sat=\(Int(co.num("sat")))")
                if co.status == .setup { print("TRACE   checklist:", e.openingChecklist(companyID: id).filter { !$0.isDone }.map { "\($0.title): \($0.detail)" }) }
            }
        }
        if let co = e.state.company(id), let bd = e.data.catalog[co.type] {
            let y = co.books.lastYear
            print("TRACE last year books:", y.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value / 1000))k" })
            print("TRACE calib: normalDemand=\(Int(bd.normalDemand)) cap=\(Int(bd.normalCapacity)) F=\(Int(bd.weeklyFixedCosts)) vc=\(bd.variableCostShare) margin=\(bd.margin) ticket=\(bd.ticket) size=\(co.size)")
        }
        let notes = e.state.inbox.filter { $0.companyID == id }.prefix(40).map { "w\($0.week) \($0.title)" }
        print("TRACE messages:", notes)
    }
}

/// Regular checks that run in every test pass.
final class BalanceGuardTests: XCTestCase {
    /// Nothing turns a stake into a fortune in two years: even the best trades return their money a few times at most.
    func testNoTradeMakesYouRichQuickly() throws {
        for t in ["cons", "foodtruck", "acctfirm", "photo", "law"] {
            guard let o = try BalanceProbeTests.play(trade: t, seed: 21, years: 2) else { return XCTFail("\(t) did not start") }
            XCTAssertLessThan(o.profitY3, max(o.invested * 1.6, 1_500_000), "\(t): yearly profit \(Int(o.profitY3)) on \(Int(o.invested)) invested")
            XCTAssertLessThan(o.value, o.invested * 6 + 2_000_000, "\(t): worth \(Int(o.value)) after two years on \(Int(o.invested))")
        }
    }

    /// Trades that need a vehicle open with the standard set-up: the van is financed or leased when cash is short.
    func testVehicleTradesOpen() throws {
        for t in ["carclean", "handy", "foodtruck", "carrental"] {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
            var id = 0
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 50_000_000, why: "Test funds")
                guard case .success(let i) = CompanySetup.create(&s, tradeID: t, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
                id = i
                let est = CompanySetup.estimate(tradeID: t, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
                Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 0) * 1.2)
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            }
            for _ in 0..<(10 * 7) { e.nextDay() }
            XCTAssertEqual(e.state.company(id)?.status, .open, "\(t) should be open after ten weeks")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        }
    }

    /// A café run by a hired barista alone still serves customers: the team covers the empty support jobs.
    func testHiredTeamWithoutOwnerHasCapacity() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 6)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            Payments.injectCash(&s, companyID: id, amount: 3_000_000)
            s.companies[s.companyIndex(id)!].ownerHours = 0
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(6 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertGreaterThan(co.lastWeekUnits, 0)
        XCTAssertFalse(co.staff.isEmpty)
    }
}
