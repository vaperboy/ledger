import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Investments
@testable import SaveSystem
import Events
@testable import Simulation

/// Audit part 4b: (1) the same seed and the same actions give the same game, to the last digit; (2) a rich game saved and loaded plays on
/// exactly as the one that was never saved, and old saves still load; (3) every date-fired item of a three-year game fires the right number
/// of times on the right dates.
final class DeterminismSavesDatesTests: XCTestCase {

    // MARK: Helpers

    static func fund(_ e: inout GameEngine, _ amount: Double = 100_000_000) {
        let a = e.homeCurrency.scaledPrice(amount)
        e.update { s, _, _ in Ledger.move(&s, .me, a, why: "Test funds") }
    }

    @discardableResult
    static func start(_ e: inout GameEngine, _ trade: String, name: String? = nil) -> Int {
        var id = 0
        e.update { s, data, ctx in
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, name: name, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.5)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        return id
    }

    /// Paperwork a business needs to chain or franchise, and a VAT registration.
    static func season(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].openedWeek = s.week - 200
            s.companies[i].reputation = 70
            s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: 90_000, cash: 0) }
            var docs = s.companies[i].value("docs")
            docs["chain"] = .object(["st": "ok", "done": 0, "ok": 0])
            docs["fran"] = .object(["st": "ok", "done": 0, "ok": 0])
            s.companies[i].set("docs", docs)
        }
    }

    /// One day, answering the questions a careful player always answers the same way (payroll approvals, franchise talks).
    static func play(_ e: inout GameEngine, days: Int) {
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") || Franchising.handlesAnswer(m.actionID) { e.answer(messageID: m.id, option: 0) }
        }
    }

    /// A game with many systems running: chain, franchise brand unit, franchisor, luxury, equipment, loans, deposit, startups, rivals, reports.
    static func richGame(seed: Int) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "Rich", seed: seed)
        fund(&e, 2_000_000_000)
        let cafe = start(&e, "cafe", name: "Rich Cafe")
        let barber = start(&e, "barber")
        let bakery = start(&e, "bakery")
        XCTAssertNotEqual(cafe, 0); XCTAssertNotEqual(barber, 0); XCTAssertNotEqual(bakery, 0)
        season(&e, cafe); season(&e, barber)
        e.update { s, _, _ in if let i = s.companyIndex(cafe) { s.companies[i].set("mgr", 0) } }
        if let chain = e.makeChain(companyID: cafe, name: "Rich Cafe") {
            e.setChainRule(chainID: chain, rule: .price(1))
            _ = e.openChainStore(chainID: chain, cityID: e.state.player.cityID, size: 1)
        }
        // A franchisor
        e.update { s, _, _ in
            if let i = s.companyIndex(barber) {
                s.companies[i].set("fr", .object(["on": 1, "fee": 150_000, "roy": 0.06, "supp": 0, "share": 0.45, "brand": 30, "mkt": 0.02, "units": .array([]), "app": .array([]), "w0": .number(Double(s.week))]))
            }
        }
        // A franchise unit under somebody else's brand
        if let brand = ["gym", "carclean", "bakery", "cafe"].lazy.compactMap({ t in
            FranchiseBrands.brands(t, country: "NO", World(state: e.state, data: e.data)).first { $0.openness == "open" }
        }).first, e.applyToFranchiseBrand(brand.id, country: "NO") == .ok {
            play(&e, days: 4 * 7)
            if let n = e.negotiateFranchise(brand.id, ask: FranchiseBrands.Ask()), let terms = n.terms {
                e.signFranchiseTerms(brand.id, terms: terms)
                _ = e.startFranchisedCompany(brandID: brand.id, cityID: e.state.player.cityID, form: .limited, name: "Unit", fundWith: e.homeCurrency.scaledPrice(30_000_000))
            }
        }
        // Luxury
        for item in Luxury.categories.prefix(4).compactMap({ $0.items.first }) { _ = e.buyLuxury(itemID: item.id) }
        // Equipment
        e.update { s, data, _ in
            for id in [cafe, barber, bakery] {
                guard let i = s.companyIndex(id), let bd = data.catalog[s.companies[i].type], let eq = bd.equipment.first else { continue }
                _ = CompanySetup.buyEquipment(&s, companyID: id, equipmentID: eq.id, quantity: 1, data: data)
            }
        }
        // Money
        _ = e.takeLoan(kind: "biz", amount: e.homeCurrency.scaledPrice(500_000), termMonths: 36, companyID: bakery)
        e.update { s, _, _ in _ = Brokerage.openDeposit(&s, amount: s.cash * 0.01, weeks: 30) }
        // Startups
        e.update { s, data, _ in _ = Startups.pitches(&s, data: data) }
        play(&e, days: 60 * 7)
        if let p = Startups.pitchesOnOffer(e.state).first { _ = e.investInStartup(pitchID: p.id, amount: p.raise * 0.05) }
        return e
    }

    static func tree(_ s: GameState) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(s)) }

    /// The first place where two states differ, for a readable failure.
    static func firstDifference(_ a: JSONValue, _ b: JSONValue, _ path: String = "") -> String? {
        switch (a, b) {
        case (.object(let x), .object(let y)):
            for k in Set(x.keys).union(y.keys).sorted() {
                if let d = firstDifference(x[k] ?? .null, y[k] ?? .null, path + "/" + k) { return d }
            }
            return nil
        case (.array(let x), .array(let y)):
            if x.count != y.count { return "\(path): \(x.count) items vs \(y.count)" }
            for i in x.indices { if let d = firstDifference(x[i], y[i], "\(path)[\(i)]") { return d } }
            return nil
        default:
            return a == b ? nil : "\(path): \(a) vs \(b)"
        }
    }

    func assertSame(_ a: GameEngine, _ b: GameEngine, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        if a.state == b.state { return }
        XCTFail("\(what): " + (Self.firstDifference(try Self.tree(a.state), try Self.tree(b.state)) ?? "states differ outside the saved fields"), file: file, line: line)
    }

    // MARK: (1) Determinism

    func testSameSeedSameActionsGiveTheSameGameExactly() throws {
        var a = try Self.richGame(seed: 31337), b = try Self.richGame(seed: 31337)
        try assertSame(a, b, "after building")
        for w in 1...40 {
            Self.play(&a, days: 7); Self.play(&b, days: 7)
            if a.state != b.state { try assertSame(a, b, "week \(w) after the build"); return }
        }
        XCTAssertEqual(a.state.cash, b.state.cash)   // exactly, not "to 1e-9"
        let other = try Self.richGame(seed: 31338)
        XCTAssertNotEqual(other.state.random.state, a.state.random.state, "a different seed must give a different game")
    }

    /// Sums over stored dictionaries add in key order, so they do not depend on how the dictionary was built.
    func testSumsOverDictionariesAreOrderStable() {
        let keys = (0..<60).map { "eq\($0)" }
        func company(_ order: [String]) -> Company {
            var eq: [String: JSONValue] = [:], mkt: [String: JSONValue] = [:]
            for (n, k) in order.enumerated() {
                let v = 0.1 * Double(k.dropFirst(2).isEmpty ? 1 : Int(k.dropFirst(2))! + 1) + 1.0 / 3.0
                eq[k] = .object(["bv": .number(v)]); mkt[k] = .object(["b": .number(v / 7 + Double(n % 1))])
            }
            return Company(raw: ["eq": .object(eq), "mkt": .object(mkt), "veh": .array([])])
        }
        let a = company(keys), b = company(keys.reversed()), c = company(keys.shuffled())
        XCTAssertEqual(CompanyFigures.equipmentBookValue(a), CompanyFigures.equipmentBookValue(b))
        XCTAssertEqual(CompanyFigures.equipmentBookValue(a), CompanyFigures.equipmentBookValue(c))
        var sorted = 0.0
        for k in keys.sorted() { sorted += a.value("eq")[k]["bv"].double }
        XCTAssertEqual(CompanyFigures.equipmentBookValue(a), sorted, "equipment is added in key order")
        let fa = CompanyFigures.weeklyCostEstimate(a, fixedCost: 100, employerFactor: 1.2)
        XCTAssertEqual(fa, CompanyFigures.weeklyCostEstimate(b, fixedCost: 100, employerFactor: 1.2))
        XCTAssertEqual(fa, CompanyFigures.weeklyCostEstimate(c, fixedCost: 100, employerFactor: 1.2))
    }

    // MARK: (2) Saves

    func testRichGameSavesLoadsAndPlaysOnIdentically() throws {
        var e = try Self.richGame(seed: 777)
        Self.play(&e, days: 10 * 7)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-rich-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
        let loaded = try store.load()
        if loaded != e.state { XCTFail("the loaded game differs: " + (Self.firstDifference(try Self.tree(e.state), try Self.tree(loaded)) ?? "outside the saved fields")) }
        let (data, events, marketing) = try GameEngine.loadResources()
        var b = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        try assertSame(e, b, "just after loading")
        for w in 1...30 {
            Self.play(&e, days: 7); Self.play(&b, days: 7)
            if e.state != b.state { try assertSame(e, b, "week \(w) after loading"); return }
        }
        XCTAssertTrue(Ledger.gaps(b.state).isEmpty, "\(Ledger.gaps(b.state))")
        // Saved again and again does not change it.
        try store.save(b.state, summary: store.summary(of: b.state, trades: b.data.catalog))
        XCTAssertEqual(try store.load(), b.state)
    }

    /// Saves from before reports, rivals, reviews, chains, luxury, equipment and the decisions queue: they load, play for a year, the books balance
    /// and the newer systems start up by themselves.
    func testOldSavesLoadAndPlayForAYear() throws {
        let (data, events, marketing) = try GameEngine.loadResources()
        for name in ["save_cafe_week3", "save_cafe_week15", "save_uk25", "save_projects"] {
            let s = try Golden.state(name)
            XCTAssertNil(s.rest["reports"], "\(name) is from before reports")
            var e = GameEngine(state: s, data: data, events: events, marketing: marketing)
            let gaps0 = Ledger.gaps(e.state).count
            Self.play(&e, days: 56 * 7)
            XCTAssertFalse(e.state.cash.isNaN, name)
            XCTAssertLessThanOrEqual(Ledger.gaps(e.state).count, gaps0, "\(name): playing must not open gaps in the books")
            XCTAssertGreaterThanOrEqual(e.reports(.week).count, 20, "\(name): weekly reports start by themselves")
            XCTAssertGreaterThanOrEqual(e.reports(.year).count, 1, name)
            // and the result saves and loads again
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-old-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try SaveStore(directory: dir)
            try store.save(e.state, summary: store.summary(of: e.state, trades: data.catalog))
            XCTAssertEqual(try store.load(), e.state, name)
        }
    }

    func testEnvelopeMigrationsAreVersionedAndOneWay() throws {
        XCTAssertEqual(NativeSaveFormat.currentVersion, NativeMigrations.steps.keys.max().map { $0 + 1 }, "every version has a step to the next")
        var env: [String: JSONValue] = ["format": "ledger-native", "version": 1, "state": .object([:])]
        try NativeMigrations.upgrade(&env)
        XCTAssertEqual(env["version"]?.int, NativeSaveFormat.currentVersion)
        XCTAssertNotNil(env["state"]?["reports"])
        var newer: [String: JSONValue] = ["version": .number(Double(NativeSaveFormat.currentVersion + 1))]
        XCTAssertThrowsError(try NativeMigrations.upgrade(&newer))
    }

    // MARK: (3) Dates

    struct Ev { var kind: String; var co: Int; var week: Int; var day: Int; var month = 0; var note = "" }

    static func isoDay(week: Int, day: Int) -> Int { GameCalendar.startDay + week * 7 + day }
    static func lastDayOfMonth(_ y: Int, _ m0: Int) -> Int {
        GameCalendar.daysFromCivil(year: m0 == 11 ? y + 1 : y, month: m0 == 11 ? 1 : m0 + 2, day: 1) - 1
    }
    /// The 25th, or the Friday before when it is a weekend. Written out here, independent of the engine.
    static func expectedPayDay(year: Int, month0: Int) -> Int {
        let d = GameCalendar.daysFromCivil(year: year, month: month0 + 1, day: 25)
        let weekday = ((d % 7) + 7 + 3) % 7   // 0 Monday ... 6 Sunday
        return weekday == 5 ? d - 1 : weekday == 6 ? d - 2 : d
    }
    static func months(from a: Int, to b: Int) -> [(year: Int, month0: Int, index: Int)] {
        var out: [(Int, Int, Int)] = []
        var y = GameCalendar.civilFromDays(a).year, m = GameCalendar.civilFromDays(a).month - 1
        while true {
            if GameCalendar.daysFromCivil(year: y, month: m + 1, day: 1) > b { break }
            out.append((y, m, y * 12 + m))
            m += 1; if m == 12 { m = 0; y += 1 }
        }
        return out.map { (year: $0.0, month0: $0.1, index: $0.2) }
    }

    struct Dated {
        var events: [Ev] = []
        var paydayMessageDays: [Int] = []
        var weeks = 0
        var companies: [Int] = []
        var filing = 0
    }

    /// Plays `weeks` weeks of a seeded game with three companies and records every dated thing that happens.
    func playDated(country: String, weeks: Int) throws -> Dated {
        var e = try GameEngine.newGame(countryCode: country, playerName: "Dates", seed: 2026)
        Self.fund(&e, 200_000_000)
        var out = Dated(weeks: weeks)
        let ids = [Self.start(&e, "cafe"), Self.start(&e, "barber"), Self.start(&e, "bakery")]
        XCTAssertFalse(ids.contains(0), "\(country): the three companies start")
        out.companies = ids
        let freq = max(1, e.homeCountry.vatFilingMonths == 0 ? 2 : e.homeCountry.vatFilingMonths)
        out.filing = freq
        e.update { s, _, _ in
            for id in ids {
                guard let i = s.companyIndex(id) else { continue }
                var docs = s.companies[i].value("docs"); docs["vat"] = .object(["st": "ok", "done": 0, "ok": 0]); s.companies[i].set("docs", docs)
            }
        }
        // A 36 month loan for the café, a fixed deposit, a fixed-term worker.
        let loan = e.takeLoan(kind: "biz", amount: e.homeCurrency.scaledPrice(300_000), termMonths: 36, companyID: ids[0])
        XCTAssertEqual(loan, .ok, "\(country): the business loan is granted")
        let depositWeeks = min(30, max(4, weeks / 3))
        e.update { s, _, _ in _ = Brokerage.openDeposit(&s, amount: s.cash * 0.01, weeks: depositWeeks) }
        let fixedEnd = min(6, max(5, weeks / 2))
        var fixedStaff = 0
        e.update { s, _, _ in
            guard let i = s.companyIndex(ids[1]), let k = s.companies[i].staff.indices.first else { return }
            var st = s.companies[i].staff
            fixedStaff = st[k].id
            st[k].set("ft", fixedEnd); st[k].set("ftl", fixedEnd)
            s.companies[i].staff = st
        }
        XCTAssertNotEqual(fixedStaff, 0, "\(country): the barber has somebody to put on a fixed term")

        struct Snap { var pm = -99, bm = -99, lastMonth = -99, taxDueWeek = -1, txHead = "" }
        var snaps: [Int: Snap] = [:]
        var loanBalances: [Int: Double] = [:]
        var years = e.state.stats.yearsPlayed
        var deposits = e.state.rest["inv"]?["deposits"].array.count ?? 0
        let floor = e.homeCurrency.scaledPrice(3_000_000)
        func key(_ t: JSONValue) -> String { "\(t["w"].int):\(t["a"].double):\(t["l"].string)" }
        for id in ids {
            let co = e.state.company(id)!
            let t = Payday.dayNumber(week: 0, day: 0)
            let cfg = Payday.config(co, today: t)
            snaps[id] = Snap(pm: cfg.paidMonth, bm: cfg.billsMonth, lastMonth: co.monthlyHistory.last?.monthIndex ?? -99, taxDueWeek: co.taxDueWeek, txHead: co.transactions.first.map(key) ?? "")
        }
        for l in e.state.loans { loanBalances[l.id] = l.balance }
        var fixedGone = false
        for _ in 0..<(weeks * 7) {
            let outcome = e.nextDay()
            for m in e.openDecisions {
                if m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                else if m.actionID == FixedTerm.action { e.answer(messageID: m.id, option: 1) }   // let it end on its date
            }
            let w = e.state.week, d = e.state.day, t = Payday.dayNumber(week: w, day: d)
            for m in outcome.newMessages {
                if m.title.hasPrefix("Payday:") { out.paydayMessageDays.append(t) }
                if m.title.contains("fixed term") && m.title.contains("ends in") { out.events.append(Ev(kind: "fixedAsk", co: m.companyID, week: w, day: d)) }
            }
            for id in ids {
                guard let co = e.state.company(id) else { continue }
                var sn = snaps[id]!
                let cfg = Payday.config(co, today: t)
                if cfg.paidMonth != sn.pm { out.events.append(Ev(kind: "payroll", co: id, week: w, day: d, month: cfg.paidMonth)); sn.pm = cfg.paidMonth }
                if cfg.billsMonth != sn.bm { out.events.append(Ev(kind: "bills", co: id, week: w, day: d, month: cfg.billsMonth)); sn.bm = cfg.billsMonth }
                if co.vatBalance != 0, !out.events.contains(where: { $0.kind == "vatSeen" && $0.co == id }) { out.events.append(Ev(kind: "vatSeen", co: id, week: w, day: d)) }
                if cfg.lateSince != nil { out.events.append(Ev(kind: "latePayroll", co: id, week: w, day: d, note: cfg.lateWhy)) }
                if let last = co.monthlyHistory.last?.monthIndex, last != sn.lastMonth { out.events.append(Ev(kind: "monthClose", co: id, week: w, day: d, month: last)); sn.lastMonth = last }
                if co.taxDueWeek != sn.taxDueWeek, co.taxDue { out.events.append(Ev(kind: "yearEnd", co: id, week: w, day: d, month: co.taxDueWeek, note: "\(co.taxPrevYear)")); sn.taxDueWeek = co.taxDueWeek }
                for tx in co.transactions {
                    if key(tx) == sn.txHead { break }
                    let l = tx["l"].string
                    if l == "VAT settlement" || l == "VAT refund" { out.events.append(Ev(kind: "vat", co: id, week: w, day: d, note: l)) }
                    if l == "Corporate tax" { out.events.append(Ev(kind: "corpTax", co: id, week: w, day: d)) }
                }
                sn.txHead = co.transactions.first.map(key) ?? sn.txHead
                snaps[id] = sn
                if co.cash < floor { e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: floor * 2) } }
            }
            // Loans: an instalment is a fall in the balance; a missed one raises it.
            for l in e.state.loans {
                if let before = loanBalances[l.id] {
                    if l.balance < before - 0.005 { out.events.append(Ev(kind: "instalment", co: l.companyID, week: w, day: d, month: l.id)) }
                    if l.balance > before + 0.005 { out.events.append(Ev(kind: "missedInstalment", co: l.companyID, week: w, day: d, month: l.id)) }
                }
                loanBalances[l.id] = l.balance
            }
            for (id, _) in loanBalances where !e.state.loans.contains(where: { $0.id == id }) {
                out.events.append(Ev(kind: "instalment", co: 0, week: w, day: d, month: id, note: "last")); loanBalances[id] = nil
            }
            if e.state.stats.yearsPlayed != years { out.events.append(Ev(kind: "personalYear", co: 0, week: w, day: d)); years = e.state.stats.yearsPlayed }
            let nd = e.state.rest["inv"]?["deposits"].array.count ?? 0
            if nd < deposits { out.events.append(Ev(kind: "depositMatured", co: 0, week: w, day: d)) }
            deposits = nd
            if !fixedGone, let co = e.state.company(ids[1]), !co.staff.contains(where: { $0.id == fixedStaff }) {
                fixedGone = true; out.events.append(Ev(kind: "fixedEnded", co: ids[1], week: w, day: d))
            }
            if e.state.isGameOver { XCTFail("\(country): game over during the dates run"); break }
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(country): \(Ledger.gaps(e.state))")
        out.events.append(Ev(kind: "meta", co: fixedStaff, week: depositWeeks, day: 0, month: fixedEnd))
        return out
    }

    static var weeksToPlay: Int { Int(ProcessInfo.processInfo.environment["LEDGER_DATES_WEEKS"] ?? "") ?? 156 }

    func checkDates(_ r: Dated, country: String) {
        let W = r.weeks, start = Self.isoDay(week: 0, day: 0), end = Self.isoDay(week: W, day: 0)
        let calendar = Self.months(from: start, to: end)
        let at = { (e: Ev) in Self.isoDay(week: e.week, day: e.day) }
        let meta = r.events.first { $0.kind == "meta" }!
        func tag(_ s: String) -> String { "\(country): \(s)" }
        var counts: [String: Int] = [:]
        for e in r.events { counts[e.kind, default: 0] += 1 }
        print("DATES \(country) weeks=\(W) filing=\(r.filing):", counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        XCTAssertTrue(r.events.filter { $0.kind == "latePayroll" || $0.kind == "missedInstalment" }.isEmpty, tag("nothing is late or missed in a well-funded game: \(r.events.filter { $0.kind == "latePayroll" || $0.kind == "missedInstalment" }.prefix(3))"))

        // Pay day: once a month per company, on the 25th (the Friday before on a weekend), and a "Payday" message that day.
        let expectedPay = calendar.map { Self.expectedPayDay(year: $0.year, month0: $0.month0) }.filter { $0 > start && $0 <= end }
        let payIndexes = calendar.filter { Self.expectedPayDay(year: $0.year, month0: $0.month0) > start && Self.expectedPayDay(year: $0.year, month0: $0.month0) <= end }.map { $0.index }
        for id in r.companies {
            let ev = r.events.filter { $0.kind == "payroll" && $0.co == id }
            XCTAssertEqual(ev.map { $0.month }, payIndexes, tag("company \(id): one payroll a month, in order"))
            XCTAssertEqual(ev.map(at), expectedPay, tag("company \(id): payroll on the right dates"))
        }
        XCTAssertEqual(Set(r.paydayMessageDays), Set(expectedPay), tag("a Payday message arrives on every pay day and on no other day"))
        if W == 156 { XCTAssertEqual(payIndexes.count, 36, tag("36 payrolls in three years")) }

        // Rent and supplier bills: the last day of each month.
        let lastDays = calendar.map { Self.lastDayOfMonth($0.year, $0.month0) }.filter { $0 > start && $0 <= end }
        let billIndexes = calendar.filter { Self.lastDayOfMonth($0.year, $0.month0) > start && Self.lastDayOfMonth($0.year, $0.month0) <= end }.map { $0.index }
        for id in r.companies {
            let ev = r.events.filter { $0.kind == "bills" && $0.co == id }
            XCTAssertEqual(ev.map { $0.month }, billIndexes, tag("company \(id): bills once a month"))
            XCTAssertEqual(ev.map(at), lastDays, tag("company \(id): bills on the last day of the month"))
        }

        // Month close: the first day of the week before a month turns, once per month.
        let closeWeeks = (1...W).filter { GameCalendar.isMonthEnd(week: $0) }
        for id in r.companies {
            let ev = r.events.filter { $0.kind == "monthClose" && $0.co == id }
            XCTAssertEqual(ev.map { $0.week }, closeWeeks, tag("company \(id): month closes in the right weeks"))
            XCTAssertTrue(ev.allSatisfy { $0.day == 0 }, tag("month closes on the first day of the week"))
            XCTAssertEqual(ev.map { $0.month }, closeWeeks.map { GameCalendar.monthIndex(week: $0) }, tag("company \(id): month numbers"))
        }

        // VAT: only at closes whose month ends a filing period, once each.
        let filingWeeks = closeWeeks.filter { GameCalendar.monthIndex(week: $0) % r.filing == r.filing - 1 }
        for id in r.companies {
            let ev = r.events.filter { $0.kind == "vat" && $0.co == id }
            XCTAssertTrue(ev.allSatisfy { filingWeeks.contains($0.week) && $0.day == 0 }, tag("company \(id): VAT only in filing months: \(ev.map { $0.week })"))
            XCTAssertEqual(Set(ev.map { $0.week }).count, ev.count, tag("company \(id): never two VAT payments in one filing"))
            let charges = r.events.first { $0.kind == "vatSeen" && $0.co == id }
            XCTAssertTrue(charges != nil || ev.isEmpty, tag("company \(id): no VAT is filed when none was ever charged"))
            if charges != nil { XCTAssertGreaterThanOrEqual(ev.count, filingWeeks.filter { $0 > charges!.week }.count - 1, tag("company \(id): VAT filed every \(r.filing) month(s): \(ev.count) of \(filingWeeks.count)")) }
            if charges != nil, charges!.week < 8, r.filing == 1 && W == 156 { XCTAssertGreaterThanOrEqual(ev.count, 35, tag("12 filings a year where VAT is filed monthly")) }
        }

        // Loan instalments: one per month close, no gaps, from the first close; the 36 month loan ends after 36 (35 to 36 allowed for the weeks-to-months rounding).
        let byLoan = Dictionary(grouping: r.events.filter { $0.kind == "instalment" }, by: { $0.month })
        XCTAssertGreaterThanOrEqual(byLoan.count, 2, tag("the start-up loan and the business loan both run"))
        for (loanID, ev) in byLoan.sorted(by: { $0.key < $1.key }) {
            let unique = Set(ev.map { $0.week }).sorted()
            XCTAssertEqual(unique, Array(closeWeeks.prefix(unique.count)), tag("loan \(loanID): instalments in consecutive month-close weeks from the first"))
            XCTAssertTrue(ev.allSatisfy { $0.day == 0 }, tag("loan \(loanID): instalments on the month-close day"))
        }
        if W == 156, let biz = byLoan.values.first(where: { list in list.contains { $0.co != 0 } }) {
            let n = Set(biz.map { $0.week }).count
            XCTAssertTrue((35...36).contains(n), tag("a 36 month loan took \(n) instalments"))
            XCTAssertTrue(biz.contains { $0.note == "last" }, tag("the 36 month loan is paid off and gone"))
        }

        // Year end: company tax falls due 26 weeks later and is paid at the first month close from then on; the personal assessment runs at each year end.
        let yearEnds = (1...W).filter { GameCalendar.isYearEnd(week: $0) }
        XCTAssertEqual(r.events.filter { $0.kind == "personalYear" }.map { $0.week }, yearEnds, tag("the annual personal tax assessment runs at each year end"))
        for id in r.companies {
            let ye = r.events.filter { $0.kind == "yearEnd" && $0.co == id }
            XCTAssertEqual(ye.map { $0.week }, yearEnds, tag("company \(id): year ends"))
            let paid = r.events.filter { $0.kind == "corpTax" && $0.co == id }
            let owing = ye.filter { (Double($0.note) ?? 0) >= 1 }
            for y in owing {
                let due = y.month
                let first = closeWeeks.first { $0 >= due }
                if let first, first <= W { XCTAssertTrue(paid.contains { $0.week == first }, tag("company \(id): tax from the year end of week \(y.week) is paid in week \(first); payments: \(paid.map { $0.week })")) }
            }
            XCTAssertTrue(paid.allSatisfy { p in ye.contains { y in closeWeeks.first(where: { $0 >= y.month }) == p.week } }, tag("company \(id): tax is paid only when due: \(paid.map { $0.week })"))
        }

        // Expiry dates: a fixed deposit pays out in the week it ends, a fixed-term worker leaves on the date and was asked before it.
        let depositEnd = meta.week
        if depositEnd <= W { XCTAssertEqual(r.events.filter { $0.kind == "depositMatured" }.map { $0.week }, [depositEnd], tag("the deposit pays out exactly when it ends")) }
        let fixedEnd = meta.month
        if fixedEnd <= W {
            XCTAssertEqual(r.events.filter { $0.kind == "fixedEnded" }.map { $0.week }, [fixedEnd], tag("the fixed-term worker leaves in the week the term ends"))
            let asked = r.events.filter { $0.kind == "fixedAsk" }.map { $0.week }
            XCTAssertTrue(!asked.isEmpty && asked.allSatisfy { $0 < fixedEnd && $0 >= fixedEnd - 12 }, tag("the renewal question comes before the end date: \(asked)"))
        }
    }

    func testEveryDateFiredItemOverThreeYearsMonthlyFilingCountry() throws {
        let (data, _, _) = try GameEngine.loadResources()
        let code = try XCTUnwrap(data.countries.countries.map { $0.code }.sorted().first { data.countries[$0]?.vatFilingMonths == 1 })
        let r = try playDated(country: code, weeks: Self.weeksToPlay)
        checkDates(r, country: code)
    }

    func testEveryDateFiredItemOverThreeYearsQuarterlyFilingCountry() throws {
        let (data, _, _) = try GameEngine.loadResources()
        let code = data.countries["UK"]?.vatFilingMonths == 3 ? "UK" : try XCTUnwrap(data.countries.countries.map { $0.code }.sorted().first { data.countries[$0]?.vatFilingMonths == 3 })
        let r = try playDated(country: code, weeks: Self.weeksToPlay)
        checkDates(r, country: code)
    }
}
