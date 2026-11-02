import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// Stage 10 regression: the books balance after each money event, valuation is not double counted, employment pay lines, management routing, and a save mid-game.
final class Stage10ReconciliationTests: XCTestCase {
    private func firm(_ code: String = "UK", trade: String = "cafe", form: LegalForm = .limited, seed: Int = 31, days: Int = 14) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 400_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: form, fundWith: 120_000_000) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        for _ in 0..<days { _ = e.nextDay() }
        return (e, id)
    }
    private func balanced(_ e: GameEngine, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))", file: file, line: line)
    }
    private func candidate(_ e: inout GameEngine, _ id: Int) -> Int {
        var pid = 0
        for _ in 0..<20 {
            e.update { s, d, _ in
                var p = Hiring.generateCandidate(role: "cook", company: s.company(id), tier: "mid", state: &s, data: d)
                p.set("sec", 0.1); s.people[p.id] = p; pid = p.id
            }
            if Hiring.maxHoursPerWeek(personID: pid) == nil { break }
        }
        return pid
    }

    // MARK: financial reconciliation

    func testConversionKeepsTheBooksBalanced() throws {
        var (e, id) = try firm(form: .soleTrader)
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        balanced(e, "conversion")
        for _ in 0..<14 { _ = e.nextDay() }
        balanced(e, "two weeks after conversion")
    }

    func testLoanTakenAndRepaidKeepsTheBooksBalanced() throws {
        var (e, id) = try firm()
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: 3_000_000, termMonths: 24, companyID: id), .ok)
        balanced(e, "loan taken")
        let loanID = try XCTUnwrap(e.state.loans.last { $0.companyID == id }).id
        for _ in 0..<40 { _ = e.nextDay() }
        balanced(e, "instalment month end")
        e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: 20_000_000) }
        XCTAssertTrue(e.payOffLoan(loanID: loanID))
        XCTAssertFalse(e.state.loans.contains { $0.id == loanID })
        balanced(e, "loan repaid")
    }

    func testPayrollInvoicesTaxAndDividendKeepTheBooksBalanced() throws {
        var (e, id) = try firm(days: 10)
        _ = e.runPayrollFromAccounting(companyID: id)
        balanced(e, "payroll run")
        for _ in 0..<(6 * 7) { _ = e.nextDay() }      // invoices raised, sent and paid; a tax month closes
        balanced(e, "six weeks of trading")
        XCTAssertNotNil(e.invoices(companyID: id))
        e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: 30_000_000) }
        if e.maximumDividend(companyID: id) > 0 { XCTAssertGreaterThan(e.payDividendShare(companyID: id, share: 0.5), 0) }
        balanced(e, "dividend paid")
    }

    func testEquipmentBoughtSoldAndInsuranceBoughtKeepTheBooksBalanced() throws {
        var (e, id) = try firm(trade: "webdev", days: 7)
        let need = try XCTUnwrap(e.equipmentNeeds(companyID: id).first { !$0.isVehicle })
        let offer = try XCTUnwrap(e.equipmentOffers(companyID: id, equipmentID: need.equipmentID).first)
        _ = e.buyEquipmentItem(companyID: id, equipmentID: need.equipmentID, offer: offer, quantity: 1, payment: .cash)
        balanced(e, "equipment bought")
        for _ in 0..<14 { _ = e.nextDay() }           // depreciation
        _ = e.sellAllEquipment(companyID: id, equipmentID: need.equipmentID)
        balanced(e, "equipment sold")
        if let p = e.coverageOverview(companyID: id)?.policies.first(where: { !$0.isOn }) {
            _ = e.toggleInsurancePolicy(companyID: id, product: p.id)
            for _ in 0..<35 { _ = e.nextDay() }       // premium collected
        }
        balanced(e, "insurance bought")
    }

    // MARK: valuation

    func testCompanyValueIsCountedOnceInNetWorth() throws {
        var (e, id) = try firm(days: 21)
        let nw = e.netWorth
        XCTAssertEqual(nw.total, nw.personal + nw.stocks + nw.crypto + nw.funds + nw.companies + nw.luxury - nw.debt - nw.pendingTax, accuracy: max(1, abs(nw.total) * 0.001), "total is the sum of its parts")
        let before = nw.total
        e.update { s, _, _ in Ledger.move(&s, .me, -10_000_000, why: "Into company"); Ledger.moveRaw(&s, .company(id), 10_000_000) }
        let after = e.netWorth
        XCTAssertEqual(after.total, before, accuracy: 10_000_000 * 0.35, "the company's value rises by about what the owner's cash fell by, not twice it or not at all")
        XCTAssertLessThan(after.personal, nw.personal)
        balanced(e, "valuation move")
    }

    // MARK: employment pay lines

    func testHourlyPartTimeFixedAndSeasonalPayLinesArePaidAndBalanced() throws {
        var (e, id) = try firm(days: 7)
        let w = e.marketWage(role: "cook", companyID: id) * 2
        let terms: [Hiring.Terms] = [Hiring.Terms(), Hiring.Terms(percent: 50), Hiring.Terms(basis: "fix", percent: 100), Hiring.Terms(seasonMonths: [6, 7, 8], percent: 50, seasonCount: 1)]
        var hired: [Int] = []
        for t in terms {
            let pid = candidate(&e, id)
            if e.hire(personID: pid, companyID: id, monthlyWage: w, terms: t) == .ok { hired.append(pid) }
        }
        XCTAssertGreaterThanOrEqual(hired.count, 3)
        for pid in hired { XCTAssertNotNil(e.employmentContract(companyID: id, personID: pid)) }
        for _ in 0..<(5 * 7) { _ = e.nextDay() }
        balanced(e, "five weeks of payroll for every pay line")
        let leaver = hired[0]
        if e.state.company(id)?.staff.contains(where: { $0.id == leaver }) == true {
            XCTAssertNotNil(e.dismissStaff(companyID: id, staffID: leaver))
            XCTAssertFalse(e.state.company(id)?.staff.contains { $0.id == leaver } ?? true)
        }
        balanced(e, "dismissal")
    }

    func testEmployerCostIsAtLeastTheWage() throws {
        for code in ["UK", "DE", "US"] {
            var (e, id) = try firm(code, days: 7)
            let pid = candidate(&e, id)
            let wage = e.marketWage(role: "cook", companyID: id) * 2
            let b = try XCTUnwrap(e.hiringEmployerCost(companyID: id, personID: pid, monthlyWage: wage), code)
            XCTAssertGreaterThanOrEqual(b.totalMonthly, b.grossMonthlyWage * 0.99, code)
            XCTAssertGreaterThan(b.totalMonthly, 0, code)
            _ = wage
        }
    }

    // MARK: business systems

    func testANewCompanyStartsEmptyAndPricingStaysInRange() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 41)
        e.update { s, _, _ in Ledger.move(&s, .me, 800_000_000, why: "Test funds") }
        let city = e.state.player.cityID
        let plan = try XCTUnwrap(e.newCompanyPlan(tradeID: "grocery", cityID: city, form: .limited, size: 1))
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "grocery", cityID: city, form: .limited, size: 1, name: nil, pick: nil, fundWith: plan.intoCompany, choices: SetupChoices(stock: .none)) else { return XCTFail("start") }
        let id = out.companyID
        let c = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(c.staff.isEmpty, "no staff are hired for you at the start")
        XCTAssertNotEqual(c.status, .open)
        for _ in 0..<10 { _ = e.changePrice(companyID: id, byShare: 0.3) }
        let range = try XCTUnwrap(e.data.balance.priceRangeByTrade["grocery"])
        XCTAssertLessThanOrEqual(e.data.balance.priceMultiplier(level: try XCTUnwrap(e.state.company(id)).priceLevel), range[1] + 1e-6)
        balanced(e, "new company")
    }

    func testFranchiseApplyAndSignKeepTheBooksBalanced() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 43)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard let b = e.franchiseBrands().first else { throw XCTSkip("no brand") }
        _ = e.applyToFranchiseBrand(b.id)
        balanced(e, "franchise application")
        if let terms = e.franchiseAgreedTerms(b.id) { e.signFranchiseTerms(b.id, terms: terms) }
        balanced(e, "franchise signed")
        for _ in 0..<7 { _ = e.nextDay() }
        balanced(e, "week after")
    }

    // MARK: management

    func testManagedCompanyDelegationAndSeverityGrowsWithSize() throws {
        var (e, id) = try firm(days: 7)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].managerID = 0 } }
        let line = try XCTUnwrap(e.delegationLines().first { $0.id == id })
        XCTAssertEqual(line.rehire, "Manager")
        func ask(_ amt: Double) -> Message {
            var m = Message(raw: [:])
            m.kind = "ask"; m.status = "open"; m.actionID = "x"; m.tone = "n"
            m.raw["opts"] = .array([.object(["t": "Spend", "fx": .object(["cash": .number(amt)])])])
            return m
        }
        XCTAssertLessThanOrEqual(Delegation.level(of: ask(-1_000), netWorth: 10_000_000), Delegation.level(of: ask(-5_000_000), netWorth: 10_000_000))
        if let m = e.openDecisions.first {
            XCTAssertTrue(e.answer(messageID: m.id, option: 0))
            XCTAssertFalse(e.openDecisions.contains { $0.id == m.id })
        }
        balanced(e, "decision answered")
    }

    // MARK: save and load

    func testSaveReloadThenSevenDaysEqualsTheUnsavedRun() throws {
        var (e, id) = try firm(days: 21)
        _ = e.takeLoan(kind: "biz", amount: 2_000_000, termMonths: 24, companyID: id)
        let pid = candidate(&e, id)
        _ = e.hire(personID: pid, companyID: id, monthlyWage: e.marketWage(role: "cook", companyID: id) * 2, terms: Hiring.Terms(percent: 50))
        for _ in 0..<10 { _ = e.nextDay() }
        let bytes = try JSONEncoder().encode(e.state)
        let loaded = try JSONDecoder().decode(GameState.self, from: bytes)
        XCTAssertTrue(loaded == e.state)
        let (data, events, marketing) = try GameEngine.loadResources()
        var b = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        for _ in 0..<7 { _ = e.nextDay(); _ = b.nextDay() }
        XCTAssertTrue(e.state == b.state, "the reloaded game plays on exactly like the unsaved one")
        balanced(b, "reloaded game")
    }
}
