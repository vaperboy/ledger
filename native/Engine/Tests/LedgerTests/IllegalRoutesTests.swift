import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class IllegalRoutesTests: XCTestCase {

    func testARouteNeedsAWarningAndAFreshConfirmation() throws {
        var b = RouteBook()
        XCTAssertThrowsError(try b.begin(.cashInHand, companyID: 1, token: 1, confirmed: true, week: 1), "no warning was shown") { XCTAssertEqual($0 as? GovError, .needsConfirmation) }
        let w = b.warn(act: "route:cashInHand", title: "Cash in hand", companyID: 1, week: 1)
        XCTAssertFalse(w.text.lowercased().contains("heat"), "the warning never shows how close you are")
        XCTAssertTrue(w.text.contains("crime"))
        XCTAssertThrowsError(try b.begin(.cashInHand, companyID: 1, token: w.token, confirmed: false, week: 1), "reading is not confirming")
        XCTAssertThrowsError(try b.begin(.cashInHand, companyID: 1, token: w.token + 7, confirmed: true, week: 1), "wrong token")
        XCTAssertThrowsError(try b.begin(.cashInHand, companyID: 1, token: w.token, confirmed: true, week: 3), "a warning goes stale")
        XCTAssertTrue(b.active(1).isEmpty)
        let w2 = b.warn(act: "route:cashInHand", title: "Cash in hand", companyID: 1, week: 3)
        try b.begin(.cashInHand, companyID: 1, token: w2.token, confirmed: true, week: 3)
        XCTAssertEqual(b.active(1), [.cashInHand])
        XCTAssertThrowsError(try b.begin(.cashInHand, companyID: 1, token: w2.token, confirmed: true, week: 3), "a warning is used once")
    }

    func testAtMostTwoRoutesAtACompany() throws {
        var b = RouteBook()
        for r in [IllegalRoute.cashInHand, .fakeInvoices] {
            let w = b.warn(act: "route:\(r.rawValue)", title: r.title, companyID: 1, week: 1)
            try b.begin(r, companyID: 1, token: w.token, confirmed: true, week: 1)
        }
        let w = b.warn(act: "route:cheapInputs", title: "x", companyID: 1, week: 1)
        XCTAssertThrowsError(try b.begin(.cheapInputs, companyID: 1, token: w.token, confirmed: true, week: 1))
    }

    func testRoutesEarnWhileOpenAndNothingWhileShut() throws {
        var b = RouteBook()
        let w = b.warn(act: "route:fakeInvoices", title: "x", companyID: 9, week: 1)
        try b.begin(.fakeInvoices, companyID: 9, token: w.token, confirmed: true, week: 1)
        XCTAssertEqual(b.step(companyID: 9, week: 2, base: 10_000, open: false).gain, 0)
        let r = b.step(companyID: 9, week: 3, base: 10_000, open: true)
        XCTAssertEqual(r.gain, 800)
        XCTAssertEqual(b.step(companyID: 77, week: 3, base: 10_000, open: true).gain, 0, "a company with no route earns nothing extra")
    }

    private func meanNet(_ route: IllegalRoute, on: Int, off: Int) throws -> Double {
        let base = 1_000.0
        var total = 0.0
        for cid in 1...300 {
            var b = RouteBook()
            var net = 0.0, active = false, weeks = 0
            for w in 0..<300 {
                let want = (w % (on + off)) < on
                if want && !active {
                    let t = b.warn(act: "route:\(route.rawValue)", title: route.title, companyID: cid, week: w)
                    try b.begin(route, companyID: cid, token: t.token, confirmed: true, week: w)
                    active = true
                }
                if !want && active { b.stop(route, companyID: cid); active = false }
                let r = b.step(companyID: cid, week: w, base: base, open: true)
                net += r.gain
                weeks = w + 1
                if let a = r.audit {
                    net -= a.liability * (RouteRules.backMultiple + RouteRules.fineMultiple(level: a.level))
                    if a.suspends { net -= 6 * 0.1 * base }
                    if a.closes { net -= 50 * base + a.liability * RouteRules.convictionFineMultiple(level: a.level); break }
                    if a.level >= 3 { active = false }
                }
            }
            total += net / Double(weeks)
        }
        return total / 300
    }

    func testNoRoutePaysOnAverageWhateverTheSchedule() throws {
        for route in IllegalRoute.allCases {
            for (on, off) in [(26, 0), (8, 8), (13, 26), (3, 2)] {
                let m = try meanNet(route, on: on, off: off)
                XCTAssertLessThan(m, 0, "\(route) on \(on) off \(off): \(m)")
            }
        }
    }

    func testAuditsAreDeterministicAndOutcomeGrowsWithSeverity() throws {
        func firstAudit(_ route: IllegalRoute, id: Int) throws -> (Int, RouteAudit)? {
            var b = RouteBook()
            let t = b.warn(act: "route:\(route.rawValue)", title: "x", companyID: id, week: 0)
            try b.begin(route, companyID: id, token: t.token, confirmed: true, week: 0)
            for w in 1..<200 { if let a = b.step(companyID: id, week: w, base: 1_000, open: true).audit { return (w, a) } }
            return nil
        }
        for id in 1...20 {
            let x = try XCTUnwrap(firstAudit(.counterfeitLabels, id: id)), y = try XCTUnwrap(firstAudit(.counterfeitLabels, id: id))
            XCTAssertEqual(x.0, y.0)
            XCTAssertEqual(x.1, y.1)
            XCTAssertGreaterThan(x.1.liability, 0)
        }
        func average(_ r: IllegalRoute) throws -> Double {
            try (1...60).reduce(0.0) { acc, id in acc + Double(try XCTUnwrap(firstAudit(r, id: id)).1.level) } / 60
        }
        XCTAssertGreaterThan(try average(.counterfeitLabels), try average(.cashInHand), "a grave route ends worse than a minor one")
    }

    func testAnAuditClearsWhatWasTakenSoItIsNotChargedTwice() throws {
        var b = RouteBook()
        let t = b.warn(act: "route:counterfeitLabels", title: "x", companyID: 5, week: 0)
        try b.begin(.counterfeitLabels, companyID: 5, token: t.token, confirmed: true, week: 0)
        var found: RouteAudit?
        var w = 1
        while found == nil && w < 200 { found = b.step(companyID: 5, week: w, base: 1_000, open: true).audit; w += 1 }
        let a = try XCTUnwrap(found)
        XCTAssertEqual(b.risk(5)?.offences, 1)
        if a.level >= 3 { XCTAssertTrue(b.active(5).isEmpty, "a serious outcome ends the routes") }
        XCTAssertEqual(b.risk(5)?.gains.reduce(0) { $0 + $1.amount }, 0)
    }

    func testDirtyTricksAreCapped() throws {
        var b = RouteBook()
        func use(_ k: DirtyTrick, week: Int, target: String, confirmed: Bool = true) throws -> TrickOutcome {
            let w = b.warn(act: "trick:\(k.rawValue)", title: k.title, companyID: 1, week: week)
            return try b.useTrick(k, account: "me", companyID: 1, target: target, token: w.token, confirmed: confirmed, week: week)
        }
        XCTAssertThrowsError(try use(.sabotage, week: 1, target: "t", confirmed: false))
        XCTAssertTrue(b.tricks.isEmpty, "nothing happens without the confirmation")
        XCTAssertEqual(try use(.sabotage, week: 1, target: "t").effect, 5)
        XCTAssertThrowsError(try use(.smear, week: 1, target: "u"), "one a week")
        XCTAssertEqual(try use(.sabotage, week: 2, target: "t").effect, 5)
        XCTAssertEqual(try use(.sabotage, week: 3, target: "t").effect, 2, "the target's total loss is capped")
        XCTAssertThrowsError(try use(.sabotage, week: 4, target: "t"), "hurt enough already")
        XCTAssertEqual(try use(.smear, week: 4, target: "u").effect, 3)
        XCTAssertThrowsError(try use(.smear, week: 5, target: "v"), "four in twelve weeks")
        XCTAssertNoThrow(try use(.smear, week: 20, target: "v"), "the window moves on")
    }

    private func openCompany(_ e: inout GameEngine) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else {
            XCTFail("start"); throw XCTSkip("no company")
        }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return id
    }

    private func engine() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "Tester", seed: 5) }

    func testAGameThatNeverUsesGovernmentIsUnchanged() throws {
        var e = try engine()
        let before = e.state
        e.update { s, d, c in GovernmentBridge.weekly(&s, data: d, context: c) }
        XCTAssertEqual(e.state, before)
        XCTAssertNil(e.state.rest["gov"])
    }

    func testWorldSurvivesSaveAndLoad() throws {
        var e = try engine()
        e.update { s, _, _ in
            GovernmentBridge.ensure(&s, country: s.homeCountryCode, admins: ["boss"], startingSupply: 5_000_000)
            _ = try? GovernmentBridge.act(&s, country: s.homeCountryCode) { g, _, w in try g.printMoney(admin: "boss", amount: 1_000, reason: "test run", week: w) }
        }
        let world = try XCTUnwrap(e.state.governmentWorld)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.governmentWorld, e.state.governmentWorld)
        XCTAssertEqual(world.countries.values.first?.supply.mints.count, 1)
    }

    func testDonationMovesMoneyFromPlayerToTreasury() throws {
        var e = try engine()
        try e.updateThrowing { s, _, _ in
            let cc = s.homeCountryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["boss"], startingSupply: 5_000_000)
            Ledger.move(&s, .me, 10_000_000, why: "Test funds")
            let cash0 = s.cash
            XCTAssertNoThrow(try GovernmentBridge.donate(&s, country: cc, amount: 250_000))
            XCTAssertEqual(cash0 - s.cash, 250_000)
            XCTAssertEqual(GovernmentBridge.world(s).countries[cc]?.treasury.balance, 250_000)
            XCTAssertThrowsError(try GovernmentBridge.donate(&s, country: cc, amount: s.cash + 1), "not from an overdraft")
            XCTAssertTrue(Ledger.gaps(s).isEmpty, "\(Ledger.gaps(s))")
        }
    }

    func testStandingTakesTheFeeOnceAndNeverReturnsIt() throws {
        var e = try engine()
        e.update { s, d, c in
            let cc = s.homeCountryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["boss"], startingSupply: 5_000_000)
            s.week = 30
            GovernmentBridge.weekly(&s, data: d, context: c)
        }
        XCTAssertNotNil(e.state.governmentWorld?.countries[e.state.homeCountryCode]?.election, "nominations opened")
        try e.updateThrowing { s, _, c in
            let cc = s.homeCountryCode
            let fee = GovernmentBridge.candidacyFee(s, country: cc, context: c)
            XCTAssertGreaterThan(fee, 100_000, "very high")
            Ledger.move(&s, .me, fee * 3, why: "Test funds")
            let cash0 = s.cash
            XCTAssertThrowsError(try GovernmentBridge.stand(&s, country: cc, manifesto: "m", promises: [CampaignPromise(kind: .gainsTax, value: 0.05)], context: c), "unrealistic")
            XCTAssertEqual(s.cash, cash0, "a refused candidacy costs nothing")
            XCTAssertNoThrow(try GovernmentBridge.stand(&s, country: cc, manifesto: "m", promises: [CampaignPromise(kind: .gainsTax, value: 0.19)], context: c))
            XCTAssertEqual(cash0 - s.cash, fee)
            XCTAssertThrowsError(try GovernmentBridge.stand(&s, country: cc, manifesto: "m", promises: [], context: c), "already standing")
            XCTAssertEqual(cash0 - s.cash, fee, "no second fee")
            XCTAssertEqual(GovernmentBridge.world(s).countries[cc]?.treasury.balance, fee)
            XCTAssertTrue(Ledger.gaps(s).isEmpty)
        }
    }

    func testPrintingRaisesPricesOnlyAfterTheLag() throws {
        var e = try engine()
        try e.updateThrowing { s, d, c in
            let cc = s.homeCountryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["me"], startingSupply: 1_000_000)
            s.week = 10
            XCTAssertNoThrow(try GovernmentBridge.act(&s, country: cc) { g, a, w in try g.printMoney(admin: a, amount: 50_000, reason: "stimulus", week: w) })
            let ix0 = s.economy.inflationIndex
            for w in 10..<(10 + GovInflation.lagWeeks) {
                s.week = w
                GovernmentBridge.weekly(&s, data: d, context: c)
                XCTAssertEqual(s.economy.inflationIndex, ix0, "week \(w)")
            }
            s.week = 10 + GovInflation.lagWeeks
            GovernmentBridge.weekly(&s, data: d, context: c)
            XCTAssertGreaterThan(s.economy.inflationIndex, ix0)
            XCTAssertTrue(s.rest["news"]?.array.contains { $0["t"].string.contains("stimulus") } ?? false, "printing is in the news")
        }
    }

    func testPriceSupportIsPaidFromTheTreasuryToTheCompany() throws {
        var e = try engine()
        let id = try openCompany(&e)
        try e.updateThrowing { s, d, c in
            let i = s.companyIndex(id)!
            let cc = s.companies[i].countryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["boss"], startingSupply: 5_000_000)
            Ledger.move(&s, .me, 5_000_000, why: "Test funds")
            XCTAssertNoThrow(try GovernmentBridge.donate(&s, country: cc, amount: 1_000_000))
            var w = GovernmentBridge.world(s)
            var g = w.countries[cc]!
            g.supports.append(GovPriceSupport(id: 900, tradeID: s.companies[i].type, percent: 0.05, weeklyBudget: 40_000, weeks: 4, startWeek: 40, status: .active, proposer: "x"))
            w.countries[cc] = g
            s.governmentWorld = w
            var b = s.companies[i].books
            b.week["rev"] = 100_000
            s.companies[i].books = b
            s.week = 41
            let co0 = s.companies[i].cash, tr0 = g.treasury.balance
            GovernmentBridge.weekly(&s, data: d, context: c)
            let paid = s.companies[i].cash - co0
            XCTAssertEqual(paid, 5_000)
            XCTAssertEqual(tr0 - (GovernmentBridge.world(s).countries[cc]?.treasury.balance ?? 0), paid, "what the company gets is what the treasury loses")
            XCTAssertTrue(Ledger.gaps(s).isEmpty, "\(Ledger.gaps(s))")
        }
    }

    private func audited(level: Int, _ body: (GameState, GovernmentWorld, Double, Double, Int) -> Void) throws {
        var e = try engine()
        let id = try openCompany(&e)
        e.update { s, d, c in
            let i = s.companyIndex(id)!
            let cc = s.companies[i].countryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["me"], startingSupply: 5_000_000)
            Ledger.move(&s, .company(id), 100_000_000, why: nil)
            s.week = 50
            var w = GovernmentBridge.world(s)
            let cashCo = s.companies[i].cash, cashMe = s.cash
            GovernmentBridge.settle(&s, &w, audit: RouteAudit(level: level, liability: 20_000, route: level >= 5 ? .counterfeitLabels : .cashInHand), companyIndex: i, data: d, context: c)
            s.governmentWorld = w
            body(s, w, cashCo, cashMe, i)
        }
    }

    func testFineGoesToTheTreasuryAndNothingIsLost() throws {
        try audited(level: 2) { s, w, cashCo, _, i in
            let cc = s.companies[i].countryCode
            let drop = cashCo - s.companies[i].cash
            XCTAssertEqual(drop, 80_000, "20 000 handed back and a fine of three times that")
            XCTAssertEqual(w.countries[cc]?.treasury.balance, drop)
            XCTAssertEqual(w.countries[cc]?.treasury.gap, 0)
            XCTAssertEqual(s.companies[i].status, .open)
            XCTAssertTrue(w.justice.convictions.isEmpty)
            XCTAssertTrue(Ledger.gaps(s).isEmpty, "\(Ledger.gaps(s))")
        }
    }

    func testASeriousAuditSuspendsTheCompany() throws {
        try audited(level: 3) { s, _, _, _, i in
            XCTAssertEqual(s.companies[i].status, .closed)
            XCTAssertEqual(s.companies[i].int("closeW"), RouteRules.suspensionWeeks)
        }
    }

    func testForcedClosureSeizesCashPaysNothingOutAndConvicts() throws {
        try audited(level: 4) { s, w, cashCo, cashMe, i in
            let cc = s.companies[i].countryCode
            XCTAssertEqual(s.companies[i].status, .bust)
            XCTAssertLessThanOrEqual(s.companies[i].cash.magnitude, 1)
            XCTAssertLessThanOrEqual(s.cash, cashMe, "the owner receives nothing from the closure")
            let conv = w.justice.convictions
            XCTAssertEqual(conv.count, 1)
            XCTAssertTrue(w.justice.watchlist.isEmpty, "not grave enough to be public")
            XCTAssertTrue(w.justice.barred("me", .trade, week: 51))
            XCTAssertTrue(w.justice.barred("me", .office, week: 51))
            XCTAssertFalse(w.justice.barred("me", .vote, week: 51))
            let pf = conv[0].fine
            XCTAssertEqual(pf, 10_000, "half of what was taken")
            XCTAssertEqual(w.countries[cc]?.treasury.balance ?? 0, cashCo + pf, accuracy: 1.5, "all of the company's cash and the fine went to the treasury")
            XCTAssertEqual(w.countries[cc]?.treasury.gap, 0)
            XCTAssertTrue(Ledger.gaps(s).isEmpty, "\(Ledger.gaps(s))")
        }
    }

    func testAGraveCaseIsOnThePublicWatchlistAndEndsTheirPresidency() throws {
        try audited(level: 5) { s, w, _, _, _ in
            XCTAssertEqual(w.justice.watchlist.count, 1)
            XCTAssertEqual(w.justice.watchlist.first?.kind, .counterfeiting)
            XCTAssertTrue(w.justice.barred("me", .vote, week: 51))
            XCTAssertEqual(w.justice.count("me"), 1)
            XCTAssertTrue(s.rest["news"]?.array.contains { $0["t"].string.contains("shut down") } ?? false)
        }
    }

    func testQuashingReturnsTheFineFromTheTreasuryAndLiftsTheBans() throws {
        var e = try engine()
        let id = try openCompany(&e)
        try e.updateThrowing { s, d, c in
            let i = s.companyIndex(id)!
            let cc = s.companies[i].countryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["me"], startingSupply: 5_000_000)
            Ledger.move(&s, .company(id), 100_000_000, why: nil)
            s.week = 50
            var w = GovernmentBridge.world(s)
            GovernmentBridge.settle(&s, &w, audit: RouteAudit(level: 5, liability: 20_000, route: .counterfeitLabels), companyIndex: i, data: d, context: c)
            s.governmentWorld = w
            let conv = w.justice.convictions[0]
            let cash0 = s.cash, tr0 = w.countries[cc]!.treasury.balance
            XCTAssertNoThrow(try GovernmentBridge.quash(&s, country: cc, convictionID: conv.id))
            let after = GovernmentBridge.world(s)
            XCTAssertEqual(s.cash - cash0, conv.fine)
            XCTAssertEqual(tr0 - after.countries[cc]!.treasury.balance, conv.fine)
            XCTAssertTrue(after.justice.watchlist.isEmpty)
            XCTAssertFalse(after.justice.barred("me", .trade, week: 51))
            XCTAssertEqual(after.justice.count("me"), 0)
            XCTAssertThrowsError(try GovernmentBridge.quash(&s, country: cc, convictionID: conv.id), "only once")
            XCTAssertTrue(Ledger.gaps(s).isEmpty)
        }
    }

    func testABanOnTradingBlocksNewRoutes() throws {
        var e = try engine()
        let id = try openCompany(&e)
        try e.updateThrowing { s, d, c in
            let i = s.companyIndex(id)!
            let cc = s.companies[i].countryCode
            GovernmentBridge.ensure(&s, country: cc, admins: ["boss"], startingSupply: 5_000_000)
            s.week = 5
            var w = GovernmentBridge.world(s)
            _ = w.justice.record(account: w.account, name: "You", kind: .fraud, summary: "x", fine: 0, country: cc, week: 5, tradeBanWeeks: 10, grave: false)
            s.governmentWorld = w
            let warn = GovernmentBridge.routeWarning(&s, route: .cashInHand, companyID: id)
            XCTAssertThrowsError(try GovernmentBridge.beginRoute(&s, route: .cashInHand, companyID: id, token: warn.token, confirmed: true))
            s.week = 16
            let warn2 = GovernmentBridge.routeWarning(&s, route: .cashInHand, companyID: id)
            XCTAssertNoThrow(try GovernmentBridge.beginRoute(&s, route: .cashInHand, companyID: id, token: warn2.token, confirmed: true))
        }
    }
}

extension GameEngine {
    mutating func updateThrowing(_ body: (inout GameState, GameData, FinanceContext) throws -> Void) throws {
        var failure: Error?
        update { s, d, c in
            do { try body(&s, d, c) } catch { failure = error }
        }
        if let failure { throw failure }
    }
}
