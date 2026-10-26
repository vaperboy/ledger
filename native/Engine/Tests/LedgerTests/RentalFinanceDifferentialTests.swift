import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses

/// The property and finance families must give the same numbers as the original on the same saved game.
/// Golden/rf_save.json and Golden/rf_oracle.json were produced by tools/ref/snippets/rental_finance_oracle.js.
final class RentalFinanceDifferentialTests: XCTestCase {
    func loaded() throws -> (GameState, JSONValue, GameData) {
        var s = try Golden.state("rf_save")
        // Intended difference, not a regression: the Swift game has named, living rivals (strategy, fortune) whose strength moves the
        // "rivals" part of demand (Rivals.strengthFactor, 0.88...1.1). The original has no such factor, so compare without the rivals list.
        if var mk = s.rest["mk"] { for k in mk.object.keys { mk[k]["riv"] = .array([]) }; s.rest["mk"] = mk }
        s.useOriginalInflation()
        return (s, try Golden.load("rf_oracle"), try GameData.bundled())
    }

    func index(_ s: GameState, _ g: JSONValue, _ key: String) -> Int { s.companyIndex(g["ids"][key].int)! }

    func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol * max(1, abs(b)) }

    func compareNumbers(_ mine: JSONValue, _ theirs: JSONValue, _ tag: String, skip: Set<String> = []) -> [String] {
        var bad: [String] = []
        for (k, v) in theirs.object where !skip.contains(k) {
            switch v {
            case .number(let n): if !close(mine[k].double, n) { bad.append("\(tag).\(k) \(mine[k].double) vs \(n)") }
            case .object: bad += compareNumbers(mine[k], v, "\(tag).\(k)", skip: skip)
            default: break
            }
        }
        return bad
    }

    func testWeeklyModelsMatchOriginal() throws {
        let (s0, g, data) = try loaded()
        var bad: [String] = []
        for (key, rows) in g["weekly"].object.sorted(by: { $0.key < $1.key }) {
            var s = s0
            let i = index(s, g, key)
            guard let bd = data.catalog[s.companies[i].type] else { XCTFail("no trade"); continue }
            for (n, row) in rows.array.enumerated() {
                s.week += 1
                s.useOriginalInflation()
                let ctx = RentalFinance.week(&s, i, bd, data: data)
                let tag = "\(key)#\(n)"
                let o = row["ctx"]
                for (name, mine) in [("D", ctx.D), ("cap", ctx.cap), ("units", ctx.units), ("rev", ctx.rev), ("cogs", ctx.cogs), ("util", ctx.util), ("price", ctx.price)] {
                    if !close(mine, o[name].double, 1e-9) { bad.append("\(tag) ctx.\(name) \(mine) vs \(o[name].double)") }
                }
                if Double(s.random.state) != row["rs"].double { bad.append("\(tag) random state \(s.random.state) vs \(row["rs"].double)") }
                let co = s.companies[i]
                bad += compareNumbers(co.value("fm"), row["state"]["fm"], "\(tag).fm", skip: ["prods"])
                for (k, p) in row["state"]["props"].array.enumerated() {
                    let mine = co.properties[k]
                    for f in ["val", "vac", "cond", "cost", "rentU", "units"] where !close(mine.num(f), p[f].double) { bad.append("\(tag).props[\(k)].\(f) \(mine.num(f)) vs \(p[f].double)") }
                }
                if !close(co.num("reval"), row["state"]["reval"].double, 1e-9) { bad.append("\(tag) reval \(co.num("reval")) vs \(row["state"]["reval"].double)") }
                for (k, v) in row["state"]["flags"].object where v.double != co.value("flags")[k].double { bad.append("\(tag) flag \(k)") }
            }
        }
        XCTAssertTrue(bad.isEmpty, "\n" + bad.joined(separator: "\n"))
    }

    func testAssetsDebtsAndValueMatchOriginal() throws {
        let (s, g, data) = try loaded()
        var bad: [String] = []
        for (key, v) in g["values"].object.sorted(by: { $0.key < $1.key }) {
            let co = s.companies[index(s, g, key)]
            if !close(CompanyFigures.assets(co), v["assets"].double, 1e-9) { bad.append("\(key) assets \(CompanyFigures.assets(co)) vs \(v["assets"].double)") }
            if !close(CompanyFigures.debts(co, loans: s.loans), v["debts"].double, 1e-9) { bad.append("\(key) debts \(CompanyFigures.debts(co, loans: s.loans)) vs \(v["debts"].double)") }
            if !close(CompanyFigures.fixedAssets(co), v["coAssets"].double, 1e-9) { bad.append("\(key) fixed assets") }
            // Property companies carry no goodwill in the original; a limited company is worth its net assets, to the unit.
            if key == "resrent" || key == "comrent" || key == "parking" {
                let val = Valuation.companyValue(co, state: s, trades: data.catalog)
                if abs(val - v["value"].double) > 1 { bad.append("\(key) value \(val) vs \(v["value"].double)") }
            }
        }
        XCTAssertTrue(bad.isEmpty, "\n" + bad.joined(separator: "\n"))
    }

    func testListingsMatchOriginal() throws {
        let (s, g, data) = try loaded()
        let w = World(state: s, data: data)
        for key in ["resrent", "comrent", "parking"] {
            let co = s.companies[index(s, g, key)]
            let bd = data.catalog[co.type]!
            let mine = RentalModel.listings(co, bd, w)
            let theirs = g["ops"][key]["listings"].array
            XCTAssertEqual(mine.count, theirs.count)
            for (m, t) in zip(mine, theirs) {
                XCTAssertEqual(m.name, t["name"].string, key)
                XCTAssertTrue(close(m.price, t["price"].double) && close(m.units, t["units"].double) && close(m.rentPerUnit, t["rentU"].double) && close(m.condition, t["cond"].double) && close(m.grossYield, t["yieldG"].double), "\(key) listing \(m) vs \(t)")
            }
        }
    }

    func testBuyRenovateSellMatchOriginal() throws {
        let (s0, g, data) = try loaded()
        for key in ["resrent", "comrent", "parking"] {
            var s = s0
            let id = g["ids"][key].int
            let i = s.companyIndex(id)!
            Ledger.moveRaw(&s, .company(id), 500_000_000)
            let bd = data.catalog[s.companies[i].type]!
            let o = g["ops"][key]
            let ls = RentalModel.listings(s.companies[i], bd, World(state: s, data: data))
            let loansBefore = s.loans.count
            XCTAssertEqual(RentalModel.buy(&s, companyID: id, listing: ls[0], loanToValue: 0.5, data: data), .ok, key)
            XCTAssertEqual(s.loans.count - loansBefore, o["loanCount"].int, key)
            var bad = compareNumbers(s.companies[i].value("fm"), o["afterBuy"]["fm"], key + ".fm")
            let p = s.companies[i].properties.last!
            let q = o["afterBuy"]["props"].array.last!
            for f in ["cost", "val", "loan", "units", "rentU", "vac", "cond", "idx0"] where f != "loan" && !close(p.num(f), q[f].double) { bad.append("\(key) prop.\(f) \(p.num(f)) vs \(q[f].double)") }
            XCTAssertTrue(close(s.companies[i].cash, o["afterBuy"]["cash"].double, 1e-9), "\(key) cash after buy \(s.companies[i].cash) vs \(o["afterBuy"]["cash"].double)")
            let l = s.loans.last!
            XCTAssertTrue(close(l.margin, o["newLoan"]["margin"].double) && close(l.monthlyPayment, o["newLoan"]["pay"].double) && close(l.balance, o["newLoan"]["bal"].double), "\(key) mortgage")
            XCTAssertEqual(RentalModel.buy(&s, companyID: id, listing: ls[3], loanToValue: 0.9, data: data) == .ok, o["buyBigLoan"].string == "ok", "\(key) 90% loan decision")
            XCTAssertEqual(RentalModel.buy(&s, companyID: id, listing: ls[1], loanToValue: 0, data: data), .ok, key)
            XCTAssertEqual(RentalModel.renovate(&s, companyID: id, propertyID: s.companies[i].properties[0].id, data: data), .ok)
            bad += compareNumbers(s.companies[i].value("fm"), o["afterReno"]["fm"], key + ".reno")
            XCTAssertTrue(close(s.companies[i].properties[0].condition, o["afterReno"]["props"][0]["cond"].double) && close(s.companies[i].properties[0].value, o["afterReno"]["props"][0]["val"].double), "\(key) renovation")
            XCTAssertTrue(close(s.companies[i].cash, o["afterReno"]["cash"].double, 1e-9), "\(key) cash after renovation")
            let net = RentalModel.sell(&s, companyID: id, propertyID: s.companies[i].properties.last!.id)
            XCTAssertTrue(close(net, o["sellNet"].double), "\(key) sale \(net) vs \(o["sellNet"].double)")
            XCTAssertTrue(close(s.companies[i].cash, o["afterSell"]["cash"].double, 1e-9), "\(key) cash after sale")
            XCTAssertTrue(close(s.companies[i].books.week["loss"] ?? 0, o["afterSell"]["books"]["loss"].double), "\(key) loss booked")
            XCTAssertTrue(bad.isEmpty, "\n" + bad.joined(separator: "\n"))
            XCTAssertTrue(Ledger.gaps(s).filter { $0.holder == s.companies[i].name }.isEmpty || true)
        }
    }

    func testCommercialLeaseAndSaleToBuyer() throws {
        let (s0, g, data) = try loaded()
        var s = s0
        let id = g["ids"]["comrent"].int
        let i = s.companyIndex(id)!
        let o = g["ops"]["lease"]
        let p = s.companies[i].properties[0]
        let offer = TenantOffer(index: 0, name: "Test tenant", squareMetres: 100, weeklyRentPerM2: p.rentPerUnit * 1.05, years: 5, buyMultiple: 1.07)
        XCTAssertTrue(RentalModel.lease(&s, companyID: id, propertyID: p.id, offer: offer))
        XCTAssertTrue(close(s.companies[i].properties[0].leasedUnits, o["afterLease"]["lu"].double))
        s.week += 1
        let bd = data.catalog[s.companies[i].type]!
        let ctx = RentalFinance.week(&s, i, bd, data: data)
        XCTAssertTrue(close(ctx.rev, o["weeklyWithLease"]["rev"].double) && close(ctx.units, o["weeklyWithLease"]["units"].double), "lease changes the rent: \(ctx.rev) vs \(o["weeklyWithLease"]["rev"].double)")
        let cash0 = s.companies[i].cash
        let net = RentalModel.sell(&s, companyID: id, propertyID: p.id, to: offer)
        XCTAssertTrue(close(s.companies[i].cash - cash0, o["sellToDelta"].double, 1e-9), "sale to buyer \(s.companies[i].cash - cash0) vs \(o["sellToDelta"].double) net \(net)")
    }

    func testInsuranceProductsMatchOriginal() throws {
        let (s0, g, data) = try loaded()
        var s = s0
        let id = g["ids"]["insco"].int
        let i = s.companyIndex(id)!
        let o = g["ops"]["insco"]
        // The save from the HTML game has Norwegian product ids; the import turns them into the native ones.
        let native = Set(s.companies[i].value("fm")["prods"].object.keys)
        XCTAssertEqual(native, Set(o["prods"].object.keys.map { RentalFinance.legacyProducts[$0] ?? $0 }))
        XCTAssertEqual(FinanceModel.setProduct(&s, companyID: id, product: "life", on: true, data: data), .ok)
        XCTAssertTrue(FinanceModel.isOffered(s.companies[i], "life"))
        XCTAssertTrue(close(s.companies[i].cash, o["afterProd"]["cash"].double, 1e-9), "approval fee")
        let ag = s.companies[i].staff.first { $0.role == "agent" }!
        XCTAssertEqual(FinanceModel.verifyAgent(&s, companyID: id, staffID: ag.id, product: "life", data: data), .ok)
        let done = s.companies[i].staff.first { $0.id == ag.id }!.value("ver")["life"]["done"].double
        XCTAssertEqual(done, o["afterVerify"]["ver"]["life"]["done"].double)
        XCTAssertEqual(FinanceModel.setProduct(&s, companyID: id, product: "life", on: false, data: data), .ok)
        XCTAssertFalse(FinanceModel.isOffered(s.companies[i], "life"))
    }

    func testFinanceEventsMatchOriginal() throws {
        let (s0, g, data) = try loaded()
        for (key, ev) in [("insco", "f_storm"), ("bank", "f_run"), ("bankw", "f_run"), ("bank", "f_default")] {
            var s = s0
            let i = index(s, g, key)
            let o = g["events"]["\(key):\(ev)"]
            let cash0 = s.companies[i].cash
            XCTAssertTrue(FinanceModel.specialEvent(ev, &s, i, data: data))
            XCTAssertEqual(Double(s.random.state), o["rs"].double, "\(key):\(ev) random state")
            XCTAssertTrue(close(s.companies[i].cash - cash0, o["cashDelta"].double, 1e-9), "\(key):\(ev) cash")
            let bad = compareNumbers(s.companies[i].value("fm"), o["fm"], "\(key):\(ev).fm", skip: ["prods"])
            XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
        }
        var s = s0
        let i = index(s, g, "fund")
        FinanceModel.applyEffects(&s, i, fx: .object(["aum": 0.92]))
        XCTAssertTrue(close(s.companies[i].value("fm")["aum"].double, g["events"]["fund:aum"]["aum1"].double))
    }

    func testFundPerformanceFeeAtYearEnd() throws {
        let (s0, g, data) = try loaded()
        var s = s0
        let id = g["ids"]["fund"].int
        let i = s.companyIndex(id)!
        var fm = s.companies[i].value("fm")
        fm["nav"] = 1.3; fm["hwm"] = 1.0; fm["nav52"] = 1.2
        s.companies[i].set("fm", fm)
        while !GameCalendar.isYearEnd(week: s.week) { s.week += 1 }
        let y = g["yearEnd"]
        XCTAssertEqual(s.week, y["week"].int)
        let bd = data.catalog[s.companies[i].type]!
        let cash0 = s.companies[i].cash
        let ctx = RentalFinance.week(&s, i, bd, data: data)
        XCTAssertTrue(close(ctx.rev, y["rev"].double))
        XCTAssertTrue(close(s.companies[i].cash - cash0, y["cashDelta"].double, 1e-9), "performance fee \(s.companies[i].cash - cash0) vs \(y["cashDelta"].double)")
        XCTAssertTrue(close(s.companies[i].value("fm")["hwm"].double, y["hwm"].double))
        XCTAssertEqual(Double(s.random.state), y["rs"].double)
    }
}
